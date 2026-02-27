import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SubscriptionStatus {
  final bool hasAccess;
  final bool isTrial;
  final int? daysLeft;

  const SubscriptionStatus({
    required this.hasAccess,
    required this.isTrial,
    this.daysLeft,
  });
}

class SubscriptionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<SubscriptionStatus> getStatus() async {
    final isSubscribed = await _storage.read(key: 'is_subscribed');
    final isPaid = await _storage.read(key: 'is_paid');
    final isTrialActive = await _storage.read(key: 'is_stock_analysis_trial_active');
    final endDateStr = await _storage.read(key: 'subscription_end_date');

    // Paid user
    if (isSubscribed == 'true' && isPaid == 'true') {
      int? daysLeft;
      if (endDateStr != null && endDateStr.isNotEmpty) {
        try {
          final end = DateTime.parse(endDateStr);
          daysLeft = end.difference(DateTime.now()).inDays;
        } catch (_) {}
      }
      return SubscriptionStatus(hasAccess: true, isTrial: false, daysLeft: daysLeft);
    }

    // Trial user
    if (isTrialActive == 'true' && endDateStr != null && endDateStr.isNotEmpty) {
      try {
        final end = DateTime.parse(endDateStr);
        final daysLeft = end.difference(DateTime.now()).inDays;
        if (daysLeft >= 0) {
          return SubscriptionStatus(hasAccess: true, isTrial: true, daysLeft: daysLeft);
        }
      } catch (_) {}
    }

    return const SubscriptionStatus(hasAccess: false, isTrial: false);
  }

  static Future<bool> hasAccess() async {
    final status = await getStatus();
    return status.hasAccess;
  }
}
