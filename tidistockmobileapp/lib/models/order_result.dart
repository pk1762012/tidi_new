class OrderResult {
  final String symbol;
  final String transactionType; // buy, sell
  final int quantity;
  final double? price;
  final String? orderId;
  final String status; // pending, success, failed, partial
  final String? exchange;
  final String? productType;
  final String? orderType;
  final String? message;

  OrderResult({
    required this.symbol,
    required this.transactionType,
    required this.quantity,
    this.price,
    this.orderId,
    this.status = 'pending',
    this.exchange,
    this.productType,
    this.orderType,
    this.message,
  });

  factory OrderResult.fromJson(Map<String, dynamic> json) {
    return OrderResult(
      symbol: json['tradingSymbol'] ?? json['symbol'] ?? '',
      transactionType: json['transactionType'] ?? 'buy',
      quantity: (json['quantity'] ?? json['tradedQty'] ?? 0).toInt(),
      price: json['price']?.toDouble() ?? json['tradedPrice']?.toDouble(),
      orderId: json['orderId'],
      status: _parseStatus(json['trade_place_status'] ?? json['status']),
      exchange: json['exchange'],
      productType: json['productType'],
      orderType: json['orderType'],
      message: json['message'],
    );
  }

  static String _parseStatus(dynamic status) {
    if (status == null) return 'pending';
    final s = status.toString().toLowerCase();
    if (s.contains('success') || s.contains('complete') || s.contains('executed')) {
      return 'success';
    }
    if (s.contains('fail') || s.contains('reject')) return 'failed';
    if (s.contains('partial')) return 'partial';
    return 'pending';
  }

  Map<String, dynamic> toApiJson() => {
    'symbol': symbol,
    'rebalance_status': status == 'success' ? 'success' : (status == 'partial' ? 'partial' : 'failed'),
    'transactionType': transactionType,
  };

  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
}
