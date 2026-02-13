import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_stock.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'AqWebViewPage.dart';

class ModelPortfolioDetailPage extends StatefulWidget {
  final ModelPortfolio portfolio;

  const ModelPortfolioDetailPage({
    super.key,
    required this.portfolio,
  });

  @override
  State<ModelPortfolioDetailPage> createState() => _ModelPortfolioDetailPageState();
}

class _ModelPortfolioDetailPageState extends State<ModelPortfolioDetailPage> {
  late ModelPortfolio portfolio;

  @override
  void initState() {
    super.initState();
    portfolio = widget.portfolio;
    _refreshDetails();
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
            // Merge only stocks/rebalance from strategy, keep Plans API data as source of truth
            setState(() => portfolio = portfolio.mergeStrategyData(strategyData));
          }
        },
      );
    } catch (e) {
      debugPrint('[DetailPage] _refreshDetails error: $e');
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
                  if (portfolio.whyThisStrategy != null && portfolio.whyThisStrategy!.isNotEmpty)
                    _whySection(),
                  if (portfolio.investmentStrategy.isNotEmpty)
                    _strategySection(),
                  if (portfolio.frequency != null || portfolio.nextRebalanceDate != null || portfolio.rebalanceHistory.isNotEmpty)
                    _rebalanceInfo(),
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
        ],
      ),
    );
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
    if (portfolio.stocks.isEmpty) return const SizedBox.shrink();

    // Sort by weight descending
    final sorted = List<PortfolioStock>.from(portfolio.stocks)
      ..sort((a, b) => b.weight.compareTo(a.weight));

    // Calculate total weight for percentage
    final totalWeight = sorted.fold(0.0, (sum, s) => sum + s.weight);
    final maxPct = totalWeight > 0 ? (sorted.first.weight / totalWeight * 100) : 1.0;

    return _section(
      "Stock Composition",
      Column(
        children: [
          // Header
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
          ...List.generate(sorted.length, (index) {
            final stock = sorted[index];
            final pct = totalWeight > 0 ? (stock.weight / totalWeight * 100) : 0.0;
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
                  // Weight bar
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: maxPct > 0 ? (pct / maxPct).clamp(0.0, 1.0) : 0,
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

  Widget _whySection() {
    return _section(
      "Why This Strategy",
      Text(
        portfolio.whyThisStrategy!,
        style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
      ),
    );
  }

  Widget _strategySection() {
    return _section(
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
    );
  }

  Widget _rebalanceInfo() {
    return _section(
      "Rebalance Schedule",
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow("Frequency", portfolio.frequency ?? "—"),
          if (portfolio.nextRebalanceDate != null)
            _infoRow("Next Rebalance",
                DateFormat("dd MMM yyyy").format(portfolio.nextRebalanceDate!)),
          if (portfolio.rebalanceHistory.isNotEmpty)
            _infoRow("Total Rebalances", "${portfolio.rebalanceHistory.length}"),
        ],
      ),
    );
  }

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

  Widget _bottomCta() {
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
            onPressed: () {
              final encodedName = Uri.encodeComponent(portfolio.modelName);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AqWebViewPage(
                    url: 'https://prod.alphaquark.in/model-portfolio/$encodedName',
                    title: portfolio.modelName,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const SizedBox.shrink(),
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Subscribe & Invest",
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
