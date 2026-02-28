import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';

import '../components/home/portfolio/CurrentHoldingsPreviewPage.dart';
import '../components/home/portfolio/ModelPortfolioDetailPage.dart';
import '../components/home/portfolio/ModelPortfolioListPage.dart';
import '../components/home/portfolio/PendingOrdersPage.dart';
import '../models/model_portfolio.dart';
import '../service/RebalanceStatusService.dart';

/// Shows each subscribed portfolio as an individual card on the Market page,
/// with a color-coded rebalance action button.
///
/// Self-contained: resolves user email internally (same as ModelPortfolioListPage).
class PortfolioSummaryCard extends StatefulWidget {
  const PortfolioSummaryCard({super.key});

  @override
  State<PortfolioSummaryCard> createState() => _PortfolioSummaryCardState();
}

class _PortfolioSummaryCardState extends State<PortfolioSummaryCard> {
  bool _loading = true;
  String? _userEmail;
  Map<String, PortfolioRebalanceStatus> _rebalanceStatusMap = {};

  // All portfolios from API + subscribed IDs/names (mirrors ModelPortfolioListPage)
  List<ModelPortfolio> _allPortfolios = [];
  Set<String> _subscribedStrategyIds = {};
  Set<String> _subscribedModelNames = {};

  List<ModelPortfolio> get _subscribedPortfolios =>
      _allPortfolios.where((p) => _isSubscribed(p)).toList();

  bool _isSubscribed(ModelPortfolio p) {
    if (_subscribedStrategyIds.contains(p.strategyId)) return true;
    if (_subscribedStrategyIds.contains(p.id)) return true;
    if (_subscribedModelNames.contains(p.modelName.toLowerCase().trim())) return true;
    if (_userEmail != null && p.isSubscribedBy(_userEmail!)) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // ── Step 0: Resolve email (same as ModelPortfolioListPage) ──
    try {
      final email = await AqApiService.resolveUserEmail();
      if (mounted && email != null) {
        setState(() => _userEmail = email);
      }
      debugPrint('[PortfolioSummaryCard] resolved email=$email');
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] resolveUserEmail error: $e');
    }

    // ── Step 1: Load local subscriptions first (for instant display) ──
    await _loadLocalSubscriptions();

    // ── Step 2: Fetch all data in parallel ──
    await Future.wait([
      _fetchAllPortfolios(),
      _fetchSubscribedStrategies(),
      _fetchRebalanceStatuses(),
    ]);

    if (mounted) {
      final subscribed = _subscribedPortfolios;
      debugPrint('[PortfolioSummaryCard] FINAL: allPortfolios=${_allPortfolios.length}, '
          'subscribedIds=$_subscribedStrategyIds, subscribedNames=$_subscribedModelNames, '
          'matched=${subscribed.length}');
      setState(() => _loading = false);
    }
  }

  /// Fetch ALL available portfolios — same approach as ModelPortfolioListPage._fetchPortfolios
  Future<void> _fetchAllPortfolios() async {
    try {
      await AqApiService.instance.getCachedPortfolios(
        email: _userEmail ?? '',
        onData: (data, {required fromCache}) {
          if (!mounted) return;

          List<dynamic> list;
          String extractionPath;
          if (data is List) {
            list = data;
            extractionPath = 'top-level List';
          } else if (data is Map) {
            if (data['data'] is List) {
              list = data['data'];
              extractionPath = 'data key';
            } else if (data['portfolios'] is List) {
              list = data['portfolios'];
              extractionPath = 'portfolios key';
            } else if (data['models'] is List) {
              list = data['models'];
              extractionPath = 'models key';
            } else {
              list = data.values.whereType<List>().firstOrNull ?? [];
              extractionPath = 'fallback first List value';
            }
          } else {
            list = [];
            extractionPath = 'empty (unknown type)';
          }

          list = list.where((e) => e is Map && e['draft'] != true).toList();

          debugPrint('[PortfolioSummaryCard] portfolios: ${list.length} via $extractionPath (fromCache=$fromCache)');

          // Don't overwrite existing data with empty cache results
          if (fromCache && list.isEmpty && _allPortfolios.isNotEmpty) return;

          setState(() {
            _allPortfolios = list.map((e) => ModelPortfolio.fromJson(e)).toList();
          });
        },
      );
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] _fetchAllPortfolios error: $e');
    }
  }

  /// Fetch subscribed strategy IDs/names — same dual-API approach as
  /// ModelPortfolioListPage._fetchSubscribedStrategies
  Future<void> _fetchSubscribedStrategies() async {
    // ── 1. Try tidi_Front_back API first (resolves email from JWT internally) ──
    bool tidiApiSuccess = false;
    try {
      final response = await ApiService().getUserModelPortfolioSubscriptions();
      debugPrint('[PortfolioSummaryCard] tidi_subscriptions status=${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = json.decode(response.body);
        debugPrint('[PortfolioSummaryCard] tidi_subscriptions body type=${body.runtimeType}');
        final List<dynamic> strategies = body is List
            ? body
            : (body is Map
                ? (body['subscriptions'] ?? body['subscribedPortfolios'] ?? body['data'] ?? body['strategies'] ?? [])
                : []);
        debugPrint('[PortfolioSummaryCard] tidi strategies count=${strategies.length}');
        if (strategies.isNotEmpty) {
          tidiApiSuccess = true;
          final ids = <String>{};
          final names = <String>{};
          for (final s in strategies) {
            if (s is Map) {
              final id = s['_id']?.toString() ?? s['strategyId']?.toString();
              if (id != null && id.isNotEmpty) ids.add(id);
              final modelId = s['model_id']?.toString() ?? s['modelId']?.toString();
              if (modelId != null && modelId.isNotEmpty) ids.add(modelId);
              final modelName = s['model_name']?.toString() ?? s['name']?.toString();
              if (modelName != null && modelName.isNotEmpty) {
                names.add(modelName.toLowerCase().trim());
              }
            } else if (s is String && s.isNotEmpty) {
              ids.add(s);
            }
          }
          debugPrint('[PortfolioSummaryCard] tidi subscribedIds=$ids, names=$names');
          if (mounted) {
            setState(() {
              _subscribedStrategyIds = ids;
              _subscribedModelNames = names;
            });
          }
          return; // Success — no need to fall back
        }
      }
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] tidi_subscriptions error (will fallback): $e');
    }

    // ── 2. Fallback: AlphaQuark API if tidi_Front_back failed or returned empty ──
    if (!tidiApiSuccess && _userEmail != null && _userEmail!.isNotEmpty) {
      debugPrint('[PortfolioSummaryCard] falling back to AlphaQuark API');
      try {
        final response = await AqApiService.instance.getSubscribedStrategies(_userEmail!);
        debugPrint('[PortfolioSummaryCard] AQ subscribedStrategies status=${response.statusCode}');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = json.decode(response.body);
          debugPrint('[PortfolioSummaryCard] AQ body type=${body.runtimeType}');
          final List<dynamic> strategies = body is List
              ? body
              : (body is Map
                  ? (body['subscribedPortfolios'] ?? body['data'] ?? body['strategies'] ?? [])
                  : []);
          debugPrint('[PortfolioSummaryCard] AQ strategies count=${strategies.length}');
          final ids = <String>{};
          final names = <String>{};
          for (final s in strategies) {
            if (s is Map) {
              final id = s['_id']?.toString() ?? s['strategyId']?.toString();
              if (id != null && id.isNotEmpty) ids.add(id);
              final modelId = s['model_id']?.toString() ?? s['modelId']?.toString();
              if (modelId != null && modelId.isNotEmpty) ids.add(modelId);
              final modelName = s['model_name']?.toString() ?? s['name']?.toString();
              if (modelName != null && modelName.isNotEmpty) {
                names.add(modelName.toLowerCase().trim());
              }
            } else if (s is String && s.isNotEmpty) {
              ids.add(s);
            }
          }
          debugPrint('[PortfolioSummaryCard] AQ subscribedIds=$ids, names=$names');
          if (mounted) {
            setState(() {
              _subscribedStrategyIds = ids;
              _subscribedModelNames = names;
            });
          }
        }
      } catch (e) {
        debugPrint('[PortfolioSummaryCard] AQ fallback error: $e');
      }
    }
  }

  /// Load locally-saved subscriptions so they appear immediately even before
  /// the backend APIs reflect them.
  Future<void> _loadLocalSubscriptions() async {
    try {
      final raw = await const FlutterSecureStorage().read(key: 'local_subscribed_portfolios');
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> entries = json.decode(raw);
      if (entries.isEmpty) return;

      final localIds = <String>{};
      final localNames = <String>{};
      for (final e in entries) {
        if (e is Map) {
          final sid = e['strategyId']?.toString();
          final pid = e['planId']?.toString();
          final name = e['modelName']?.toString();
          if (sid != null && sid.isNotEmpty) localIds.add(sid);
          if (pid != null && pid.isNotEmpty) localIds.add(pid);
          if (name != null && name.isNotEmpty) {
            localNames.add(name.toLowerCase().trim());
          }
        }
      }
      if (localIds.isEmpty && localNames.isEmpty) return;

      debugPrint('[PortfolioSummaryCard] local subscriptions: ids=$localIds, names=$localNames');
      if (mounted) {
        setState(() {
          _subscribedStrategyIds = {..._subscribedStrategyIds, ...localIds};
          _subscribedModelNames = {..._subscribedModelNames, ...localNames};
        });
      }
    } catch (e) {
      debugPrint('[PortfolioSummaryCard] _loadLocalSubscriptions error: $e');
    }
  }

  Future<void> _fetchRebalanceStatuses() async {
    if (_userEmail == null || _userEmail!.isEmpty) return;
    try {
      final connectedBroker = await RebalanceStatusService.fetchConnectedBrokerName(_userEmail!);
      final statuses = await RebalanceStatusService.fetchAllRebalanceStatuses(
        _userEmail!,
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

    final subscribed = _subscribedPortfolios;
    if (subscribed.isEmpty) return const SizedBox.shrink();

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
                  "My Portfolios (${subscribed.length})",
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
        ...subscribed.map((p) => _portfolioCard(p)),
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
        if (_userEmail == null) return;
        if (status != null && status.cardState == RebalanceCardState.pendingVerification) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PendingOrdersPage(
                portfolio: portfolio,
                email: _userEmail!,
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
                email: _userEmail!,
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
