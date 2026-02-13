import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'StockPortfolioPage.dart';
import 'StockRecommendationPage.dart';
import '../../../widgets/SubscriptionPromptDialog.dart';
import '../portfolio/ModelPortfolioListPage.dart';

class StockRecommendationScreen extends StatefulWidget {
  const StockRecommendationScreen({super.key});

  @override
  State<StockRecommendationScreen> createState() => _StockRecommendationScreenState();
}

class _StockRecommendationScreenState extends State<StockRecommendationScreen> with SingleTickerProviderStateMixin {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool isSubscribed = false;
  late AnimationController _pageSlideController;
  late Animation<Offset> _pageSlideAnimation;
  late Animation<double> _pageFadeAnimation;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      loadSubscriptionStatus();
    });

    // Slide + fade animation for page content
    _pageSlideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pageSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _pageSlideController, curve: Curves.easeOutCubic));

    _pageFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pageSlideController, curve: Curves.easeIn),
    );

    _pageSlideController.forward();
  }

  Future<void> loadSubscriptionStatus() async {
    String? subscribed = await secureStorage.read(key: 'is_subscribed');
    String? isPaid = await secureStorage.read(key: 'is_paid');
    setState(() {
      isSubscribed = ((subscribed == 'true') && (isPaid == 'true'));
    });
  }

  @override
  void dispose() {
    _pageSlideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        child: SafeArea(
          child: FadeTransition(
            opacity: _pageFadeAnimation,
            child: SlideTransition(
              position: _pageSlideAnimation,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  _header(),
                  const SizedBox(height: 28),

                  _menuCard(
                    icon: Icons.insert_chart_rounded,
                    title: "Stock Recommendations",
                    subtitle: "Expert curated stock ideas",
                      gradient: const [
                        Color(0xFFE3F2FD), // light blue
                        Color(0xFFBBDEFB),
                      ],

                      onTap: () {Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StockRecommendationsPage()),
                  );}
                  ),

                  _menuCard(
                    icon: Icons.pie_chart_rounded,
                    title: "TIDI Wealth Portfolio",
                    subtitle: "Track & manage your investments",
                    gradient: const [
                      Color(0xFFE8F5E9), // light green
                      Color(0xFFC8E6C9),
                    ],

                    onTap: () async {
                      await loadSubscriptionStatus();
                      if (!isSubscribed) {
                        SubscriptionPromptDialog.show(context);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StockPortfolioPage()),
                        );
                      }
                    },
                  ),

                  _menuCard(
                    icon: Icons.account_balance_rounded,
                    title: "Model Portfolios",
                    subtitle: "Expert-managed investment strategies",
                    gradient: const [
                      Color(0xFFF3E5F5),
                      Color(0xFFE1BEE7),
                    ],

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ModelPortfolioListPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          "Invest Smarter",
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        SizedBox(height: 8),
        Text(
          "Your premium stock & wealth tools",
          style: TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.black87,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }


}
