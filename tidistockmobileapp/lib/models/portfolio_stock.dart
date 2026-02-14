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
      weight: _toDouble(json['value'] ?? json['weight'] ?? 0) ?? 0,
      price: _toDouble(json['price']),
      exchange: json['exchange'],
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'value': weight,
    'price': price,
    'exchange': exchange,
  };
}
