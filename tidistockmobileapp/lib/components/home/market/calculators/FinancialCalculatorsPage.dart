import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidistockmobileapp/components/home/market/calculators/ReverseCagrCalculatorPage.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'CagrCalculatorPage.dart';
import 'LoanCalculatorPage.dart';
import 'LumpsumCalculatorPage.dart';
import 'SipCalculatorPage.dart';
import 'SwpCalculatorPage.dart';

class FinancialCalculatorsPage extends StatefulWidget {
  const FinancialCalculatorsPage({super.key});

  @override
  State<FinancialCalculatorsPage> createState() => _FinancialCalculatorsPageState();
}

class _FinancialCalculatorsPageState extends State<FinancialCalculatorsPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pageController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final List<_CalculatorMenuItem> calculators = [
    _CalculatorMenuItem(
      icon: Icons.stacked_line_chart,
      label: "SIP Calculator",
      page: SipCalculatorPage(),
      gradient: [Color(0xFFA1C4FD), Color(0xFFC2E9FB)],
    ),
    _CalculatorMenuItem(
      icon: Icons.trending_up,
      label: "Lumpsum Calculator",
      page: LumpsumCalculatorPage(),
      gradient: [Color(0xFFFBC2EB), Color(0xFFA6C1EE)],
    ),
    _CalculatorMenuItem(
      icon: Icons.south,
      label: "SWP Calculator",
      page: SwpCalculatorPage(),
      gradient: [Color(0xFFFAD0C4), Color(0xFFFFE9E9)],
    ),
    _CalculatorMenuItem(
      icon: Icons.payments,
      label: "EMI Calculator",
      page: LoanCalculatorPage(),
      gradient: [Color(0xFFFFECD2), Color(0xFFFCB69F)],
    ),
    _CalculatorMenuItem(
      icon: Icons.show_chart,
      label: "CAGR Calculator",
      page: CagrCalculatorPage(),
      gradient: [Color(0xFFA1FFCE), Color(0xFFFAFFD1)],
    ),
    _CalculatorMenuItem(
      icon: Icons.show_chart,
      label: "Reverse CAGR Calculator",
      page: ReverseCagrCalculatorPage(),
      gradient: [Color(0xFFFFE0B2), Color(0xFFFFCC80)],
    ),

  ];

  @override
  void initState() {
    super.initState();

    _pageController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _pageController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pageController, curve: Curves.easeIn),
    );

    _pageController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      menu: "Financial Calculators",
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: calculators.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final item = calculators[index];
              return _buildCalculatorCard(
                icon: item.icon,
                label: item.label,
                gradientColors: item.gradient,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => item.page),
                  );
                },
              );
            },
          ),
        ),
      ),
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
    );
  }

  Widget _buildCalculatorCard({
    required IconData icon,
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      splashColor: Colors.white24,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: Colors.black),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// Model for cleaner data handling
class _CalculatorMenuItem {
  final IconData icon;
  final String label;
  final Widget page;
  final List<Color> gradient;

  _CalculatorMenuItem({
    required this.icon,
    required this.label,
    required this.page,
    required this.gradient,
  });
}
