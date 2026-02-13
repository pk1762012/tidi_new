class PortfolioPerformance {
  final double investedValue;
  final double currentValue;
  final double absoluteReturns;
  final double returnsPercent;
  final double? cagr;
  final double? sharpeRatio;
  final double? volatility;
  final double? maxDrawdown;

  PortfolioPerformance({
    required this.investedValue,
    required this.currentValue,
    required this.absoluteReturns,
    required this.returnsPercent,
    this.cagr,
    this.sharpeRatio,
    this.volatility,
    this.maxDrawdown,
  });

  factory PortfolioPerformance.fromJson(Map<String, dynamic> json) {
    final invested = (json['investedValue'] ?? json['invested'] ?? 0).toDouble();
    final current = (json['currentValue'] ?? json['current'] ?? 0).toDouble();
    final abs = json['absoluteReturns']?.toDouble() ?? (current - invested);
    final pct = json['returnsPercent']?.toDouble() ??
        (invested > 0 ? ((current - invested) / invested) * 100 : 0.0);

    return PortfolioPerformance(
      investedValue: invested,
      currentValue: current,
      absoluteReturns: abs,
      returnsPercent: pct,
      cagr: json['cagr']?.toDouble(),
      sharpeRatio: json['sharpeRatio']?.toDouble() ?? json['sharpe_ratio']?.toDouble(),
      volatility: json['volatility']?.toDouble(),
      maxDrawdown: json['maxDrawdown']?.toDouble() ?? json['max_drawdown']?.toDouble(),
    );
  }

  factory PortfolioPerformance.empty() => PortfolioPerformance(
    investedValue: 0,
    currentValue: 0,
    absoluteReturns: 0,
    returnsPercent: 0,
  );

  bool get isProfit => absoluteReturns >= 0;
}
