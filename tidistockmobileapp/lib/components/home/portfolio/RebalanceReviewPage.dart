import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_stock.dart';
import 'package:tidistockmobileapp/models/rebalance_entry.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerSelectionPage.dart';
import 'DdpiAuthPage.dart';
import 'ExecutionStatusPage.dart';

class RebalanceReviewPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;

  /// When non-null, skip the preference modal and use this flag directly.
  /// 0 = full rebalance, 1 = 2% threshold.
  /// Passed from CurrentHoldingsPreviewPage (matching prod flow order).
  final int? rebalanceFlag;

  /// Symbols held by the user as confirmed in Step 2 (CurrentHoldingsPreviewPage).
  /// When non-null and empty, all SELL orders are filtered out since user holds nothing.
  /// Matches prod flow where handleCheckStatus validates holdings before rebalance.
  final Set<String>? heldSymbols;

  const RebalanceReviewPage({
    super.key,
    required this.portfolio,
    required this.email,
    this.rebalanceFlag,
    this.heldSymbols,
  });

  @override
  State<RebalanceReviewPage> createState() => _RebalanceReviewPageState();
}

class _RebalanceReviewPageState extends State<RebalanceReviewPage> {
  List<_RebalanceAction> actions = [];
  bool loading = true;
  bool termsAccepted = false;
  RebalanceHistoryEntry? latestRebalance;
  RebalanceHistoryEntry? previousRebalance;

  // Execution status tracking
  bool _alreadyExecuted = false;
  bool _partiallyExecuted = false;
  bool _serverCalculated = false; // true when actions came from POST /rebalance/calculate
  String? _researchReportLink;

  // Rebalance preference (matching alphab2b RebalanceCard.js showCheckboxModal)
  int _rebalanceFlag = 0; // 0 = full rebalance, 1 = 2% threshold

  // CA pending info from /rebalance/calculate response
  List<Map<String, dynamic>> _caPendingInfo = [];

  // Corporate action upcoming warnings
  List<Map<String, dynamic>> _upcomingSplits = [];
  List<Map<String, dynamic>> _upcomingDividends = [];

  // Unique ID from server calculation (needed for execution)
  String? _calculatedUniqueId;

  // Connected broker (cached after initial check)
  BrokerConnection? _connectedBroker;

  // DummyBroker (non-broker) editable data — matching alphab2b UpdateRebalanceModal.js
  bool _isDummyBrokerMode = false;
  List<Map<String, dynamic>> _editableData = [];

  // Funds check state
  bool _fundsCheckFailed = false;

  @override
  void initState() {
    super.initState();
    _initRebalance();
  }

  Future<void> _initRebalance() async {
    var history = widget.portfolio.rebalanceHistory;

    // Plans API may return rebalanceHistory without adviceEntries.
    // Fetch full strategy data (which includes adviceEntries) if needed.
    if (history.isEmpty || history.last.adviceEntries.isEmpty) {
      debugPrint('[RebalanceReview] rebalanceHistory empty or no adviceEntries — fetching strategy details for "${widget.portfolio.modelName}"');
      history = await _fetchEnrichedHistory() ?? history;
    }

    if (history.isEmpty) {
      debugPrint('[RebalanceReview] No rebalance history available after enrichment');
      setState(() => loading = false);
      return;
    }

    latestRebalance = history.last;
    previousRebalance = history.length > 1 ? history[history.length - 2] : null;

    // Check execution status for the latest rebalance
    final execForUser = latestRebalance!.getExecutionForUser(widget.email);
    if (execForUser != null) {
      if (execForUser.isExecuted) {
        _alreadyExecuted = true;
      } else if (execForUser.status.toLowerCase() == 'partial') {
        _partiallyExecuted = true;
      }
    }

    // Check for research report link
    _researchReportLink = latestRebalance!.researchReportLink;

    // Pre-fetch connected broker for credential passthrough
    await _prefetchBroker();

    // Use pre-selected preference if provided (from CurrentHoldingsPreviewPage flow),
    // otherwise show the preference modal (matching prod RebalanceCard.js step order).
    if (widget.rebalanceFlag != null) {
      _rebalanceFlag = widget.rebalanceFlag!;
    } else if (mounted && !_alreadyExecuted) {
      await _showRebalancePreferenceModal();
    }

    await _computeRebalanceActions(history);

    // Check if user is in DummyBroker (non-broker) mode
    // matching alphab2b UpdateRebalanceModal.js selectNonBroker check
    if (_connectedBroker == null && actions.isNotEmpty) {
      _isDummyBrokerMode = true;
      _initEditableData();
    }
  }

  /// Initialize editable data for DummyBroker mode
  /// (matching alphab2b UpdateRebalanceModal.js editableData initialization)
  void _initEditableData() {
    _editableData = actions.asMap().entries.map((entry) {
      final action = entry.value;
      return {
        'index': entry.key,
        'symbol': action.symbol,
        'exchange': action.exchange,
        'orderType': action.type == _ActionType.buy ? 'BUY' : 'SELL',
        'editablePrice': action.price,
        'editableQty': action.quantity > 0 ? action.quantity : 1,
        'token': action.token ?? '',
        'isCaPending': action.isCaPending,
        'zerodhaTradeId': action.zerodhaTradeId ?? '',
      };
    }).toList();
    if (mounted) setState(() {});
  }

  /// Pre-fetch the user's connected broker so we can pass credentials
  /// to /rebalance/calculate (matching alphab2b flow).
  Future<void> _prefetchBroker() async {
    try {
      final brokerResp = await AqApiService.instance.getConnectedBrokers(widget.email);
      if (brokerResp.statusCode == 200) {
        final brokerData = jsonDecode(brokerResp.body);
        final connections = BrokerConnection.parseApiResponse(brokerData);
        final connected = connections.where((b) => b.isEffectivelyConnected).toList();
        if (connected.isNotEmpty) {
          // Prefer primary broker
          _connectedBroker = connected.firstWhere(
            (b) => b.isPrimary,
            orElse: () => connected.first,
          );
        }
      }
    } catch (e) {
      debugPrint('[RebalanceReview] _prefetchBroker error: $e');
    }
  }

  /// Show preference modal: full rebalance vs 2% threshold
  /// (matching alphab2b RebalanceCard.js showCheckboxModal)
  Future<void> _showRebalancePreferenceModal() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Rebalance Preference",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text("Choose how to handle small weight changes",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            _preferenceOption(
              title: "Full Rebalance",
              subtitle: "Execute all weight changes regardless of size",
              icon: Icons.sync,
              color: Colors.blue,
              value: 0,
              onTap: () => Navigator.pop(ctx, 0),
            ),
            const SizedBox(height: 12),
            _preferenceOption(
              title: "Ignore Small Changes (2%)",
              subtitle: "Skip trades where weight change is less than 2%",
              icon: Icons.filter_alt_outlined,
              color: Colors.orange,
              value: 1,
              onTap: () => Navigator.pop(ctx, 1),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (result != null) {
      _rebalanceFlag = result;
    }
  }

  Widget _preferenceOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _computeRebalanceActions(List<RebalanceHistoryEntry> history) async {
    // ── SERVER-SIDE CALCULATION (rgx_app approach) ──
    final serverActions = await _tryServerSideCalculation();
    if (serverActions != null && serverActions.isNotEmpty) {
      debugPrint('[RebalanceReview] Using server-side calculation: ${serverActions.length} actions');
      _serverCalculated = true;

      // Check for upcoming corporate actions (matching alphab2b)
      await _checkUpcomingCorporateActions(serverActions);

      // Filter sell actions for stocks user doesn't hold (matching prod flow
      // where handleCheckStatus validates holdings before rebalance/calculate)
      _filterSellsAgainstHoldings(serverActions);

      setState(() {
        actions = serverActions;
        loading = false;
      });
      return;
    }

    // ── CLIENT-SIDE FALLBACK ──
    debugPrint('[RebalanceReview] Server-side calculation unavailable, using client-side fallback');
    final computed = _computeClientSideActions(history);

    // Filter sell actions for stocks user doesn't hold
    _filterSellsAgainstHoldings(computed);

    setState(() {
      actions = computed;
      loading = false;
    });
  }

  /// Check for upcoming corporate actions (splits, dividends) for trade symbols.
  /// Matching alphab2b UpdateRebalanceModal.js corporate action check.
  Future<void> _checkUpcomingCorporateActions(List<_RebalanceAction> actionList) async {
    try {
      final symbols = actionList.map((a) => a.symbol).toList();
      if (symbols.isEmpty) return;

      final resp = await AqApiService.instance.getUpcomingCorporateActions(symbols: symbols);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['status'] == 0 && data['data'] != null) {
          final splits = data['data']['splits'];
          final dividends = data['data']['dividends'];
          if (splits is List && splits.isNotEmpty) {
            _upcomingSplits = splits.map((s) => Map<String, dynamic>.from(s)).toList();
          }
          if (dividends is List && dividends.isNotEmpty) {
            _upcomingDividends = dividends.map((d) => Map<String, dynamic>.from(d)).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[RebalanceReview] corporate action check error: $e');
    }
  }

  /// Filter sell actions for stocks user doesn't actually hold.
  /// Uses heldSymbols from Step 2 (CurrentHoldingsPreviewPage) which already
  /// did the prod handleCheckStatus min(modelQty, brokerQty) cross-reference.
  /// If heldSymbols is empty → user has no holdings → remove all SELL actions.
  void _filterSellsAgainstHoldings(List<_RebalanceAction> actionList) {
    if (widget.heldSymbols == null) return; // no Step 2 data, skip filter

    final held = widget.heldSymbols!;
    final removedSymbols = <String>[];

    actionList.removeWhere((action) {
      if (action.type != _ActionType.sell) return false;
      final sym = action.symbol.toUpperCase();
      if (!held.contains(sym)) {
        removedSymbols.add(action.symbol);
        return true;
      }
      return false;
    });

    if (removedSymbols.isNotEmpty) {
      debugPrint(
          '[RebalanceReview] Filtered ${removedSymbols.length} sell action(s) — '
          'not in Step 2 holdings: ${removedSymbols.join(', ')}');
    }
  }

  /// Call POST /rebalance/calculate (server-side, like rgx_app).
  /// Returns BUY/SELL actions with exact quantities, or null on failure.
  /// Passes broker credentials so CCXT can fetch live holdings.
  Future<List<_RebalanceAction>?> _tryServerSideCalculation() async {
    try {
      String? modelId;
      if (widget.portfolio.rebalanceHistory.isNotEmpty) {
        modelId = widget.portfolio.rebalanceHistory.last.modelId;
      }
      modelId ??= widget.portfolio.strategyId ?? widget.portfolio.id;

      final broker = _connectedBroker;
      final userBroker = broker?.broker ?? 'DummyBroker';
      final userFund = '0';

      final advisor = widget.portfolio.advisor.isNotEmpty
          ? widget.portfolio.advisor
          : AqApiService.instance.advisorName;

      debugPrint('[RebalanceReview] Calling rebalanceCalculate: model=${widget.portfolio.modelName}, modelId=$modelId, broker=$userBroker, advisor=$advisor, flag=$_rebalanceFlag');

      final resp = await AqApiService.instance.rebalanceCalculate(
        userEmail: widget.email,
        modelName: widget.portfolio.modelName,
        advisor: advisor,
        modelId: modelId,
        userBroker: userBroker,
        userFund: userFund,
        flag: _rebalanceFlag,
        apiKey: broker?.apiKey,
        secretKey: broker?.secretKey,
        jwtToken: broker?.jwtToken,
        clientCode: broker?.clientCode,
        viewToken: broker?.viewToken,
        sid: broker?.sid,
        serverId: broker?.serverId,
      );

      debugPrint('[RebalanceReview] rebalanceCalculate status=${resp.statusCode}');
      debugPrint('[RebalanceReview] rebalanceCalculate body=${resp.body.length > 500 ? resp.body.substring(0, 500) : resp.body}');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);

        // Extract CA pending info (matching alphab2b)
        final caPending = data['caPendingInfo'];
        if (caPending is List && caPending.isNotEmpty) {
          _caPendingInfo = caPending.map((e) => Map<String, dynamic>.from(e)).toList();
        }

        // Extract unique_id for execution
        _calculatedUniqueId = data['uniqueId']?.toString();

        final result = _parseServerActions(data);
        if (result.isNotEmpty) return result;
        debugPrint('[RebalanceReview] Server returned empty buy/sell');
      }
    } catch (e) {
      debugPrint('[RebalanceReview] rebalanceCalculate error: $e');
    }
    return null;
  }

  /// Re-call server-side calculation with the actual connected broker.
  /// Called at execution time when the initial DummyBroker call failed.
  Future<List<_RebalanceAction>?> _tryServerSideCalculationWithBroker(
      BrokerConnection broker) async {
    try {
      String? modelId;
      if (widget.portfolio.rebalanceHistory.isNotEmpty) {
        modelId = widget.portfolio.rebalanceHistory.last.modelId;
      }
      modelId ??= widget.portfolio.strategyId ?? widget.portfolio.id;

      final advisor = widget.portfolio.advisor.isNotEmpty
          ? widget.portfolio.advisor
          : AqApiService.instance.advisorName;

      debugPrint('[RebalanceReview] Re-calling rebalanceCalculate with real broker=${broker.broker}');

      final resp = await AqApiService.instance.rebalanceCalculate(
        userEmail: widget.email,
        modelName: widget.portfolio.modelName,
        advisor: advisor,
        modelId: modelId,
        userBroker: broker.broker,
        userFund: '0',
        flag: _rebalanceFlag,
        apiKey: broker.apiKey,
        secretKey: broker.secretKey,
        jwtToken: broker.jwtToken,
        clientCode: broker.clientCode,
        viewToken: broker.viewToken,
        sid: broker.sid,
        serverId: broker.serverId,
      );

      debugPrint('[RebalanceReview] rebalanceCalculate (retry) status=${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        final result = _parseServerActions(data);
        if (result.isNotEmpty) return result;
      }
    } catch (e) {
      debugPrint('[RebalanceReview] rebalanceCalculate (retry) error: $e');
    }
    return null;
  }

  /// Parse server response from POST /rebalance/calculate.
  /// Handles two formats returned by the CCXT server:
  ///   Array format: { buy: [{symbol, quantity, exchange, price}], sell: [...] }
  ///   Object format: { buy: {"SYMBOL": qty}, sell: {"SYMBOL": qty} }
  /// Filters out CASH-EQ (not a real tradeable stock, per rgx_app).
  List<_RebalanceAction> _parseServerActions(Map<String, dynamic> data) {
    final List<_RebalanceAction> result = [];
    final rawBuy = data['buy'];
    final rawSell = data['sell'];

    void addActions(dynamic raw, _ActionType type) {
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final symbol = (item['symbol'] ?? '').toString();
          if (symbol.isEmpty || symbol.contains('CASH-EQ')) continue;
          result.add(_RebalanceAction(
            symbol: symbol,
            exchange: (item['exchange'] ?? (symbol.endsWith('-EQ') ? 'NSE' : 'BSE')).toString(),
            type: type,
            quantity: _toInt(item['quantity']) ?? 0,
            price: _toDouble(item['price']) ?? 0,
            token: item['token']?.toString(),
            isCaPending: item['isCaPending'] == true,
            zerodhaTradeId: item['zerodhaTradeId']?.toString(),
          ));
        }
      } else if (raw is Map) {
        for (final entry in raw.entries) {
          final symbol = entry.key.toString();
          if (symbol.isEmpty || symbol.contains('CASH-EQ')) continue;
          final qty = _toInt(entry.value) ?? 0;
          result.add(_RebalanceAction(
            symbol: symbol,
            exchange: symbol.endsWith('-EQ') ? 'NSE' : 'BSE',
            type: type,
            quantity: qty,
            price: 0,
          ));
        }
      }
    }

    addActions(rawSell, _ActionType.sell);
    addActions(rawBuy, _ActionType.buy);

    debugPrint('[RebalanceReview] Parsed server actions: ${result.length} (sell=${result.where((a) => a.type == _ActionType.sell).length}, buy=${result.where((a) => a.type == _ActionType.buy).length})');
    return result;
  }

  /// Client-side fallback when server calculation is unavailable.
  /// Unlike the old logic, this does NOT produce HOLD actions (matching rgx_app).
  /// For new subscribers (never executed), all stocks are BUY.
  List<_RebalanceAction> _computeClientSideActions(List<RebalanceHistoryEntry> history) {
    final latest = history.last;
    final previous = history.length > 1 ? history[history.length - 2] : null;

    // Check if user has ever executed a rebalance for this portfolio
    final execForUser = latest.getExecutionForUser(widget.email);
    final neverExecuted = execForUser == null ||
        execForUser.status.toLowerCase() == 'toexecute' ||
        execForUser.status.toLowerCase() == 'pending';

    final Map<String, PortfolioStock> previousStocks = {};
    if (previous != null) {
      for (final s in previous.adviceEntries) {
        previousStocks[s.symbol] = s;
      }
    }

    final latestMap = <String, PortfolioStock>{};
    for (final s in latest.adviceEntries) {
      latestMap[s.symbol] = s;
    }

    final allSymbols = <String>{
      ...latestMap.keys,
      ...previousStocks.keys,
    };

    final List<_RebalanceAction> computed = [];

    for (final symbol in allSymbols) {
      // Filter out CASH-EQ — not a real tradeable stock (same as rgx_app)
      if (symbol.contains('CASH-EQ')) continue;

      final inLatest = latestMap.containsKey(symbol);
      final inPrevious = previousStocks.containsKey(symbol);

      if (inLatest && !inPrevious) {
        // New stock → BUY
        computed.add(_RebalanceAction(
          symbol: symbol,
          exchange: latestMap[symbol]!.exchange ?? 'NSE',
          type: _ActionType.buy,
          quantity: 0,
          price: latestMap[symbol]!.price ?? 0,
        ));
      } else if (!inLatest && inPrevious) {
        // Removed stock → SELL
        computed.add(_RebalanceAction(
          symbol: symbol,
          exchange: previousStocks[symbol]?.exchange ?? 'NSE',
          type: _ActionType.sell,
          quantity: 0,
          price: previousStocks[symbol]?.price ?? 0,
        ));
      } else if (inLatest && inPrevious) {
        final newWeight = latestMap[symbol]!.weight;
        final oldWeight = previousStocks[symbol]?.weight ?? 0;
        final weightDiff = newWeight - oldWeight;

        if (neverExecuted && newWeight > 0) {
          // User never executed → they need to BUY everything in the portfolio
          computed.add(_RebalanceAction(
            symbol: symbol,
            exchange: latestMap[symbol]!.exchange ?? 'NSE',
            type: _ActionType.buy,
            quantity: 0,
            price: latestMap[symbol]!.price ?? 0,
          ));
        } else if (weightDiff > 0.01) {
          computed.add(_RebalanceAction(
            symbol: symbol,
            exchange: latestMap[symbol]!.exchange ?? 'NSE',
            type: _ActionType.buy,
            quantity: 0,
            price: latestMap[symbol]!.price ?? 0,
          ));
        } else if (weightDiff < -0.01) {
          computed.add(_RebalanceAction(
            symbol: symbol,
            exchange: latestMap[symbol]!.exchange ?? 'NSE',
            type: _ActionType.sell,
            quantity: 0,
            price: latestMap[symbol]!.price ?? 0,
          ));
        }
        // No HOLD — stocks with unchanged weight and already executed are
        // simply not shown, matching rgx_app behavior.
      }
    }

    // Sort: sells first, then buys
    computed.sort((a, b) {
      final order = {_ActionType.sell: 0, _ActionType.buy: 1};
      return (order[a.type] ?? 2).compareTo(order[b.type] ?? 2);
    });

    return computed;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Fetch full rebalance history with adviceEntries from the strategy
  /// details endpoint or subscribed-strategies endpoint.
  Future<List<RebalanceHistoryEntry>?> _fetchEnrichedHistory() async {
    // 1. Try strategy details endpoint (has full rebalanceHistory)
    try {
      CacheService.instance.invalidate('aq/model-portfolio/strategy:${widget.portfolio.modelName}');
      final resp = await AqApiService.instance.getStrategyDetails(widget.portfolio.modelName);
      debugPrint('[RebalanceReview] getStrategyDetails status=${resp.statusCode}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final raw = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final strategyPortfolio = ModelPortfolio.fromJson(raw);
        if (strategyPortfolio.rebalanceHistory.isNotEmpty &&
            strategyPortfolio.rebalanceHistory.last.adviceEntries.isNotEmpty) {
          debugPrint('[RebalanceReview] Got ${strategyPortfolio.rebalanceHistory.length} entries from strategy details, latest has ${strategyPortfolio.rebalanceHistory.last.adviceEntries.length} advice entries');
          return strategyPortfolio.rebalanceHistory;
        }
      }
    } catch (e) {
      debugPrint('[RebalanceReview] getStrategyDetails error: $e');
    }

    // 2. Fallback: try subscribed-strategies endpoint
    try {
      CacheService.instance.invalidate('aq/model-portfolio/subscribed:${widget.email}');
      final resp = await AqApiService.instance.getSubscribedStrategies(widget.email);
      debugPrint('[RebalanceReview] getSubscribedStrategies status=${resp.statusCode}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final List<dynamic> list = data is List
            ? data
            : (data is Map
                ? (data['subscribedPortfolios'] ?? data['data'] ?? data['strategies'] ?? [])
                : []);
        for (final item in list) {
          if (item is! Map) continue;
          final portfolio = ModelPortfolio.fromJson(Map<String, dynamic>.from(item));
          if (portfolio.modelName == widget.portfolio.modelName &&
              portfolio.rebalanceHistory.isNotEmpty &&
              portfolio.rebalanceHistory.last.adviceEntries.isNotEmpty) {
            debugPrint('[RebalanceReview] Got ${portfolio.rebalanceHistory.length} entries from subscribed-strategies, latest has ${portfolio.rebalanceHistory.last.adviceEntries.length} advice entries');
            return portfolio.rebalanceHistory;
          }
        }
      }
    } catch (e) {
      debugPrint('[RebalanceReview] getSubscribedStrategies error: $e');
    }

    debugPrint('[RebalanceReview] Could not fetch enriched rebalance history');
    return null;
  }

  Future<void> _executeRebalance() async {
    if (!termsAccepted) return;

    // --- DummyBroker mode: skip broker check, go directly to confirmation ---
    if (_isDummyBrokerMode) {
      await _executeDummyBrokerOrders();
      return;
    }

    // --- Broker pre-check ---
    final connectedBroker = await _checkBrokerConnection();
    if (connectedBroker == null || !mounted) return;

    // --- Funds check (matching alphab2b RebalanceCard.js fetchFunds) ---
    try {
      final fundsResp = await AqApiService.instance.fetchFunds(
        broker: connectedBroker.broker,
        email: widget.email,
        clientCode: connectedBroker.clientCode,
        apiKey: connectedBroker.apiKey,
        jwtToken: connectedBroker.jwtToken,
        secretKey: connectedBroker.secretKey,
        sid: connectedBroker.sid,
        serverId: connectedBroker.serverId,
      );
      if (fundsResp.statusCode == 200) {
        final fundsData = jsonDecode(fundsResp.body);
        final fundsStatus = fundsData['status'];
        // status 1 or 2 means token expired (matching alphab2b)
        if (fundsStatus == 1 || fundsStatus == 2) {
          if (mounted) {
            _fundsCheckFailed = true;
            await _showTokenExpiredDialog(connectedBroker.broker);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[RebalanceReview] fetchFunds error: $e');
      // Don't block execution if funds check fails
    }

    if (!mounted) return;

    // --- Validate broker match ---
    if (latestRebalance != null) {
      final execForUser = latestRebalance!.getExecutionForUser(widget.email);
      if (execForUser != null) {
        final execBroker = execForUser.userBroker ?? '';
        if (execBroker.isNotEmpty &&
            execBroker != 'DummyBroker' &&
            execBroker.toLowerCase() != connectedBroker.broker.toLowerCase()) {
          final proceed = await _showBrokerMismatchDialog(execBroker, connectedBroker.broker);
          if (proceed != true || !mounted) return;
        }
      }
    }

    // ── Re-compute with real broker (rgx_app calls /rebalance/calculate at
    //    execute time with the actual broker, not DummyBroker) ──
    List<_RebalanceAction> execActions = actions;
    if (!_serverCalculated) {
      // Initial page load failed to get server data — retry now with real broker.
      final freshActions = await _tryServerSideCalculationWithBroker(connectedBroker);
      if (freshActions != null && freshActions.isNotEmpty) {
        execActions = freshActions;
        _serverCalculated = true;
        if (mounted) setState(() => actions = freshActions);
      }
    }

    // Generate orders from actions.
    final orders = <Map<String, dynamic>>[];

    for (final action in execActions) {
      final qty = action.quantity > 0 ? action.quantity : (_serverCalculated ? 0 : 1);
      if (qty <= 0) continue;

      orders.add({
        'symbol': action.symbol,
        'exchange': action.exchange,
        'transactionType': action.type == _ActionType.buy ? 'BUY' : 'SELL',
        'quantity': qty,
        'orderType': 'MARKET',
        'productType': 'CNC',
        'price': action.price,
        if (action.token != null) 'token': action.token,
        if (action.isCaPending) 'isCaPending': true,
        if (action.zerodhaTradeId != null) 'zerodhaTradeId': action.zerodhaTradeId,
      });
    }

    if (orders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No trades required for this rebalance.")),
        );
      }
      return;
    }

    // --- CA Pending repair: verify shares credited at broker ---
    // (matching prod UpdateRebalanceModal.js checkCaPendingRepair)
    final caPendingOrders = orders.where((o) => o['isCaPending'] == true).toList();
    if (caPendingOrders.isNotEmpty && connectedBroker != null) {
      try {
        final symbols = caPendingOrders.map((o) => <String, String>{
          'symbol': (o['symbol'] ?? '').toString(),
          'exchange': (o['exchange'] ?? 'NSE').toString(),
        }).toList();

        final holdingsResp = await AqApiService.instance.checkBrokerHoldings(
          userEmail: widget.email,
          userBroker: connectedBroker.broker,
          symbols: symbols,
          apiKey: connectedBroker.apiKey,
          secretKey: connectedBroker.secretKey,
          accessToken: connectedBroker.jwtToken,
          clientCode: connectedBroker.clientCode,
        );

        if (holdingsResp.statusCode == 200 && mounted) {
          final data = jsonDecode(holdingsResp.body);
          final shortfall = data['shortfall'] ?? data['missing'] ?? [];
          if (shortfall is List && shortfall.isNotEmpty) {
            final proceed = await _showCaPendingShortfallDialog(shortfall);
            if (proceed != true || !mounted) return;
          }
        }
      } catch (e) {
        debugPrint('[RebalanceReview] checkBrokerHoldings error: $e');
      }
    }

    // --- Holdings validation: filter sell orders with 0 broker holdings ---
    final hasSellOrders = orders.any((o) => o['transactionType'] == 'SELL');
    if (hasSellOrders) {
      try {
        final holdingsResp = await AqApiService.instance.getBrokerHoldings(
          email: widget.email,
          broker: connectedBroker.broker,
        );
        if (holdingsResp.statusCode == 200) {
          final holdingsData = jsonDecode(holdingsResp.body);
          final holdingsList = _parseBrokerHoldings(holdingsData);

          final removedSymbols = <String>[];
          orders.removeWhere((order) {
            if (order['transactionType'] != 'SELL') return false;
            final sym = (order['symbol'] ?? '').toString();
            final held = holdingsList[sym] ?? holdingsList[_normalizeSymbol(sym)] ?? 0;
            if (held <= 0) {
              removedSymbols.add(sym);
              return true;
            }
            return false;
          });

          if (removedSymbols.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Removed ${removedSymbols.length} sell order(s) — not held in ${connectedBroker.broker}: "
                  "${removedSymbols.join(', ')}",
                ),
                duration: const Duration(seconds: 5),
                backgroundColor: Colors.orange.shade700,
              ),
            );
          }
        } else {
          // BUG FIX: Non-200 from holdings API → log warning but don't block.
          // The qty=0 guard above already filtered the worst cases.
          debugPrint(
              '[RebalanceReview] Holdings API returned ${holdingsResp.statusCode} '
              'for ${connectedBroker.broker} — relying on qty=0 pre-filter only.');
        }
      } catch (e) {
        debugPrint('[RebalanceReview] Holdings validation error: $e');
      }

      if (!mounted) return;

      if (orders.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No valid trades remaining after holdings check."),
          ),
        );
        return;
      }
    }

    // --- EDIS / DDPI / TPIN check for all brokers with sell orders ---
    final hasSellOrdersAfterFilter = orders.any((o) => o['transactionType'] == 'SELL');
    final brokerLower = connectedBroker.broker.toLowerCase();
    // DummyBroker doesn't need real EDIS authorization
    final needsEdisCheck = hasSellOrdersAfterFilter && brokerLower != 'dummybroker';

    if (needsEdisCheck) {
      // Work with a potentially-refreshed broker object.
      BrokerConnection effectiveBroker = connectedBroker;

      // For Zerodha: call save-ddpi-status so the server updates
      // is_authorized_for_sell based on today's TPIN session, then re-fetch
      // fresh broker data before deciding whether to show the auth page.
      if (brokerLower == 'zerodha' &&
          connectedBroker.apiKey != null &&
          connectedBroker.secretKey != null &&
          connectedBroker.jwtToken != null) {
        try {
          await AqApiService.instance.zerodhaSaveDdpiStatus(
            email: widget.email,
            apiKey: connectedBroker.apiKey!,
            secretKey: connectedBroker.secretKey!,
            accessToken: connectedBroker.jwtToken!,
          );
          // Re-fetch so we get the freshly-updated is_authorized_for_sell
          // and ddpi_status from the DB.
          final freshBroker = await _checkBrokerConnection();
          if (freshBroker != null) effectiveBroker = freshBroker;
        } catch (e) {
          debugPrint('[RebalanceReview] zerodhaSaveDdpiStatus error: $e');
        }
      }

      // Permanent DDPI (physical demat or DDPI POA) never expires.
      final hasPermanentDdpi = effectiveBroker.ddpiEnabled ||
          (effectiveBroker.ddpiStatus != null &&
              ['physical', 'ddpi'].contains(effectiveBroker.ddpiStatus!.toLowerCase()));

      // Determine if selling is authorized — matching prod UpdateRebalanceModal.js
      // per-broker EDIS/DDPI checks.
      bool canSell = false;

      if (brokerLower == 'zerodha') {
        // Zerodha: permanent DDPI or session-level TPIN authorization
        canSell = hasPermanentDdpi || effectiveBroker.isAuthorizedForSell;
      } else if (brokerLower == 'dhan') {
        // Dhan: live EDIS status check (matching prod dhanEdisStatus check)
        canSell = await _checkDhanEdisStatus(effectiveBroker);
      } else if (brokerLower == 'angel one' || brokerLower == 'angelone') {
        // Angel One: ddpi_enabled or is_authorized_for_sell
        canSell = effectiveBroker.ddpiEnabled || effectiveBroker.isAuthorizedForSell;
      } else if (brokerLower == 'fyers') {
        // Fyers: is_authorized_for_sell
        canSell = effectiveBroker.isAuthorizedForSell;
      } else {
        // Other brokers (AliceBlue, IIFL, ICICI, Upstox, Kotak, HDFC, Motilal, Groww):
        // is_authorized_for_sell
        canSell = effectiveBroker.isAuthorizedForSell;
      }

      if (!canSell) {
        if (!mounted) return;

        // Collect sell order details for brokers that need ISIN info (Dhan)
        final sellOrderDetails = orders
            .where((o) => o['transactionType'] == 'SELL')
            .toList();

        final edisResult = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => DdpiAuthPage(
              broker: effectiveBroker,
              sellOrders: sellOrderDetails,
              email: widget.email,
            ),
          ),
        );

        if (edisResult != true) {
          // User cancelled EDIS auth — abort execution
          return;
        }
        if (!mounted) return;
      }
    }

    // Resolve modelId from latest rebalance history
    String? modelId;
    if (widget.portfolio.rebalanceHistory.isNotEmpty) {
      modelId = widget.portfolio.rebalanceHistory.last.modelId;
    }
    modelId ??= widget.portfolio.id;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ExecutionStatusPage(
          portfolio: widget.portfolio,
          email: widget.email,
          orders: orders,
          modelId: modelId,
          modelName: widget.portfolio.modelName,
          advisor: widget.portfolio.advisor,
        ),
      ),
    );
  }

  /// Check broker connection before execution. Returns a connected broker or null.
  Future<BrokerConnection?> _checkBrokerConnection() async {
    try {
      CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
      final response = await AqApiService.instance.getConnectedBrokers(widget.email);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawData = data['data'];
        final List<dynamic> brokerList;
        if (rawData is List) {
          brokerList = rawData;
        } else if (rawData is Map) {
          brokerList = rawData['connected_brokers'] ?? [];
        } else {
          brokerList = data['connected_brokers'] ?? [];
        }
        final connected = brokerList
            .map((e) => BrokerConnection.fromJson(e))
            .where((b) => b.isEffectivelyConnected)
            .toList();

        if (connected.isNotEmpty) {
          return connected.first;
        }
      }
    } catch (e) {
      debugPrint('[RebalanceReview] _checkBrokerConnection error: $e');
    }

    // No connected broker — open broker selection modal
    if (!mounted) return null;
    final result = await BrokerSelectionPage.show(context, email: widget.email);
    return result;
  }

  /// Show warning dialog when execution broker doesn't match connected broker.
  Future<bool?> _showBrokerMismatchDialog(String executionBroker, String connectedBroker) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
            const SizedBox(width: 8),
            const Text("Broker Mismatch", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          "This rebalance was set up for $executionBroker, but you are "
          "currently connected to $connectedBroker.\n\n"
          "Orders will be placed through $connectedBroker.",
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Continue Anyway"),
          ),
        ],
      ),
    );
  }

  /// Show warning when CA pending stocks have a shortfall at broker.
  /// (matching prod UpdateRebalanceModal.js CA pending repair warning modal)
  Future<bool?> _showCaPendingShortfallDialog(List<dynamic> shortfall) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text("Shares Not Yet Credited", style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Some stocks from a recent corporate action have not been "
              "credited to your broker yet. Proceeding may result in rejected orders.",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 12),
            ...shortfall.take(5).map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                "\u2022 ${s is Map ? (s['symbol'] ?? s) : s}",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Proceed Anyway"),
          ),
        ],
      ),
    );
  }

  /// Live Dhan EDIS status check — matching prod UpdateRebalanceModal.js:
  ///   if (!dhanEdisStatus?.data?.length || dhanEdisStatus?.data?.some(h => h.edis === false))
  /// Returns true if all holdings are EDIS-authorized.
  Future<bool> _checkDhanEdisStatus(BrokerConnection broker) async {
    try {
      final clientId = broker.clientCode ?? '';
      final accessToken = broker.jwtToken ?? '';
      if (clientId.isEmpty || accessToken.isEmpty) return false;

      final resp = await AqApiService.instance.getDhanEdisStatus(
        clientId: clientId,
        accessToken: accessToken,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final holdings = data['data'];
        if (holdings == null || holdings is! List || holdings.isEmpty) {
          return false;
        }
        // If ANY holding has edis === false, authorization is needed
        return !holdings.any((h) => h is Map && h['edis'] == false);
      }
    } catch (e) {
      debugPrint('[RebalanceReview] Dhan EDIS status check error: $e');
    }
    return false;
  }

  /// Parse broker holdings response into a symbol → quantity map.
  Map<String, double> _parseBrokerHoldings(dynamic data) {
    final holdings = <String, double>{};
    List<dynamic> list = [];

    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = data['holdings'] ?? data['data'] ?? data['data']?['holdings'] ?? [];
      if (list.isEmpty && data['data'] is List) {
        list = data['data'];
      }
    }

    for (final h in list) {
      if (h is! Map) continue;
      final symbol = (h['tradingsymbol'] ?? h['tradingSymbol'] ?? h['symbol'] ?? '').toString();
      final qty = (h['quantity'] ?? h['qty'] ?? h['t1_quantity'] ?? 0);
      final dQty = (qty is num) ? qty.toDouble() : double.tryParse(qty.toString()) ?? 0;
      if (symbol.isNotEmpty) {
        holdings[symbol] = (holdings[symbol] ?? 0) + dQty;
        // Also store normalized version
        holdings[_normalizeSymbol(symbol)] = (holdings[_normalizeSymbol(symbol)] ?? 0) + dQty;
      }
    }
    return holdings;
  }

  /// Normalize a trading symbol: strip exchange suffixes like -EQ, .NS etc.
  String _normalizeSymbol(String symbol) {
    return symbol
        .replaceAll(RegExp(r'[-.]EQ$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.NS$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.BSE$', caseSensitive: false), '')
        .trim();
  }

  /// Execute orders in DummyBroker mode (matching alphab2b DummyBrokerHoldingConfirmation.js)
  /// User manually places trades and confirms here with editable prices/quantities.
  Future<void> _executeDummyBrokerOrders() async {
    final orders = <Map<String, dynamic>>[];

    for (final ed in _editableData) {
      final qty = (ed['editableQty'] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;

      orders.add({
        'symbol': ed['symbol'],
        'exchange': ed['exchange'] ?? 'NSE',
        'transactionType': ed['orderType'],
        'quantity': qty,
        'orderType': 'MARKET',
        'productType': 'CNC',
        'price': (ed['editablePrice'] as num?)?.toDouble() ?? 0,
        if ((ed['token'] ?? '').toString().isNotEmpty) 'token': ed['token'],
        if (ed['isCaPending'] == true) 'isCaPending': true,
        if ((ed['zerodhaTradeId'] ?? '').toString().isNotEmpty)
          'zerodhaTradeId': ed['zerodhaTradeId'],
      });
    }

    if (orders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No trades to execute.")),
        );
      }
      return;
    }

    String? modelId;
    if (widget.portfolio.rebalanceHistory.isNotEmpty) {
      modelId = widget.portfolio.rebalanceHistory.last.modelId;
    }
    modelId ??= widget.portfolio.id;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ExecutionStatusPage(
          portfolio: widget.portfolio,
          email: widget.email,
          orders: orders,
          modelId: modelId,
          modelName: widget.portfolio.modelName,
          advisor: widget.portfolio.advisor,
        ),
      ),
    );
  }

  /// Show token expired dialog (matching alphab2b setOpenTokenExpireModel)
  Future<void> _showTokenExpiredDialog(String broker) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.timer_off, color: Colors.red.shade600, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text("Session Expired", style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Text(
          "Your $broker session has expired. Please reconnect your broker to continue with trade execution.",
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (!mounted) return;
              final result = await BrokerSelectionPage.show(context, email: widget.email);
              if (result != null && mounted) {
                setState(() {
                  _connectedBroker = result;
                  _fundsCheckFailed = false;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Reconnect Broker"),
          ),
        ],
      ),
    );
  }

  /// Calculate total investment for DummyBroker mode
  /// (matching alphab2b UpdateRebalanceModal.js calculateTotalInvestment)
  double _calculateDummyBrokerTotal() {
    double total = 0;
    for (final ed in _editableData) {
      final price = (ed['editablePrice'] as num?)?.toDouble() ?? 0;
      final qty = (ed['editableQty'] as num?)?.toDouble() ?? 0;
      final investment = qty * price;
      if (ed['orderType'] == 'BUY') {
        total += investment;
      } else {
        total -= investment;
      }
    }
    return total < 0 ? 0 : total;
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Rebalance",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      // Rebalance header
                      _rebalanceHeader(),

                      // Execution status badges
                      if (_alreadyExecuted)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "This rebalance has already been executed.",
                                  style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_partiallyExecuted)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded, color: Colors.amber.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Partially executed. You can resume execution below.",
                                  style: TextStyle(fontSize: 13, color: Colors.amber.shade800, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Research report link
                      if (_researchReportLink != null && _researchReportLink!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: InkWell(
                            onTap: () {
                              // Open research report — could use url_launcher
                              debugPrint('[RebalanceReview] Research report: $_researchReportLink');
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.description_outlined, color: Colors.blue.shade700, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "View Research Report",
                                      style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Icon(Icons.open_in_new, color: Colors.blue.shade400, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // CA Pending Warning (matching alphab2b UpdateRebalanceModal.js)
                      if (_caPendingInfo.isNotEmpty) _caPendingWarning(),

                      // Corporate Action Upcoming Warnings
                      if (_upcomingSplits.isNotEmpty || _upcomingDividends.isNotEmpty)
                        _corporateActionWarning(),

                      // Summary
                      _summary(),
                      const SizedBox(height: 16),

                      // Actions list
                      _actionsSection(),
                      const SizedBox(height: 16),

                      // Rebalance history
                      _historySection(),
                      const SizedBox(height: 16),

                      // Terms
                      GestureDetector(
                        onTap: () => setState(() => termsAccepted = !termsAccepted),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: termsAccepted,
                              onChanged: (v) => setState(() => termsAccepted = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  "I have reviewed the rebalance changes and authorize "
                                  "the execution of these trades via my connected broker.",
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom CTA
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                        blurRadius: 10, offset: const Offset(0, -4))],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: termsAccepted ? _executeRebalance : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          _alreadyExecuted
                              ? "Already Executed"
                              : _partiallyExecuted
                                  ? "Resume Execution"
                                  : _isDummyBrokerMode
                                      ? "Confirm Manual Execution"
                                      : "Accept & Execute Rebalance",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// CA Pending Warning (matching alphab2b UpdateRebalanceModal.js)
  Widget _caPendingWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text("Corporate Action Pending",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Some stocks have pending corporate actions (splits/bonus). "
            "Shares may not have been credited to your broker yet.",
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800, height: 1.4),
          ),
          const SizedBox(height: 10),
          // CA pending table
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: const [
                      Expanded(flex: 2, child: Text("Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                      Expanded(child: Text("Ratio", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(child: Text("Expected", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(child: Text("Available", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(child: Text("Pending", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ..._caPendingInfo.map((ca) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(ca['symbol'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                      Expanded(child: Text(ca['ratio'] ?? '', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(child: Text('${ca['expected_qty'] ?? '-'}', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(child: Text('${ca['available_qty'] ?? '-'}', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(child: Text('${ca['pending_qty'] ?? '-'}',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Corporate Action Upcoming Warning (matching alphab2b UpdateRebalanceModal.js)
  Widget _corporateActionWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, size: 20, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Text("Upcoming Corporate Actions",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.amber.shade900)),
            ],
          ),
          const SizedBox(height: 10),
          if (_upcomingSplits.isNotEmpty) ...[
            Text("Stock Splits:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900)),
            const SizedBox(height: 4),
            ..._upcomingSplits.map((s) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                "\u2022 ${s['symbol']} — Ratio ${s['ratio']} on ${s['date']}",
                style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
              ),
            )),
          ],
          if (_upcomingDividends.isNotEmpty) ...[
            if (_upcomingSplits.isNotEmpty) const SizedBox(height: 6),
            Text("Dividends:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900)),
            const SizedBox(height: 4),
            ..._upcomingDividends.map((d) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                "\u2022 ${d['symbol']} — \u20B9${d['amount']} ex-date ${d['ex_date']}",
                style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _rebalanceHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, color: Colors.orange.shade700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.portfolio.modelName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800),
                  overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (latestRebalance?.rebalanceDate != null) ...[
            const SizedBox(height: 8),
            Text(
              "Rebalance date: ${DateFormat("dd MMM yyyy").format(latestRebalance!.rebalanceDate!)}",
              style: TextStyle(fontSize: 13, color: Colors.orange.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary() {
    final buyCount = actions.where((a) => a.type == _ActionType.buy).length;
    final sellCount = actions.where((a) => a.type == _ActionType.sell).length;

    return Row(
      children: [
        _summaryChip("BUY", buyCount, Colors.green),
        const SizedBox(width: 10),
        _summaryChip("SELL", sellCount, Colors.red),
      ],
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text("$count",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _actionsSection() {
    if (actions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("No rebalance actions available.",
            style: TextStyle(fontSize: 15, color: Colors.grey)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text("Proposed Changes",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (_isDummyBrokerMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text("Manual Mode",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                ),
            ],
          ),
          // DummyBroker note (matching alphab2b UpdateRebalanceModal.js selectNonBroker note)
          if (_isDummyBrokerMode) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Note: ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                  Expanded(
                    child: Text(
                      "Requires \u20B9${NumberFormat('#,##,###.##').format(_calculateDummyBrokerTotal())} in your broker. "
                      "Execute manually and confirm below.",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Table header for DummyBroker editable mode
          if (_isDummyBrokerMode) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: Text("Stock",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  const Expanded(flex: 2, child: Text("Price (\u20B9)",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                  const Expanded(flex: 2, child: Text("Qty",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                ],
              ),
            ),
            ...actions.asMap().entries.map((entry) => _editableActionRow(entry.key, entry.value)),
          ] else
            ...actions.map((action) => _actionRow(action)),
        ],
      ),
    );
  }

  /// Editable action row for DummyBroker mode
  /// (matching alphab2b UpdateRebalanceModal.js editable price/qty inputs)
  Widget _editableActionRow(int index, _RebalanceAction action) {
    final color = action.type == _ActionType.buy ? Colors.green : Colors.red;
    final label = action.type == _ActionType.buy ? "BUY" : "SELL";
    final editable = index < _editableData.length ? _editableData[index] : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.symbol,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
                Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                if (action.isCaPending)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text("Split Pending",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: TextEditingController(
                  text: editable != null ? (editable['editablePrice'] as num).toStringAsFixed(2) : '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                onChanged: (val) {
                  final price = double.tryParse(val) ?? 0;
                  if (index < _editableData.length) {
                    setState(() => _editableData[index]['editablePrice'] = price);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: TextEditingController(
                  text: editable != null ? '${editable['editableQty']}' : '0',
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                onChanged: (val) {
                  final qty = int.tryParse(val) ?? 0;
                  if (index < _editableData.length) {
                    setState(() => _editableData[index]['editableQty'] = qty);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(_RebalanceAction action) {
    Color color;
    IconData icon;
    String label;
    switch (action.type) {
      case _ActionType.buy:
        color = Colors.green;
        icon = Icons.add_circle;
        label = "BUY";
        break;
      case _ActionType.sell:
        color = Colors.red;
        icon = Icons.remove_circle;
        label = "SELL";
        break;
    }

    final qtyText = action.quantity > 0 ? 'Qty: ${action.quantity}' : action.exchange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.symbol,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text("$qtyText${action.price > 0 ? ' | \u20B9${action.price.toStringAsFixed(2)}' : ''}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _historySection() {
    final history = widget.portfolio.rebalanceHistory;
    if (history.length <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Rebalance History",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...history.reversed.take(5).map((entry) {
            final exec = entry.getExecutionForUser(widget.email);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: exec?.isExecuted == true ? Colors.green : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.rebalanceDate != null
                          ? DateFormat("dd MMM yyyy").format(entry.rebalanceDate!)
                          : "Unknown date",
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    "${entry.adviceEntries.length} stocks",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    exec?.status ?? "—",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: exec?.isExecuted == true ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

enum _ActionType { buy, sell }

class _RebalanceAction {
  final String symbol;
  final String exchange;
  final _ActionType type;
  final int quantity;   // Server-computed quantity (0 = not yet computed)
  final double price;
  final String? token;  // Zerodha instrument token
  final bool isCaPending; // Corporate action pending flag
  final String? zerodhaTradeId; // For Zerodha basket repair

  _RebalanceAction({
    required this.symbol,
    required this.exchange,
    required this.type,
    required this.quantity,
    required this.price,
    this.token,
    this.isCaPending = false,
    this.zerodhaTradeId,
  });
}
