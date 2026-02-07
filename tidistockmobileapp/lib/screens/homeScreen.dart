import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:tidistockmobileapp/components/home/MarketPage.dart';
import 'package:tidistockmobileapp/components/home/profile/profilePage.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import '../components/home/AcademyPage.dart';
import '../components/home/advisory/StockRecommendationScreen.dart';

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

  @override
  void initState() {
    super.initState();
    currentIndex = widget.currentIndex;
    imageUrl = widget.userData?['profilePicture'];
    currentMenu = _menuMap[currentIndex];
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
        body: pages[currentIndex],
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBottomBar() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: lightColorScheme.primary.withOpacity(0.1),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.2)),
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
        ),
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
