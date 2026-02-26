import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'RebalanceReviewPage.dart';

/// Pending orders page — shows individual order statuses after execution.
/// Matches rgx_app's PendingOrdersModal.
class PendingOrdersPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;
  final String broker;
  final String advisor;

  const PendingOrdersPage({
    super.key,
    required this.portfolio,
    required this.email,
    required this.broker,
    required this.advisor,
  });

  @override
  State<PendingOrdersPage> createState() => _PendingOrdersPageState();
}

class _PendingOrdersPageState extends State<PendingOrdersPage> {
  List<_OrderStatus> _orders = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  // Auto-poll state
  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 5;
  static const Duration _pollInterval = Duration(seconds: 15);

  String get _modelName => widget.portfolio.modelName;

  @override
  void initState() {
    super.initState();
    _fetchOrderStatuses();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrderStatuses() async {
    try {
      final response = await AqApiService.instance.getLatestUserPortfolio(
        email: widget.email,
        modelName: _modelName,
        broker: widget.broker,
      );

      debugPrint('[PendingOrders] getLatestUserPortfolio status=${response.statusCode}');
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final orders = _parseOrders(data);
        setState(() {
          _orders = orders;
          _loading = false;
          _error = null;
        });
        _startAutoPollingIfNeeded();
      } else {
        debugPrint('[PendingOrders] getLatestUserPortfolio error body: ${response.body}');
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Failed to fetch order status (${response.statusCode})';
          });
        }
      }
    } catch (e) {
      debugPrint('[PendingOrders] _fetchOrderStatuses error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to fetch order status';
        });
      }
    }
  }

  List<_OrderStatus> _parseOrders(dynamic data) {
    final orders = <_OrderStatus>[];

    // Try multiple possible shapes — actual API returns:
    // { data: { user_net_pf_model: { order_results: [...] } } }
    List<dynamic> orderList = [];
    if (data is Map) {
      final innerData = data['data'];

      // Direct top-level
      orderList = data['order_results'] ??
          data['orderResults'] ??
          data['orders'] ??
          [];

      // Inside data wrapper
      if (orderList.isEmpty && innerData is Map) {
        orderList = innerData['order_results'] ??
            innerData['orderResults'] ??
            innerData['orders'] ??
            [];

        // data.data.user_net_pf_model.order_results (Map form — actual API shape)
        if (orderList.isEmpty) {
          final userNetPf = innerData['user_net_pf_model'];
          if (userNetPf is Map) {
            orderList = userNetPf['order_results'] ?? userNetPf['stocks'] ?? userNetPf['holdings'] ?? [];
          } else if (userNetPf is List && userNetPf.isNotEmpty) {
            final latest = userNetPf.last;
            if (latest is List) orderList = latest;
            if (latest is Map) orderList = latest['order_results'] ?? latest['stocks'] ?? latest['holdings'] ?? [];
          }
        }
      }

      // Fallback: top-level user_net_pf_model
      if (orderList.isEmpty) {
        final userNetPf = data['user_net_pf_model'];
        if (userNetPf is Map) {
          orderList = userNetPf['order_results'] ?? userNetPf['stocks'] ?? userNetPf['holdings'] ?? [];
        } else if (userNetPf is List && userNetPf.isNotEmpty) {
          final latest = userNetPf.last;
          if (latest is List) orderList = latest;
          if (latest is Map) orderList = latest['order_results'] ?? latest['stocks'] ?? latest['holdings'] ?? [];
        }
      }
    } else if (data is List) {
      orderList = data;
    }

    debugPrint('[PendingOrders] _parseOrders: found ${orderList.length} orders');

    for (final order in orderList) {
      if (order is! Map) continue;
      final symbol = (order['symbol'] ?? order['tradingSymbol'] ?? order['trading_symbol'] ?? '').toString();
      if (symbol.isEmpty) continue;

      final rawStatus = (order['orderStatus'] ?? order['order_status'] ?? order['status'] ?? order['trade_place_status'] ?? '').toString().toUpperCase();
      final quantity = (order['quantity'] ?? order['filledQuantity'] ?? order['filled_quantity'] ?? order['qty'] ?? 0);
      final price = _safeDouble(order['averageEntryPrice'] ?? order['averagePrice'] ?? order['average_price'] ?? order['avgPrice'] ?? order['avg_price'] ?? order['executedPrice'] ?? order['price']);
      final transactionType = (order['transactionType'] ?? order['transaction_type'] ?? order['type'] ?? '').toString().toUpperCase();
      final orderId = (order['orderId'] ?? order['order_id'] ?? '').toString();
      final message = (order['message'] ?? order['status_message'] ?? order['rejectionReason'] ?? '').toString();

      orders.add(_OrderStatus(
        symbol: symbol,
        status: rawStatus,
        quantity: quantity is num ? quantity.toInt() : int.tryParse(quantity.toString()) ?? 0,
        price: price,
        transactionType: transactionType,
        orderId: orderId,
        message: message,
      ));
    }

    return orders;
  }

  double _safeDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  void _startAutoPollingIfNeeded() {
    _pollTimer?.cancel();
    final hasPending = _orders.any((o) => o.isPending);
    if (hasPending && _pollCount < _maxPolls) {
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        _pollCount++;
        _refreshOrderStatus();
        if (_pollCount >= _maxPolls) {
          _pollTimer?.cancel();
        }
      });
    }
  }

  Future<void> _refreshOrderStatus() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      // Step 1: Add to status check queue
      await AqApiService.instance.addToStatusCheckQueue(
        email: widget.email,
        modelName: _modelName,
        advisor: widget.advisor,
        broker: widget.broker,
      );

      // Step 2: Wait 3 seconds for backend processing
      await Future.delayed(const Duration(seconds: 3));

      // Step 3: Re-fetch
      final response = await AqApiService.instance.getLatestUserPortfolio(
        email: widget.email,
        modelName: _modelName,
        broker: widget.broker,
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final orders = _parseOrders(data);
        setState(() {
          _orders = orders;
          _refreshing = false;
        });
        _startAutoPollingIfNeeded();
      } else {
        if (mounted) setState(() => _refreshing = false);
      }
    } catch (e) {
      debugPrint('[PendingOrders] _refreshOrderStatus error: $e');
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _cancelAndRetry() async {
    final isZerodha = widget.broker.toLowerCase() == 'zerodha';

    if (isZerodha) {
      // Show info dialog for Zerodha users
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Zerodha Orders", style: TextStyle(fontSize: 18)),
          content: const Text(
            "Please cancel pending orders from the Kite app, then return here to retry the rebalance.",
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Retry Rebalance"),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    } else {
      // Cancel pending orders for non-Zerodha brokers
      final pendingOrders = _orders.where((o) => o.isPending).toList();
      for (final order in pendingOrders) {
        if (order.orderId.isNotEmpty) {
          try {
            await AqApiService.instance.cancelOrder(
              email: widget.email,
              orderId: order.orderId,
              broker: widget.broker,
            );
          } catch (e) {
            debugPrint('[PendingOrders] cancelOrder ${order.orderId} error: $e');
          }
        }
      }
    }

    // Reset execution to toExecute
    try {
      await AqApiService.instance.resetExecutionToExecute(
        email: widget.email,
        modelName: _modelName,
        advisor: widget.advisor,
        broker: widget.broker,
      );
    } catch (e) {
      debugPrint('[PendingOrders] resetExecution error: $e');
    }

    // Navigate to RebalanceReviewPage
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RebalanceReviewPage(
          portfolio: widget.portfolio,
          email: widget.email,
        ),
      ),
    );
  }

  int get _filledCount => _orders.where((o) => o.isFilled).length;
  int get _pendingCount => _orders.where((o) => o.isPending).length;
  int get _rejectedCount => _orders.where((o) => o.isRejected).length;

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Order Status",
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshOrderStatus,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      children: [
                        _headerCard(),
                        const SizedBox(height: 16),
                        _summaryRow(),
                        const SizedBox(height: 16),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_error!,
                                style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
                          ),
                        ..._orders.map((o) => _orderRow(o)),
                      ],
                    ),
                  ),
                ),
                _bottomActions(),
              ],
            ),
    );
  }

  Widget _headerCard() {
    final hasError = _error != null && _orders.isEmpty;

    final List<Color> gradientColors;
    final IconData headerIcon;
    final String headerTitle;

    if (hasError) {
      gradientColors = [Colors.red.shade600, Colors.red.shade400];
      headerIcon = Icons.error_outline;
      headerTitle = "Unable to Fetch Orders";
    } else if (_pendingCount > 0) {
      gradientColors = [Colors.amber.shade600, Colors.amber.shade400];
      headerIcon = Icons.hourglass_top;
      headerTitle = "Orders in Progress";
    } else if (_rejectedCount > 0) {
      gradientColors = [Colors.red.shade600, Colors.red.shade400];
      headerIcon = Icons.warning_rounded;
      headerTitle = "Some Orders Failed";
    } else if (_orders.isEmpty) {
      gradientColors = [Colors.amber.shade600, Colors.amber.shade400];
      headerIcon = Icons.hourglass_top;
      headerTitle = "Awaiting Order Status";
    } else {
      gradientColors = [const Color(0xFF2E7D32), const Color(0xFF43A047)];
      headerIcon = Icons.check_circle;
      headerTitle = "All Orders Complete";
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(headerIcon, size: 40, color: Colors.white),
          const SizedBox(height: 10),
          Text(
            headerTitle,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _modelName,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          if (_refreshing) ...[
            const SizedBox(height: 10),
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow() {
    return Row(
      children: [
        _summaryChip("Filled", _filledCount, Colors.green),
        const SizedBox(width: 10),
        _summaryChip("Pending", _pendingCount, Colors.amber.shade700),
        const SizedBox(width: 10),
        _summaryChip("Rejected", _rejectedCount, Colors.red),
      ],
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text("$count",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _orderRow(_OrderStatus order) {
    Color color;
    IconData icon;

    if (order.isFilled) {
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (order.isPending) {
      color = Colors.amber.shade700;
      icon = Icons.hourglass_top;
    } else {
      color = Colors.red;
      icon = Icons.cancel;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  "${order.transactionType} x ${order.quantity}"
                  "${order.price > 0 ? ' @ \u20B9${order.price.toStringAsFixed(2)}' : ''}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (order.isRejected && order.message.isNotEmpty)
                  Text(order.message,
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(order.status,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              if (order.orderId.isNotEmpty)
                Text("#${order.orderId}",
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomActions() {
    final hasPending = _pendingCount > 0;
    final hasRejected = _rejectedCount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (hasPending || hasRejected)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _cancelAndRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(
                      widget.broker.toLowerCase() == 'zerodha'
                          ? "Retry Rebalance"
                          : "Cancel & Retry",
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _refreshing ? null : _refreshOrderStatus,
                icon: _refreshing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: Text(
                  _refreshing ? "Checking..." : "Refresh Status",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1A237E)),
                  foregroundColor: const Color(0xFF1A237E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade400),
                  foregroundColor: Colors.grey.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Back",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderStatus {
  final String symbol;
  final String status;
  final int quantity;
  final double price;
  final String transactionType;
  final String orderId;
  final String message;

  _OrderStatus({
    required this.symbol,
    required this.status,
    required this.quantity,
    required this.price,
    required this.transactionType,
    required this.orderId,
    required this.message,
  });

  static const _filledStatuses = {'COMPLETE', 'TRADED', 'FILLED', 'SUCCESS'};
  static const _pendingStatuses = {'OPEN', 'PENDING', 'TRANSIT', 'TRIGGER PENDING', 'AFTER MARKET ORDER REQ RECEIVED'};
  static const _rejectedStatuses = {'REJECTED', 'CANCELLED', 'CANCELED', 'FAILED', 'ERROR'};

  bool get isFilled => _filledStatuses.contains(status);
  bool get isPending => _pendingStatuses.contains(status) || (!isFilled && !isRejected && status.isNotEmpty);
  bool get isRejected => _rejectedStatuses.contains(status);
}
