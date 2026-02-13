import 'portfolio_stock.dart';

class RebalanceHistoryEntry {
  final String? modelId;
  final DateTime? rebalanceDate;
  final String? updatedModelName;
  final double? totalInvestmentValue;
  final String? researchReportLink;
  final List<PortfolioStock> adviceEntries;
  final List<SubscriberExecution> subscriberExecutions;

  RebalanceHistoryEntry({
    this.modelId,
    this.rebalanceDate,
    this.updatedModelName,
    this.totalInvestmentValue,
    this.researchReportLink,
    this.adviceEntries = const [],
    this.subscriberExecutions = const [],
  });

  factory RebalanceHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RebalanceHistoryEntry(
      modelId: json['model_Id'] ?? json['_id'],
      rebalanceDate: json['rebalanceDate'] != null
          ? DateTime.tryParse(json['rebalanceDate'].toString())
          : null,
      updatedModelName: json['updatedModelName'],
      totalInvestmentValue: json['totalInvestmentvalue']?.toDouble(),
      researchReportLink: json['rr_link_mpf'],
      adviceEntries: (json['adviceEntries'] as List<dynamic>?)
              ?.map((e) => PortfolioStock.fromJson(e))
              .toList() ??
          [],
      subscriberExecutions: (json['subscriberExecutions'] as List<dynamic>?)
              ?.map((e) => SubscriberExecution.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// Check if a specific user has a pending execution
  SubscriberExecution? getExecutionForUser(String email) {
    try {
      return subscriberExecutions.firstWhere((e) => e.userEmail == email);
    } catch (_) {
      return null;
    }
  }

  bool hasPendingExecution(String email) {
    final exec = getExecutionForUser(email);
    return exec != null && (exec.status == 'pending' || exec.status == 'toExecute');
  }
}

class SubscriberExecution {
  final String? userEmail;
  final String? userBroker;
  final String status; // pending, executed, toExecute, partial, failed
  final DateTime? executionDate;

  SubscriberExecution({
    this.userEmail,
    this.userBroker,
    this.status = 'pending',
    this.executionDate,
  });

  factory SubscriberExecution.fromJson(Map<String, dynamic> json) {
    return SubscriberExecution(
      userEmail: json['user_email'],
      userBroker: json['user_broker'],
      status: json['status'] ?? 'pending',
      executionDate: json['executionDate'] != null
          ? DateTime.tryParse(json['executionDate'].toString())
          : null,
    );
  }

  bool get isPending => status == 'pending' || status == 'toExecute';
  bool get isExecuted => status == 'executed';
}
