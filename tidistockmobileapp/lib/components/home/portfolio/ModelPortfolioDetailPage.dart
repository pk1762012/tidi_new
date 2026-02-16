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
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'InvestedPortfoliosPage.dart';
import 'PlanSelectionSheet.dart';

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

  // Cached sorted stock composition (recomputed when portfolio changes)
  List<PortfolioStock> _sortedStocks = [];
  double _totalWeight = 0;
  double _maxPct = 1;

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
    _loadUserEmail();
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

  Future<void> _loadUserEmail() async {
    final email = await const FlutterSecureStorage().read(key: 'user_email');
    if (mounted) setState(() => userEmail = email);
  }

  Future<void> _refreshDetails() async {
    try {
      await AqApiService.instance.getCachedStrategyDetails(
        modelName: portfolio.modelName,
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final raw = data is Map ? data : (data is List && data.isNotEmpty ? data[0] : null);
          if (raw != null && raw is Map) {
            final strategyData = ModelPortfolio.fromJson(Map<String, dynamic>.from(raw));
            setState(() {
              portfolio = portfolio.mergeStrategyData(strategyData);
              _updateSortedStocks();
              _loadingStrategy = false;
            });
          } else {
            if (mounted) setState(() => _loadingStrategy = false);
          }
        },
      );
    } catch (e) {
      debugPrint('[DetailPage] _refreshDetails error: $e');
      if (mounted) setState(() => _loadingStrategy = false);
    }
  }

  Future<void> _fetchPerformanceData() async {
    try {
      final response = await AqApiService.instance.getPortfolioPerformance(
        advisor: portfolio.advisor,
        modelName: portfolio.modelName,
      );
      if (response.statusCode == 200) {
        final body = await DataRepository.parseJsonMap(response.body);
        final data = body['data'];
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
                children: [
                  _header(),
                  if (portfolio.overView != null && portfolio.overView!.isNotEmpty)
                    _overviewSection(),
                  const SizedBox(height: 16),
                  _statsGrid(),
                  const SizedBox(height: 16),
                  _stockComposition(),
                  const SizedBox(height: 16),
                  _tabBar(),
                  const SizedBox(height: 12),
                  _tabContent(),
                ],
              ),
            ),
          ),
          _bottomCta(),
        ],
      ),
    );
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

  Widget _statsGrid() {
    final cards = <Widget>[
      _statCard("Min Investment", "\u20B9${NumberFormat('#,##,###').format(portfolio.minInvestment)}",
          Icons.currency_rupee, Colors.blue),
    ];
    if (portfolio.frequency != null && portfolio.frequency!.isNotEmpty && portfolio.frequency != "—") {
      cards.add(_statCard("Frequency", portfolio.frequency!,
          Icons.calendar_today_rounded, Colors.purple));
    }
    if (portfolio.stocks.isNotEmpty) {
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
        tabs: const [
          Tab(text: "Distribution"),
          Tab(text: "Why this Strategy"),
          Tab(text: "Methodology"),
        ],
      ),
    );
  }

  Widget _tabContent() {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rebalanceInfoSection(),
        if (_performancePoints.isNotEmpty || _loadingPerformance)
          _performanceChartSection(),
        if (portfolio.performanceData != null)
          _performanceMetricsSection(),
      ],
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
        _metricsCard("Returns", [
          _metricItem("CAGR", perf.cagr, isPercent: true),
          _metricItem("Total Return", perf.totalReturn, isPercent: true),
          _metricItem("YTD Return", perf.ytdReturn, isPercent: true),
          _metricItem("1Y Return", perf.oneYearReturn, isPercent: true),
        ]),
        _metricsCard("Risk", [
          _metricItem("Volatility", perf.volatility, isPercent: true),
          _metricItem("Value at Risk", perf.valueAtRisk, isPercent: true),
          _metricItem("CVaR", perf.cvar, isPercent: true),
          _metricItem("Ulcer Index", perf.ulcerIndex),
        ]),
        _metricsCard("Drawdown", [
          _metricItem("Max Drawdown", perf.maxDrawdown, isPercent: true),
          _metricItem("Avg Drawdown", perf.avgDrawdown, isPercent: true),
          if (perf.longestDdDays != null)
            _metricItemRaw("Longest DD", "${perf.longestDdDays} days"),
        ]),
        _metricsCard("Ratios", [
          _metricItem("Sharpe Ratio", perf.sharpeRatio),
          _metricItem("Sortino Ratio", perf.sortinoRatio),
          _metricItem("Profit Factor", perf.profitFactor),
          _metricItem("Gain to Pain", perf.gainToPain),
        ]),
        _metricsCard("Timing", [
          _metricItem("Win Rate", perf.winRate, isPercent: true),
          _metricItem("Best Day", perf.bestDay, isPercent: true),
          _metricItem("Worst Day", perf.worstDay, isPercent: true),
          _metricItem("Time in Market", perf.timeInMarket, isPercent: true),
        ]),
      ],
    );
  }

  Widget _metricsCard(String title, List<Widget?> items) {
    final validItems = items.whereType<Widget>().toList();
    if (validItems.isEmpty) return const SizedBox.shrink();

    return _section(
      title,
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: validItems,
      ),
    );
  }

  Widget? _metricItem(String label, double? value, {bool isPercent = false}) {
    if (value == null) return null;
    final display = isPercent
        ? "${value.toStringAsFixed(2)}%"
        : value.toStringAsFixed(2);
    return _metricItemRaw(label, display, valueColor: value >= 0 ? Colors.green.shade700 : Colors.red.shade700);
  }

  Widget _metricItemRaw(String label, String display, {Color? valueColor}) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 2),
          Text(display,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: valueColor ?? Colors.grey.shade800)),
        ],
      ),
    );
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

  void _showPlanSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlanSelectionSheet(
        portfolio: portfolio,
        onSubscribed: () {
          _refreshDetails();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _bottomCta() {
    final bool isSubscribed =
        userEmail != null && portfolio.isSubscribedBy(userEmail!);

    String label;
    IconData icon;
    VoidCallback onPressed;

    if (isSubscribed) {
      label = "View Holdings";
      icon = Icons.account_balance_wallet_rounded;
      onPressed = () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvestedPortfoliosPage(email: userEmail!),
          ),
        );
      };
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
              backgroundColor: isSubscribed
                  ? const Color(0xFF1565C0)
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
