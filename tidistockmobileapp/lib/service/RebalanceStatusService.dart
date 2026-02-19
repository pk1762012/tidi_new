import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'AqApiService.dart';

/// Represents a pending rebalance that needs user attention.
class PendingRebalance {
  final String modelName;
  final String modelId;
  final String? rebalanceDate;
  final String executionStatus;
  final String broker;
  final String advisor;

  PendingRebalance({
    required this.modelName,
    required this.modelId,
    this.rebalanceDate,
    required this.executionStatus,
    required this.broker,
    required this.advisor,
  });
}

/// Shared utility for detecting pending rebalances across the app.
///
/// Used by HomeScreen (floating alert), MarketPage (PortfolioSummaryCard),
/// and ModelPortfolioListPage (pending rebalances section).
class RebalanceStatusService {
  RebalanceStatusService._();

  /// Fetch all pending rebalances for a user's subscribed strategies.
  ///
  /// Returns an empty list if the user has no subscriptions or no
  /// pending rebalances.
  static Future<List<PendingRebalance>> fetchPendingRebalances(String email) async {
    if (email.isEmpty) return [];

    try {
      final response = await AqApiService.instance.getSubscribedStrategies(email);
      debugPrint('[RebalanceStatusService] response: ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) return [];

      final body = json.decode(response.body);
      final List<dynamic> subscriptions = body is List
          ? body
          : (body['subscribedPortfolios'] ?? body['data'] ?? []);

      debugPrint('[RebalanceStatusService] subscriptions count: ${subscriptions.length}');

      final pending = <PendingRebalance>[];

      for (final sub in subscriptions) {
        if (sub is! Map) continue;

        final modelName = sub['model_name']?.toString() ?? sub['modelName']?.toString() ?? '';
        final model = sub['model'] as Map<String, dynamic>?;
        if (model == null) continue;

        final rebalanceHistory = model['rebalanceHistory'] as List<dynamic>? ?? [];

        // Find the latest rebalance with execution status
        for (final rebalance in rebalanceHistory.reversed) {
          final execData = rebalance['execution'] ??
              rebalance['subscriberExecutions'] ??
              rebalance;
          final status = (execData['executionStatus'] ??
                  execData['status'] ??
                  execData['userExecution']?['status'] ??
                  '')
              .toString()
              .toLowerCase();

          // Check for pending/toExecute/partial statuses
          if (status == 'toexecute' ||
              status == 'pending' ||
              status == 'partial' ||
              status == '') {
            pending.add(PendingRebalance(
              modelName: modelName,
              modelId: sub['_id']?.toString() ?? sub['id']?.toString() ?? sub['model_id']?.toString() ?? '',
              rebalanceDate: (rebalance['rebalanceDate'] ?? rebalance['date'])?.toString(),
              executionStatus: status,
              broker: (execData['user_broker'] ?? execData['broker'] ?? 'DummyBroker').toString(),
              advisor: (model['advisor'] ?? '').toString(),
            ));
            break;
          }
        }
      }

      debugPrint('[RebalanceStatusService] pending rebalances: ${pending.length}');
      return pending;
    } catch (e) {
      debugPrint('[RebalanceStatusService] error: $e');
      return [];
    }
  }
}
