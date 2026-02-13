class PortfolioHolding {
  final String symbol;
  final int quantity;
  final double avgPrice;
  final double? ltp;
  final double? pnl;
  final double? pnlPercent;
  final double? allocationPercent;
  final String? exchange;

  PortfolioHolding({
    required this.symbol,
    required this.quantity,
    required this.avgPrice,
    this.ltp,
    this.pnl,
    this.pnlPercent,
    this.allocationPercent,
    this.exchange,
  });

  factory PortfolioHolding.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] ?? json['qty'] ?? 0).toInt();
    final avg = (json['avgPrice'] ?? json['avg_price'] ?? 0).toDouble();
    final ltp = json['ltp']?.toDouble() ?? json['lastPrice']?.toDouble();

    double? pnl;
    double? pnlPercent;
    if (ltp != null && avg > 0) {
      pnl = (ltp - avg) * qty;
      pnlPercent = ((ltp - avg) / avg) * 100;
    }

    return PortfolioHolding(
      symbol: json['symbol'] ?? json['tradingSymbol'] ?? '',
      quantity: qty,
      avgPrice: avg,
      ltp: ltp,
      pnl: json['pnl']?.toDouble() ?? pnl,
      pnlPercent: json['pnlPercent']?.toDouble() ?? pnlPercent,
      allocationPercent: json['allocationPercent']?.toDouble(),
      exchange: json['exchange'],
    );
  }

  double get investedValue => avgPrice * quantity;
  double get currentValue => (ltp ?? avgPrice) * quantity;
}
