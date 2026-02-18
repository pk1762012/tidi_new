import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../components/login/PaymentSuccess.dart';
import '../components/login/splash.dart';
import '../components/home/portfolio/RebalanceNotificationScreen.dart';

class FCMHandler {
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final context = navigatorKey.currentContext;
      final data = message.data;

      if (notification == null || context == null) return;

      final title = notification.title ?? '';
      final body = notification.body ?? '';

      // Get notification type from data
      final notificationType = data['notificationType'] ?? '';
      final modelName = data['modelName'] ?? '';
      final stocksData = data['stocks'] ?? '[]';

      debugPrint('[FCMHandler] Received notification: title=$title, type=$notificationType, modelName=$modelName');

      // Handle subscription notifications
      if (title == 'You are Subscribed!' || title == 'Course fees payment successful!'  || title == 'Workshop fees payment successful!') {
        _showStandardDialog(context, title, body).then((_) {
          Navigator.of(navigatorKey.currentContext!, rootNavigator: true)
              .pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const SuccessSplashScreen(),
              transitionDuration: Duration.zero, // No animation
              reverseTransitionDuration: Duration.zero,
            ),
                (route) => false,
          );
        });
      }
      // Handle model portfolio rebalance notifications
      else if (notificationType == 'New Rebalance' || title.contains('Rebalance')) {
        _handleRebalanceNotification(context, title, body, data, navigatorKey);
      }
      // Handle stock recommendation notifications
      else if (notificationType == 'Stock Recommendation' || data['symbol'] != null) {
        _handleStockNotification(context, title, body, data);
      }
      // Default: show standard dialog
      else {
        _showStandardDialog(context, title, body);
      }
    });

    // Handle background/terminated state notifications
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final context = navigatorKey.currentContext;
      final data = message.data;
      final notificationType = data['notificationType'] ?? '';

      debugPrint('[FCMHandler] App opened from notification: type=$notificationType');

      if (context != null && (notificationType == 'New Rebalance' || (data['modelName'] != null))) {
        _navigateToRebalanceNotification(context, data, navigatorKey);
      }
    });
  }

  static void _handleRebalanceNotification(
    BuildContext context,
    String title,
    String body,
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    final modelName = data['modelName'] ?? '';

    // Show dialog with option to view details
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.sync_alt_rounded, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 14)),
            if (modelName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      modelName,
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _navigateToRebalanceNotification(context, data, navigatorKey);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text("View Details"),
          ),
        ],
      ),
    );
  }

  static void _navigateToRebalanceNotification(
    BuildContext context,
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    if (context == null) return;

    final modelName = data['modelName'] ?? '';
    final advisorName = data['advisorName'] ?? data['advisor'] ?? '';
    final stocksData = data['stocks'] ?? '[]';

    // Parse stocks data
    List<Map<String, dynamic>> stocks = [];
    try {
      if (stocksData is String) {
        stocks = List<Map<String, dynamic>>.from(json.decode(stocksData));
      } else if (stocksData is List) {
        stocks = List<Map<String, dynamic>>.from(stocksData);
      }
    } catch (e) {
      debugPrint('[FCMHandler] Error parsing stocks data: $e');
    }

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => RebalanceNotificationScreen(
          modelName: modelName,
          advisorName: advisorName,
          trades: stocks,
        ),
      ),
    );
  }

  static void _handleStockNotification(
    BuildContext context,
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    final symbol = data['symbol'] ?? '';
    final price = data['price'] ?? '';
    final type = data['type'] ?? ''; // BUY or SELL

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              type == 'BUY' ? Icons.trending_up : Icons.trending_down,
              color: type == 'BUY' ? Colors.green : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 14)),
            if (symbol.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _stockInfoChip("Symbol", symbol, Colors.blue),
                  if (price.toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _stockInfoChip("Price", "₹$price", Colors.green),
                  ],
                  if (type.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _stockInfoChip("Action", type, type == 'BUY' ? Colors.green : Colors.red),
                  ],
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  static Widget _stockInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 13)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8))),
        ],
      ),
    );
  }

  static Future<void> _showStandardDialog(BuildContext context, String title,
      String body) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme
                      .of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                    color: Theme
                        .of(context)
                        .colorScheme
                        .primary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: Theme
                      .of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(
                    color: Theme
                        .of(context)
                        .colorScheme
                        .onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      backgroundColor: Theme
                          .of(context)
                          .colorScheme
                          .primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}
