import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_stock.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerSelectionPage.dart';
import 'InvestmentModal.dart';

class ModelPortfolioDetailPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String? userEmail;

  const ModelPortfolioDetailPage({
    super.key,
    required this.portfolio,
    this.userEmail,
  });

  @override
  State<ModelPortfolioDetailPage> createState() => _ModelPortfolioDetailPageState();
}

class _ModelPortfolioDetailPageState extends State<ModelPortfolioDetailPage> {
  late ModelPortfolio portfolio;
  bool subscribing = false;

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
          if (raw != null) {
            setState(() => portfolio = ModelPortfolio.fromJson(raw));
          }
        },
      );
    } catch (_) {}
  }

  bool get _isSubscribed =>
      widget.userEmail != null && portfolio.isSubscribedBy(widget.userEmail!);

  Future<void> _handleInvestTap() async {
    if (widget.userEmail == null) return;

    if (!_isSubscribed) {
      await _subscribe();
    }

    if (!mounted) return;

    // Check broker connection, then proceed to investment
    final response = await AqApiService.instance.getConnectedBrokers(widget.userEmail!);
    if (!mounted) return;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final brokers = data['data'] ?? data['connected_brokers'] ?? [];
      final connected = (brokers as List).where((b) =>
          b['status'] == 'connected').toList();

      if (connected.isEmpty) {
        // No connected broker — go to broker selection
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrokerSelectionPage(
              email: widget.userEmail!,
              portfolio: portfolio,
            ),
          ),
        );
      } else {
        // Has connected broker — proceed to investment
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvestmentModal(
              portfolio: portfolio,
              email: widget.userEmail!,
            ),
          ),
        );
      }
    }
  }

  Future<void> _subscribe() async {
    setState(() => subscribing = true);
    try {
      await AqApiService.instance.subscribeStrategy(
        strategyId: portfolio.id,
        email: widget.userEmail!,
        action: 'subscribe',
      );
      await _refreshDetails();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to subscribe. Please try again.")),
        );
      }
    }
    if (mounted) setState(() => subscribing = false);
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
                  const SizedBox(height: 20),
                  if (portfolio.overView != null) _overviewSection(),
                  const SizedBox(height: 16),
                  _statsGrid(),
                  const SizedBox(height: 20),
                  _stockComposition(),
                  const SizedBox(height: 20),
                  if (portfolio.whyThisStrategy != null) _whySection(),
                  if (portfolio.investmentStrategy.isNotEmpty) _strategySection(),
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

  Widget _header() {
    return Row(
      children: [
        if (portfolio.image != null && portfolio.image!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              portfolio.image!,
              width: 56,
              height: 56,
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
              const SizedBox(height: 4),
              if (portfolio.riskProfile != null)
                _riskBadge(portfolio.riskProfile!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.account_balance, size: 28, color: Color(0xFF3F51B5)),
    );
  }

  Widget _riskBadge(String risk) {
    Color color;
    switch (risk.toLowerCase()) {
      case 'aggressive': color = Colors.red.shade400; break;
      case 'moderate': color = Colors.orange.shade400; break;
      default: color = Colors.green.shade400;
    }
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
    return Row(
      children: [
        _statCard("Min Investment", "\u20B9${NumberFormat('#,##,###').format(portfolio.minInvestment)}",
            Icons.currency_rupee, Colors.blue),
        const SizedBox(width: 12),
        _statCard("Frequency", portfolio.frequency ?? "—",
            Icons.calendar_today_rounded, Colors.purple),
        const SizedBox(width: 12),
        _statCard("Stocks", "${portfolio.stocks.length}",
            Icons.pie_chart_rounded, Colors.teal),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
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
          ...sorted.map((stock) {
            final pct = totalWeight > 0 ? (stock.weight / totalWeight * 100) : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.userEmail == null || subscribing ? null : _handleInvestTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSubscribed ? const Color(0xFF1A237E) : const Color(0xFF2E7D32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: subscribing
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    _isSubscribed ? "Invest Now" : "Subscribe & Invest",
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
          ),
        ),
      ),
    );
  }
}
