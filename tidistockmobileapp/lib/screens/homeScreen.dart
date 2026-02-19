import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:tidistockmobileapp/components/home/MarketPage.dart';
import 'package:tidistockmobileapp/components/home/profile/profilePage.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import '../components/home/AcademyPage.dart';
import '../components/home/advisory/StockRecommendationScreen.dart';
import '../components/home/portfolio/ModelPortfolioListPage.dart';
import '../service/AqApiService.dart';
import '../service/RebalanceStatusService.dart';

class HomeScreen extends StatefulWidget {
  final int currentIndex;
  final Map<String, dynamic>? userData;

  const HomeScreen({
    super.key,
    this.currentIndex = 0,
    this.userData,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late int currentIndex;
  String? imageUrl;
  String? currentMenu;
  final List<Widget> pages = const [
    MarketPage(),
    StockRecommendationScreen(),
    AcademyPage(),
    ProfilePage(),
  ];

  // Mapping for menu text based on page
  final Map<int, String> _menuMap = {
    0: 'Market',
    1: 'Advisory',
    2: 'Academy',
    3: 'Profile',
  };

  // Floating rebalance alert state
  List<PendingRebalance> _pendingRebalances = [];
  bool _alertDismissed = false;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.currentIndex;
    imageUrl = widget.userData?['profilePicture'];
    currentMenu = _menuMap[currentIndex];
    _loadRebalanceAlerts();
  }

  Future<void> _loadRebalanceAlerts() async {
    final email = await AqApiService.resolveUserEmail();
    if (email == null || !mounted) return;
    try {
      final pending = await RebalanceStatusService.fetchPendingRebalances(email);
      if (mounted) setState(() => _pendingRebalances = pending);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: false,
      displayActions: true,
      imageUrl: imageUrl,
      menu: currentMenu,
      onProfileTap: () => setState(() {
        currentIndex = 3;
        currentMenu = _menuMap[3];
      }),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            pages[currentIndex],
            // Floating rebalance alert — visible on Market (0) and Advisory (1) tabs
            if (_pendingRebalances.isNotEmpty &&
                !_alertDismissed &&
                (currentIndex == 0 || currentIndex == 1))
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: _buildFloatingRebalanceAlert(),
              ),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildFloatingRebalanceAlert() {
    final first = _pendingRebalances.first;
    final label = _pendingRebalances.length == 1
        ? "Rebalance: ${first.modelName}"
        : "${_pendingRebalances.length} Rebalances Pending";

    return Dismissible(
      key: const Key('rebalance_alert'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => setState(() => _alertDismissed = true),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (_pendingRebalances.length == 1) {
            // Navigate directly to ModelPortfolioListPage which handles rebalance
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ModelPortfolioListPage()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ModelPortfolioListPage()),
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade600, Colors.orange.shade800],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Review",
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _alertDismissed = true),
                child: const Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: lightColorScheme.primary.withOpacity(0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(FeatherIcons.activity, 'Market', 0),
          _navItem(FeatherIcons.target, 'Advisory', 1),
          _navItem(FeatherIcons.bookOpen, 'Academy', 2),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final bool active = currentIndex == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              currentIndex = index;
              currentMenu = _menuMap[index]; // update menu text
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    icon,
                    size: active ? 26 : 22,
                    color: active ? lightColorScheme.primary : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? lightColorScheme.primary : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
