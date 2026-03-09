import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/service/OrderExecutionService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'BrokerAuthPage.dart';
import 'BrokerCredentialPage.dart';
import 'BrokerSelectionPage.dart';
import 'MPStatusModal.dart';
import 'PendingOrdersPage.dart';
import 'PortfolioHoldingsPage.dart';

class ExecutionStatusPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;
  final List<Map<String, dynamic>> orders;
  final String? modelId;
  final String? modelName;
  final String? advisor;

  const ExecutionStatusPage({
    super.key,
    required this.portfolio,
    required this.email,
    required this.orders,
    this.modelId,
    this.modelName,
    this.advisor,
  });

  @override
  State<ExecutionStatusPage> createState() => _ExecutionStatusPageState();
}

class _ExecutionStatusPageState extends State<ExecutionStatusPage> {
  List<OrderResult> results = [];
  int completedCount = 0;

  // States: executing, zerodha_webview, recording, done, error
  String _state = 'executing';
  bool get executing => _state == 'executing' || _state == 'recording';
  bool hasError = false;
  bool isBrokerError = false;
  String? errorMessage;

  // Zerodha WebView state
  WebViewController? _zerodhaWebController;
  List<Map<String, dynamic>>? _zerodhaStockDetails;
  String? _zerodhaApiKey;

  // Delayed status poll timer
  Timer? _statusPollTimer;

  // Execution date recorded when orders are placed
  final DateTime _executionDate = DateTime.now();

  // Order error details (matching alphab2b UpdateRebalanceModal.js orderErrorData)
  List<Map<String, dynamic>> _orderErrors = [];
  double? _fundsRequired;

  String get _modelName => widget.modelName ?? widget.portfolio.modelName;
  String get _advisor => widget.advisor ?? widget.portfolio.advisor;
  String get _modelId {
    if (widget.modelId != null && widget.modelId!.isNotEmpty) return widget.modelId!;
    if (widget.portfolio.rebalanceHistory.isNotEmpty) {
      return widget.portfolio.rebalanceHistory.last.modelId ?? widget.portfolio.id;
    }
    return widget.portfolio.id;
  }

  @override
  void initState() {
    super.initState();
    _executeOrders();
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Cautionary listing detection
  // ---------------------------------------------------------------------------

  List<OrderResult> get _cautionaryStocks => results.where((r) {
        final msg = (r.message ?? '').toLowerCase();
        return msg.contains('cautionary') && msg.contains('listing');
      }).toList();

  bool get _hasCautionaryListingFailures => _cautionaryStocks.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Status poll
  // ---------------------------------------------------------------------------

  void _scheduleStatusPoll() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      try {
        await AqApiService.instance.addToStatusCheckQueue(
          email: widget.email,
          modelName: _modelName,
          advisor: _advisor,
          broker: OrderExecutionService.instance.lastUsedBrokerName.isNotEmpty
              ? OrderExecutionService.instance.lastUsedBrokerName
              : 'DummyBroker',
        );
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        final brokerName = OrderExecutionService.instance.lastUsedBrokerName.isNotEmpty
            ? OrderExecutionService.instance.lastUsedBrokerName
            : null;
        final response = await AqApiService.instance.getLatestUserPortfolio(
          email: widget.email,
          modelName: _modelName,
          broker: brokerName,
        );
        debugPrint('[ExecutionStatus] _scheduleStatusPoll fetch status=${response.statusCode}');
        if (response.statusCode == 200 && mounted) {
          final data = jsonDecode(response.body);
          _updateResultsFromPoll(data);
        } else {
          debugPrint('[ExecutionStatus] _scheduleStatusPoll fetch failed: ${response.statusCode} body=${response.body}');
        }
      } catch (e) {
        debugPrint('[ExecutionStatus] _scheduleStatusPoll error: $e');
      }
    });
  }

  void _updateResultsFromPoll(dynamic data) {
    List<dynamic> orderList = [];
    if (data is Map) {
      final innerData = data['data'];

      // Direct top-level order_results
      orderList = data['order_results'] ??
          data['orderResults'] ??
          [];

      // Check inside data wrapper: data.data.order_results
      if (orderList.isEmpty && innerData is Map) {
        orderList = innerData['order_results'] ??
            innerData['orderResults'] ??
            [];

        // Check data.data.user_net_pf_model.order_results (Map form — actual API shape)
        if (orderList.isEmpty) {
          final userNetPf = innerData['user_net_pf_model'];
          if (userNetPf is Map) {
            orderList = userNetPf['order_results'] ?? userNetPf['stocks'] ?? [];
          } else if (userNetPf is List && userNetPf.isNotEmpty) {
            final latest = userNetPf.last;
            if (latest is List) orderList = latest;
            if (latest is Map) orderList = latest['order_results'] ?? latest['stocks'] ?? [];
          }
        }
      }

      // Fallback: top-level user_net_pf_model
      if (orderList.isEmpty) {
        final userNetPf = data['user_net_pf_model'];
        if (userNetPf is Map) {
          orderList = userNetPf['order_results'] ?? userNetPf['stocks'] ?? [];
        } else if (userNetPf is List && userNetPf.isNotEmpty) {
          final latest = userNetPf.last;
          if (latest is List) orderList = latest;
          if (latest is Map) orderList = latest['order_results'] ?? latest['stocks'] ?? [];
        }
      }
    }

    debugPrint('[ExecutionStatus] _updateResultsFromPoll: found ${orderList.length} orders');

    if (orderList.isEmpty) return;

    // Rebuild results from poll data (matching rgx_app MPStatusModal approach).
    // The poll data from user-portfolio/latest is the authoritative source.
    final newResults = <OrderResult>[];
    for (final order in orderList) {
      if (order is! Map) continue;
      final map = Map<String, dynamic>.from(order);
      newResults.add(OrderResult.fromJson(map));
    }

    if (newResults.isNotEmpty) {
      debugPrint('[ExecutionStatus] rebuilt ${newResults.length} results from poll '
          '(success=${newResults.where((r) => r.isSuccess).length}, '
          'failed=${newResults.where((r) => r.isFailed).length}, '
          'pending=${newResults.where((r) => !r.isSuccess && !r.isFailed).length})');
      results = newResults;
      completedCount = newResults.length;
    }

    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Order execution
  // ---------------------------------------------------------------------------

  Future<void> _executeOrders() async {
    List<OrderResult> orderResults;
    try {
      orderResults = await OrderExecutionService.instance.executeOrders(
        orders: widget.orders,
        email: widget.email,
        modelName: _modelName,
        modelId: _modelId,
        advisor: _advisor,
        onOrderUpdate: (completed, total, latest) {
          if (!mounted) return;
          setState(() {
            completedCount = completed;
            final idx = results.indexWhere((r) => r.symbol == latest.symbol);
            if (idx >= 0) {
              results[idx] = latest;
            } else {
              results.add(latest);
            }
          });
        },
      );
    } on ZerodhaBasketRequiredException catch (e) {
      _zerodhaStockDetails = e.stockDetails;
      _zerodhaApiKey = e.apiKey;
      _setupZerodhaWebView(e.apiKey, e.basketItems);
      return;
    } catch (e) {
      final errStr = e.toString();
      final brokerErr = errStr.contains('No connected broker') ||
          errStr.contains('No credentials found') ||
          errStr.contains('broker credentials') ||
          errStr.contains('session expired') ||
          errStr.contains('token expired') ||
          errStr.contains('Invalid token') ||
          errStr.contains('authentication') ||
          errStr.contains('unauthorized') ||
          errStr.contains('Please reconnect') ||
          errStr.contains('401');

      // Parse order errors from exception if available
      // (matching alphab2b UpdateRebalanceModal.js orderErrors capture)
      _parseOrderErrors(e);

      setState(() {
        _state = 'error';
        hasError = true;
        isBrokerError = brokerErr;
        errorMessage = brokerErr
            ? 'Broker session expired or not connected. Please reconnect your broker.'
            : errStr;
      });
      return;
    }

    CacheService.instance.invalidatePortfolioData(
      widget.email,
      _modelName,
    );

    // Extract per-order errors from failed results
    // (matching alphab2b UpdateRebalanceModal.js orderErrors extraction)
    final failedResults = orderResults.where((r) => r.isFailed).toList();
    if (failedResults.isNotEmpty) {
      _orderErrors = failedResults.map((r) => <String, dynamic>{
        'symbol': r.symbol,
        'transactionType': r.transactionType,
        'quantity': r.quantity,
        'message': r.message ?? 'Order rejected',
        'orderStatus': r.status,
      }).toList();
    }

    if (mounted) {
      setState(() {
        _state = 'done';
        results = orderResults;
      });
      if (_hasPendingOrPartialOrders || _failedCount > 0) {
        _scheduleStatusPoll();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Zerodha WebView Basket Flow
  // ---------------------------------------------------------------------------

  void _setupZerodhaWebView(String apiKey, List<Map<String, dynamic>> basketItems) {
    final basketJson = jsonEncode(basketItems);
    final html = '''
<html>
<body>
<form id="zerodhaForm" method="POST" action="https://kite.zerodha.com/connect/basket">
  <input type="hidden" name="api_key" value="$apiKey" />
  <input type="hidden" name="data" value='$basketJson' />
  <input type="hidden" name="redirect_params" value="test=true" />
</form>
<script>document.getElementById('zerodhaForm').submit();</script>
</body>
</html>
''';

    _zerodhaWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (_isZerodhaSuccessUrl(request.url)) {
            _handleZerodhaBasketSuccess();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) {
          if (_isZerodhaSuccessUrl(url)) {
            _handleZerodhaBasketSuccess();
          }
        },
        onWebResourceError: (error) {
          if (error.url != null && _isZerodhaSuccessUrl(error.url!)) {
            _handleZerodhaBasketSuccess();
          }
        },
      ))
      ..loadHtmlString(html);

    setState(() => _state = 'zerodha_webview');
  }

  bool _isZerodhaSuccessUrl(String url) {
    final advisorSubdomain = AqApiService.instance.advisorSubdomain;
    return url.contains('success') ||
        url.contains('completed') ||
        url.contains('status=success') ||
        url.contains('broker-callback') ||
        url.contains('callback_url') ||
        url.contains('postback') ||
        url.contains('connect/finish') ||
        (advisorSubdomain.isNotEmpty && url.contains(advisorSubdomain));
  }

  Future<void> _handleZerodhaBasketSuccess() async {
    if (_state == 'recording') return;
    setState(() => _state = 'recording');

    try {
      final uniqueId = '${_modelId}_${DateTime.now().millisecondsSinceEpoch}_${widget.email}';

      final recordResp = await AqApiService.instance.recordZerodhaOrders(
        stockDetails: _zerodhaStockDetails ?? [],
        email: widget.email,
        modelId: _modelId,
        modelName: _modelName,
        advisor: _advisor,
        uniqueId: uniqueId,
      );

      debugPrint('[ExecutionStatus:Zerodha] record-orders status=${recordResp.statusCode}');

      if (recordResp.statusCode == 200) {
        final data = jsonDecode(recordResp.body);
        // Check all common response key names (matches non-Zerodha processTrade parsing)
        final innerData = data['data'];
        final orderData = data['tradeDetails'] ??
            data['response'] ??
            data['order_results'] ??
            data['results'] ??
            data['trade_details'] ??
            (innerData is List ? innerData : null) ??
            (innerData is Map
                ? (innerData['tradeDetails'] ??
                    innerData['order_results'] ??
                    innerData['results'] ??
                    [])
                : []);
        if (orderData is List && orderData.isNotEmpty) {
          for (int i = 0; i < orderData.length; i++) {
            results.add(OrderResult.fromJson(
              orderData[i] is Map ? Map<String, dynamic>.from(orderData[i]) : {},
            ));
          }
        } else {
          for (final order in widget.orders) {
            results.add(OrderResult(
              symbol: order['symbol'] ?? order['tradingSymbol'] ?? '',
              transactionType: order['transactionType'] ?? 'BUY',
              quantity: order['quantity'] ?? 0,
              price: (order['price'] as num?)?.toDouble(),
              status: 'pending',
              message: 'Order submitted via Zerodha Kite — awaiting confirmation',
            ));
          }
        }
      } else {
        for (final order in widget.orders) {
          results.add(OrderResult(
            symbol: order['symbol'] ?? order['tradingSymbol'] ?? '',
            transactionType: order['transactionType'] ?? 'BUY',
            quantity: order['quantity'] ?? 0,
            status: 'pending',
            message: 'Basket submitted to Zerodha Kite — check Kite app for status',
          ));
        }
      }

      try {
        await AqApiService.instance.syncZerodhaUserPortfolio(email: widget.email);
        debugPrint('[ExecutionStatus:Zerodha] user-portfolio sync success');
      } catch (e) {
        debugPrint('[ExecutionStatus:Zerodha] user-portfolio sync failed: $e');
      }

      final successCount = results.where((r) => r.isSuccess).length;
      final execStatus = successCount == results.length
          ? 'executed'
          : (successCount > 0 ? 'partial' : 'pending');
      try {
        await AqApiService.instance.updateSubscriberExecution(
          email: widget.email,
          modelName: _modelName,
          advisor: _advisor,
          broker: 'Zerodha',
          executionStatus: execStatus,
        );
      } catch (e) {
        debugPrint('[ExecutionStatus:Zerodha] updateSubscriberExecution failed: $e');
      }

      try {
        await AqApiService.instance.addToStatusCheckQueue(
          email: widget.email,
          modelName: _modelName,
          advisor: _advisor,
          broker: 'Zerodha',
        );
      } catch (e) {
        debugPrint('[ExecutionStatus:Zerodha] addToStatusCheckQueue failed: $e');
      }

      try {
        if (_modelId.isNotEmpty) {
          await OrderExecutionService.instance.updatePortfolioAfterExecution(
            modelId: _modelId,
            results: results,
            email: widget.email,
            broker: 'Zerodha',
          );
        }
      } catch (e) {
        debugPrint('[ExecutionStatus:Zerodha] Portfolio update failed: $e');
      }

      CacheService.instance.invalidatePortfolioData(widget.email, _modelName);

      if (mounted) {
        setState(() {
          _state = 'done';
          completedCount = widget.orders.length;
        });
        _scheduleStatusPoll();
      }
    } catch (e) {
      debugPrint('[ExecutionStatus:Zerodha] post-basket error: $e');
      if (mounted) {
        setState(() {
          _state = 'error';
          hasError = true;
          errorMessage = 'Failed to record Zerodha orders: $e';
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Retry failed orders
  // ---------------------------------------------------------------------------

  /// Show MPStatusModal for viewing/editing/confirming orders
  /// (matching alphab2b MPStatusModal.js)
  Future<void> _showMPStatusModal(String mode) async {
    final brokerName = OrderExecutionService.instance.lastUsedBrokerName.isNotEmpty
        ? OrderExecutionService.instance.lastUsedBrokerName
        : 'DummyBroker';

    // Build stock data from current results
    final stockData = results.map((r) => <String, dynamic>{
      'symbol': r.symbol,
      'transactionType': r.transactionType,
      'quantity': r.quantity,
      'filledShares': r.quantity,
      'averagePrice': r.price ?? 0,
      'averageEntryPrice': r.price ?? 0,
      'exchange': r.exchange ?? 'NSE',
      'orderStatus': r.status.toUpperCase(),
      'orderId': r.orderId ?? '',
    }).toList();

    final result = await MPStatusModal.show(
      context,
      email: widget.email,
      modelName: _modelName,
      advisor: _advisor,
      broker: brokerName,
      stockData: stockData,
      mode: mode,
    );

    if (result != null && mounted) {
      // Refresh the page if data was updated
      setState(() {});
    }
  }

  /// Parse order errors from an exception (matching alphab2b orderErrors/fundsRequired)
  void _parseOrderErrors(dynamic e) {
    try {
      final errStr = e.toString();
      // Try to extract JSON from error string
      final jsonStart = errStr.indexOf('{');
      final jsonEnd = errStr.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final jsonStr = errStr.substring(jsonStart, jsonEnd + 1);
        final data = jsonDecode(jsonStr);
        if (data['orderErrors'] is List) {
          _orderErrors = (data['orderErrors'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (data['fundsRequired'] != null) {
          _fundsRequired = (data['fundsRequired'] as num).toDouble();
        }
      }
    } catch (_) {
      // Not JSON-parseable, ignore
    }
  }

  /// Show detailed order error modal
  /// (matching alphab2b UpdateRebalanceModal.js showOrderErrorModal)
  Future<void> _showOrderErrorModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade600, size: 24),
                  const SizedBox(width: 10),
                  const Text("Order Errors",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(errorMessage!,
                  style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
              ),
            // Funds required
            if (_fundsRequired != null)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Funds Required",
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade800, fontWeight: FontWeight.w600)),
                          Text("\u20B9${NumberFormat('#,##,###.##').format(_fundsRequired)}",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.amber.shade900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // Order errors list
            if (_orderErrors.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  itemCount: _orderErrors.length,
                  itemBuilder: (ctx, i) {
                    final err = _orderErrors[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (err['transactionType'] ?? 'BUY').toString().toUpperCase() == 'BUY'
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (err['transactionType'] ?? 'BUY').toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: (err['transactionType'] ?? 'BUY').toString().toUpperCase() == 'BUY'
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  err['symbol']?.toString() ?? err['tradingSymbol']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                if (err['message'] != null || err['error'] != null)
                                  Text(
                                    (err['message'] ?? err['error']).toString(),
                                    style: TextStyle(fontSize: 11, color: Colors.red.shade700, height: 1.3),
                                  ),
                              ],
                            ),
                          ),
                          if (err['quantity'] != null)
                            Text("Qty: ${err['quantity']}",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text("No detailed error information available.",
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              ),
            // Close button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Close", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryFailed() async {
    final failedOrders = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.orders.length; i++) {
      if (i < results.length && results[i].isFailed) {
        failedOrders.add(widget.orders[i]);
      }
    }

    if (failedOrders.isEmpty) return;

    setState(() {
      _state = 'executing';
      completedCount = 0;
    });

    try {
      final retryResults = await OrderExecutionService.instance.executeOrders(
        orders: failedOrders,
        email: widget.email,
        modelName: _modelName,
        modelId: _modelId,
        advisor: _advisor,
        onOrderUpdate: (completed, total, latest) {
          if (!mounted) return;
          setState(() => completedCount = completed);
        },
      );

      for (final retry in retryResults) {
        final idx = results.indexWhere((r) => r.symbol == retry.symbol);
        if (idx >= 0) {
          results[idx] = retry;
        }
      }

      setState(() => _state = 'done');
    } on ZerodhaBasketRequiredException catch (e) {
      _zerodhaStockDetails = e.stockDetails;
      _setupZerodhaWebView(e.apiKey, e.basketItems);
    } catch (e) {
      setState(() {
        _state = 'error';
        errorMessage = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Computed getters
  // ---------------------------------------------------------------------------

  int get _successCount => results.where((r) => r.isSuccess).length;
  int get _failedCount => results.where((r) => r.isFailed).length;
  int get _pendingCount => results.where((r) => r.status == 'pending').length;

  bool get _hasPendingOrPartialOrders {
    if (results.isEmpty) return false;
    return results.any((r) =>
        r.status == 'partial' ||
        r.status == 'pending' ||
        (!r.isSuccess && !r.isFailed));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Zerodha WebView mode
    if (_state == 'zerodha_webview' && _zerodhaWebController != null) {
      return CustomScaffold(
        allowBackNavigation: true,
        displayActions: false,
        imageUrl: null,
        menu: "Place Orders — Zerodha",
        child: Column(
          children: [
            Expanded(
              child: WebViewWidget(controller: _zerodhaWebController!),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _handleZerodhaBasketSuccess,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      "I've completed placing orders",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return CustomScaffold(
      allowBackNavigation: !executing,
      displayActions: false,
      imageUrl: null,
      menu: "Trade Details",
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
              children: [
                // Subtitle row matching RGX "All Trade Details"
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    "All Trade Details",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),

                // Status section (icon circle + title + subtitle)
                _statusSection(),

                // Info row: Placed On | Status | X of Y Executed + progress bar
                if (!executing && _state == 'done') _infoRow(),

                // Cautionary listing alert
                if (_hasCautionaryListingFailures && !executing) _cautionaryListingAlert(),

                // Broker error message
                if (hasError && errorMessage != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(errorMessage!,
                            style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
                        if (isBrokerError) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final brokerName = OrderExecutionService.instance.lastUsedBrokerName;
                                final config = brokerName.isNotEmpty
                                    ? BrokerRegistry.getByName(brokerName)
                                    : null;

                                bool? result;
                                if (config != null && config.authType == BrokerAuthType.oauth) {
                                  result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BrokerAuthPage(
                                        email: widget.email,
                                        brokerName: config.name,
                                      ),
                                    ),
                                  );
                                } else if (config != null) {
                                  result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BrokerCredentialPage(
                                        email: widget.email,
                                        brokerConfig: config,
                                      ),
                                    ),
                                  );
                                } else {
                                  final connection = await BrokerSelectionPage.show(
                                    context,
                                    email: widget.email,
                                  );
                                  result = connection != null;
                                }
                                if (result == true && mounted) {
                                  CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
                                  setState(() {
                                    _state = 'executing';
                                    hasError = false;
                                    isBrokerError = false;
                                    errorMessage = null;
                                    results.clear();
                                    completedCount = 0;
                                  });
                                  _executeOrders();
                                }
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text("Reconnect Broker"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                // Order result cards (RGX style — full-width flat)
                const SizedBox(height: 8),
                ...results.map((r) => _orderResultCard(r)),

                // Skeleton cards while executing
                if (executing)
                  ...List.generate(
                    widget.orders.length - results.length,
                    (i) => _pendingOrderCard(
                        widget.orders[results.length + i]['symbol'] ?? ''),
                  ),
              ],
            ),
          ),
          if (!executing && _state == 'done') _bottomActions(),
          if (_state == 'error') _bottomActions(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status section — matches RGX icon circle + title + subtitle layout
  // ---------------------------------------------------------------------------

  Widget _statusSection() {
    if (executing) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF1A237E)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _state == 'recording'
                    ? "Recording Zerodha orders..."
                    : "Placing orders... ($completedCount/${widget.orders.length})",
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Error, no results
    if (hasError && results.isEmpty) {
      return _statusRow(
        icon: Icons.cancel,
        iconBgColor: const Color(0xFFEF4639),
        iconColor: Colors.white,
        title: "Execution Failed",
        subtitle: errorMessage ?? "Please try again or reconnect your broker.",
      );
    }

    // No orders sent
    if (results.isEmpty) {
      return _statusRow(
        icon: Icons.cancel,
        iconBgColor: const Color(0xFFEF4639),
        iconColor: Colors.white,
        title: "No Orders Placed",
        subtitle:
            "No trades were sent to the broker. This may be because the rebalance returned no trades. Please go back and try again.",
      );
    }

    // All confirmed success
    if (_failedCount == 0 && _successCount > 0 && _successCount == results.length) {
      return _statusRow(
        icon: Icons.check,
        iconBgColor: const Color(0xFF29A400),
        iconColor: Colors.white,
        title: "All Orders Placed Successfully",
        subtitle: "Please review the order details below.",
      );
    }

    // All failed
    if (_failedCount == results.length && results.isNotEmpty && !_hasCautionaryListingFailures) {
      final msg = results.first.message ?? '';
      return _statusRow(
        icon: Icons.cancel,
        iconBgColor: const Color(0xFFEF4639),
        iconColor: Colors.white,
        title: "Order Failed",
        subtitle: msg.isNotEmpty
            ? msg
            : "Your order could not be placed. Please contact your advisor.",
      );
    }

    // Partial — some placed, some not
    if (_successCount > 0 && _successCount < results.length && !_hasCautionaryListingFailures) {
      return _statusRow(
        icon: Icons.warning_rounded,
        iconBgColor: const Color(0xFFFFCD28),
        iconColor: Colors.black,
        title: "Some orders are not placed",
        subtitle:
            "Please review the order details below and contact your advisor for next steps.",
      );
    }

    // All pending / submitted
    return _statusRow(
      icon: Icons.hourglass_top_rounded,
      iconBgColor: Colors.blueGrey,
      iconColor: Colors.white,
      title: "Orders Submitted — Awaiting Confirmation",
      subtitle: "Check back in a moment for the updated status.",
    );
  }

  Widget _statusRow({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Info row — matches RGX: Placed On | Status | X of Y Executed + progress bar
  // ---------------------------------------------------------------------------

  Widget _infoRow() {
    final dateStr = DateFormat("d MMM yyyy").format(_executionDate);
    final total = results.length;
    final sc = _successCount;
    final statusText = sc == total
        ? 'Placed'
        : (sc > 0
            ? 'Partially Placed'
            : (_pendingCount == total ? 'Pending' : 'Failed'));
    final successFraction = total > 0 ? sc / total : 0.0;
    final failureFraction = total > 0 ? _failedCount / total : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          // Placed On
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Placed On",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(dateStr,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF464646))),
                ],
              ),
            ),
          ),
          Container(width: 0.5, height: 36, color: Colors.grey.shade400),
          // Status
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(statusText,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF464646))),
                ],
              ),
            ),
          ),
          Container(width: 0.5, height: 36, color: Colors.grey.shade400),
          // X of Y Executed + segmented progress bar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$sc of $total Executed",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Row(
                        children: [
                          if (sc > 0)
                            Flexible(
                              flex: (successFraction * 100).round(),
                              child: Container(color: const Color(0xFF338D72)),
                            ),
                          if (_failedCount > 0)
                            Flexible(
                              flex: (failureFraction * 100).round(),
                              child: Container(color: const Color(0xFFEF344A)),
                            ),
                          if (sc == 0 && _failedCount == 0)
                            Flexible(
                              flex: 100,
                              child: Container(color: Colors.grey.shade300),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Order result card — matches RGX style
  // ---------------------------------------------------------------------------

  Widget _orderResultCard(OrderResult result) {
    final isSuccess = result.isSuccess;
    final isPending = result.status == 'pending';
    final isFailed = result.isFailed;

    final bgColor = isSuccess
        ? const Color(0xFFB6FF92)  // green — confirmed placed
        : (isPending
            ? const Color(0xFFFFF9C4)  // light yellow — submitted, awaiting confirmation
            : const Color(0xFFFFEBEB)); // light red — failed / rejected

    final failureReason = result.message ?? '';
    final dateStr = DateFormat("d MMM yyyy").format(_executionDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Symbol + status badge + BUY/SELL pill
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      result.symbol,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                    ),
                    if (isFailed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (result.status.isNotEmpty ? result.status : 'REJECTED').toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFFDC2626), fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: result.transactionType.toUpperCase() == 'BUY'
                      ? const Color(0xFF29A400)
                      : const Color(0xFFFF2F2F),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  result.transactionType.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),

          // Row 2: Qty
          const SizedBox(height: 2),
          Row(
            children: [
              Text("Qty.",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w400)),
              Text(
                " ${result.quantity}",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF15171A)),
              ),
            ],
          ),

          // Row 3: Order type | Exchange + Date
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text("Ord. Type:",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(
                    " ${result.orderType ?? 'MARKET'} |",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF15171A)),
                  ),
                  Text(
                    " ${result.exchange ?? 'NSE'}",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF15171A)),
                  ),
                ],
              ),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 12, color: Color(0xFF4A4A4A)),
              ),
            ],
          ),

          // Rejection reason box (inline, matches RGX AlertCircle box)
          if (isFailed && failureReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFECACA)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      failureReason,
                      style: const TextStyle(
                          color: Color(0xFF991B1B), fontSize: 11, height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cautionary listing alert — matches RGX amber banner with stock badges
  // ---------------------------------------------------------------------------

  Widget _cautionaryListingAlert() {
    final stocks = _cautionaryStocks;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFCD34D)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7), shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Cautionary Listing Restriction",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 12, color: Color(0xFFB45309), height: 1.5),
              children: [
                TextSpan(text: "Your broker does not allow stocks under "),
                TextSpan(
                    text: "Exchange Cautionary Listing",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(
                    text:
                        " to be placed through the broker API. The following stocks need to be traded directly:"),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: stocks
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(16)),
                      child: Text(s.symbol,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF92400E))),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Color(0xFF2563EB)),
                    SizedBox(width: 6),
                    Text("What you need to do:",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E40AF))),
                  ],
                ),
                SizedBox(height: 4),
                Text("1. Open your broker app or web platform directly",
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF1D4ED8), height: 1.6)),
                Text("2. Place the order for the above stock(s) manually",
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF1D4ED8), height: 1.6)),
                Text(
                    "3. This is a default restriction by your broker for cautionary listed stocks",
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF1D4ED8), height: 1.6)),
              ],
            ),
          ),
          if (_successCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                border: Border.all(color: const Color(0xFFBBF7D0)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "$_successCount of ${results.length} order(s) were placed successfully. Only the above stock(s) require manual placement.",
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF166534)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Skeleton card while executing
  // ---------------------------------------------------------------------------

  Widget _pendingOrderCard(String symbol) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 12),
          Text(symbol,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
          const Spacer(),
          Text("Pending",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom actions
  // ---------------------------------------------------------------------------

  Widget _bottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -4))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Order Error Details button (matching alphab2b showOrderErrorModal)
            if (_orderErrors.isNotEmpty || _fundsRequired != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _showOrderErrorModal,
                    icon: const Icon(Icons.error_outline, size: 18),
                    label: const Text("View Error Details",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade400),
                      foregroundColor: Colors.red.shade600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            if (_failedCount > 0) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _retryFailed,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text("Retry $_failedCount Failed Orders",
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange)),
                  ),
                ),
              ),
              // Confirm Failed Orders button (matching alphab2b MPStatusModal)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () => _showMPStatusModal('confirmFailed'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text("Confirm Failed Orders Manually",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade400),
                      foregroundColor: Colors.red.shade600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
            // View/Edit Orders button (matching alphab2b MPStatusModal)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => _showMPStatusModal('viewing'),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text("View / Edit Orders",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.blue.shade400),
                    foregroundColor: Colors.blue.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            if (_hasPendingOrPartialOrders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PendingOrdersPage(
                            portfolio: widget.portfolio,
                            email: widget.email,
                            broker: OrderExecutionService.instance.lastUsedBrokerName
                                    .isNotEmpty
                                ? OrderExecutionService.instance.lastUsedBrokerName
                                : 'DummyBroker',
                            advisor: _advisor,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.hourglass_top, size: 18),
                    label: const Text("Check Order Status",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.amber.shade700),
                      foregroundColor: Colors.amber.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PortfolioHoldingsPage(
                        portfolio: widget.portfolio,
                        email: widget.email,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text("View Updated Portfolio",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1A237E)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Back to Portfolios",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A237E))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
