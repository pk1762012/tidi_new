import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'ModelPortfolioDetailPage.dart';
import 'InvestedPortfoliosPage.dart';

class ModelPortfolioListPage extends StatefulWidget {
  const ModelPortfolioListPage({super.key});

  @override
  State<ModelPortfolioListPage> createState() => _ModelPortfolioListPageState();
}

class _ModelPortfolioListPageState extends State<ModelPortfolioListPage>
    with SingleTickerProviderStateMixin {
  List<ModelPortfolio> portfolios = [];
  bool loading = true;
  String? error;
  String? userEmail;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );
    _init();
  }

  Future<void> _init() async {
    final email = await const FlutterSecureStorage().read(key: 'user_email');
    if (mounted) setState(() => userEmail = email);
    await _fetchPortfolios();
  }

  Future<void> _fetchPortfolios() async {
    try {
      await AqApiService.instance.getCachedPortfolios(
        email: userEmail ?? '',
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          debugPrint('[ModelPortfolio] raw type=${data.runtimeType}, fromCache=$fromCache');

          List<dynamic> list;
          if (data is List) {
            list = data;
          } else if (data is Map) {
            debugPrint('[ModelPortfolio] keys=${(data as Map).keys.toList()}');
            // Plans API wraps in { data: [...], total, page, pageSize }
            final d = data['data'] ?? data['portfolios'] ?? data['models'];
            if (d is List) {
              list = d;
            } else {
              list = data.values.whereType<List>().firstOrNull ?? [];
            }
          } else {
            list = [];
          }

          // Filter out draft plans (Plans API includes drafts)
          list = list.where((e) => e is Map && e['draft'] != true).toList();

          debugPrint('[ModelPortfolio] parsed ${list.length} portfolios');
          setState(() {
            portfolios = list.map((e) => ModelPortfolio.fromJson(e)).toList();
            loading = false;
            error = null;
          });
          _animController.forward();
        },
      );
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

  @override
  void dispose() {
    _animController.dispose();
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
                  _fetchPortfolios();
                },
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() => loading = true);
          await _fetchPortfolios();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Invested portfolios shortcut
            if (userEmail != null)
              _investedPortfoliosBanner(),

            const SizedBox(height: 4),

            // Portfolio cards
            ...portfolios.map((p) => _portfolioCard(p)),

            if (portfolios.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    "No model portfolios available yet.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

  Widget _portfolioCard(ModelPortfolio portfolio) {
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
        // Refresh email & portfolios in case user logged in via AQ WebView
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
                // Status badge
                if (isSubscribed)
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
