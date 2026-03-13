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
      symbol: json['tradingSymbol'] ?? json['trading_symbol'] ?? json['symbol'] ?? '',
      transactionType: json['transactionType'] ?? json['transaction_type'] ?? json['type'] ?? 'buy',
      quantity: (json['quantity'] ?? json['filledQuantity'] ?? json['filled_quantity'] ?? json['tradedQty'] ?? json['qty'] ?? 0).toInt(),
      price: _safeDouble(json['averageEntryPrice'] ?? json['averagePrice'] ?? json['average_price'] ?? json['avgPrice'] ?? json['avg_price'] ?? json['executedPrice'] ?? json['tradedPrice'] ?? json['price']),
      orderId: (json['orderId'] ?? json['order_id'] ?? json['uniqueOrderId'] ?? '').toString(),
      // Check all possible status field names returned by different brokers.
      // Also check rebalance_status — prod MPStatusModal.js treats
      // rebalance_status "failed"/"failure" as failed (lines 38-39).
      status: _parseStatusWithRebalance(
          json['orderStatus'] ?? json['order_status'] ?? json['trade_place_status'] ?? json['status'],
          json['rebalance_status']),
      exchange: json['exchange'],
      productType: json['productType'] ?? json['product_type'],
      orderType: json['orderType'] ?? json['order_type'],
      message: json['message'] ?? json['orderStatusMessage'] ?? json['message_aq'] ?? json['rejectionReason'] ?? json['status_message'],
    );
  }

  static double? _safeDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Combines orderStatus and rebalance_status to determine final status.
  /// Matches prod MPStatusModal.js isStockFailed() which checks both fields.
  static String _parseStatusWithRebalance(dynamic orderStatus, dynamic rebalanceStatus) {
    final parsed = _parseStatus(orderStatus);
    if (parsed != 'pending') return parsed;
    // If orderStatus is ambiguous/pending but rebalance_status signals failure,
    // treat as failed (matching prod MPStatusModal.js lines 38-39).
    if (rebalanceStatus != null) {
      final rs = rebalanceStatus.toString().toLowerCase().trim();
      if (rs == 'failed' || rs == 'failure') return 'failed';
    }
    return parsed;
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
