import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';

import '../components/home/portfolio/CurrentHoldingsPreviewPage.dart';
import '../components/home/portfolio/ModelPortfolioDetailPage.dart';
import '../components/home/portfolio/ModelPortfolioListPage.dart';
import '../components/home/portfolio/PendingOrdersPage.dart';
import '../models/model_portfolio.dart';
import '../service/RebalanceStatusService.dart';

/// Shows each subscribed portfolio as an individual card on the Market page,
/// with a color-coded rebalance action button.
class PortfolioSummaryCard extends StatefulWidget {
  final String email;

  const PortfolioSummaryCard({super.key, required this.email});

  @override
  State<PortfolioSummaryCard> createState() => _PortfolioSummaryCardState();
}

class _PortfolioSummaryCardState extends State<PortfolioSummaryCard> {
  bool _loading = true;
  int _portfolioCount = 0;
  Map<String, PortfolioRebalanceStatus> _rebalanceStatusMap = {};
  List<ModelPortfolio> _subscribedPortfolios = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _fetchSubscribedStrategies(),
      _fetchRebalanceStatuses(),
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
        },
      );
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] fetchSubscribed error: $e');
    }

    // If AQ API returned nothing, check local subscriptions
    if (_portfolioCount == 0) {
      await _mergeLocalSubscriptions();
    }
  }

  /// Load locally-saved subscriptions (from subscribe-free flow) so they
  /// appear immediately even before the backend APIs reflect them.
  Future<void> _mergeLocalSubscriptions() async {
    try {
      final raw = await const FlutterSecureStorage().read(key: 'local_subscribed_portfolios');
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> entries = json.decode(raw);
      if (entries.isEmpty) return;

      final localNames = <String>{};
      for (final e in entries) {
        if (e is Map) {
          final name = e['modelName']?.toString();
          if (name != null && name.isNotEmpty) localNames.add(name);
        }
      }
      if (localNames.isEmpty) return;

      debugPrint('[PortfolioSummaryCard] found ${localNames.length} local subscriptions: $localNames');

      // Try to match local subscriptions against the full portfolio list from API
      try {
        final response = await AqApiService.instance.getPortfolios(email: widget.email);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = json.decode(response.body);
          final List<dynamic> allPlans = body is List
              ? body
              : (body is Map ? (body['data'] ?? body['plans'] ?? []) : []);
          final matched = <ModelPortfolio>[];
          for (final plan in allPlans) {
            if (plan is Map<String, dynamic>) {
              final p = ModelPortfolio.fromJson(plan);
              if (localNames.contains(p.modelName)) {
                matched.add(p);
              }
            }
          }
          if (matched.isNotEmpty && mounted) {
            setState(() {
              _subscribedPortfolios = matched;
              _portfolioCount = matched.length;
            });
            debugPrint('[PortfolioSummaryCard] matched ${matched.length} local subs to portfolios');
          }
        }
      } catch (e) {
        debugPrint('[PortfolioSummaryCard] portfolio match error: $e');
      }

      // Even if we can't match full portfolio objects, show the count
      if (_portfolioCount == 0 && localNames.isNotEmpty && mounted) {
        setState(() {
          _portfolioCount = localNames.length;
        });
      }
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] _mergeLocalSubscriptions error: $e');
    }
  }

  Future<void> _fetchRebalanceStatuses() async {
    try {
      final connectedBroker = await RebalanceStatusService.fetchConnectedBrokerName(widget.email);
      final statuses = await RebalanceStatusService.fetchAllRebalanceStatuses(
        widget.email,
        connectedBroker: connectedBroker,
      );
      if (mounted) setState(() => _rebalanceStatusMap = statuses);
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] fetchRebalanceStatuses error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_portfolioCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Row(
            children: [
              Icon(Icons.dashboard_rounded, color: Colors.indigo.shade800, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "My Portfolios ($_portfolioCount)",
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ModelPortfolioListPage()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("View All",
                    style: TextStyle(color: Colors.indigo.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),

        // Individual portfolio cards
        ..._subscribedPortfolios.map((p) => _portfolioCard(p)),
      ],
    );
  }

  Widget _portfolioCard(ModelPortfolio portfolio) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelPortfolioDetailPage(portfolio: portfolio),
          ),
        ).then((_) => _fetchRebalanceStatuses());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF1A237E), const Color(0xFF283593)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A237E).withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Portfolio name + risk badge + stock count
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      portfolio.modelName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (portfolio.riskProfile != null && portfolio.riskProfile!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _riskColor(portfolio.riskProfile).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        portfolio.riskProfile!,
                        style: TextStyle(
                          color: _riskColor(portfolio.riskProfile),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (portfolio.stocks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        "${portfolio.stocks.length} stocks",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Rebalance action row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _rebalanceActionRow(portfolio),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rebalanceActionRow(ModelPortfolio portfolio) {
    final status = _rebalanceStatusMap[portfolio.modelName] ??
        _rebalanceStatusMap[portfolio.modelName.toLowerCase()];

    String label;
    Color color;
    IconData icon;

    if (status == null) {
      label = 'View & Rebalance';
      color = Colors.blue;
      icon = Icons.sync;
    } else {
      switch (status.cardState) {
        case RebalanceCardState.pending:
        case RebalanceCardState.partiallyExecuted:
        case RebalanceCardState.failed:
          label = 'View & Rebalance';
          color = Colors.orange;
          icon = Icons.sync;
          break;
        case RebalanceCardState.pendingVerification:
          label = 'Check Order Status';
          color = Colors.amber.shade700;
          icon = Icons.hourglass_top;
          break;
        case RebalanceCardState.executed:
          label = 'View & Rebalance';
          color = Colors.blue;
          icon = Icons.sync;
          break;
      }
    }

    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        if (status != null && status.cardState == RebalanceCardState.pendingVerification) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PendingOrdersPage(
                portfolio: portfolio,
                email: widget.email,
                broker: status.broker,
                advisor: status.advisor,
              ),
            ),
          );
        } else {
          // All other states → rebalance flow
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CurrentHoldingsPreviewPage(
                portfolio: portfolio,
                email: widget.email,
              ),
            ),
          );
        }
        // Refresh status on return
        await _fetchRebalanceStatuses();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: color.withOpacity(0.7)),
          ],
        ),
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
}
