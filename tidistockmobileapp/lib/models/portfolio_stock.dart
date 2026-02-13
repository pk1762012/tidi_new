class PortfolioStock {
  final String symbol;
  final double weight;
  final double? price;
  final String? exchange;
  final DateTime? date;

  PortfolioStock({
    required this.symbol,
    required this.weight,
    this.price,
    this.exchange,
    this.date,
  });

  factory PortfolioStock.fromJson(Map<String, dynamic> json) {
    return PortfolioStock(
      symbol: json['symbol'] ?? '',
      weight: (json['value'] ?? json['weight'] ?? 0).toDouble(),
      price: json['price']?.toDouble(),
      exchange: json['exchange'],
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'value': weight,
    'price': price,
    'exchange': exchange,
  };
}
