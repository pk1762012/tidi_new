import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../widgets/SubscriptionPromptDialog.dart';
import '../../../widgets/customScaffold.dart';
import 'BrowserPage.dart';

class ScreenersScreen extends StatefulWidget {
  const ScreenersScreen({super.key});

  @override
  State<ScreenersScreen> createState() => _ScreenersScreenState();
}

class _ScreenersScreenState extends State<ScreenersScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  bool isSubscribed = false;

  final List<Map<String, dynamic>> screenerOptions = [];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _controller.forward();

    screenerOptions.addAll([
      {
        'title': 'Heatmap',
        'description': 'View sector & stock performance at a glance',
        'icon': Icons.grid_view,
        'color': Colors.redAccent,
        'url': "https://www.tradingview.com/heatmap/stock/#%7B%22dataSource%22%3A%22NIFTY50%22%2C%22blockColor%22%3A%22change%22%2C%22blockSize%22%3A%22market_cap_basic%22%2C%22grouping%22%3A%22sector%22%7D",
        'is_free' : true
      },
      {
        'title': 'CloseCall Dashboard',
        'description': 'Interactive dashboard for CloseCall analytics',
        'icon': Icons.dashboard,
        'color': Colors.indigo,
        'url': "https://chartink.com/dashboard/155056",
        'is_free' : false
      },
      {
        'title': 'Good for SIP',
        'description': 'ChartInk screener for SIP',
        'icon': Icons.playlist_add,
        'color': Colors.orangeAccent,
        'url': "https://chartink.com/screener/copy-dada-sip-buy-5",
        'is_free' : false
      },
      {
        'title': 'Fundamentally Undervalued',
        'description': 'Stocks undervalued by fundamentals',
        'icon': Icons.low_priority,
        'color': Colors.deepPurple,
        'url': "https://chartink.com/screener/copy-fundamentally-undervalued-stocks-434",
        'is_free' : false
      },
      {
        'title': 'Short-Term Breakouts',
        'description': 'Detecting recent breakout stocks',
        'icon': Icons.flash_on,
        'color': Colors.amber,
        'url': "https://chartink.com/screener/copy-short-term-breakouts-28050301",
        'is_free' : false
      },
      {
        'title': 'Intraday Bullish Scan',
        'description': 'Today’s strongest bullish stocks',
        'icon': Icons.trending_up,
        'color': Colors.green,
        'url': "https://chartink.com/screener/jatre-intraday-bullish-scan-1",
        'is_free' : false
      },
      {
        'title': 'Intraday Bearish Scan',
        'description': 'Today’s strongest bearish stocks',
        'icon': Icons.trending_down,
        'color': Colors.red,
        'url': "https://chartink.com/screener/jatre-intraday-sell-scan",
        'is_free' : false
      },
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> loadSubscriptionStatus() async {
    String? value = await secureStorage.read(key: 'is_subscribed');
    setState(() {
      isSubscribed =  value == 'true';
    });
  }

  void openUrl(BuildContext context, String url) async {
    if (defaultTargetPlatform == TargetPlatform.android &&
        url.contains("chartink.com")) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BrowserPage(url: url)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Screeners',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: screenerOptions.length,
                itemBuilder: (context, index) {
                  final option = screenerOptions[index];
                  return ScaleTransition(
                    scale: Tween<double>(begin: 0.8, end: 1.0)
                        .animate(CurvedAnimation(
                      parent: _controller,
                      curve: Interval(0.1 * index, 1.0,
                          curve: Curves.elasticOut),
                    )),
                    child: FadeTransition(
                      opacity: _animation,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            await loadSubscriptionStatus();
                            if (!isSubscribed && !option['is_free']) {
                              SubscriptionPromptDialog.show(context);
                              return;
                            }
                            openUrl(context, option['url']);
                          },
                          child: Card(
                            color: Colors.white10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: option['color'],
                                child: Icon(option['icon'], color: Colors.white),
                              ),
                              title: Text(option['title'],
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(option['description'],
                                  style:
                                  const TextStyle(color: Colors.white70)),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
