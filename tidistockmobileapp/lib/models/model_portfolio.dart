import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'portfolio_stock.dart';
import 'rebalance_entry.dart';

class ModelPortfolio {
  final String id;
  final String advisor;
  final String modelName;
  final int minInvestment;
  final int? maxNetWorth;
  final String? overView;
  final List<String> investmentStrategy;
  final String? whyThisStrategy;
  final String? frequency;
  final DateTime? nextRebalanceDate;
  final String? riskProfile;
  final String? image;
  final String? blogLink;
  final String? researchReportLink;
  final String? definingUniverse;
  final String? researchOverView;
  final String? constituentScreening;
  final String? weighting;
  final String? rebalanceMethodologyText;
  final String? assetAllocationText;
  final List<String> subscribedBy;
  final List<PortfolioStock> stocks;
  final List<RebalanceHistoryEntry> rebalanceHistory;
  final DateTime? lastUpdated;
  final DateTime? createdAt;

  ModelPortfolio({
    required this.id,
    required this.advisor,
    required this.modelName,
    required this.minInvestment,
    this.maxNetWorth,
    this.overView,
    this.investmentStrategy = const [],
    this.whyThisStrategy,
    this.frequency,
    this.nextRebalanceDate,
    this.riskProfile,
    this.image,
    this.blogLink,
    this.researchReportLink,
    this.definingUniverse,
    this.researchOverView,
    this.constituentScreening,
    this.weighting,
    this.rebalanceMethodologyText,
    this.assetAllocationText,
    this.subscribedBy = const [],
    this.stocks = const [],
    this.rebalanceHistory = const [],
    this.lastUpdated,
    this.createdAt,
  });

  factory ModelPortfolio.fromJson(Map<String, dynamic> json) {
    // Strategy endpoint wraps data in {"originalData": {...}}
    if (json.containsKey('originalData') && json['originalData'] is Map) {
      json = Map<String, dynamic>.from(json['originalData']);
    }

    // Extract stocks from the latest rebalance history entry
    List<PortfolioStock> stocks = [];
    List<RebalanceHistoryEntry> rebalanceHistory = [];

    final model = json['model'];
    if (model != null && model['rebalanceHistory'] != null) {
      final List<dynamic> history = model['rebalanceHistory'] ?? [];
      rebalanceHistory = history.map((e) => RebalanceHistoryEntry.fromJson(e)).toList();

      if (history.isNotEmpty) {
        final latest = history.last;
        final List<dynamic> entries = latest['adviceEntries'] ?? [];
        stocks = entries.map((e) => PortfolioStock.fromJson(e)).toList();
      }
    }

    // Handle frequency: Plans API returns array, model_portfolio API returns string
    String? frequency;
    final rawFreq = json['frequency'];
    if (rawFreq is String) {
      frequency = rawFreq;
    } else if (rawFreq is List && rawFreq.isNotEmpty) {
      frequency = rawFreq.first.toString();
    }

    // Handle subscription: Plans API appends a 'subscription' object (non-null = subscribed)
    List<String> subscribedBy = _toStringList(json['subscribed_by']);
    if (json['subscription'] != null && subscribedBy.isEmpty) {
      // Plans API: mark subscription status via the appended subscription object
      final subEmail = json['subscription']['user_email'];
      if (subEmail != null) subscribedBy = [subEmail.toString()];
    }

    // Handle lastUpdated: Plans API uses 'updated_at', model_portfolio uses 'last_updated'
    final lastUpdatedRaw = json['last_updated'] ?? json['updated_at'];

    return ModelPortfolio(
      id: json['_id'] ?? '',
      advisor: json['advisor'] ?? '',
      // Plans API uses 'name', model_portfolio API uses 'model_name'
      modelName: json['model_name'] ?? json['name'] ?? '',
      minInvestment: (json['minInvestment'] ?? 0).toInt(),
      maxNetWorth: json['maxNetWorth']?.toInt(),
      // Plans API uses 'description' (may contain HTML), model_portfolio API uses 'overView'
      overView: _stripHtml(json['overView'] ?? json['description']),
      investmentStrategy: _toStringList(json['investmentStrategy']),
      whyThisStrategy: json['whyThisStrategy'],
      frequency: frequency,
      nextRebalanceDate: json['nextRebalanceDate'] != null
          ? DateTime.tryParse(json['nextRebalanceDate'].toString())
          : null,
      riskProfile: json['riskProfile'],
      image: _resolveImageUrl(json['image']),
      blogLink: json['blogLink'],
      researchReportLink: json['researchReportLink'],
      definingUniverse: json['definingUniverse'],
      researchOverView: json['researchOverView'],
      constituentScreening: json['constituentScreening'],
      weighting: json['weighting'],
      rebalanceMethodologyText: json['rebalanceMethodologyText'],
      assetAllocationText: json['assetAllocationText'],
      subscribedBy: subscribedBy,
      stocks: stocks,
      rebalanceHistory: rebalanceHistory,
      lastUpdated: lastUpdatedRaw != null
          ? DateTime.tryParse(lastUpdatedRaw.toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  bool isSubscribedBy(String email) => subscribedBy.contains(email);

  /// Merge only stocks & rebalance data from the strategy endpoint,
  /// keeping Plans API data as the source of truth for plan-level fields.
  ModelPortfolio mergeStrategyData(ModelPortfolio strategyData) {
    return ModelPortfolio(
      id: id,
      advisor: advisor,
      modelName: modelName,
      minInvestment: minInvestment,
      maxNetWorth: maxNetWorth,
      overView: overView,
      investmentStrategy: investmentStrategy.isNotEmpty
          ? investmentStrategy
          : strategyData.investmentStrategy,
      whyThisStrategy: whyThisStrategy ?? strategyData.whyThisStrategy,
      frequency: frequency ?? strategyData.frequency,
      nextRebalanceDate: nextRebalanceDate ?? strategyData.nextRebalanceDate,
      riskProfile: riskProfile ?? strategyData.riskProfile,
      image: image ?? strategyData.image,
      blogLink: blogLink ?? strategyData.blogLink,
      researchReportLink: researchReportLink ?? strategyData.researchReportLink,
      definingUniverse: definingUniverse ?? strategyData.definingUniverse,
      researchOverView: researchOverView ?? strategyData.researchOverView,
      constituentScreening: constituentScreening ?? strategyData.constituentScreening,
      weighting: weighting ?? strategyData.weighting,
      rebalanceMethodologyText: rebalanceMethodologyText ?? strategyData.rebalanceMethodologyText,
      assetAllocationText: assetAllocationText ?? strategyData.assetAllocationText,
      subscribedBy: subscribedBy.isNotEmpty ? subscribedBy : strategyData.subscribedBy,
      stocks: strategyData.stocks,
      rebalanceHistory: strategyData.rebalanceHistory,
      lastUpdated: lastUpdated ?? strategyData.lastUpdated,
      createdAt: createdAt ?? strategyData.createdAt,
    );
  }

  /// Safely convert a dynamic value to List<String>.
  /// Handles: null → [], String → [string], List → List<String>.from(list)
  static List<String> _toStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return List<String>.from(raw.map((e) => e.toString()));
    if (raw is String && raw.isNotEmpty) return [raw];
    return [];
  }

  /// Strip HTML tags from text (Plans API descriptions may contain HTML)
  static String? _stripHtml(dynamic raw) {
    if (raw == null || raw is! String || raw.isEmpty) return null;
    return raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  /// Resolve relative image paths (Plans API stores e.g. "uploads/plans/abc.png")
  static String? _resolveImageUrl(dynamic raw) {
    if (raw == null || raw is! String || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final baseUrl = dotenv.env['AQ_BACKEND_URL'] ?? '';
    return '$baseUrl$raw';
  }
}
