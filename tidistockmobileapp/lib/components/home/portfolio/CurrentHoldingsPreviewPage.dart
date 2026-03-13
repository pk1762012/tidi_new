import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:tidistockmobileapp/widgets/step_progress_bar.dart';

import 'RebalanceReviewPage.dart';

/// Matches prod MPStatusModal.js — shows current holdings with view/edit/confirmFailed
/// modes before proceeding to the rebalance review page (Step 2 of the flow).
///
/// Flow (matching prod RebalanceCard.js):
///   Step 1: Rebalance Preference (shown before navigating here)
///   Step 2: Current Holdings (THIS page) — view/edit/confirm
///   Step 3: Final Rebalance (RebalanceReviewPage)
class CurrentHoldingsPreviewPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;

  /// Rebalance preference selected in Step 1.
  /// 0 = full rebalance, 1 = 2% threshold.
  final int rebalanceFlag;

  /// When true, opens directly in confirmFailed mode.
  final bool isConfirmingFailed;

  /// When true, opens directly in edit mode.
  final bool openedFromEdit;

  /// Broker name for the user.
  final String? userBroker;

  /// Optional callbacks for custom navigation.
  final VoidCallback? onProceed;
  final String? proceedLabel;

  const CurrentHoldingsPreviewPage({
    super.key,
    required this.portfolio,
    required this.email,
    this.rebalanceFlag = 0,
    this.isConfirmingFailed = false,
    this.openedFromEdit = false,
    this.userBroker,
    this.onProceed,
    this.proceedLabel,
  });

  @override
  State<CurrentHoldingsPreviewPage> createState() =>
      _CurrentHoldingsPreviewPageState();
}

/// Internal stock item matching prod MPStatusModal localStockList shape.
class _StockItem {
  String symbol;
  String exchange;
  int quantity;
  double avgPrice;
  double ltp;
  String transactionType; // BUY or SELL
  String orderStatus;
  String rebalanceStatus;

  _StockItem({
    required this.symbol,
    this.exchange = 'NSE',
    required this.quantity,
    required this.avgPrice,
    this.ltp = 0,
    this.transactionType = 'BUY',
    this.orderStatus = 'complete',
    this.rebalanceStatus = 'success',
  });

  bool get isFailed =>
      const ['REJECTED', 'rejected', 'Rejected', 'cancelled', 'CANCELLED', 'Cancelled']
          .contains(orderStatus) ||
      const ['failed', 'failure'].contains(rebalanceStatus);

  double get investedValue => avgPrice * quantity;
  double get currentValue => ltp > 0 ? ltp * quantity : investedValue;
  double get pnl => currentValue - investedValue;
  double get pnlPct => investedValue > 0 ? (pnl / investedValue) * 100 : 0;

  Map<String, dynamic> toApiJson() => {
        'symbol': symbol,
        'exchange': exchange,
        'quantity': quantity.toString(),
        'filledShares': quantity.toString(),
        'transactionType': transactionType,
        'averageEntryPrice': avgPrice,
        'averagePrice': avgPrice,
        'orderStatus': orderStatus,
        'rebalance_status': rebalanceStatus,
        'uniqueOrderId': '',
        'orderId': '',
        'productType': 'DELIVERY',
        'orderType': 'MARKET',
        'user_broker': '',
      };
}

enum _ViewMode { viewing, editing, confirmFailed }

class _CurrentHoldingsPreviewPageState
    extends State<CurrentHoldingsPreviewPage> {
  List<_StockItem> _stocks = [];
  bool _loading = true;
  String? _portfolioDocId;
  _ViewMode _viewMode = _ViewMode.viewing;
  bool _isUpdating = false;
  String? _error;
  String? _successMessage;

  // Confirm-failed state: index → confirmed
  Map<int, bool> _confirmedStocks = {};

  // Add stock form
  final _symbolController = TextEditingController();
  final _addQtyController = TextEditingController();
  final _addPriceController = TextEditingController();
  String _addExchange = '';
  bool _symbolSelected = false;
  List<Map<String, dynamic>> _symbolResults = [];
  bool _symbolSearching = false;
  Timer? _searchDebounce;

  final _currencyFmt = NumberFormat('#,##,###');

  @override
  void initState() {
    super.initState();
    if (widget.isConfirmingFailed) {
      _viewMode = _ViewMode.confirmFailed;
    } else if (widget.openedFromEdit) {
      _viewMode = _ViewMode.editing;
    }
    _fetchHoldings();
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _addQtyController.dispose();
    _addPriceController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data Fetching (matches prod MPStatusModal fetchUserPortfolio)
  // ---------------------------------------------------------------------------

  Future<void> _fetchHoldings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Primary: user-portfolio/latest
    try {
      final response = await AqApiService.instance.getLatestUserPortfolio(
        email: widget.email,
        modelName: widget.portfolio.modelName,
      );
      debugPrint('[MPStatus] getLatestUserPortfolio status=${response.statusCode}');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final innerData = data is Map ? data['data'] : null;

        if (innerData is Map) {
          // Extract portfolio doc ID (matches prod _id.$oid)
          final idField = innerData['_id'];
          if (idField is Map && idField['\$oid'] != null) {
            _portfolioDocId = idField['\$oid'].toString();
          } else if (idField is String) {
            _portfolioDocId = idField;
          }

          final userNetPf = innerData['user_net_pf_model'];
          List<dynamic> orderResults = [];

          if (userNetPf is List && userNetPf.isNotEmpty) {
            // Sort by execDate to get latest (matches prod)
            final sorted = List<dynamic>.from(userNetPf);
            sorted.sort((a, b) {
              final dateA = a is Map ? (a['execDate'] ?? '') : '';
              final dateB = b is Map ? (b['execDate'] ?? '') : '';
              return dateB.toString().compareTo(dateA.toString());
            });
            final latest = sorted.first;
            if (latest is Map) {
              orderResults = latest['order_results'] ?? latest['stocks'] ?? [];
            }
          } else if (userNetPf is Map) {
            orderResults = userNetPf['order_results'] ?? userNetPf['stocks'] ?? [];
          }

          if (orderResults.isNotEmpty) {
            _parseOrderResults(orderResults);
            // Cross-reference with live broker holdings (matching prod
            // handleCheckStatus: finalQty = Math.min(modelQty, brokerQty))
            await _capHoldingsAtBrokerQty();
            if (mounted) setState(() => _loading = false);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[MPStatus] getLatestUserPortfolio error: $e');
    }

    // Fallback: subscription-raw-amount
    try {
      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: widget.email,
        modelName: widget.portfolio.modelName,
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final subData = data is Map ? data['data'] : null;
        if (subData is Map) {
          _parseSubscriptionData(subData as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[MPStatus] getSubscriptionRawAmount error: $e');
    }

    // Cross-reference with live broker holdings for fallback path too
    await _capHoldingsAtBrokerQty();

    if (mounted) setState(() => _loading = false);
  }

  /// Cross-reference model holdings with live broker holdings.
  /// Matches prod handleCheckStatus() in RebalanceCard.js:
  ///   1. Fetch live broker holdings via fetchAllHoldings()
  ///   2. Build brokerMap keyed by symbol|exchange
  ///   3. For each model holding: finalQty = Math.min(modelQty, brokerQty)
  ///   4. If stock not in broker → qty = 0 → filtered out
  Future<void> _capHoldingsAtBrokerQty() async {
    if (widget.userBroker == null ||
        widget.userBroker!.toLowerCase() == 'dummybroker' ||
        _stocks.isEmpty) return;

    try {
      // Fetch broker credentials (matching prod: uses stored broker state)
      final brokerResp = await AqApiService.instance.getConnectedBrokers(widget.email);
      if (brokerResp.statusCode != 200) return;

      final brokerData = jsonDecode(brokerResp.body);
      final connections = BrokerConnection.parseApiResponse(brokerData);
      final broker = connections
          .where((b) => b.isEffectivelyConnected && b.broker == widget.userBroker)
          .firstOrNull;
      if (broker == null || broker.jwtToken == null) return;

      // Fetch live broker holdings (matching prod fetchAllHoldings)
      final holdingsResp = await AqApiService.instance.fetchAllHoldings(
        broker: broker.broker,
        userEmail: widget.email,
        jwtToken: broker.jwtToken,
        clientCode: broker.clientCode,
        sid: broker.sid,
        serverId: broker.serverId,
      );
      if (holdingsResp.statusCode != 200 || !mounted) return;

      final holdingsData = jsonDecode(holdingsResp.body);

      // Handle different response structures from various brokers
      // (matching prod handleCheckStatus lines 326-335)
      List<dynamic> brokerHoldings = [];
      if (holdingsData is List) {
        brokerHoldings = holdingsData;
      } else if (holdingsData is Map) {
        if (holdingsData['data'] is List) {
          brokerHoldings = holdingsData['data'];
        } else if (holdingsData['holdings'] is List) {
          brokerHoldings = holdingsData['holdings'];
        } else if (holdingsData['holding'] is List) {
          brokerHoldings = holdingsData['holding'];
        }
      }

      if (brokerHoldings.isEmpty) {
        // Broker has no holdings at all — clear everything
        _stocks.clear();
        if (mounted) setState(() {});
        debugPrint('[MPStatus] Broker has 0 holdings — cleared all model holdings');
        return;
      }

      // Build broker map keyed by SYMBOL|EXCHANGE (matching prod lines 339-347)
      final brokerMap = <String, int>{};
      for (final bh in brokerHoldings) {
        if (bh is! Map) continue;
        final sym = (bh['symbol'] ?? bh['tradingSymbol'] ?? bh['tradingsymbol'] ?? '')
            .toString().toUpperCase();
        final exch = (bh['exchange'] ?? 'NSE').toString().toUpperCase();
        final qty = bh['quantity'] ?? bh['qty'] ?? 0;
        final iQty = (qty is num) ? qty.toInt() : int.tryParse(qty.toString()) ?? 0;
        if (iQty > 0) {
          brokerMap['$sym|$exch'] = (brokerMap['$sym|$exch'] ?? 0) + iQty;
        }
      }

      // For each model holding, cap at broker's actual quantity
      // (matching prod lines 350-364)
      for (final stock in _stocks) {
        final sym = stock.symbol.toUpperCase();
        final exch = stock.exchange.toUpperCase();
        final key = '$sym|$exch';
        final brokerQty = brokerMap[key];

        if (brokerQty != null) {
          // Take the lower of model qty and broker qty
          if (brokerQty < stock.quantity) {
            stock.quantity = brokerQty;
          }
        } else {
          // Stock not in broker at all — user may have sold it entirely
          stock.quantity = 0;
        }
      }
      // Remove stocks with 0 or negative quantity (matching prod .filter(h => Number(h.quantity) > 0))
      _stocks.removeWhere((s) => s.quantity <= 0);

      if (mounted) setState(() {});
      debugPrint('[MPStatus] After broker cross-ref: ${_stocks.length} holdings remain');
    } catch (e) {
      debugPrint('[MPStatus] _capHoldingsAtBrokerQty error: $e');
      // On error, fall back to model data as-is (matching prod catch block)
    }
  }

  void _parseOrderResults(List<dynamic> orderResults) {
    final parsed = <_StockItem>[];
    for (final item in orderResults) {
      if (item is! Map) continue;
      final symbol = (item['symbol'] ?? item['tradingSymbol'] ?? '').toString();
      if (symbol.isEmpty || symbol.contains('CASH')) continue;

      final qty = item['quantity'] ?? item['qty'] ?? item['filledShares'] ?? 0;
      final quantity = qty is num ? qty.toInt() : int.tryParse(qty.toString()) ?? 0;
      final avgPrice = _toDouble(item['averageEntryPrice'] ?? item['averagePrice'] ??
          item['average_price'] ?? item['avgPrice'] ?? item['price'] ?? 0);
      final ltp = _toDouble(item['ltp'] ?? item['lastPrice'] ?? item['currentPrice'] ?? 0);
      final exchange = (item['exchange'] ?? 'NSE').toString();
      final txnType = (item['transactionType'] ?? 'BUY').toString();
      final orderStatus = (item['orderStatus'] ?? 'complete').toString();
      final rebalStatus = (item['rebalance_status'] ?? 'success').toString();

      parsed.add(_StockItem(
        symbol: symbol,
        exchange: exchange,
        quantity: quantity,
        avgPrice: avgPrice,
        ltp: ltp,
        transactionType: txnType,
        orderStatus: orderStatus,
        rebalanceStatus: rebalStatus,
      ));
    }

    // For confirmFailed: show all. For viewing: filter out failed.
    final display = _viewMode == _ViewMode.confirmFailed
        ? parsed
        : parsed.where((s) => !s.isFailed).toList();

    // Init confirmed map for failed stocks
    if (_viewMode == _ViewMode.confirmFailed) {
      _confirmedStocks = {};
      for (int i = 0; i < parsed.length; i++) {
        if (parsed[i].isFailed) {
          _confirmedStocks[i] = false;
        }
      }
    }

    setState(() => _stocks = display);
  }

  void _parseSubscriptionData(Map<String, dynamic> subData) {
    final userNetPf = subData['user_net_pf_model'] ??
        subData['net_pf_model'] ??
        subData['holdings'] ?? [];

    final parsed = <_StockItem>[];
    if (userNetPf is List && userNetPf.isNotEmpty) {
      final latest = userNetPf.last;
      List<dynamic> stockList = [];
      if (latest is List) {
        stockList = latest;
      } else if (latest is Map) {
        stockList = latest['stocks'] ?? latest['holdings'] ?? latest['order_results'] ?? [];
      }
      for (final s in stockList) {
        if (s is! Map) continue;
        final symbol = (s['symbol'] ?? '').toString();
        if (symbol.isEmpty || symbol.contains('CASH')) continue;
        final qty = s['quantity'] ?? s['qty'] ?? 0;
        parsed.add(_StockItem(
          symbol: symbol,
          exchange: (s['exchange'] ?? 'NSE').toString(),
          quantity: qty is num ? qty.toInt() : int.tryParse(qty.toString()) ?? 0,
          avgPrice: _toDouble(s['avgPrice'] ?? s['averagePrice'] ?? s['price'] ?? 0),
          ltp: _toDouble(s['ltp'] ?? s['lastPrice'] ?? 0),
        ));
      }
    }
    setState(() => _stocks = parsed);
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------------

  double get _totalInvested => _stocks.fold(0, (s, i) => s + i.investedValue);
  double get _totalCurrent => _stocks.fold(0, (s, i) => s + i.currentValue);
  double get _totalPnl => _totalCurrent - _totalInvested;
  double get _totalPnlPct =>
      _totalInvested > 0 ? (_totalPnl / _totalInvested) * 100 : 0;

  // ---------------------------------------------------------------------------
  // Edit Mode Actions (matches prod MPStatusModal)
  // ---------------------------------------------------------------------------

  void _handleQuantityChange(int index, String value) {
    final qty = int.tryParse(value) ?? 0;
    if (qty >= 0 && index < _stocks.length) {
      setState(() => _stocks[index].quantity = qty);
    }
  }

  void _handlePriceChange(int index, String value) {
    final price = double.tryParse(value) ?? 0;
    if (price >= 0 && index < _stocks.length) {
      setState(() {
        _stocks[index].avgPrice = price;
      });
    }
  }

  void _handleDeleteStock(int index) {
    if (index < _stocks.length) {
      setState(() => _stocks.removeAt(index));
    }
  }

  // Symbol search (matches prod MPStatusModal symbol autocomplete)
  void _onSymbolSearch(String query) {
    _symbolSelected = false;
    _symbolResults = [];
    _searchDebounce?.cancel();
    if (query.length < 3) {
      setState(() => _symbolResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _symbolSearching = true);
      try {
        final resp = await AqApiService.instance.searchSymbol(query);
        if (resp.statusCode == 200 && mounted) {
          final data = jsonDecode(resp.body);
          final matches = data['match'];
          if (matches is List) {
            setState(() {
              _symbolResults = matches
                  .map((m) => Map<String, dynamic>.from(m))
                  .take(10)
                  .toList();
            });
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _symbolSearching = false);
    });
  }

  void _selectSymbol(Map<String, dynamic> match) {
    setState(() {
      _symbolController.text = match['symbol']?.toString() ?? '';
      _addExchange = match['segment']?.toString() ?? match['exchange']?.toString() ?? 'NSE';
      _symbolSelected = true;
      _symbolResults = [];
    });
  }

  void _handleAddStock() {
    final symbol = _symbolController.text.trim();
    final qty = int.tryParse(_addQtyController.text) ?? 0;
    final price = double.tryParse(_addPriceController.text) ?? 0;

    if (symbol.isEmpty || !_symbolSelected || qty <= 0 || price < 0) {
      setState(() => _error = 'Please fill all fields correctly');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _error = null);
      });
      return;
    }

    setState(() {
      _stocks.add(_StockItem(
        symbol: symbol,
        exchange: _addExchange.isNotEmpty ? _addExchange : 'NSE',
        quantity: qty,
        avgPrice: price,
        orderStatus: 'complete',
        rebalanceStatus: 'success',
      ));
      _symbolController.clear();
      _addQtyController.clear();
      _addPriceController.clear();
      _addExchange = '';
      _symbolSelected = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Save / Confirm API Calls (matches prod MPStatusModal)
  // ---------------------------------------------------------------------------

  Future<void> _saveEditedPortfolio() async {
    if (_portfolioDocId == null) {
      setState(() => _error = 'Portfolio document not found. Try refreshing.');
      return;
    }
    setState(() => _isUpdating = true);

    try {
      final orderResults = _stocks.map((s) => s.toApiJson()).toList();
      final resp = await AqApiService.instance.updateUserPortfolioLatest(
        portfolioDocId: _portfolioDocId!,
        modelName: widget.portfolio.modelName,
        email: widget.email,
        orderResults: orderResults,
        userBroker: widget.userBroker ?? 'DummyBroker',
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() {
          _successMessage = 'Portfolio updated successfully';
          _viewMode = _ViewMode.viewing;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _successMessage = null);
        });
      } else {
        setState(() => _error = 'Failed to update portfolio');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    }

    setState(() => _isUpdating = false);
  }

  Future<void> _confirmFailedOrders() async {
    if (_portfolioDocId == null) {
      setState(() => _error = 'Portfolio document not found.');
      return;
    }
    setState(() => _isUpdating = true);

    try {
      // Collect confirmed failed stocks
      final confirmedPortfolio = <Map<String, dynamic>>[];
      for (final entry in _confirmedStocks.entries) {
        if (entry.value && entry.key < _stocks.length) {
          final s = _stocks[entry.key];
          confirmedPortfolio.add({
            'symbol': s.symbol,
            'exchange': s.exchange,
            'transactionType': s.transactionType,
            'filledShares': s.quantity,
            'averagePrice': s.avgPrice,
          });
        }
      }

      final allConfirmed = _confirmedStocks.values.every((v) => v);
      final resp = await AqApiService.instance.confirmManualOrders(
        email: widget.email,
        portfolioDocId: _portfolioDocId!,
        updatedPortfolio: confirmedPortfolio,
        advisor: widget.portfolio.advisor.isNotEmpty
            ? widget.portfolio.advisor
            : AqApiService.instance.advisorName,
        modelName: widget.portfolio.modelName,
        userBroker: widget.userBroker ?? 'DummyBroker',
        allOrdersComplete: allConfirmed,
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() => _successMessage = 'Orders confirmed successfully');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        setState(() => _error = 'Failed to confirm orders');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    }

    setState(() => _isUpdating = false);
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _proceedToRebalance() {
    if (widget.onProceed != null) {
      widget.onProceed!();
    } else {
      // Pass held symbols to Step 3 so it can filter sell orders for unheld stocks
      // (matching prod flow where handleCheckStatus validates holdings before rebalance)
      final heldSymbols = _stocks.map((s) => s.symbol.toUpperCase()).toSet();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RebalanceReviewPage(
            portfolio: widget.portfolio,
            email: widget.email,
            rebalanceFlag: widget.rebalanceFlag,
            heldSymbols: heldSymbols,
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: Column(
        children: [
          // Step progress bar (Step 2 active)
          const StepProgressBar(currentStep: 2),
          _buildHeader(),
          // Messages
          if (_error != null) _messageBanner(_error!, Colors.red),
          if (_successMessage != null) _messageBanner(_successMessage!, Colors.green),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchHoldings,
                    child: _stocks.isEmpty
                        ? _buildEmptyState()
                        : _viewMode == _ViewMode.editing
                            ? _buildEditList()
                            : _viewMode == _ViewMode.confirmFailed
                                ? _buildConfirmFailedList()
                                : _buildViewList(),
                  ),
          ),
          _buildBottomCta(),
        ],
      ),
    );
  }

  Widget _messageBanner(String message, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            color == Colors.red ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (_viewMode == _ViewMode.editing) {
                    setState(() => _viewMode = _ViewMode.viewing);
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: const Icon(Icons.arrow_back, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _viewMode == _ViewMode.editing
                          ? 'Edit Holdings'
                          : _viewMode == _ViewMode.confirmFailed
                              ? 'Confirm Failed Orders'
                              : 'Current Holdings',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      widget.portfolio.modelName,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF757575)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Edit button in view mode (matches prod MPStatusModal "Edit Portfolio Holdings")
              if (_viewMode == _ViewMode.viewing && _stocks.isNotEmpty)
                IconButton(
                  onPressed: () => setState(() => _viewMode = _ViewMode.editing),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit Portfolio Holdings',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                  ),
                ),
            ],
          ),
          if (!_loading && _totalInvested > 0 && _viewMode != _ViewMode.editing) ...[
            const SizedBox(height: 12),
            _buildSummaryCard(),
          ],
          // Description text matching prod step description
          if (!_loading) ...[
            const SizedBox(height: 8),
            Text(
              _viewMode == _ViewMode.editing
                  ? 'Edit quantities and prices. Add or remove stocks as needed.'
                  : _viewMode == _ViewMode.confirmFailed
                      ? 'Confirm the failed orders that you have manually placed in your broker.'
                      : 'Verify your current stock holdings. If any information appears inaccurate, tap edit to update.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final isProfit = _totalPnl >= 0;
    final pnlColor = isProfit ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryItem(
              'Invested',
              '₹${_currencyFmt.format(_totalInvested.round())}',
              const Color(0xFF424242),
            ),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFE0E0E0)),
          Expanded(
            child: _summaryItem(
              'Current',
              '₹${_currencyFmt.format(_totalCurrent.round())}',
              const Color(0xFF424242),
            ),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFE0E0E0)),
          Expanded(
            child: _summaryItem(
              'P&L',
              '${isProfit ? '+' : ''}${_totalPnlPct.toStringAsFixed(1)}%',
              pnlColor,
              subtitle: '${isProfit ? '+' : ''}₹${_currencyFmt.format(_totalPnl.abs().round())}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color valueColor, {String? subtitle}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: valueColor)),
        if (subtitle != null)
          Text(subtitle, style: TextStyle(fontSize: 10, color: valueColor)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW MODE LIST (matches prod MPStatusModal viewing mode)
  // ---------------------------------------------------------------------------

  Widget _buildViewList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _stocks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildViewListHeader();
        return _buildViewCard(_stocks[index - 1]);
      },
    );
  }

  Widget _buildViewListHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${_stocks.length} Holding${_stocks.length != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
            ),
          ),
          const Expanded(flex: 2, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF757575)))),
          const Expanded(flex: 2, child: Text('LTP', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Color(0xFF757575)))),
          const Expanded(flex: 3, child: Text('P&L', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Color(0xFF757575)))),
        ],
      ),
    );
  }

  Widget _buildViewCard(_StockItem s) {
    final isProfit = s.pnl >= 0;
    final pnlColor = isProfit ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.symbol, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                Text(s.exchange, style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E))),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${s.quantity}', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF424242))),
          ),
          Expanded(
            flex: 2,
            child: Text(
              s.ltp > 0 ? '₹${s.ltp.toStringAsFixed(2)}' : '—',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Color(0xFF424242)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.ltp > 0 ? '${isProfit ? '+' : ''}${s.pnlPct.toStringAsFixed(1)}%' : '—',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pnlColor),
                ),
                if (s.ltp > 0)
                  Text(
                    '${isProfit ? '+' : '-'}₹${_currencyFmt.format(s.pnl.abs().round())}',
                    style: TextStyle(fontSize: 10, color: pnlColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EDIT MODE LIST (matches prod MPStatusModal editing mode)
  // ---------------------------------------------------------------------------

  Widget _buildEditList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        // Existing stocks
        for (int i = 0; i < _stocks.length; i++) _buildEditCard(i, _stocks[i]),
        const SizedBox(height: 16),
        // Add new stock section
        _buildAddStockSection(),
      ],
    );
  }

  Widget _buildEditCard(int index, _StockItem s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(s.exchange, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                  ],
                ),
              ),
              if (s.ltp > 0)
                Text('LTP: ₹${s.ltp.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _handleDeleteStock(index),
                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFC62828)),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: '${s.quantity}'),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) => _handleQuantityChange(index, v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: s.avgPrice.toStringAsFixed(2)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Entry Price',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) => _handlePriceChange(index, v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddStockSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add New Stock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1565C0))),
          const SizedBox(height: 12),
          // Symbol search
          TextField(
            controller: _symbolController,
            decoration: InputDecoration(
              labelText: 'Search Symbol (min 3 chars)',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: const OutlineInputBorder(),
              suffixIcon: _symbolSearching
                  ? const SizedBox(width: 20, height: 20, child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ))
                  : null,
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: _onSymbolSearch,
          ),
          // Search results dropdown
          if (_symbolResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _symbolResults.length,
                itemBuilder: (ctx, i) {
                  final m = _symbolResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(m['symbol']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(m['name']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                    trailing: Text(m['segment']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
                    onTap: () => _selectSymbol(m),
                  );
                },
              ),
            ),
          if (_addExchange.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Exchange: $_addExchange', style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Entry Price',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _addQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _symbolSelected ? _handleAddStock : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Stock'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFBDBDBD),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONFIRM FAILED MODE LIST (matches prod MPStatusModal confirmFailed mode)
  // ---------------------------------------------------------------------------

  Widget _buildConfirmFailedList() {
    final failedCount = _confirmedStocks.length;
    final confirmedCount = _confirmedStocks.values.where((v) => v).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        // Confirmation counter
        if (failedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '$confirmedCount of $failedCount confirmed',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
            ),
          ),
        for (int i = 0; i < _stocks.length; i++) _buildConfirmCard(i, _stocks[i]),
      ],
    );
  }

  Widget _buildConfirmCard(int index, _StockItem s) {
    final isFailed = _confirmedStocks.containsKey(index);
    final isConfirmed = _confirmedStocks[index] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFailed
            ? (isConfirmed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0))
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFailed
              ? (isConfirmed ? const Color(0xFF81C784) : const Color(0xFFFFCC80))
              : const Color(0xFFE8E8E8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.symbol, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: s.transactionType == 'BUY'
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        s.transactionType,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: s.transactionType == 'BUY'
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                    if (isFailed && !isConfirmed)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Failed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFC62828))),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${s.exchange} | Qty: ${s.quantity} | ₹${s.avgPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
              ],
            ),
          ),
          if (isFailed)
            TextButton(
              onPressed: () {
                setState(() => _confirmedStocks[index] = !isConfirmed);
              },
              style: TextButton.styleFrom(
                backgroundColor: isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFFF5F5F5),
                foregroundColor: isConfirmed ? Colors.white : const Color(0xFF424242),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConfirmed) const Icon(Icons.check, size: 14),
                  if (isConfirmed) const SizedBox(width: 4),
                  Text(isConfirmed ? 'Confirmed' : 'Confirm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, size: 36, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 16),
              const Text('No Holdings Yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'This will be your initial investment in this portfolio. Review the recommended stocks below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF757575), height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom CTA (changes per mode)
  // ---------------------------------------------------------------------------

  Widget _buildBottomCta() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFEEEEEE))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _viewMode == _ViewMode.editing
            ? _buildEditCta()
            : _viewMode == _ViewMode.confirmFailed
                ? _buildConfirmFailedCta()
                : _buildViewCta(),
      ),
    );
  }

  Widget _buildViewCta() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFE082)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFFF9A825)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _stocks.isEmpty
                      ? 'Review the rebalance recommendations on the next screen.'
                      : 'If holdings match your broker, tap "Confirm & Continue" to proceed.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _proceedToRebalance,
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: Text(
              widget.proceedLabel ?? 'Confirm & Continue',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditCta() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isUpdating ? null : () => setState(() => _viewMode = _ViewMode.viewing),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF424242),
              side: const BorderSide(color: Color(0xFFBDBDBD)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isUpdating ? null : _saveEditedPortfolio,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
            ),
            child: _isUpdating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Done Editing', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmFailedCta() {
    final allConfirmed = _confirmedStocks.isNotEmpty && _confirmedStocks.values.every((v) => v);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isUpdating ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF424242),
              side: const BorderSide(color: Color(0xFFBDBDBD)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: (_isUpdating || !allConfirmed) ? null : _confirmFailedOrders,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
            ),
            child: _isUpdating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
