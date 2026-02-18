import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/service/DataRepository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_stock.dart';
import 'package:tidistockmobileapp/models/rebalance_entry.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/models/portfolio_holding.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tidistockmobileapp/models/broker_connection.dart';

import 'BrokerSelectionPage.dart';
import 'InvestInPlanSheet.dart';
import 'InvestmentModal.dart';
import 'PortfolioHoldingsPage.dart';
import 'RebalanceReviewPage.dart';

class ModelPortfolioDetailPage extends StatefulWidget {
  final ModelPortfolio portfolio;

  const ModelPortfolioDetailPage({
    super.key,
    required this.portfolio,
  });

  @override
  State<ModelPortfolioDetailPage> createState() => _ModelPortfolioDetailPageState();
}

class _ModelPortfolioDetailPageState extends State<ModelPortfolioDetailPage>
    with SingleTickerProviderStateMixin {
  late ModelPortfolio portfolio;
  bool _loadingStrategy = true;
  String? userEmail;

  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Performance chart state
  List<Map<String, dynamic>> _performancePoints = [];
  Map<String, List<Map<String, dynamic>>> _indexData = {};
  bool _loadingPerformance = true;
  String _selectedIndex = 'Nifty 50';

  // Subscription state
  bool _isSubscribed = false;

  // Cached sorted stock composition (recomputed when portfolio changes)
  List<PortfolioStock> _sortedStocks = [];
  double _totalWeight = 0;
  double _maxPct = 1;

  // Subscribed user data
  List<PortfolioHolding> _holdings = [];
  bool _loadingHoldings = true;
  String? _selectedBroker;
  List<String> _availableBrokers = ['ALL'];
  double _totalInvested = 0;
  double _totalCurrent = 0;
  bool _hasPendingRebalance = false;
  bool _disclaimerAccepted = false;

  static const Map<String, String> _indexSymbols = {
    'Nifty 50': '^NSEI',
    'Midcap': 'NIFTY_MID_SELECT.NS',
    'Nifty 500': '^CRSLDX',
  };

  @override
  void initState() {
    super.initState();
    portfolio = widget.portfolio;
    _updateSortedStocks();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _selectedTabIndex = _tabController.index);
    });
    _recordRecentVisit();
    _loadUserEmail();
    _loadDisclaimerStatus();
    _refreshDetails();
    _fetchPerformanceData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateSortedStocks() {
    _sortedStocks = List<PortfolioStock>.from(portfolio.stocks)
      ..sort((a, b) => b.weight.compareTo(a.weight));
    _totalWeight = _sortedStocks.fold(0.0, (sum, s) => sum + s.weight);
    _maxPct = _totalWeight > 0 && _sortedStocks.isNotEmpty
        ? (_sortedStocks.first.weight / _totalWeight * 100)
        : 1.0;
  }

  Future<void> _recordRecentVisit() async {
    try {
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: 'recently_visited_portfolios');
      List<dynamic> entries = [];
      if (raw != null && raw.isNotEmpty) {
        entries = json.decode(raw);
      }
      // Remove duplicate by modelName or id
      entries.removeWhere((e) =>
          e is Map &&
          ((e['modelName']?.toString() ?? '') == portfolio.modelName ||
              (e['id']?.toString() ?? '') == (portfolio.id)));
      // Insert current portfolio at front
      entries.insert(0, {
        'modelName': portfolio.modelName,
        'id': portfolio.id,
        'image': portfolio.image ?? '',
        'riskProfile': portfolio.riskProfile ?? '',
        'advisor': portfolio.advisor,
        'visitedAt': DateTime.now().toIso8601String(),
      });
      // Cap at 10
      if (entries.length > 10) entries = entries.sublist(0, 10);
      await storage.write(
        key: 'recently_visited_portfolios',
        value: json.encode(entries),
      );
    } catch (e) {
      debugPrint('[DetailPage] _recordRecentVisit error: $e');
    }
  }

  Future<void> _loadUserEmail() async {
    final email = await const FlutterSecureStorage().read(key: 'user_email');
    debugPrint('[DetailPage] loaded email: $email');
    if (mounted) setState(() => userEmail = email);
    await _checkSubscriptionStatus();
  }

  Future<void> _loadDisclaimerStatus() async {
    // Check if user has previously accepted disclaimer for this portfolio
    final key = 'disclaimer_accepted_${portfolio.id ?? portfolio.modelName}';
    final accepted = await const FlutterSecureStorage().read(key: key);
    if (mounted) {
      setState(() => _disclaimerAccepted = accepted == 'true');
    }
  }

  Future<void> _acceptDisclaimer() async {
    // Save that user has accepted disclaimer for this portfolio
    final key = 'disclaimer_accepted_${portfolio.id ?? portfolio.modelName}';
    await const FlutterSecureStorage().write(key: key, value: 'true');
    if (mounted) {
      setState(() => _disclaimerAccepted = true);
    }
  }

  void _showPerformanceDisclaimer() {
    if (_disclaimerAccepted || _isSubscribed) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text("Disclaimer", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          "Past performance is not a guarantee of future returns.\n\n"
          "Investment in securities market is subject to market risks. "
          "Please read all related documents carefully before investing.",
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("I Understand"),
          ),
        ],
      ),
    );
    _acceptDisclaimer();
  }

  Future<void> _checkSubscriptionStatus() async {
    debugPrint('[DetailPage] _checkSubscriptionStatus called, email=$userEmail');

    // Try tidi_Front_back API first (resolves master email internally)
    bool found = false;
    try {
      final response = await ApiService().getUserModelPortfolioSubscriptions();
      debugPrint('[DetailPage] tidi subscriptionCheck statusCode=${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = json.decode(response.body);
        final List<dynamic> strategies = body is List
            ? body
            : (body is Map
                ? (body['subscriptions'] ?? body['subscribedPortfolios'] ?? body['data'] ?? body['strategies'] ?? [])
                : []);
        debugPrint('[DetailPage] tidi strategies count=${strategies.length}');
        for (final s in strategies) {
          if (s is Map) {
            final id = s['_id']?.toString();
            final modelName = (s['model_name']?.toString() ?? s['name']?.toString() ?? '').toLowerCase().trim();
            debugPrint('[DetailPage] checking tidi strategy: id=$id, model_name=$modelName');
            if (id == portfolio.strategyId ||
                id == portfolio.id ||
                modelName == portfolio.modelName.toLowerCase().trim()) {
              found = true;
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DetailPage] tidi subscriptionCheck error (will fallback): $e');
    }

    // Fallback: Try AlphaQuark API directly if tidi_Front_back fails
    if (!found && userEmail != null && userEmail!.isNotEmpty) {
      try {
        final response = await AqApiService.instance.getSubscribedStrategies(userEmail!);
        debugPrint('[DetailPage] AlphaQuark subscriptionCheck statusCode=${response.statusCode}');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = json.decode(response.body);
          final List<dynamic> strategies = body is List
              ? body
              : (body is Map
                  ? (body['subscribedPortfolios'] ?? body['data'] ?? body['strategies'] ?? [])
                  : []);
          for (final s in strategies) {
            if (s is Map) {
              final id = s['_id']?.toString();
              final modelName = (s['model_name']?.toString() ?? '').toLowerCase().trim();
              if (id == portfolio.strategyId ||
                  id == portfolio.id ||
                  modelName == portfolio.modelName.toLowerCase().trim()) {
                found = true;
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[DetailPage] AlphaQuark fallback error: $e');
      }
    }

    // Final fallback: check local subscriptions
    if (!found) {
      found = await _checkLocalSubscription();
    }

    debugPrint('[DetailPage] subscriptionCheck: found=$found for ${portfolio.modelName}');
    if (mounted) setState(() => _isSubscribed = found);
    if (found) _fetchSubscribedData();
  }

  Future<bool> _checkLocalSubscription() async {
    try {
      final raw = await const FlutterSecureStorage().read(key: 'local_subscribed_portfolios');
      if (raw == null || raw.isEmpty) return false;
      final List<dynamic> entries = json.decode(raw);
      for (final e in entries) {
        if (e is! Map) continue;
        final sid = e['strategyId']?.toString() ?? '';
        final pid = e['planId']?.toString() ?? '';
        final name = (e['modelName']?.toString() ?? '').toLowerCase().trim();
        if (sid == portfolio.strategyId ||
            sid == portfolio.id ||
            pid == portfolio.id ||
            name == portfolio.modelName.toLowerCase().trim()) {
          debugPrint('[DetailPage] found local subscription for ${portfolio.modelName}');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[DetailPage] _checkLocalSubscription error: $e');
    }
    return false;
  }

  Future<void> _fetchSubscribedData() async {
    await Future.wait([
      _fetchHoldings(),
      Future(() => _checkPendingRebalance()),
    ]);
  }

  Future<void> _fetchHoldings() async {
    if (userEmail == null) {
      if (mounted) setState(() => _loadingHoldings = false);
      return;
    }
    try {
      final email = userEmail!;
      final modelName = portfolio.modelName;

      final brokersResp = await AqApiService.instance.getAvailableBrokers(
        email: email,
        modelName: modelName,
      );
      if (brokersResp.statusCode == 200) {
        final bData = await DataRepository.parseJsonMap(brokersResp.body);
        final brokerList = bData['data']?['brokers'] ?? [];
        if (brokerList is List && brokerList.isNotEmpty) {
          _availableBrokers = ['ALL', ...brokerList.map((b) => b['broker'].toString())];
        }
      }

      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: email,
        modelName: modelName,
        userBroker: _selectedBroker == 'ALL' ? null : _selectedBroker,
      );
      debugPrint('[DetailPage] _fetchHoldings $modelName raw response (${response.statusCode}): ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      if (response.statusCode == 200 && mounted) {
        final data = await DataRepository.parseJsonMap(response.body);
        final subData = data['data'];
        if (subData != null) {
          _parseHoldings(subData);
        }
      }
      if (mounted) setState(() => _loadingHoldings = false);
    } catch (e) {
      debugPrint('[DetailPage] _fetchHoldings error: $e');
      if (mounted) setState(() => _loadingHoldings = false);
    }
  }

  void _parseHoldings(Map<String, dynamic> subData) {
    final userNetPf = subData['user_net_pf_model']
        ?? subData['userNetPfModel']
        ?? [];
    final List<PortfolioHolding> parsed = [];

    debugPrint('[DetailPage] _parseHoldings subData.keys=${subData.keys.toList()}, userNetPf.type=${userNetPf.runtimeType}, userNetPf.length=${userNetPf is List ? userNetPf.length : 'N/A'}');

    if (userNetPf is List && userNetPf.isNotEmpty) {
      final latest = userNetPf.last;
      List<dynamic> stockList = [];
      if (latest is List) {
        stockList = latest;
      } else if (latest is Map) {
        stockList = latest['stocks'] ?? latest['holdings'] ?? [];
      }
      for (final stock in stockList) {
        if (stock is Map<String, dynamic>) {
          parsed.add(PortfolioHolding.fromJson(stock));
        }
      }
    }

    // Parse totals from subscription_amount_raw
    double invested = 0;
    double current = 0;
    final rawAmounts = subData['subscription_amount_raw']
        ?? subData['subscriptionAmountRaw']
        ?? [];
    debugPrint('[DetailPage] _parseHoldings rawAmounts.type=${rawAmounts.runtimeType}, rawAmounts.length=${rawAmounts is List ? rawAmounts.length : 'N/A'}');

    if (rawAmounts is List && rawAmounts.isNotEmpty) {
      final latest = rawAmounts.last;
      if (latest is Map) {
        invested = (latest['totalInvestment'] ?? latest['invested'] ?? 0).toDouble();
        current = (latest['currentValue'] ?? latest['current'] ?? invested).toDouble();
      }
    }

    // Fallback: try top-level fields in subData
    if (invested == 0 && subData.containsKey('totalInvestment')) {
      invested = (subData['totalInvestment'] ?? 0).toDouble();
      current = (subData['currentValue'] ?? subData['current'] ?? invested).toDouble();
    }

    // Fallback: compute from holdings if raw amounts unavailable
    if (invested == 0 && parsed.isNotEmpty) {
      for (final h in parsed) {
        invested += h.investedValue;
        current += h.currentValue;
      }
    }

    debugPrint('[DetailPage] _parseHoldings final: invested=$invested, current=$current, holdings=${parsed.length}');

    setState(() {
      _holdings = parsed;
      _totalInvested = invested;
      _totalCurrent = current;
    });
  }

  void _checkPendingRebalance() {
    if (portfolio.rebalanceHistory.isNotEmpty && userEmail != null) {
      final pending = portfolio.rebalanceHistory.last.hasPendingExecution(userEmail!);
      if (mounted) setState(() => _hasPendingRebalance = pending);
    }
  }

  Future<void> _refreshDetails() async {
    // Invalidate cached subscription data so pull-to-refresh forces a real fetch
    if (userEmail != null) {
      CacheService.instance.invalidateByPrefix('aq/subscription-raw:$userEmail:${portfolio.modelName}');
    }

    try {
      await AqApiService.instance.getCachedStrategyDetails(
        modelName: portfolio.modelName,
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final raw = data is Map ? data : (data is List && data.isNotEmpty ? data[0] : null);
          if (raw != null && raw is Map) {
            try {
              final strategyData = ModelPortfolio.fromJson(Map<String, dynamic>.from(raw));
              setState(() {
                portfolio = portfolio.mergeStrategyData(strategyData);
                _updateSortedStocks();
                _loadingStrategy = false;
              });
            } catch (e) {
              debugPrint('[DetailPage] ModelPortfolio.fromJson failed: $e');
              if (mounted) setState(() => _loadingStrategy = false);
            }
          } else {
            debugPrint('[DetailPage] _refreshDetails: unexpected data shape: ${data.runtimeType}');
            if (mounted) setState(() => _loadingStrategy = false);
          }
        },
      );
    } catch (e) {
      debugPrint('[DetailPage] _refreshDetails error: $e');
      if (mounted) setState(() => _loadingStrategy = false);
    }

    // Re-fetch subscribed data after strategy refresh
    if (_isSubscribed && userEmail != null) {
      _fetchSubscribedData();
    }
  }

  Future<void> _fetchPerformanceData() async {
    try {
      debugPrint('[DetailPage] _fetchPerformanceData: advisor=${portfolio.advisor}, modelName=${portfolio.modelName}');
      final response = await AqApiService.instance.getPortfolioPerformance(
        advisor: portfolio.advisor,
        modelName: portfolio.modelName,
      );
      debugPrint('[DetailPage] _fetchPerformanceData status=${response.statusCode}, bodyLen=${response.body.length}');
      if (response.statusCode == 200) {
        final body = await DataRepository.parseJsonMap(response.body);
        final data = body['data'];
        debugPrint('[DetailPage] _fetchPerformanceData data is List=${data is List}, isEmpty=${data is List ? data.isEmpty : 'N/A'}');
        if (data is List && data.isNotEmpty) {
          if (mounted) {
            setState(() {
              _performancePoints = List<Map<String, dynamic>>.from(data);
              _loadingPerformance = false;
            });
          }
          _fetchIndexData();
          return;
        }
      }
    } catch (e) {
      debugPrint('[DetailPage] _fetchPerformanceData error: $e');
    }
    if (mounted) setState(() => _loadingPerformance = false);
  }

  Future<void> _fetchIndexData() async {
    if (_performancePoints.isEmpty) return;
    final startDate = _performancePoints.first['date']?.toString();
    final endDate = _performancePoints.last['date']?.toString();
    if (startDate == null || endDate == null) return;

    final results = <String, List<Map<String, dynamic>>>{};
    await Future.wait(
      _indexSymbols.entries.map((entry) async {
        try {
          final response = await AqApiService.instance.getIndexData(
            symbol: entry.value,
            startDate: startDate,
            endDate: endDate,
          );
          if (response.statusCode == 200) {
            final body = await DataRepository.parseJsonMap(response.body);
            final data = body['data'] ?? body;
            if (data is List && data.isNotEmpty) {
              results[entry.key] = List<Map<String, dynamic>>.from(data);
            }
          }
        } catch (e) {
          debugPrint('[DetailPage] _fetchIndexData ${entry.key} error: $e');
        }
      }),
    );
    if (mounted && results.isNotEmpty) {
      setState(() {
        _indexData.addAll(results);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshDetails,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: _isSubscribed && userEmail != null
                    ? _subscribedViewChildren()
                    : _unsubscribedViewChildren(),
              ),
            ),
          ),
          _bottomCta(),
        ],
      ),
    );
  }

  List<Widget> _unsubscribedViewChildren() {
    return [
      _header(),
      if (portfolio.overView != null && portfolio.overView!.isNotEmpty)
        _overviewSection(),
      const SizedBox(height: 16),
      _statsGrid(showStockCount: false),
      const SizedBox(height: 16),
      // Hide stock composition from non-subscribers - show subscription prompt instead
      _subscribeToViewHoldingsPrompt(),
      const SizedBox(height: 16),
      _tabBar(),
      const SizedBox(height: 12),
      _tabContent(),
    ];
  }

  List<Widget> _subscribedViewChildren() {
    return [
      _subscribedHeader(),
      const SizedBox(height: 16),
      _subscribedStatsGrid(),
      const SizedBox(height: 16),
      _rebalanceInfoSection(),
      if (_hasPendingRebalance) _rebalanceBanner(),
      _tabBar(),
      const SizedBox(height: 12),
      _tabContent(),
    ];
  }

  Color _riskColor(String? risk) {
    switch (risk?.toLowerCase()) {
      case 'aggressive':
        return Colors.red.shade400;
      case 'moderate':
        return Colors.orange.shade400;
      default:
        return Colors.green.shade400;
    }
  }

  // ---------------------------------------------------------------------------
  // Subscribed Header
  // ---------------------------------------------------------------------------

  Widget _subscribedHeader() {
    final riskColor = _riskColor(portfolio.riskProfile);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            riskColor.withOpacity(0.08),
            riskColor.withOpacity(0.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (portfolio.image != null && portfolio.image!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    portfolio.image!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    cacheHeight: 120,
                    errorBuilder: (_, __, ___) => _placeholderIcon(),
                  ),
                )
              else
                _placeholderIcon(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      portfolio.modelName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Subscribed",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                          ),
                        ),
                        if (portfolio.riskProfile != null && portfolio.riskProfile!.trim().isNotEmpty)
                          _riskBadge(portfolio.riskProfile!),
                      ],
                    ),
                    if (portfolio.advisor.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "by ${portfolio.advisor}",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _sharePortfolio,
                icon: const Icon(Icons.share_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final broker = await _ensureBrokerConnected();
                    if (broker == null || !mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InvestmentModal(
                          portfolio: portfolio,
                          email: userEmail!,
                          brokerName: broker.broker,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text("Invest More"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PortfolioHoldingsPage(
                          portfolio: portfolio,
                          email: userEmail!,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                  label: const Text("View Holdings"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Subscribed Stats Grid
  // ---------------------------------------------------------------------------

  Widget _subscribedStatsGrid() {
    // Show informational message when no financial data is available yet
    if (!_loadingHoldings && _totalInvested == 0 && _totalCurrent == 0 && _holdings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(
            "Investment data is being processed. This may take a few minutes after your first trade.",
            style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
          )),
        ]),
      );
    }

    final returns = _totalInvested > 0
        ? ((_totalCurrent - _totalInvested) / _totalInvested * 100)
        : 0.0;
    final isPositive = returns >= 0;
    final fmt = NumberFormat('#,##,###');

    final perf = portfolio.performanceData;
    final cagrStr = perf?.cagr != null ? '${perf!.cagr!.toStringAsFixed(1)}%' : 'N/A';
    final sharpeStr = perf?.sharpeRatio != null ? perf!.sharpeRatio!.toStringAsFixed(2) : 'N/A';

    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _statCard("Invested", "\u20B9${fmt.format(_totalInvested.round())}",
              Icons.account_balance_wallet, Colors.blue),
          const SizedBox(width: 10),
          _statCard("Current", "\u20B9${fmt.format(_totalCurrent.round())}",
              Icons.trending_up, Colors.teal),
          const SizedBox(width: 10),
          _statCard("Returns", "${isPositive ? '+' : ''}${returns.toStringAsFixed(1)}%",
              Icons.show_chart, isPositive ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          _statCard("CAGR", cagrStr, Icons.timeline, Colors.purple),
          const SizedBox(width: 10),
          _statCard("Sharpe", sharpeStr, Icons.analytics, Colors.orange),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Rebalance Banner (for subscribed view)
  // ---------------------------------------------------------------------------

  Widget _rebalanceBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RebalanceReviewPage(
              portfolio: portfolio,
              email: userEmail!,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.sync, color: Colors.orange.shade700, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Rebalance Available",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: Colors.orange.shade800)),
                  Text("Review and execute the latest changes.",
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.orange.shade400),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final riskColor = _riskColor(portfolio.riskProfile);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            riskColor.withOpacity(0.08),
            riskColor.withOpacity(0.03),
          ],
        ),
      ),
      child: Row(
        children: [
          if (portfolio.image != null && portfolio.image!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                portfolio.image!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                cacheWidth: 120,
                cacheHeight: 120,
                errorBuilder: (_, __, ___) => _placeholderIcon(),
              ),
            )
          else
            _placeholderIcon(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  portfolio.modelName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (portfolio.riskProfile != null && portfolio.riskProfile!.trim().isNotEmpty)
                      _riskBadge(portfolio.riskProfile!),
                    if (portfolio.stocks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${portfolio.stocks.length} stocks",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
                if (portfolio.advisor.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "by ${portfolio.advisor}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _sharePortfolio,
            icon: const Icon(Icons.share_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              foregroundColor: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  void _sharePortfolio() {
    final encodedName = Uri.encodeComponent(portfolio.modelName);
    final url = 'https://prod.alphaquark.in/model-portfolio/$encodedName';
    Share.share('Check out ${portfolio.modelName} on AlphaQuark:\n$url');
  }

  Widget _placeholderIcon() {
    return Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.account_balance, size: 28, color: Color(0xFF3F51B5)),
    );
  }

  Widget _riskBadge(String risk) {
    if (risk.trim().isEmpty) return const SizedBox.shrink();
    final color = _riskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(risk,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _overviewSection() {
    return _section(
      "Overview",
      Text(
        portfolio.overView!,
        style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
      ),
    );
  }

  Widget _statsGrid({bool showStockCount = true}) {
    final cards = <Widget>[
      _statCard("Min Investment", "\u20B9${NumberFormat('#,##,###').format(portfolio.minInvestment)}",
          Icons.currency_rupee, Colors.blue),
    ];
    if (portfolio.frequency != null && portfolio.frequency!.isNotEmpty && portfolio.frequency != "—") {
      cards.add(_statCard("Frequency", portfolio.frequency!,
          Icons.calendar_today_rounded, Colors.purple));
    }
    // Only show stock count for subscribed users
    if (showStockCount && portfolio.stocks.isNotEmpty) {
      cards.add(_statCard("Stocks", "${portfolio.stocks.length}",
          Icons.pie_chart_rounded, Colors.teal));
    }
    if (portfolio.pricingDisplayText.isNotEmpty) {
      cards.add(_statCard("Subscription Fee", portfolio.pricingDisplayText,
          Icons.card_membership, Colors.green));
    }

    final children = <Widget>[];
    for (int i = 0; i < cards.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 12));
      children.add(Expanded(child: cards[i]));
    }
    return Row(children: children);
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Widget shown to non-subscribers instead of stock composition
  Widget _subscribeToViewHoldingsPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 40, color: Color(0xFF1565C0)),
          const SizedBox(height: 12),
          const Text(
            "Subscribe to View Holdings",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
          ),
          const SizedBox(height: 8),
          Text(
            "Stock composition and allocation details are available for subscribers only.",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showPlanSelectionSheet,
            icon: const Icon(Icons.subscriptions_rounded, size: 18),
            label: const Text("Subscribe Now"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockComposition() {
    if (portfolio.stocks.isEmpty) {
      if (_loadingStrategy) {
        return _section(
          "Stock Composition",
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return _section(
      "Stock Composition",
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(flex: 3, child: Text("Symbol",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey))),
                const Expanded(flex: 2, child: Text("Exchange",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                    textAlign: TextAlign.center)),
                const Expanded(flex: 2, child: Text("Weight",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                    textAlign: TextAlign.right)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...List.generate(_sortedStocks.length, (index) {
            final stock = _sortedStocks[index];
            final pct = _totalWeight > 0 ? (stock.weight / _totalWeight * 100) : 0.0;
            final isEven = index % 2 == 0;
            return Container(
              color: isEven ? Colors.grey.shade50 : Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(stock.symbol,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(stock.exchange ?? "NSE",
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            textAlign: TextAlign.center),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text("${pct.toStringAsFixed(1)}%",
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _maxPct > 0 ? (pct / _maxPct).clamp(0.0, 1.0) : 0,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
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

  // ---------------------------------------------------------------------------
  // Tab bar & tab content
  // ---------------------------------------------------------------------------

  Widget _tabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.black87,
        unselectedLabelColor: Colors.grey.shade500,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor: Colors.transparent,
        tabs: _isSubscribed
            ? const [
                Tab(text: "Distribution"),
                Tab(text: "My Holdings"),
                Tab(text: "Research"),
              ]
            : const [
                Tab(text: "Distribution"),
                Tab(text: "Why this Strategy"),
                Tab(text: "Methodology"),
              ],
      ),
    );
  }

  Widget _tabContent() {
    if (_isSubscribed) {
      switch (_selectedTabIndex) {
        case 0:
          return _subscribedDistributionTab();
        case 1:
          return _myHoldingsTab();
        case 2:
          return _researchReportsTab();
        default:
          return const SizedBox.shrink();
      }
    }
    switch (_selectedTabIndex) {
      case 0:
        return _distributionTab();
      case 1:
        return _whyStrategyTab();
      case 2:
        return _methodologyTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Tab 0: Distribution
  // ---------------------------------------------------------------------------

  Widget _distributionTab() {
    // Show disclaimer warning for non-subscribers viewing performance
    if (!_isSubscribed && !_disclaimerAccepted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPerformanceDisclaimer();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Disclaimer warning banner for non-subscribers
        if (!_isSubscribed && !_disclaimerAccepted)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Past performance is not guarantee of future returns",
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
                GestureDetector(
                  onTap: _showPerformanceDisclaimer,
                  child: Text(
                    "Read more",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                  ),
                ),
              ],
            ),
          ),
        _rebalanceInfoSection(),
        if (_performancePoints.isNotEmpty || _loadingPerformance)
          _performanceChartSection(),
        if (portfolio.performanceData != null)
          _performanceMetricsSectionFull(),
      ],
    );
  }

  Widget _performanceMetricsSectionFull() {
    final perf = portfolio.performanceData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricsCardGrouped("Returns & Risk", [
          [
            _metricItem("CAGR", perf.cagr, isPercent: true),
            _metricItem("Total Return", perf.totalReturn, isPercent: true),
            _metricItem("YTD Return", perf.ytdReturn, isPercent: true),
            _metricItem("1Y Return", perf.oneYearReturn, isPercent: true),
          ],
          [
            _metricItem("Volatility", perf.volatility, isPercent: true),
            _metricItem("Max Drawdown", perf.maxDrawdown, isPercent: true),
            _metricItem("Value at Risk", perf.valueAtRisk, isPercent: true),
            _metricItem("CVaR", perf.cvar, isPercent: true),
          ],
        ]),
        _metricsCardGrouped("Ratios & Timing", [
          [
            _metricItem("Sharpe Ratio", perf.sharpeRatio),
            _metricItem("Sortino Ratio", perf.sortinoRatio),
            _metricItem("Profit Factor", perf.profitFactor),
            _metricItem("Gain to Pain", perf.gainToPain),
          ],
          [
            _metricItem("Win Rate", perf.winRate, isPercent: true),
            _metricItem("Avg Drawdown", perf.avgDrawdown, isPercent: true),
            if (perf.longestDdDays != null)
              _metricItemRaw("Longest DD", "${perf.longestDdDays} days"),
            _metricItem("Best Day", perf.bestDay, isPercent: true),
            _metricItem("Worst Day", perf.worstDay, isPercent: true),
            _metricItem("Time in Market", perf.timeInMarket, isPercent: true),
            _metricItem("Ulcer Index", perf.ulcerIndex),
          ],
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Subscribed Tab 0: Distribution (enhanced)
  // ---------------------------------------------------------------------------

  Widget _subscribedDistributionTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _performanceSummaryCards(),
        if (portfolio.performanceData != null) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text("Detailed Metrics",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: Colors.grey.shade500, letterSpacing: 0.5)),
          ),
          _performanceMetricsSection(),
        ],
        if (_performancePoints.isNotEmpty || _loadingPerformance)
          _performanceChartSection(),
        const SizedBox(height: 16),
        _pieChartSection(),
        const SizedBox(height: 16),
        _stockComposition(),
      ],
    );
  }

  Widget _performanceSummaryCards() {
    final perf = portfolio.performanceData;
    final cagrVal = perf?.cagr;
    final sharpeVal = perf?.sharpeRatio;
    final volVal = perf?.volatility;
    final volLabel = portfolio.volatilityLabel;

    // Determine volatility display and color
    String volDisplay;
    List<Color> volColors;
    if (volVal != null) {
      volDisplay = "${volVal.toStringAsFixed(1)}%";
      volColors = [Colors.amber.shade400, Colors.amber.shade700];
    } else if (volLabel != null && volLabel.isNotEmpty) {
      volDisplay = volLabel;
      volColors = volLabel == "High"
          ? [Colors.red.shade300, Colors.red.shade600]
          : volLabel == "Low"
              ? [Colors.green.shade400, Colors.green.shade700]
              : [Colors.amber.shade400, Colors.amber.shade700];
    } else {
      volDisplay = "N/A";
      volColors = [Colors.amber.shade400, Colors.amber.shade700];
    }

    return Row(
      children: [
        Expanded(
          child: _gradientMetricCard(
            "CAGR",
            cagrVal != null ? "${cagrVal.toStringAsFixed(1)}%" : "N/A",
            Icons.timeline,
            [Colors.purple.shade400, Colors.purple.shade700],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _gradientMetricCard(
            "Sharpe",
            sharpeVal != null ? sharpeVal.toStringAsFixed(2) : "N/A",
            Icons.analytics,
            sharpeVal != null && sharpeVal >= 1.0
                ? [Colors.green.shade400, Colors.green.shade700]
                : sharpeVal != null && sharpeVal >= 0.5
                    ? [Colors.orange.shade300, Colors.orange.shade600]
                    : [Colors.red.shade300, Colors.red.shade600],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _gradientMetricCard(
            "Volatility",
            volDisplay,
            Icons.speed,
            volColors,
          ),
        ),
      ],
    );
  }

  Widget _gradientMetricCard(String label, String value, IconData icon, List<Color> colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Colors.white.withOpacity(0.9)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85))),
        ],
      ),
    );
  }

  Widget _pieChartSection() {
    if (_sortedStocks.isEmpty) return const SizedBox.shrink();

    const pieColors = [
      Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFF57C00),
      Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC62828),
      Color(0xFF4527A0), Color(0xFF00695C), Color(0xFFEF6C00),
      Color(0xFF283593), Color(0xFF558B2F), Color(0xFFAD1457),
    ];

    return _section(
      "Portfolio Allocation",
      Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: List.generate(_sortedStocks.length, (index) {
                  final stock = _sortedStocks[index];
                  final pct = _totalWeight > 0 ? (stock.weight / _totalWeight * 100) : 0.0;
                  return PieChartSectionData(
                    value: pct,
                    title: pct >= 5 ? '${pct.toStringAsFixed(0)}%' : '',
                    color: pieColors[index % pieColors.length],
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  );
                }),
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(_sortedStocks.length, (index) {
              final stock = _sortedStocks[index];
              final pct = _totalWeight > 0 ? (stock.weight / _totalWeight * 100) : 0.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: pieColors[index % pieColors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text("${stock.symbol} (${pct.toStringAsFixed(1)}%)",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Subscribed Tab 1: My Holdings
  // ---------------------------------------------------------------------------

  Widget _myHoldingsTab() {
    if (_loadingHoldings) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_holdings.isEmpty) {
      return _emptyTabContent("No holdings data available.");
    }

    final pnl = _totalCurrent - _totalInvested;
    final pnlPct = _totalInvested > 0 ? (pnl / _totalInvested * 100) : 0.0;
    final isProfit = pnl >= 0;
    final fmt = NumberFormat('#,##,###');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // P&L Summary Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isProfit
                  ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                  : [Colors.red.shade700, Colors.red.shade500],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _holdingsHeaderStat("Invested",
                      "\u20B9${fmt.format(_totalInvested.round())}"),
                  _holdingsHeaderStat("Current",
                      "\u20B9${fmt.format(_totalCurrent.round())}"),
                  _holdingsHeaderStat("P&L",
                      "${isProfit ? '+' : ''}\u20B9${fmt.format(pnl.abs().round())}"),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}% returns",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Broker selector
        if (_availableBrokers.length > 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _availableBrokers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final broker = _availableBrokers[index];
                  final isSelected = (_selectedBroker ?? 'ALL') == broker;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBroker = broker;
                        _loadingHoldings = true;
                      });
                      _fetchHoldings();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1A237E) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300),
                      ),
                      child: Center(
                        child: Text(broker,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Holdings table
        _holdingsTable(),
      ],
    );
  }

  Widget _holdingsHeaderStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _holdingsTable() {
    final sorted = List<PortfolioHolding>.from(_holdings)
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

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
          Text("Holdings (${_holdings.length})",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(flex: 3, child: Text("Symbol",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey))),
              Expanded(flex: 1, child: Text("Qty",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                  textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text("Avg / LTP",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                  textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text("P&L",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                  textAlign: TextAlign.right)),
            ],
          ),
          const Divider(height: 16),
          ...sorted.map((h) {
            final isProfit = (h.pnl ?? 0) >= 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.symbol,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        if (h.exchange != null)
                          Text(h.exchange!,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text("${h.quantity}",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Text("\u20B9${h.avgPrice.toStringAsFixed(1)}",
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            textAlign: TextAlign.center),
                        if (h.ltp != null)
                          Text("\u20B9${h.ltp!.toStringAsFixed(1)}",
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "${isProfit ? '+' : ''}\u20B9${(h.pnl ?? 0).abs().toStringAsFixed(0)}",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isProfit ? Colors.green : Colors.red,
                          ),
                        ),
                        if (h.pnlPercent != null)
                          Text(
                            "${isProfit ? '+' : ''}${h.pnlPercent!.toStringAsFixed(1)}%",
                            style: TextStyle(
                              fontSize: 11,
                              color: isProfit ? Colors.green : Colors.red,
                            ),
                          ),
                      ],
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

  // ---------------------------------------------------------------------------
  // Subscribed Tab 2: Research Reports
  // ---------------------------------------------------------------------------

  Widget _researchReportsTab() {
    final reports = portfolio.rebalanceHistory
        .where((e) => e.researchReportLink != null && e.researchReportLink!.isNotEmpty)
        .toList()
        .reversed
        .toList();

    if (reports.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.description_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text("No research reports available yet.",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: reports.map((entry) {
        final dateStr = entry.rebalanceDate != null
            ? DateFormat("dd MMM yyyy").format(entry.rebalanceDate!)
            : "Unknown date";
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04),
                  blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.description_rounded, color: Colors.blue.shade700, size: 22),
            ),
            title: const Text("Research Report",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: Text(dateStr,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            trailing: Icon(Icons.open_in_new_rounded, size: 20, color: Colors.blue.shade700),
            onTap: () async {
              final url = Uri.parse(entry.researchReportLink!);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _rebalanceInfoSection() {
    final hasInfo = portfolio.frequency != null ||
        portfolio.nextRebalanceDate != null ||
        portfolio.rebalanceHistory.isNotEmpty;
    if (!hasInfo) return const SizedBox.shrink();

    return _section(
      "Rebalance",
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (portfolio.frequency != null)
            _infoRow("Frequency", portfolio.frequency!),
          if (portfolio.rebalanceHistory.isNotEmpty)
            _infoRow("Last Rebalance",
                portfolio.rebalanceHistory.last.rebalanceDate != null
                    ? DateFormat("dd MMM yyyy").format(portfolio.rebalanceHistory.last.rebalanceDate!)
                    : "—"),
          if (portfolio.nextRebalanceDate != null)
            _infoRow("Next Rebalance",
                DateFormat("dd MMM yyyy").format(portfolio.nextRebalanceDate!)),
          if (portfolio.rebalanceHistory.isNotEmpty)
            _infoRow("Total Rebalances", "${portfolio.rebalanceHistory.length}"),
          if (portfolio.rebalanceHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: _showRebalanceHistory,
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text(
                    "View Rebalance History",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 20, color: Colors.blue.shade700),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _performanceChartSection() {
    if (_loadingPerformance) {
      return _section(
        "Portfolio Performance",
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_performancePoints.isEmpty) return const SizedBox.shrink();

    final portfolioSpots = _normalizeToBase100(_performancePoints);
    final indexSpots = _indexData.containsKey(_selectedIndex)
        ? _normalizeToBase100(_indexData[_selectedIndex]!)
        : <FlSpot>[];

    final allY = [...portfolioSpots.map((s) => s.y), ...indexSpots.map((s) => s.y)];
    final minY = allY.isEmpty ? 0.0 : allY.reduce((a, b) => a < b ? a : b);
    final maxY = allY.isEmpty ? 200.0 : allY.reduce((a, b) => a > b ? a : b);
    final yPadding = (maxY - minY) * 0.1;

    return _section(
      "Portfolio Performance",
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ((maxY - minY) / 4).clamp(1, double.infinity),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: minY - yPadding,
                maxY: maxY + yPadding,
                lineBarsData: [
                  LineChartBarData(
                    spots: portfolioSpots,
                    isCurved: true,
                    color: const Color(0xFF1565C0),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF1565C0).withOpacity(0.08),
                    ),
                  ),
                  if (indexSpots.isNotEmpty)
                    LineChartBarData(
                      spots: indexSpots,
                      isCurved: true,
                      color: Colors.orange.shade400,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      dashArray: [6, 4],
                    ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((spot) {
                      final isPortfolio = spot.barIndex == 0;
                      return LineTooltipItem(
                        '${isPortfolio ? "Portfolio" : _selectedIndex}: ${spot.y.toStringAsFixed(1)}',
                        TextStyle(
                          color: isPortfolio ? const Color(0xFF1565C0) : Colors.orange.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              _legendDot(const Color(0xFF1565C0), "Portfolio"),
              if (indexSpots.isNotEmpty) ...[
                const SizedBox(width: 16),
                _legendDot(Colors.orange.shade400, _selectedIndex),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Index toggle chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _indexSymbols.keys.map((name) {
              final isSelected = _selectedIndex == name;
              return FilterChip(
                label: Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.grey.shade700)),
                selected: isSelected,
                onSelected: (_) => setState(() => _selectedIndex = name),
                backgroundColor: Colors.grey.shade100,
                selectedColor: const Color(0xFF1565C0),
                checkmarkColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  List<FlSpot> _normalizeToBase100(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return [];
    final firstValue = (points.first['value'] as num?)?.toDouble() ??
        (points.first['close'] as num?)?.toDouble() ?? 1.0;
    if (firstValue == 0) return [];
    return List.generate(points.length, (i) {
      final val = (points[i]['value'] as num?)?.toDouble() ??
          (points[i]['close'] as num?)?.toDouble() ?? 0;
      return FlSpot(i.toDouble(), (val / firstValue) * 100);
    });
  }

  Widget _performanceMetricsSection() {
    final perf = portfolio.performanceData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricsCardGrouped("Returns & Risk", [
          [
            _metricItem("Total Return", perf.totalReturn, isPercent: true),
            _metricItem("YTD Return", perf.ytdReturn, isPercent: true),
            _metricItem("1Y Return", perf.oneYearReturn, isPercent: true),
          ],
          [
            _metricItem("Max Drawdown", perf.maxDrawdown, isPercent: true),
            _metricItem("Value at Risk", perf.valueAtRisk, isPercent: true),
            _metricItem("CVaR", perf.cvar, isPercent: true),
          ],
        ]),
        _metricsCardGrouped("Ratios & Timing", [
          [
            _metricItem("Sortino Ratio", perf.sortinoRatio),
            _metricItem("Profit Factor", perf.profitFactor),
            _metricItem("Gain to Pain", perf.gainToPain),
            _metricItem("Win Rate", perf.winRate, isPercent: true),
          ],
          [
            _metricItem("Avg Drawdown", perf.avgDrawdown, isPercent: true),
            if (perf.longestDdDays != null)
              _metricItemRaw("Longest DD", "${perf.longestDdDays} days"),
            _metricItem("Best Day", perf.bestDay, isPercent: true),
            _metricItem("Worst Day", perf.worstDay, isPercent: true),
            _metricItem("Time in Market", perf.timeInMarket, isPercent: true),
            _metricItem("Ulcer Index", perf.ulcerIndex),
          ],
        ]),
      ],
    );
  }

  Widget _metricsCard(String title, List<Widget?> items) {
    final validItems = items.whereType<Widget>().toList();
    if (validItems.isEmpty) return const SizedBox.shrink();

    return _section(title, _metricsGrid(items));
  }

  Widget? _metricItem(String label, double? value, {bool isPercent = false}) {
    if (value == null) return null;
    final display = isPercent
        ? "${value.toStringAsFixed(2)}%"
        : value.toStringAsFixed(2);
    return _metricItemRaw(label, display, valueColor: value >= 0 ? Colors.green.shade700 : Colors.red.shade700);
  }

  Widget _metricItemRaw(String label, String display, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(display,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: valueColor ?? Colors.grey.shade800)),
      ],
    );
  }

  Widget _metricsGrid(List<Widget?> items) {
    final valid = items.whereType<Widget>().toList();
    if (valid.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < valid.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: valid[i]),
              const SizedBox(width: 16),
              Expanded(child: i + 1 < valid.length ? valid[i + 1] : const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _metricsCardGrouped(String title, List<List<Widget?>> groups) {
    final groupWidgets = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      final valid = groups[i].whereType<Widget>().toList();
      if (valid.isEmpty) continue;
      if (groupWidgets.isNotEmpty) {
        groupWidgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ));
      }
      groupWidgets.add(_metricsGrid(valid));
    }
    if (groupWidgets.isEmpty) return const SizedBox.shrink();
    return _section(title, Column(crossAxisAlignment: CrossAxisAlignment.start, children: groupWidgets));
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Why this Strategy
  // ---------------------------------------------------------------------------

  Widget _whyStrategyTab() {
    final hasWhy = portfolio.whyThisStrategy != null && portfolio.whyThisStrategy!.isNotEmpty;
    final hasStrategy = portfolio.investmentStrategy.isNotEmpty;

    if (!hasWhy && !hasStrategy) {
      return _emptyTabContent("Strategy details not available yet.");
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasWhy)
          _section(
            "Why This Strategy",
            Text(
              portfolio.whyThisStrategy!,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
            ),
          ),
        if (hasStrategy)
          _section(
            "Investment Strategy",
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: portfolio.investmentStrategy.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("\u2022 ", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Expanded(child: Text(point,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4))),
                  ],
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Methodology
  // ---------------------------------------------------------------------------

  Widget _methodologyTab() {
    final sections = <MapEntry<String, String?>>[];
    sections.add(MapEntry("Defining the Universe", portfolio.definingUniverse));
    sections.add(MapEntry("Research", portfolio.researchOverView));
    sections.add(MapEntry("Constituent Screening", portfolio.constituentScreening));
    sections.add(MapEntry("Weighting", portfolio.weighting));
    sections.add(MapEntry("Rebalance", portfolio.rebalanceMethodologyText));
    sections.add(MapEntry("Asset Allocation", portfolio.assetAllocationText));

    final validSections = sections.where((e) => e.value != null && e.value!.isNotEmpty).toList();
    if (validSections.isEmpty) {
      return _emptyTabContent("Methodology details not available yet.");
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: validSections.map((entry) => _section(
        entry.key,
        Text(
          entry.value!,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
        ),
      )).toList(),
    );
  }

  Widget _emptyTabContent(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.info_outline_rounded, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Rebalance History Bottom Sheet
  // ---------------------------------------------------------------------------

  void _showRebalanceHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, scrollController) {
          final history = portfolio.rebalanceHistory.reversed.toList();
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text("Rebalance History",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text("${history.length} entries",
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    itemBuilder: (_, index) {
                      final entry = history[index];
                      return _rebalanceHistoryItem(entry, index, history.length);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rebalanceHistoryItem(RebalanceHistoryEntry entry, int index, int total) {
    final dateStr = entry.rebalanceDate != null
        ? DateFormat("dd MMM yyyy").format(entry.rebalanceDate!)
        : "Unknown date";
    final isLast = index == total - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: index == 0 ? const Color(0xFF1565C0) : Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (entry.adviceEntries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...entry.adviceEntries.take(5).map((stock) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(stock.symbol,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          Text("${stock.weight.toStringAsFixed(1)}%",
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700)),
                        ],
                      ),
                    )),
                    if (entry.adviceEntries.length > 5)
                      Text(
                        "+${entry.adviceEntries.length - 5} more",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Common widgets
  // ---------------------------------------------------------------------------

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Broker Connection Gate
  // ---------------------------------------------------------------------------

  Future<BrokerConnection?> _ensureBrokerConnected() async {
    if (userEmail == null) return null;

    // Invalidate cache to get fresh broker status
    CacheService.instance.invalidate('aq/user/brokers:$userEmail');

    try {
      final response =
          await AqApiService.instance.getConnectedBrokers(userEmail!);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> brokerList =
            data['data'] ?? data['connected_brokers'] ?? [];
        final connected = brokerList
            .map((e) => BrokerConnection.fromJson(e))
            .where((b) => b.isConnected)
            .toList();

        if (connected.isNotEmpty) {
          if (connected.length == 1) return connected.first;
          // Multiple brokers — let user pick (no portfolio = picker mode)
          if (!mounted) return null;
          final result = await Navigator.push<BrokerConnection>(
            context,
            MaterialPageRoute(
                builder: (_) => BrokerSelectionPage(email: userEmail!)),
          );
          return result;
        }
      }
    } catch (e) {
      debugPrint('[DetailPage] _ensureBrokerConnected error: $e');
    }

    // No connected broker — show dialog with options
    if (!mounted) return null;
    final choice = await _showBrokerChoiceDialog();

    if (choice == 'connect') {
      if (!mounted) return null;
      final result = await Navigator.push<BrokerConnection>(
        context,
        MaterialPageRoute(
            builder: (_) => BrokerSelectionPage(email: userEmail!)),
      );
      return result;
    } else if (choice == 'dummy') {
      return BrokerConnection(broker: 'DummyBroker', status: 'connected');
    }
    return null; // cancelled
  }

  /// Returns 'connect', 'dummy', or null (cancelled).
  Future<String?> _showBrokerChoiceDialog() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("No Broker Connected",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text(
          "You don't have a broker connected. You can either connect one now, "
          "or continue without a broker and execute orders manually.",
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text("Cancel",
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'connect'),
            icon: const Icon(Icons.account_balance, size: 18),
            label: const Text("Connect Broker"),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'dummy'),
            icon: const Icon(Icons.touch_app, size: 18),
            label: const Text("Continue Without"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlanSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: InvestInPlanSheet(
          portfolio: portfolio,
          onSubscribed: () {
            _refreshDetails();
            if (mounted) setState(() => _isSubscribed = true);
          },
        ),
      ),
    );
  }

  Widget _bottomCta() {
    String label;
    IconData icon;
    VoidCallback? onPressed;

    if (_isSubscribed && userEmail != null) {
      if (_hasPendingRebalance) {
        label = "Execute Rebalance";
        icon = Icons.sync_rounded;
        onPressed = () async {
          final broker = await _ensureBrokerConnected();
          if (broker == null || !mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RebalanceReviewPage(
                portfolio: portfolio,
                email: userEmail!,
              ),
            ),
          );
        };
      } else {
        label = "Invest More";
        icon = Icons.add_circle_outline_rounded;
        onPressed = () async {
          final broker = await _ensureBrokerConnected();
          if (broker == null || !mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvestmentModal(
                portfolio: portfolio,
                email: userEmail!,
                brokerName: broker.broker,
              ),
            ),
          );
        };
      }
    } else {
      label = "Subscribe & Invest";
      icon = Icons.arrow_forward_rounded;
      onPressed = _showPlanSelectionSheet;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0), Colors.white],
          stops: const [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSubscribed
                  ? (_hasPendingRebalance ? Colors.orange.shade700 : const Color(0xFF1565C0))
                  : const Color(0xFF2E7D32),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const SizedBox.shrink(),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
