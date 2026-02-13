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

    return ModelPortfolio(
      id: json['_id'] ?? '',
      advisor: json['advisor'] ?? '',
      modelName: json['model_name'] ?? '',
      minInvestment: (json['minInvestment'] ?? 0).toInt(),
      maxNetWorth: json['maxNetWorth']?.toInt(),
      overView: json['overView'],
      investmentStrategy: List<String>.from(json['investmentStrategy'] ?? []),
      whyThisStrategy: json['whyThisStrategy'],
      frequency: json['frequency'],
      nextRebalanceDate: json['nextRebalanceDate'] != null
          ? DateTime.tryParse(json['nextRebalanceDate'].toString())
          : null,
      riskProfile: json['riskProfile'],
      image: json['image'],
      blogLink: json['blogLink'],
      researchReportLink: json['researchReportLink'],
      definingUniverse: json['definingUniverse'],
      researchOverView: json['researchOverView'],
      constituentScreening: json['constituentScreening'],
      weighting: json['weighting'],
      rebalanceMethodologyText: json['rebalanceMethodologyText'],
      assetAllocationText: json['assetAllocationText'],
      subscribedBy: List<String>.from(json['subscribed_by'] ?? []),
      stocks: stocks,
      rebalanceHistory: rebalanceHistory,
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  bool isSubscribedBy(String email) => subscribedBy.contains(email);
}
