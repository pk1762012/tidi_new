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
  final String? planType;           // "onetime" | "recurring" | "combined"
  final Map<String, int> pricing;   // {"monthly": 999, "quarterly": 2499}
  final String? strategyId;         // model_portfolio _id for subscribe API
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
    this.planType,
    this.pricing = const {},
    this.strategyId,
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
    // Strategy API may nest under 'model', or have rebalanceHistory at the top level
    List<PortfolioStock> stocks = [];
    List<RebalanceHistoryEntry> rebalanceHistory = [];

    // Try nested 'model.rebalanceHistory' first, then top-level 'rebalanceHistory'
    final model = json['model'];
    List<dynamic>? historyRaw;
    if (model != null && model is Map && model['rebalanceHistory'] is List) {
      historyRaw = model['rebalanceHistory'];
    } else if (json['rebalanceHistory'] is List) {
      historyRaw = json['rebalanceHistory'];
    }

    if (historyRaw != null && historyRaw.isNotEmpty) {
      rebalanceHistory = historyRaw
          .whereType<Map>()
          .map((e) => RebalanceHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final latest = historyRaw.last;
      if (latest is Map) {
        final List<dynamic> entries = latest['adviceEntries'] ?? [];
        stocks = entries
            .whereType<Map>()
            .map((e) => PortfolioStock.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }

    // Fallback: some API responses include 'adviceEntries' or 'stocks' at the top level
    if (stocks.isEmpty) {
      final directEntries = json['adviceEntries'] ?? json['stocks'];
      if (directEntries is List && directEntries.isNotEmpty) {
        stocks = directEntries
            .whereType<Map>()
            .map((e) => PortfolioStock.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }

    // Fallback: check inside 'model' for direct adviceEntries
    if (stocks.isEmpty && model != null && model is Map) {
      final modelEntries = model['adviceEntries'] ?? model['stocks'];
      if (modelEntries is List && modelEntries.isNotEmpty) {
        stocks = modelEntries
            .whereType<Map>()
            .map((e) => PortfolioStock.fromJson(Map<String, dynamic>.from(e)))
            .toList();
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

    // Parse pricing tiers from Plans API
    final pricing = _parsePricing(json['pricing']);

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
      planType: json['planType'],
      pricing: pricing,
      strategyId: json['strategyId'] ?? json['strategy_id'],
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
      planType: planType ?? strategyData.planType,
      pricing: pricing.isNotEmpty ? pricing : strategyData.pricing,
      strategyId: strategyId ?? strategyData.strategyId,
      subscribedBy: subscribedBy.isNotEmpty ? subscribedBy : strategyData.subscribedBy,
      stocks: strategyData.stocks,
      rebalanceHistory: strategyData.rebalanceHistory,
      lastUpdated: lastUpdated ?? strategyData.lastUpdated,
      createdAt: createdAt ?? strategyData.createdAt,
    );
  }

  /// Parse pricing tiers from Plans API response.
  static Map<String, int> _parsePricing(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    return Map.fromEntries(
      raw.entries
          .where((e) => e.value != null && e.value != 0)
          .map((e) => MapEntry(e.key.toString(), (e.value as num).toInt())),
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
