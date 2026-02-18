import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'ModelPortfolioDetailPage.dart';
import 'InvestedPortfoliosPage.dart';
import 'RebalanceReviewPage.dart';

class ModelPortfolioListPage extends StatefulWidget {
  const ModelPortfolioListPage({super.key});

  @override
  State<ModelPortfolioListPage> createState() => _ModelPortfolioListPageState();
}

class _ModelPortfolioListPageState extends State<ModelPortfolioListPage>
    with SingleTickerProviderStateMixin {
  List<ModelPortfolio> portfolios = [];
  Set<String> _subscribedStrategyIds = {};
  Set<String> _subscribedModelNames = {};
  bool loading = true;
  String? error;
  String? userEmail;

  List<Map<String, dynamic>> _recentlyVisited = [];
  bool _showingAllPortfolios = false;

  // Rebalance tracking
  List<Map<String, dynamic>> _pendingRebalances = [];
  bool _loadingRebalances = true;

  late TabController _tabController;

  List<ModelPortfolio> get _subscribedPortfolios =>
      portfolios.where((p) => _isSubscribed(p)).toList();

  List<ModelPortfolio> get _explorePortfolios =>
      portfolios.where((p) => !_isSubscribed(p)).toList();

  bool _isSubscribed(ModelPortfolio p) {
    // Check via subscribed strategies API (strategy_id or plan _id)
    if (_subscribedStrategyIds.contains(p.strategyId)) return true;
    if (_subscribedStrategyIds.contains(p.id)) return true;
    // Check by model name (normalized comparison)
    if (_subscribedModelNames.contains(p.modelName.toLowerCase().trim())) return true;
    // Fallback: check subscribedBy from Plans API (if it ever populates)
    if (userEmail != null && p.isSubscribedBy(userEmail!)) return true;
    return false;
  }

  bool get _hasSubscribed => _subscribedPortfolios.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    // Read email for display purposes and fallback API calls
    // Note: tidi_Front_back API resolves email internally from user_id in JWT
    final email = await const FlutterSecureStorage().read(key: 'user_email');
    if (email == null || email.isEmpty) {
      debugPrint('[ModelPortfolio] INFO: user_email is null - will use master email from tidi_Front_back');
    } else {
      debugPrint('[ModelPortfolio] user_email=$email (for display/fallback)');
    }
    if (mounted) setState(() => userEmail = email);
    // Load local subscriptions and recently visited first for instant display
    await Future.wait([
      _loadLocalSubscriptions(),
      _loadRecentlyVisited(),
    ]);
    await Future.wait([
      _fetchPortfolios(),
      _fetchSubscribedStrategies(),
      _fetchRebalanceStatus(),
    ]);
  }

  Future<void> _fetchRebalanceStatus() async {
    if (userEmail == null || userEmail!.isEmpty) {
      if (mounted) setState(() => _loadingRebalances = false);
      return;
    }

    try {
      final response = await AqApiService.instance.getSubscribedStrategies(userEmail!);
      debugPrint('[ModelPortfolio] rebalanceStatus response: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = json.decode(response.body);
        final List<dynamic> subscriptions = body is List
            ? body
            : (body['subscribedPortfolios'] ?? body['data'] ?? []);

        debugPrint('[ModelPortfolio] subscriptions count: ${subscriptions.length}');

        final pending = <Map<String, dynamic>>[];

        for (final sub in subscriptions) {
          if (sub is! Map) continue;

          final modelName = sub['model_name']?.toString() ?? sub['modelName']?.toString() ?? '';
          final model = sub['model'] as Map<String, dynamic>?;
          if (model == null) continue;

          final rebalanceHistory = model['rebalanceHistory'] as List<dynamic>? ?? [];
          debugPrint('[ModelPortfolio] $modelName has ${rebalanceHistory.length} rebalances');

          // Find the latest rebalance with execution status
          for (final rebalance in rebalanceHistory.reversed) {
            // Check for executionStatus at different levels
            final execData = rebalance['execution'] ?? rebalance['subscriberExecutions'] ?? rebalance;
            final status = (execData['executionStatus'] ?? execData['status'] ?? execData['userExecution']?['status'] ?? '').toString().toLowerCase();

            debugPrint('[ModelPortfolio] $modelName rebalance status: $status');

            // Check for pending/toExecute/partial statuses
            if (status == 'toexecute' || status == 'pending' || status == 'partial' || status == '') {
              pending.add({
                'modelName': modelName,
                'modelId': sub['_id'] ?? sub['id'] ?? sub['model_id'] ?? '',
                'rebalanceDate': rebalance['rebalanceDate'] ?? rebalance['date'],
                'executionStatus': status,
                'broker': execData['user_broker'] ?? execData['broker'] ?? 'DummyBroker',
                'advisor': model['advisor'] ?? '',
              });
              break;
            }
          }
        }

        if (mounted) {
          setState(() {
            _pendingRebalances = pending;
            _loadingRebalances = false;
          });
          debugPrint('[ModelPortfolio] pending rebalances: ${pending.length}');
        }
      }
    } catch (e) {
      debugPrint('[ModelPortfolio] _fetchRebalanceStatus error: $e');
      if (mounted) setState(() => _loadingRebalances = false);
    }
  }

  Future<void> _fetchSubscribedStrategies() async {
    // Try tidi_Front_back API first (resolves email internally from user_id)
    // This ensures subscriptions work even if user has different email in AlphaQuark
    bool tidiApiSuccess = false;
    try {
      final response = await ApiService().getUserModelPortfolioSubscriptions();
      debugPrint('[ModelPortfolio] tidi_subscriptions status=${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = json.decode(response.body);
        final List<dynamic> strategies = body is List
            ? body
            : (body is Map
                ? (body['subscriptions'] ?? body['subscribedPortfolios'] ?? body['data'] ?? body['strategies'] ?? [])
                : []);
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
          debugPrint('[ModelPortfolio] tidi_subscribedStrategyIds=$ids, names=$names');
          if (mounted) {
            setState(() {
              _subscribedStrategyIds = ids;
              _subscribedModelNames = names;
            });
          }
          await _pruneLocalSubscriptions(ids, names);
          return; // Success - no need to fall back
        }
      }
    } catch (e) {
      debugPrint('[ModelPortfolio] tidi_subscriptions error (will fallback): $e');
    }

    // Fallback: Try AlphaQuark API directly if tidi_Front_back fails or returns empty
    // This maintains backward compatibility
    if (!tidiApiSuccess && userEmail != null && userEmail!.isNotEmpty) {
      debugPrint('[ModelPortfolio] Falling back to AlphaQuark API');
      try {
        final response = await AqApiService.instance.getSubscribedStrategies(userEmail!);
        debugPrint('[ModelPortfolio] AlphaQuark subscribedStrategies status=${response.statusCode}');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = json.decode(response.body);
          final List<dynamic> strategies = body is List
              ? body
              : (body is Map
                  ? (body['subscribedPortfolios'] ?? body['data'] ?? body['strategies'] ?? [])
                  : []);
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
          debugPrint('[ModelPortfolio] AlphaQuark subscribedStrategyIds=$ids, names=$names');
          if (mounted) {
            setState(() {
              _subscribedStrategyIds = ids;
              _subscribedModelNames = names;
            });
          }
          await _pruneLocalSubscriptions(ids, names);
          return;
        }
      } catch (e) {
        debugPrint('[ModelPortfolio] AlphaQuark fallback error: $e');
      }
    }

    // Merge any remaining local subscriptions not yet reflected by API
    await _loadLocalSubscriptions();
  }

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
      debugPrint('[ModelPortfolio] loaded local subscriptions: ids=$localIds, names=$localNames');
      if (mounted) {
        setState(() {
          _subscribedStrategyIds = {..._subscribedStrategyIds, ...localIds};
          _subscribedModelNames = {..._subscribedModelNames, ...localNames};
        });
      }
    } catch (e) {
      debugPrint('[ModelPortfolio] _loadLocalSubscriptions error: $e');
    }
  }

  Future<void> _loadRecentlyVisited() async {
    try {
      final raw = await const FlutterSecureStorage().read(key: 'recently_visited_portfolios');
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> entries = json.decode(raw);
      if (mounted) {
        setState(() {
          _recentlyVisited = entries.whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (e) {
      debugPrint('[ModelPortfolio] _loadRecentlyVisited error: $e');
    }
  }

  Future<void> _pruneLocalSubscriptions(Set<String> apiIds, Set<String> apiNames) async {
    try {
      final raw = await const FlutterSecureStorage().read(key: 'local_subscribed_portfolios');
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> entries = json.decode(raw);
      final remaining = entries.where((e) {
        if (e is! Map) return false;
        final sid = e['strategyId']?.toString() ?? '';
        final pid = e['planId']?.toString() ?? '';
        final name = (e['modelName']?.toString() ?? '').toLowerCase().trim();
        // Remove if API already knows about this subscription
        final confirmedById = apiIds.contains(sid) || apiIds.contains(pid);
        final confirmedByName = name.isNotEmpty && apiNames.contains(name);
        return !confirmedById && !confirmedByName;
      }).toList();
      await const FlutterSecureStorage().write(
        key: 'local_subscribed_portfolios',
        value: json.encode(remaining),
      );
      if (remaining.length < entries.length) {
        debugPrint('[ModelPortfolio] pruned ${entries.length - remaining.length} local subscriptions');
      }
    } catch (e) {
      debugPrint('[ModelPortfolio] _pruneLocalSubscriptions error: $e');
    }
  }

  Future<void> _fetchPortfolios() async {
    try {
      await AqApiService.instance.getCachedPortfolios(
        email: userEmail ?? '',
        onData: (data, {required fromCache}) {
          if (!mounted) return;

          debugPrint('[ModelPortfolio] onData type=${data.runtimeType} fromCache=$fromCache${data is Map ? ' keys=${(data as Map).keys}' : ''}');

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
              list = (data as Map).values.whereType<List>().firstOrNull ?? [];
              extractionPath = 'fallback first List value';
            }
          } else {
            list = [];
            extractionPath = 'empty (unknown type)';
          }

          list = list.where((e) => e is Map && e['draft'] != true).toList();

          debugPrint('[ModelPortfolio] parsed ${list.length} portfolios via $extractionPath, userEmail=$userEmail');

          // Don't overwrite existing data with empty cache results — wait for network
          if (fromCache && list.isEmpty && portfolios.isNotEmpty) {
            debugPrint('[ModelPortfolio] skipping empty cache update (already have ${portfolios.length} portfolios)');
            return;
          }

          setState(() {
            portfolios = list.map((e) => ModelPortfolio.fromJson(e)).toList();
            loading = false;
            error = null;
          });
          debugPrint('[ModelPortfolio] _hasSubscribed=$_hasSubscribed, subscribed=${_subscribedPortfolios.length}, explore=${_explorePortfolios.length}');

          // Auto-switch to Subscribed tab if user has subscriptions
          if (_hasSubscribed && _tabController.index == 1) {
            _tabController.animateTo(0);
          }
        },
      );
    } on HttpException catch (e) {
      debugPrint('[ModelPortfolio] fetch HTTP error: ${e.statusCode}');
      if (mounted) {
        setState(() {
          loading = false;
          error = e.statusCode == 401 || e.statusCode == 403
              ? 'Authentication failed (${e.statusCode}). Please re-login.'
              : 'Server error (${e.statusCode}). Pull to retry.';
        });
      }
    } on OfflineException {
      debugPrint('[ModelPortfolio] fetch offline');
      if (mounted) {
        setState(() {
          loading = false;
          error = 'No internet connection. Pull to retry when online.';
        });
      }
    } catch (e) {
      debugPrint('[ModelPortfolio] fetch error: $e');
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Unable to load portfolios. Pull to retry.';
        });
      }
    }
  }

  Future<void> _forceRefresh() async {
    debugPrint('[ModelPortfolio] _forceRefresh: invalidating caches');
    CacheService.instance.invalidate('aq/admin/plan/portfolios');
    if (userEmail != null) {
      CacheService.instance.invalidate('aq/model-portfolio/subscribed:$userEmail');
    }
    await _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Model Portfolios",
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() { loading = true; error = null; });
                  _forceRefresh();
                },
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    // Show recently visited landing if available and not toggled to full list
    if (_recentlyVisited.isNotEmpty && !_showingAllPortfolios) {
      return _buildRecentlyVisitedView();
    }

    // If user has no subscriptions, show flat explore list (no tabs needed)
    if (!_hasSubscribed) {
      return Column(
        children: [
          if (_recentlyVisited.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showingAllPortfolios = false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text("Recently Visited"),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _forceRefresh,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: portfolios.isEmpty ? 1 : portfolios.length,
                itemBuilder: (context, index) {
                  if (portfolios.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(
                        child: Text("No model portfolios available yet.",
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),
                    );
                  }
                  return _portfolioCard(portfolios[index]);
                },
              ),
            ),
          ),
        ],
      );
    }

    // User has subscriptions — show tab layout
    return _buildFullListView();
  }

  Widget _buildRecentlyVisitedView() {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _forceRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // Pending Rebalances section at the top
                if (_hasSubscribed && userEmail != null) _buildPendingRebalancesSection(),

                // "My Investments" banner if user has subscriptions
                if (_hasSubscribed && userEmail != null) _investedPortfoliosBanner(),

                // Recently Visited header
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 20, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      const Text("Recently Visited",
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),

                // Recently visited portfolio cards
                ..._recentlyVisited.map((entry) {
                  final modelName = entry['modelName']?.toString() ?? '';
                  final entryId = entry['id']?.toString() ?? '';
                  // Look up full portfolio from loaded list
                  final fullPortfolio = portfolios.cast<ModelPortfolio?>().firstWhere(
                    (p) =>
                        p!.modelName == modelName ||
                        p.id == entryId,
                    orElse: () => null,
                  );

                  if (fullPortfolio != null) {
                    return _portfolioCard(fullPortfolio);
                  }

                  // Fallback: render a minimal card from stored data
                  return _recentVisitFallbackCard(entry);
                }),
              ],
            ),
          ),
        ),
        // Floating bottom button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _showingAllPortfolios = true);
            },
            icon: const Icon(Icons.explore_rounded, size: 18),
            label: const Text("Browse All Portfolios"),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recentVisitFallbackCard(Map<String, dynamic> entry) {
    final modelName = entry['modelName']?.toString() ?? 'Portfolio';
    final image = entry['image']?.toString() ?? '';
    final riskProfile = entry['riskProfile']?.toString() ?? '';
    final advisor = entry['advisor']?.toString() ?? '';
    final riskColor = _riskColor(riskProfile);

    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        // Build a minimal ModelPortfolio from stored data
        final minimalPortfolio = ModelPortfolio.fromJson({
          '_id': entry['id'] ?? '',
          'model_name': modelName,
          'image': image,
          'risk_profile': riskProfile,
          'advisor': advisor,
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelPortfolioDetailPage(portfolio: minimalPortfolio),
          ),
        );
        await _init();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: riskColor, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (image.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        image,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        cacheWidth: 88,
                        cacheHeight: 88,
                        errorBuilder: (_, __, ___) => _placeholderIcon(),
                      ),
                    )
                  else
                    _placeholderIcon(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(modelName,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
                        if (advisor.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text("by $advisor",
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullListView() {
    return Column(
      children: [
        // Back to recently visited (if available)
        if (_recentlyVisited.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showingAllPortfolios = false),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text("Recently Visited"),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),

        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            onTap: (_) => setState(() {}),
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
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bookmark_rounded, size: 16),
                    const SizedBox(width: 6),
                    Text('Subscribed (${_subscribedPortfolios.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.explore_rounded, size: 16),
                    const SizedBox(width: 6),
                    Text('Explore (${_explorePortfolios.length})'),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSubscribedTab(),
              _buildExploreTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Subscribed tab
  // ---------------------------------------------------------------------------

  Widget _buildSubscribedTab() {
    final subscribed = _subscribedPortfolios;

    return RefreshIndicator(
      onRefresh: _forceRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // "My Investments" banner to go to detailed holdings
          if (userEmail != null) _investedPortfoliosBanner(),

          if (subscribed.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.folder_open_rounded, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text("No subscribed portfolios yet.",
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Text("Explore portfolios and subscribe to get started.",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            )
          else
            ...subscribed.map((p) => _portfolioCard(p, showSubscribedBadge: true)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Explore tab
  // ---------------------------------------------------------------------------

  Widget _buildExploreTab() {
    final explore = _explorePortfolios;

    return RefreshIndicator(
      onRefresh: _forceRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (explore.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade300),
                    const SizedBox(height: 12),
                    Text("You've subscribed to all available portfolios!",
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                      textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else
            ...explore.map((p) => _portfolioCard(p)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _buildPendingRebalancesSection() {
    if (_loadingRebalances) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_pendingRebalances.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade600,
            Colors.orange.shade800,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Pending Rebalance",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        "${_pendingRebalances.length} portfolio(s) need attention",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // List pending rebalances
          ..._pendingRebalances.map((rebalance) {
            final modelName = rebalance['modelName'] ?? 'Portfolio';
            final broker = rebalance['broker'] ?? 'DummyBroker';
            return InkWell(
              onTap: () => _executeRebalance(rebalance),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modelName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "Broker: $broker",
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Execute",
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _executeRebalance(Map<String, dynamic> rebalance) async {
    final modelName = rebalance['modelName'];
    final modelId = rebalance['modelId'];

    // Find the portfolio from the list
    final portfolio = portfolios.cast<ModelPortfolio?>().firstWhere(
      (p) => p?.modelName == modelName || p?.id == modelId || p?.strategyId == modelId,
      orElse: () => null,
    );

    if (portfolio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Portfolio not found")),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RebalanceReviewPage(
          portfolio: portfolio,
          email: userEmail!,
        ),
      ),
    );
    // Refresh after returning
    await _init();
  }

  Widget _investedPortfoliosBanner() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvestedPortfoliosPage(email: userEmail!),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF283593)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.dashboard_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("My Investments",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  SizedBox(height: 2),
                  Text("View your invested portfolios & P&L",
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
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

  Widget _portfolioCard(ModelPortfolio portfolio, {bool showSubscribedBadge = false}) {
    final isSubscribed = userEmail != null && portfolio.isSubscribedBy(userEmail!);
    final riskColor = _riskColor(portfolio.riskProfile);

    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelPortfolioDetailPage(
              portfolio: portfolio,
            ),
          ),
        );
        // Refresh after returning from detail page
        await _init();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: riskColor, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subscribed badge
                if (isSubscribed && showSubscribedBadge)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2E7D32),
                    ),
                    child: const Center(
                      child: Text("Subscribed",
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
                      Row(
                        children: [
                          if (portfolio.image != null && portfolio.image!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                portfolio.image!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                cacheWidth: 88,
                                cacheHeight: 88,
                                errorBuilder: (_, __, ___) => _placeholderIcon(),
                              ),
                            )
                          else
                            _placeholderIcon(),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  portfolio.modelName,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (portfolio.riskProfile != null && portfolio.riskProfile!.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: _riskBadge(portfolio.riskProfile!),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
                        ],
                      ),

                      if (portfolio.overView != null && portfolio.overView!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          portfolio.overView!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Stats row
                      Row(
                        children: [
                          _statChip(Icons.currency_rupee, "Min",
                              "\u20B9${_formatCurrency(portfolio.minInvestment)}", Colors.blue),
                          if (portfolio.riskProfile != null && portfolio.riskProfile!.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _statChip(Icons.shield_rounded, "Risk",
                                portfolio.riskProfile!, riskColor),
                          ],
                          if (portfolio.stocks.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _statChip(Icons.pie_chart_rounded, "Stocks",
                                "${portfolio.stocks.length}", Colors.teal),
                          ],
                          ...[
                            const SizedBox(width: 8),
                            _statChip(Icons.card_membership, "Fee",
                                portfolio.pricingDisplayText.isNotEmpty
                                    ? portfolio.pricingDisplayText
                                    : "Free",
                                Colors.green),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.account_balance, size: 22, color: Color(0xFF3F51B5)),
    );
  }

  Widget _riskBadge(String risk) {
    if (risk.trim().isEmpty) return const SizedBox.shrink();
    final color = _riskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        risk,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _statChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center,
            ),
            Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(int amount) {
    if (amount >= 100000) {
      return "${(amount / 100000).toStringAsFixed(1)}L";
    } else if (amount >= 1000) {
      return "${(amount / 1000).toStringAsFixed(0)}K";
    }
    return "$amount";
  }
}
