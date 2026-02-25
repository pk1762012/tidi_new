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
      // Check all possible status field names returned by different brokers
      status: _parseStatus(
          json['orderStatus'] ?? json['trade_place_status'] ?? json['status']),
      exchange: json['exchange'],
      productType: json['productType'],
      orderType: json['orderType'],
      message: json['message'] ?? json['orderStatusMessage'] ?? json['message_aq'],
    );
  }

  static String _parseStatus(dynamic status) {
    if (status == null) return 'pending';
    final s = status.toString().toLowerCase().trim();

    // Success statuses (Zerodha: 'complete', Angel One: 'traded', etc.)
    if (s == 'success' ||
        s == 'complete' ||
        s == 'completed' ||
        s == 'traded' ||
        s == 'executed' ||
        s == 'filled' ||
        s.contains('success') ||
        s.contains('complete') ||
        s.contains('executed') ||
        s.contains('traded') ||
        s.contains('filled')) {
      return 'success';
    }

    // Failure statuses
    if (s == 'rejected' ||
        s == 'failed' ||
        s == 'failure' ||
        s == 'cancelled' ||
        s == 'canceled' ||
        s.contains('reject') ||
        s.contains('fail') ||
        s.contains('cancel')) {
      return 'failed';
    }

    if (s.contains('partial')) return 'partial';

    // 'open', 'trigger pending', 'pending', 'transit', 'placed', unknown → pending
    return 'pending';
  }

  Map<String, dynamic> toApiJson() => {
    'symbol': symbol,
    'rebalance_status': status == 'success'
        ? 'success'
        : (status == 'partial'
            ? 'partial'
            : (status == 'pending' ? 'pending' : 'failed')),
    'transactionType': transactionType,
  };

  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
}
