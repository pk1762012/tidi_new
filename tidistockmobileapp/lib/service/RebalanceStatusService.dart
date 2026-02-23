import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'AqApiService.dart';
import 'CacheService.dart';

/// Color-coded card states matching the rgx_app rebalance flow.
enum RebalanceCardState {
  pending,              // Blue — "View and act"
  executed,             // Grey — "No action due"
  partiallyExecuted,    // Orange — "Retry Rebalance"
  pendingVerification,  // Amber — "Verifying Order Status..."
  failed,               // Red — "View/action on updates"
}

/// Full rebalance status for a subscribed portfolio.
class PortfolioRebalanceStatus {
  final String modelName;
  final String modelId;
  final String? rebalanceDate;
  final String executionStatus;
  final String broker;
  final String? executionBroker;
  final String advisor;
  final RebalanceCardState cardState;

  PortfolioRebalanceStatus({
    required this.modelName,
    required this.modelId,
    this.rebalanceDate,
    required this.executionStatus,
    required this.broker,
    this.executionBroker,
    required this.advisor,
    required this.cardState,
  });

  /// Determine card state from raw execution status string.
  static RebalanceCardState cardStateFromStatus(String status) {
    switch (status.toLowerCase()) {
      case 'executed':
        return RebalanceCardState.executed;
      case 'partial':
        return RebalanceCardState.partiallyExecuted;
      case 'pending':
        return RebalanceCardState.pendingVerification;
      case 'failed':
        return RebalanceCardState.failed;
      case 'toexecute':
      case '':
        return RebalanceCardState.pending;
      default:
        return RebalanceCardState.pending;
    }
  }

  /// Determine card state with broker-match check (mirrors rgx_app).
  ///
  /// If the execution was done with a different broker than the user's
  /// currently connected broker, treat it as "pending" so the user can
  /// re-execute with their actual broker.
  static RebalanceCardState cardStateWithBrokerMatch(
    String status,
    String? executionBroker,
    String? connectedBroker,
  ) {
    final rawState = cardStateFromStatus(status);

    // If no connected broker info, fall back to raw status
    if (connectedBroker == null || connectedBroker.isEmpty) return rawState;

    // If execution broker is empty/null/DummyBroker, the broker doesn't affect state
    if (executionBroker == null ||
        executionBroker.isEmpty ||
        executionBroker == 'DummyBroker') {
      // DummyBroker execution with status 'executed' should still show as pending
      // because the user hasn't executed with a real broker
      if (executionBroker == 'DummyBroker' &&
          (rawState == RebalanceCardState.executed ||
           rawState == RebalanceCardState.partiallyExecuted ||
           rawState == RebalanceCardState.pendingVerification)) {
        return RebalanceCardState.pending;
      }
      return rawState;
    }

    // Broker match check: if execution broker != connected broker,
    // override executed/partial/pending states to "pending" (toExecute)
    final brokerMatches =
        executionBroker.toLowerCase() == connectedBroker.toLowerCase();
    if (!brokerMatches &&
        (rawState == RebalanceCardState.executed ||
         rawState == RebalanceCardState.partiallyExecuted ||
         rawState == RebalanceCardState.pendingVerification)) {
      return RebalanceCardState.pending;
    }

    return rawState;
  }
}

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
  static Future<List<PendingRebalance>> fetchPendingRebalances(
    String email, {
    String? connectedBroker,
  }) async {
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
          final rawExec = rebalance['execution'] ??
              rebalance['subscriberExecutions'] ??
              rebalance;

          Map<String, dynamic>? execData;
          if (rawExec is List) {
            if (rawExec.isEmpty) {
              // Empty subscriberExecutions → user hasn't acted yet → treat as pending
              execData = {'executionStatus': 'toExecute'};
            } else {
              // subscriberExecutions is a List of per-user entries — find ours
              for (final item in rawExec) {
                if (item is Map) {
                  final execEmail = (item['user_email'] ?? '').toString().toLowerCase();
                  if (execEmail == email.toLowerCase()) {
                    execData = Map<String, dynamic>.from(item);
                    break;
                  }
                }
              }
              // Fallback: use first entry if no email match
              if (execData == null && rawExec.first is Map) {
                execData = Map<String, dynamic>.from(rawExec.first);
              }
            }
          } else if (rawExec is Map) {
            execData = Map<String, dynamic>.from(rawExec);
          }
          if (execData == null) continue;

          final status = (execData['executionStatus'] ??
                  execData['status'] ??
                  execData['userExecution']?['status'] ??
                  '')
              .toString()
              .toLowerCase();

          // Check broker match — if execution was with a different broker,
          // treat as pending regardless of raw status
          final execBroker = (execData['user_broker'] ?? execData['broker'])?.toString();
          final brokerMismatch = connectedBroker != null &&
              connectedBroker.isNotEmpty &&
              execBroker != null &&
              execBroker.isNotEmpty &&
              execBroker != 'DummyBroker' &&
              execBroker.toLowerCase() != connectedBroker.toLowerCase();
          final isDummyExecution = execBroker == 'DummyBroker' &&
              (status == 'executed' || status == 'partial' || status == 'pending');

          // Check for pending/toExecute/partial statuses, or broker mismatch
          if (status == 'toexecute' ||
              status == 'pending' ||
              status == 'partial' ||
              status == '' ||
              brokerMismatch ||
              isDummyExecution) {
            pending.add(PendingRebalance(
              modelName: modelName,
              modelId: sub['_id']?.toString() ?? sub['id']?.toString() ?? sub['model_id']?.toString() ?? '',
              rebalanceDate: (rebalance['rebalanceDate'] ?? rebalance['date'])?.toString(),
              executionStatus: status,
              broker: (execData['user_broker'] ?? execData['broker'] ?? 'DummyBroker').toString(),
              advisor: (model['advisor'] ?? sub['advisor'] ?? '').toString(),
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

  /// Fetch rebalance status for ALL subscribed portfolios (not just pending ones).
  /// Returns a map of modelName → PortfolioRebalanceStatus.
  ///
  /// [connectedBroker] — the user's currently connected broker name.
  /// When provided, execution statuses are checked against this broker:
  /// if the execution was done with a different broker, the card state
  /// is overridden to "pending" (matching rgx_app's brokerMatchesExecution).
  static Future<Map<String, PortfolioRebalanceStatus>> fetchAllRebalanceStatuses(
    String email, {
    String? connectedBroker,
  }) async {
    if (email.isEmpty) return {};

    try {
      final response = await AqApiService.instance.getSubscribedStrategies(email);
      debugPrint('[RebalanceStatusService] fetchAll response: ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) return {};

      final body = json.decode(response.body);
      final List<dynamic> subscriptions = body is List
          ? body
          : (body['subscribedPortfolios'] ?? body['data'] ?? []);

      final statuses = <String, PortfolioRebalanceStatus>{};

      for (final sub in subscriptions) {
        if (sub is! Map) continue;

        final modelName = sub['model_name']?.toString() ?? sub['modelName']?.toString() ?? '';
        // Try multiple shapes: sub['model'] (nested) or sub itself (flat)
        Map<String, dynamic>? model;
        if (sub['model'] is Map) {
          model = Map<String, dynamic>.from(sub['model']);
        } else {
          // Flat shape — rebalanceHistory may be directly on sub
          model = Map<String, dynamic>.from(sub);
        }
        if (modelName.isEmpty) continue;

        final rebalanceHistory = (model['rebalanceHistory'] ?? model['rebalance_history'] ?? []) as List<dynamic>? ?? [];
        if (rebalanceHistory.isEmpty) continue;

        // Find the latest rebalance with execution status for this user
        for (final rebalance in rebalanceHistory.reversed) {
          if (rebalance is! Map) continue;

          final rawExec = rebalance['execution'] ??
              rebalance['subscriberExecutions'] ??
              rebalance;

          Map<String, dynamic>? execData;
          if (rawExec is List) {
            if (rawExec.isEmpty) {
              // Empty subscriberExecutions → user hasn't acted yet → treat as pending
              execData = {'executionStatus': 'toExecute'};
            } else {
              for (final item in rawExec) {
                if (item is Map) {
                  final execEmail = (item['user_email'] ?? '').toString().toLowerCase();
                  if (execEmail == email.toLowerCase()) {
                    execData = Map<String, dynamic>.from(item);
                    break;
                  }
                }
              }
              if (execData == null && rawExec.first is Map) {
                execData = Map<String, dynamic>.from(rawExec.first);
              }
            }
          } else if (rawExec is Map) {
            execData = Map<String, dynamic>.from(rawExec);
          }
          if (execData == null) continue;

          final status = (execData['executionStatus'] ??
                  execData['status'] ??
                  execData['userExecution']?['status'] ??
                  '')
              .toString()
              .toLowerCase();

          final modelId = sub['_id']?.toString() ??
              sub['id']?.toString() ??
              sub['model_id']?.toString() ?? '';
          final broker = (execData['user_broker'] ?? execData['broker'] ?? 'DummyBroker').toString();
          final executionBroker = (execData['user_broker'] ?? execData['broker'])?.toString();
          final advisor = (model['advisor'] ?? sub['advisor'] ?? '').toString();
          final rebalanceDate = (rebalance['rebalanceDate'] ?? rebalance['date'])?.toString();

          statuses[modelName] = PortfolioRebalanceStatus(
            modelName: modelName,
            modelId: modelId,
            rebalanceDate: rebalanceDate,
            executionStatus: status,
            broker: broker,
            executionBroker: executionBroker,
            advisor: advisor,
            cardState: connectedBroker != null
                ? PortfolioRebalanceStatus.cardStateWithBrokerMatch(
                    status, executionBroker, connectedBroker)
                : PortfolioRebalanceStatus.cardStateFromStatus(status),
          );
          break; // only latest rebalance
        }
      }

      debugPrint('[RebalanceStatusService] fetchAll statuses: ${statuses.length}');
      return statuses;
    } catch (e) {
      debugPrint('[RebalanceStatusService] fetchAll error: $e');
      return {};
    }
  }

  /// Fetch the user's currently connected broker name (fresh, not cached).
  static Future<String?> fetchConnectedBrokerName(String email) async {
    try {
      // Invalidate cache to get fresh broker status (matches rgx_app behavior)
      CacheService.instance.invalidate('aq/user/brokers:$email');
      final response = await AqApiService.instance.getConnectedBrokers(email);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawData = data['data'];
        final List<dynamic> brokerList;
        if (rawData is List) {
          brokerList = rawData;
        } else if (rawData is Map) {
          brokerList = rawData['connected_brokers'] ?? [];
        } else {
          brokerList = data['connected_brokers'] ?? [];
        }
        for (final b in brokerList) {
          if (b is Map) {
            final status = (b['status'] ?? b['broker_status'] ?? '').toString().toLowerCase();
            if (status == 'connected') {
              return (b['broker'] ?? b['broker_name'] ?? b['user_broker'] ?? '').toString();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RebalanceStatusService] fetchConnectedBrokerName error: $e');
    }
    return null;
  }
}
