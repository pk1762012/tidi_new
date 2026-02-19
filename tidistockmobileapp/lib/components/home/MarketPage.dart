import 'dart:async';
import 'dart:convert';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../screens/welcomeScreen.dart';
import 'indexdetails/MarketDataWidget.dart';
import 'market/FiiDiiDataPage.dart';
import 'market/IpoListingPage.dart';
import 'market/PreMarketDialog.dart';
import 'market/StockAnalysisScreen.dart';
import 'market/calculators/FinancialCalculatorsPage.dart';
import 'market/OptionPulsePage.dart';
import 'market/StockScanner.dart';
import 'news/NewsScreen.dart';
import '../../widgets/PortfolioSummaryCard.dart';
import '../../service/AqApiService.dart';


class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  MarketPageState createState() => MarketPageState();
}

class MarketPageState extends State<MarketPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pageSlideController;
  late Animation<Offset> _pageSlideAnimation;
  late Animation<double> _pageFadeAnimation;
  static const int fcmVerifyIntervalMinutes = 15;

  final PageController _bannerController = PageController();
  int _currentBanner = 0;
  Timer? _bannerTimer;

  final List<String> _banners = [
    "assets/images/tidi_banner1.png",
    "assets/images/tidi_banner2.png",
    "assets/images/tidi_banner3.png",
  ];


  late AnimationController _iconsController;
  late List<Animation<double>> _iconsFadeAnimations;
  late List<Animation<Offset>> _iconsSlideAnimations;

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  List<dynamic> stockData = [];

  // Subscription
  bool isSubscribed = false;

  // User email for portfolio card
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      verifyDeviceFcmIfNeeded(context);
    });
    loadSubscriptionStatus();
    preloadStockData();
    _loadUserEmail();

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

    // Icon animations
    final int iconCount = 9;
    _iconsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _iconsFadeAnimations = List.generate(iconCount, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _iconsController,
          curve: Interval(index * 0.1, 1.0, curve: Curves.easeIn),
        ),
      );
    });

    _iconsSlideAnimations = List.generate(iconCount, (index) {
      return Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
          .animate(
        CurvedAnimation(
          parent: _iconsController,
          curve: Interval(index * 0.1, 1.0, curve: Curves.easeOutBack),
        ),
      );
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _iconsController.forward();
    });

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_bannerController.hasClients) return;

      _currentBanner = (_currentBanner + 1) % _banners.length;
      _bannerController.animateToPage(
        _currentBanner,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });

  }

  Future<void> _loadUserEmail() async {
    final email = await AqApiService.resolveUserEmail();
    if (mounted && email != null) setState(() => _userEmail = email);
  }

  Future<void> loadSubscriptionStatus() async {
    String? value = await secureStorage.read(key: 'is_subscribed');
    isSubscribed = value == 'true';
  }

  Future<void> verifyDeviceFcmIfNeeded(BuildContext context) async {
    try {
      final now = DateTime.now();
      final lastCheckStr =
      await secureStorage.read(key: 'last_fcm_verify_at');

      if (lastCheckStr != null) {
        final lastCheck = DateTime.parse(lastCheckStr);
        final diff = now.difference(lastCheck).inMinutes;

        if (diff < fcmVerifyIntervalMinutes) {
          // ⏳ Skip check
          return;
        }
      }

      await _verifyDeviceFcm(context);

      await secureStorage.write(
        key: 'last_fcm_verify_at',
        value: now.toIso8601String(),
      );
    } catch (e) {
      debugPrint("FCM time-gated check failed: $e");
    }
  }

  Future<void> _verifyDeviceFcm(BuildContext context) async {
    try {
      final currentFcm = await ApiService.getFcmTokenSafely();
      if (currentFcm == null) return;

      final response = await ApiService().getSavedDeviceFcm()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final savedFcm = jsonDecode(response.body)['FCM'];

      if (savedFcm != currentFcm) {
        await logout();
      }
    } catch (e) {
      debugPrint('[MarketPage] FCM verification skipped (network error): $e');
    }
  }

  Future<void> logout() async {
    ApiService.invalidateTokenCache();
    await CacheService.instance.clearAll();
    await secureStorage.deleteAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => WelcomeScreen()),
          (Route<dynamic> route) => false,
    );
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _bannerTimer?.cancel();
      _bannerTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _bannerTimer ??= Timer.periodic(const Duration(seconds: 4), (timer) {
        if (!_bannerController.hasClients) return;
        _currentBanner = (_currentBanner + 1) % _banners.length;
        _bannerController.animateToPage(
          _currentBanner,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageSlideController.dispose();
    _iconsController.dispose();
    _bannerTimer?.cancel();
    _bannerController.dispose();

    super.dispose();
  }

  Future<void> preloadStockData() async {
    try {
      await ApiService().getCachedNifty50StockAnalysis(
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          stockData = data is List ? data : [];
        },
      );
    } catch (_) {}
  }

  void _showHolidayDialog() async {
    try {
      await ApiService().getCachedMarketHolidays(
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          _showHolidayDialogWithData(data is List ? data : []);
        },
      );
    } catch (e) {
      debugPrint("Holiday fetch error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load holidays. Please check your connection and try again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showHolidayDialogWithData(List<dynamic> data) {
    try {
      if (data.isEmpty) {
        _showError("No holidays available");
        return;
      }

      final now = DateTime.now();
      int? nextHolidayIndex;
      for (int i = 0; i < data.length; i++) {
        final date = DateTime.parse(data[i]['date']);
        if (date.isAfter(now)) {
          nextHolidayIndex = i;
          break;
        }
      }

      final scrollController = ScrollController();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (nextHolidayIndex != null) {
          scrollController.animateTo(
            (nextHolidayIndex * 90).toDouble(),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.88),
                      Colors.black.withOpacity(0.78),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---------------- Header ----------------
                    Row(
                      children: const [
                        Icon(Icons.calendar_today, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Market Holidays",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ---------------- Holiday List ----------------
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: data.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: Colors.grey.shade600, height: 8),
                          itemBuilder: (context, index) {
                            final holiday = data[index];
                            final date = DateTime.parse(holiday['date']);
                            final formattedDate =
                                "${date.day.toString().padLeft(2, '0')}-"
                                "${date.month.toString().padLeft(2, '0')}-"
                                "${date.year} (${holiday['day']})";

                            final isToday = date.year == now.year &&
                                date.month == now.month &&
                                date.day == now.day;

                            final isUpcoming = index == nextHolidayIndex && !isToday;

                            Color bgColor = Colors.white.withOpacity(0.05);
                            Color borderColor = Colors.white.withOpacity(0.12);
                            Color textColor = Colors.white70;

                            if (isToday) {
                              bgColor = Colors.greenAccent.withOpacity(0.2);
                              borderColor = Colors.greenAccent.shade400;
                              textColor = Colors.greenAccent.shade700;
                            } else if (isUpcoming) {
                              bgColor = Colors.yellowAccent.withOpacity(0.15);
                              borderColor = Colors.orangeAccent.shade400;
                              textColor = Colors.orangeAccent.shade700;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor, width: 1.2),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: bgColor,
                                    child: Icon(
                                      Icons.event,
                                      size: 18,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          holiday['occasion'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: (isToday || isUpcoming)
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formattedDate,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: textColor.withOpacity(0.8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isToday)
                                    _buildTag("Today", Colors.greenAccent.shade400)
                                  else if (isUpcoming)
                                    _buildTag("Next", Colors.orangeAccent.shade400),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // ---------------- Close Button ----------------
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Close",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                  ],
                ),
              ),
          ),
      );
    } catch (e) {
      _showError("Error loading holidays: $e");
    }
  }

// ---------------- Helper for tag ----------------
  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SlideTransition(
            position: _pageSlideAnimation,
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _autoScrollingBanner(context),
                          RepaintBoundary(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: const MarketDataWidget(),
                            ),
                          ),
                          // Portfolio summary card
                          if (_userEmail != null)
                            PortfolioSummaryCard(email: _userEmail!),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,          // 3 icons per row
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.95,     // Taller to fit icon + text
                            ),
                            itemCount: 9,
                            itemBuilder: (context, index) {
                              final items = [
                                {'title': 'Pre-Market', 'icon': Icons.settings_input_antenna, 'color': Colors.blue, 'onTap': () => PreMarketDialog.show(context)},
                                {'title': 'Stock Analysis', 'icon': Icons.stacked_bar_chart, 'color': Colors.lime, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockAnalysisScreen(preloadedStocks: stockData)))},
                                {'title': 'Latest News', 'icon': Icons.live_tv, 'color': Colors.deepPurple, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewsScreen()))},
                                {'title': 'Market Holidays', 'icon': Icons.calendar_month_outlined, 'color': Colors.orange, 'onTap': _showHolidayDialog},
                                {'title': 'Calculators', 'icon': Icons.calculate_outlined, 'color': Colors.teal, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialCalculatorsPage()))},
                                {'title': 'IPO', 'icon': Icons.new_label_outlined, 'color': Colors.pinkAccent, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IpoListingPage()))},
                                {'title': 'FII DII', 'icon': Icons.cast_for_education, 'color': Colors.greenAccent, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FiiDiiDataPage()))},
                                {'title': 'Option Pulse', 'icon': Icons.monitor_heart_outlined, 'color': Colors.redAccent, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OptionPulsePage()))},
                                {'title': 'Stock Scanner', 'icon': Icons.radar, 'color': Colors.indigo, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockScanner(preloadedStocks: stockData)))},
                              ];

                              final item = items[index];
                              return _buildDashboardIcon(
                                title: item['title'] as String,
                                icon: item['icon'] as IconData,
                                color: item['color'] as Color,
                                onTap: item['onTap'] as VoidCallback,
                                index: index,
                              );
                            },
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoScrollingBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: PageView.builder(
          controller: _bannerController,
          itemCount: _banners.length,
          onPageChanged: (index) {
            _currentBanner = index;
          },
          itemBuilder: (context, index) {
            return InkWell(
              child: Image.asset(
                _banners[index],
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            );
          },
        ),
      ),
    );
  }


  Widget _buildDashboardIcon({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required int index,
  }) {
    return FadeTransition(
      opacity: _iconsFadeAnimations[index],
      child: SlideTransition(
        position: _iconsSlideAnimations[index],
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  flex: 2,
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: color.withOpacity(0.1),
                    child: Icon(
                      icon,
                      size: 28,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  flex: 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
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
