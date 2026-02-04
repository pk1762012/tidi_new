import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:tidistockmobileapp/components/home/MarketPage.dart';
import 'package:tidistockmobileapp/components/home/profile/profilePage.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import '../components/home/AcademyPage.dart';
import '../components/home/advisory/StockRecommendationScreen.dart';
import '../components/home/ai/AIBotScreen.dart';
import '../widgets/SubscriptionPromptDialog.dart';

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
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool isSubscribed = false;

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

  Future<void> _openAI() async {
    HapticFeedback.selectionClick();

    final value = await secureStorage.read(key: 'is_subscribed');
    isSubscribed = value == 'true';

    if (!isSubscribed) {
      SubscriptionPromptDialog.show(context);
      return;
    }

    setState(() => currentMenu = "Ask AI"); // Update menu text for AI

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        const AIBotScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeIn));
          final scaleAnim = Tween<double>(begin: 0.8, end: 1.0)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack));
          final slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

          return FadeTransition(
            opacity: fadeAnim,
            child: SlideTransition(
              position: slideAnim,
              child: ScaleTransition(
                scale: scaleAnim,
                child: child,
              ),
            ),
          );
        },
      ),
    ).then((_) {
      // Reset menu back to current page after returning from AI
      setState(() {
        currentMenu = _menuMap[currentIndex];
      });
    });
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
            children: [
              // 70% Navigation buttons
              Expanded(
                flex: 7,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _navItem(FeatherIcons.activity, 'Market', 0),
                    _navItem(FeatherIcons.target, 'Advisory', 1),
                    _navItem(FeatherIcons.bookOpen, 'Academy', 2),
                  ],
                ),
              ),

              // 30% AI button
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: _openAI,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: lightColorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white,
                          //blurRadius: 10,
                          //offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/tidi_ai.gif',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ask AI',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: lightColorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
