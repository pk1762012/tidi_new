import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/DataRepository.dart';

import '../components/home/portfolio/ModelPortfolioListPage.dart';
import '../components/home/portfolio/RebalanceReviewPage.dart';
import '../models/model_portfolio.dart';
import '../service/RebalanceStatusService.dart';

/// Compact card for the Market page showing:
/// - Count of subscribed model portfolios
/// - Aggregate invested / current value & P&L
/// - Pending rebalance alerts with a "Review" CTA
class PortfolioSummaryCard extends StatefulWidget {
  final String email;

  const PortfolioSummaryCard({super.key, required this.email});

  @override
  State<PortfolioSummaryCard> createState() => _PortfolioSummaryCardState();
}

class _PortfolioSummaryCardState extends State<PortfolioSummaryCard> {
  final _fmt = NumberFormat('#,##,###');
  bool _loading = true;
  int _portfolioCount = 0;
  double _totalInvested = 0;
  double _totalCurrent = 0;
  List<PendingRebalance> _pendingRebalances = [];
  List<ModelPortfolio> _subscribedPortfolios = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _fetchSubscribedStrategies(),
      _fetchPendingRebalances(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchSubscribedStrategies() async {
    try {
      await AqApiService.instance.getCachedSubscribedStrategies(
        email: widget.email,
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          List<dynamic> list;
          if (data is List) {
            list = data;
          } else if (data is Map) {
            list = data['subscribedPortfolios'] ?? data['data'] ?? data['strategies'] ?? [];
          } else {
            list = [];
          }
          final portfolios = list.map((e) => ModelPortfolio.fromJson(e)).toList();
          setState(() {
            _subscribedPortfolios = portfolios;
            _portfolioCount = portfolios.length;
          });
          // Fetch summaries in parallel
          for (final p in portfolios) {
            _fetchPortfolioSummary(p.modelName);
          }
        },
      );
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] fetchSubscribed error: $e');
    }
  }

  Future<void> _fetchPortfolioSummary(String modelName) async {
    try {
      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: widget.email,
        modelName: modelName,
      );
      if (response.statusCode == 200 && mounted) {
        final data = await DataRepository.parseJsonMap(response.body);
        final subData = data['data'];
        if (subData == null) return;

        final rawAmounts = subData['subscription_amount_raw'] ?? subData['subscriptionAmountRaw'] ?? [];
        double invested = 0;
        double current = 0;

        if (rawAmounts is List && rawAmounts.isNotEmpty) {
          final latest = rawAmounts.last;
          if (latest is Map) {
            invested = (latest['totalInvestment'] ?? latest['invested'] ?? 0).toDouble();
            current = (latest['currentValue'] ?? latest['current'] ?? invested).toDouble();
          }
        }

        if (invested == 0 && subData.containsKey('totalInvestment')) {
          invested = (subData['totalInvestment'] ?? 0).toDouble();
          current = (subData['currentValue'] ?? subData['current'] ?? invested).toDouble();
        }

        setState(() {
          _totalInvested += invested;
          _totalCurrent += current;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchPendingRebalances() async {
    try {
      final pending = await RebalanceStatusService.fetchPendingRebalances(widget.email);
      if (mounted) setState(() => _pendingRebalances = pending);
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] fetchRebalances error: $e');
    }
  }

  double get _pnl => _totalCurrent - _totalInvested;
  double get _pnlPct => _totalInvested > 0 ? (_pnl / _totalInvested * 100) : 0;

  @override
  Widget build(BuildContext context) {
    // Don't show anything while loading or if user has no subscribed portfolios
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_portfolioCount == 0) return const SizedBox.shrink();

    final isProfit = _pnl >= 0;
    final hasFinancialData = _totalInvested > 0 || _totalCurrent > 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ModelPortfolioListPage()),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF1A237E), const Color(0xFF283593)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A237E).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  const Icon(Icons.dashboard_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "My Portfolios ($_portfolioCount)",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text("View All",
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            // P&L summary (only when financial data exists)
            if (hasFinancialData)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Row(
                  children: [
                    _miniStat("Invested", "\u20B9${_fmt.format(_totalInvested.round())}"),
                    const SizedBox(width: 20),
                    _miniStat("Current", "\u20B9${_fmt.format(_totalCurrent.round())}"),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isProfit ? Colors.green : Colors.red).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isProfit ? Icons.trending_up : Icons.trending_down,
                            color: Colors.white, size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "${isProfit ? '+' : ''}${_pnlPct.toStringAsFixed(1)}%",
                            style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Pending rebalance alerts
            if (_pendingRebalances.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Column(
                  children: _pendingRebalances.map((r) {
                    return InkWell(
                      onTap: () => _navigateToRebalance(r),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.sync_alt_rounded, color: Colors.orange.shade300, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "${r.modelName} - New Rebalance",
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text("Review",
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }

  void _navigateToRebalance(PendingRebalance rebalance) {
    HapticFeedback.mediumImpact();
    // Find the matching portfolio
    final portfolio = _subscribedPortfolios.cast<ModelPortfolio?>().firstWhere(
      (p) => p?.modelName == rebalance.modelName,
      orElse: () => null,
    );

    if (portfolio != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RebalanceReviewPage(
            portfolio: portfolio,
            email: widget.email,
          ),
        ),
      );
    } else {
      // Fallback: navigate to list page
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ModelPortfolioListPage()),
      );
    }
  }
}
