import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../components/login/PaymentSuccess.dart';
import '../components/login/splash.dart';

class FCMHandler {
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final context = navigatorKey.currentContext;

      if (notification == null || context == null) return;

      final title = notification.title ?? '';
      final body = notification.body ?? '';

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
      } else {
        _showStandardDialog(context, title, body);
      }
    });
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

