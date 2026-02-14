import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'portfolio_stock.dart';
import 'rebalance_entry.dart';

class PerformanceData {
  // Returns
  final double? cagr;
  final double? totalReturn;
  final double? ytdReturn;
  final double? oneYearReturn;
  // Risk
  final double? volatility;
  final double? valueAtRisk;
  final double? cvar;
  final double? ulcerIndex;
  // Drawdown
  final double? maxDrawdown;
  final double? avgDrawdown;
  final int? longestDdDays;
  // Ratios
  final double? sharpeRatio;
  final double? sortinoRatio;
  final double? profitFactor;
  final double? gainToPain;
  // Timing
  final double? winRate;
  final double? bestDay;
  final double? worstDay;
  final double? timeInMarket;
  // General
  final String? startDate;
  final String? endDate;

  PerformanceData({
    this.cagr,
    this.totalReturn,
    this.ytdReturn,
    this.oneYearReturn,
    this.volatility,
    this.valueAtRisk,
    this.cvar,
    this.ulcerIndex,
    this.maxDrawdown,
    this.avgDrawdown,
    this.longestDdDays,
    this.sharpeRatio,
    this.sortinoRatio,
    this.profitFactor,
    this.gainToPain,
    this.winRate,
    this.bestDay,
    this.worstDay,
    this.timeInMarket,
    this.startDate,
    this.endDate,
  });

  factory PerformanceData.fromJson(Map<String, dynamic> json) {
    return PerformanceData(
      cagr: _toDouble(json['cagr']),
      totalReturn: _toDouble(json['total_return'] ?? json['totalReturn']),
      ytdReturn: _toDouble(json['ytd_return'] ?? json['ytdReturn']),
      oneYearReturn: _toDouble(json['one_year_return'] ?? json['oneYearReturn']),
      volatility: _toDouble(json['volatility']),
      valueAtRisk: _toDouble(json['value_at_risk'] ?? json['valueAtRisk']),
      cvar: _toDouble(json['cvar']),
      ulcerIndex: _toDouble(json['ulcer_index'] ?? json['ulcerIndex']),
      maxDrawdown: _toDouble(json['max_drawdown'] ?? json['maxDrawdown']),
      avgDrawdown: _toDouble(json['avg_drawdown'] ?? json['avgDrawdown']),
      longestDdDays: _toInt(json['longest_dd_days'] ?? json['longestDdDays']),
      sharpeRatio: _toDouble(json['sharpe_ratio'] ?? json['sharpeRatio']),
      sortinoRatio: _toDouble(json['sortino_ratio'] ?? json['sortinoRatio']),
      profitFactor: _toDouble(json['profit_factor'] ?? json['profitFactor']),
      gainToPain: _toDouble(json['gain_to_pain'] ?? json['gainToPain']),
      winRate: _toDouble(json['win_rate'] ?? json['winRate']),
      bestDay: _toDouble(json['best_day'] ?? json['bestDay']),
      worstDay: _toDouble(json['worst_day'] ?? json['worstDay']),
      timeInMarket: _toDouble(json['time_in_market'] ?? json['timeInMarket']),
      startDate: json['start_date']?.toString() ?? json['startDate']?.toString(),
      endDate: json['end_date']?.toString() ?? json['endDate']?.toString(),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

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
  final PerformanceData? performanceData;

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
    this.performanceData,
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
    final subscription = json['subscription'];
    if (subscription is Map && subscribedBy.isEmpty) {
      final subEmail = subscription['user_email'];
      if (subEmail != null) subscribedBy = [subEmail.toString()];
    }

    // Handle lastUpdated: Plans API uses 'updated_at', model_portfolio uses 'last_updated'
    final lastUpdatedRaw = json['last_updated'] ?? json['updated_at'];

    // Parse pricing tiers from Plans API
    final pricing = _parsePricing(json['pricing']);

    // Parse performance data if available
    final perfRaw = json['performance_data'] ?? json['performanceData'];
    final performanceData = perfRaw is Map
        ? PerformanceData.fromJson(Map<String, dynamic>.from(perfRaw))
        : null;

    return ModelPortfolio(
      id: json['_id'] ?? '',
      advisor: json['advisor'] ?? '',
      // Plans API uses 'name', model_portfolio API uses 'model_name'
      modelName: json['model_name'] ?? json['name'] ?? '',
      minInvestment: _safeInt(json['minInvestment']) ?? 0,
      maxNetWorth: _safeInt(json['maxNetWorth']),
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
      performanceData: performanceData,
    );
  }

  bool isSubscribedBy(String email) => subscribedBy.contains(email);

  /// Short human-readable pricing string based on the lowest-priced tier.
  /// Returns empty string if no pricing tiers exist.
  String get pricingDisplayText {
    if (pricing.isEmpty) return '';
    const abbr = {
      'monthly': '/mo',
      'quarterly': '/qtr',
      'half_yearly': '/6mo',
      'yearly': '/yr',
    };
    final sorted = pricing.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final lowest = sorted.first;
    final amount = lowest.value >= 1000
        ? '\u20B9${(lowest.value / 1000).toStringAsFixed(lowest.value % 1000 == 0 ? 0 : 1)}K'
        : '\u20B9${lowest.value}';
    final period = abbr[lowest.key] ?? '/${lowest.key}';
    return '$amount$period';
  }

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
      performanceData: performanceData ?? strategyData.performanceData,
    );
  }

  /// Parse pricing tiers from Plans API response.
  static Map<String, int> _parsePricing(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    final result = <String, int>{};
    for (final e in raw.entries) {
      if (e.value == null) continue;
      final parsed = e.value is num
          ? e.value.toInt()
          : int.tryParse(e.value.toString());
      if (parsed != null && parsed != 0) {
        result[e.key.toString()] = parsed;
      }
    }
    return result;
  }

  /// Safely parse a dynamic value (num or String) to int.
  static int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
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
