class PortfolioSubscription {
  final String id;
  final String email;
  final String modelName;
  final String advisor;
  final String? userBroker;
  final List<dynamic> adviceDetail;
  final List<dynamic> adviceExecuted;
  final List<dynamic> userNetPfModel;
  final List<dynamic> userNetPfUpdated;
  final List<dynamic> subscriptionAmountRaw;
  final List<dynamic> subscriptionUpdated;

  PortfolioSubscription({
    required this.id,
    required this.email,
    required this.modelName,
    required this.advisor,
    this.userBroker,
    this.adviceDetail = const [],
    this.adviceExecuted = const [],
    this.userNetPfModel = const [],
    this.userNetPfUpdated = const [],
    this.subscriptionAmountRaw = const [],
    this.subscriptionUpdated = const [],
  });

  factory PortfolioSubscription.fromJson(Map<String, dynamic> json) {
    return PortfolioSubscription(
      id: json['_id'] ?? '',
      email: json['email'] ?? '',
      modelName: json['model_name'] ?? '',
      advisor: json['advisor'] ?? '',
      userBroker: json['user_broker'],
      adviceDetail: json['advice_detail'] ?? [],
      adviceExecuted: json['advice_executed'] ?? [],
      userNetPfModel: json['user_net_pf_model'] ?? [],
      userNetPfUpdated: json['user_net_pf_updated'] ?? [],
      subscriptionAmountRaw: json['subscription_amount_raw'] ?? [],
      subscriptionUpdated: json['subscription_updated'] ?? [],
    );
  }
}
