import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../screens/homeScreen.dart';
import '../../screens/welcomeScreen.dart';
import '../../service/ApiService.dart';
import '../../service/CacheService.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  late Widget nextScreen;

  @override
  void initState() {
    super.initState();
    preloadNextScreen();
  }

  void preloadNextScreen() async {
    String? accessToken = await storage.read(key: 'access_token');

    if (accessToken != null && accessToken.isNotEmpty) {
      // Fetch user details while splash is showing
      final userData = await fetchUserData();
      if (!mounted) return;

      nextScreen = HomeScreen(
        currentIndex: 0,
        userData: userData,
      );
    } else {
      nextScreen = WelcomeScreen();
    }

    // Minimum splash duration
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => nextScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  Future<Map<String, dynamic>?> fetchUserData() async {
    try {
      ApiService apiService = ApiService();
      final response = await apiService.getUserDetails();

      if (response.statusCode == 200) {
        final data = json.decode(response.body)['data'];

        await storage.write(key: 'user_id', value: data['id']);
        await storage.write(key: 'phone_number', value: data['username']);
        await storage.write(key: 'profile_picture', value: data['profilePicture']);
        await storage.write(key: 'first_name', value: data['firstName']);
        await storage.write(key: 'last_name', value: data['lastName']?.toString());
        await storage.write(key: 'is_subscribed', value: data['isSubscribed'].toString());
        await storage.write(key: 'is_paid', value: data['isPaid'].toString());
        await storage.write(key: 'subscription_end_date', value: data['subscriptionEndDate']?.toString());
        await storage.write(key: 'pan', value: data['pan']?.toString());
        await storage.write(key: 'is_stock_analysis_trial_active', value: data['isStockAnalysisTrialActive'].toString());

        final List configs = data['config'] ?? [];

        for (final item in configs) {
          await storage.write(
            key: item['name'],
            value: item['value'].toString(),
          );
        }


        return data;
      } else if (response.statusCode == 401) {
        await CacheService.instance.clearAll();
        final FlutterSecureStorage secureStorage = FlutterSecureStorage();
        await secureStorage.deleteAll();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => WelcomeScreen()),
              (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint('SplashScreen fetchUserData error: $e');
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.white, // or any theme color
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/tidi_intro.gif"),
              fit: BoxFit.fill,   // 🔥 Forces full stretch to fill screen
            ),
          ),
        ),

      ),
    );
  }

}

