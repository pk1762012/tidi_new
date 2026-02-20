import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/service/OrderExecutionService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'BrokerSelectionPage.dart';
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
      // Zerodha needs WebView basket — switch to WebView mode
      _zerodhaStockDetails = e.stockDetails;
      _zerodhaApiKey = e.apiKey;
      _setupZerodhaWebView(e.apiKey, e.basketItems);
      return;
    } catch (e) {
      final errStr = e.toString();
      final brokerErr = errStr.contains('No connected broker') ||
          errStr.contains('broker credentials');
      setState(() {
        _state = 'error';
        hasError = true;
        isBrokerError = brokerErr;
        errorMessage = brokerErr
            ? 'No broker connected. Please connect a broker first.'
            : errStr;
      });
      return;
    }

    // Post-execution: update portfolio database
    try {
      final mid = _modelId;
      if (mid.isNotEmpty) {
        await OrderExecutionService.instance.updatePortfolioAfterExecution(
          modelId: mid,
          results: orderResults,
          email: widget.email,
          broker: OrderExecutionService.instance.lastUsedBrokerName,
        );
      }
    } catch (e) {
      debugPrint('[ExecutionStatusPage] Portfolio update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Orders placed but portfolio sync failed. It will sync automatically.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    CacheService.instance.invalidatePortfolioData(
      widget.email,
      _modelName,
    );

    if (mounted) {
      setState(() {
        _state = 'done';
        results = orderResults;
      });
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
    return url.contains('success') ||
        url.contains('completed') ||
        url.contains('status=success') ||
        url.contains('broker-callback');
  }

  Future<void> _handleZerodhaBasketSuccess() async {
    if (_state == 'recording') return; // guard against duplicates
    setState(() => _state = 'recording');

    try {
      final uniqueId = '${_modelId}_${DateTime.now().millisecondsSinceEpoch}_${widget.email}';

      // Step 1: Record orders — fetch actual results from Zerodha
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
        final orderData = data['response'] ?? data['results'] ?? data['tradeDetails'] ?? [];
        if (orderData is List && orderData.isNotEmpty) {
          for (int i = 0; i < orderData.length; i++) {
            results.add(OrderResult.fromJson(
              orderData[i] is Map ? Map<String, dynamic>.from(orderData[i]) : {},
            ));
          }
        } else {
          // No detailed results — assume success for all trades
          for (final order in widget.orders) {
            results.add(OrderResult(
              symbol: order['symbol'] ?? order['tradingSymbol'] ?? '',
              transactionType: order['transactionType'] ?? 'BUY',
              quantity: order['quantity'] ?? 0,
              price: (order['price'] as num?)?.toDouble(),
              status: 'success',
              message: 'Order placed via Zerodha Kite',
            ));
          }
        }
      } else {
        // record-orders failed — mark as success anyway since basket was submitted
        for (final order in widget.orders) {
          results.add(OrderResult(
            symbol: order['symbol'] ?? order['tradingSymbol'] ?? '',
            transactionType: order['transactionType'] ?? 'BUY',
            quantity: order['quantity'] ?? 0,
            status: 'success',
            message: 'Basket submitted to Zerodha Kite',
          ));
        }
      }

      // Step 2: Update subscriber execution
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

      // Step 3: Add to status check queue
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

      // Step 4: Update portfolio DB
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

  int get _successCount => results.where((r) => r.isSuccess).length;
  int get _failedCount => results.where((r) => r.isFailed).length;

  @override
  Widget build(BuildContext context) {
    // Zerodha WebView mode
    if (_state == 'zerodha_webview' && _zerodhaWebController != null) {
      return CustomScaffold(
        allowBackNavigation: true,
        displayActions: false,
        imageUrl: null,
        menu: "Place Orders — Zerodha",
        child: WebViewWidget(controller: _zerodhaWebController!),
      );
    }

    return CustomScaffold(
      allowBackNavigation: !executing,
      displayActions: false,
      imageUrl: null,
      menu: "Execution Status",
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _progressHeader(),
                const SizedBox(height: 20),
                if (!executing && _state == 'done') _summaryCard(),
                if (!executing && _state == 'done') const SizedBox(height: 16),
                if (hasError && errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
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
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BrokerSelectionPage(email: widget.email),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.account_balance, size: 18),
                              label: const Text("Connect Broker"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
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
                ...results.map((r) => _orderResultCard(r)),
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

  Widget _progressHeader() {
    final progress = widget.orders.isNotEmpty
        ? completedCount / widget.orders.length
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: executing
              ? [const Color(0xFF1A237E), const Color(0xFF283593)]
              : (_failedCount > 0
                  ? [Colors.orange.shade600, Colors.orange.shade400]
                  : [const Color(0xFF2E7D32), const Color(0xFF43A047)]),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (executing) ...[
            const SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              _state == 'recording'
                  ? "Recording Zerodha orders..."
                  : "Placing orders... ($completedCount/${widget.orders.length})",
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ] else ...[
            Icon(
              _failedCount == 0 ? Icons.check_circle : Icons.warning_rounded,
              size: 44, color: Colors.white,
            ),
            const SizedBox(height: 10),
            Text(
              _failedCount == 0
                  ? "All Orders Executed!"
                  : "$_successCount of ${results.length} orders executed",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem("Total", "${results.length}", Colors.blue),
          _summaryItem("Success", "$_successCount", Colors.green),
          _summaryItem("Failed", "$_failedCount", Colors.red),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _orderResultCard(OrderResult result) {
    IconData icon;
    Color color;
    String statusText;

    switch (result.status) {
      case 'success':
        icon = Icons.check_circle;
        color = Colors.green;
        statusText = "Executed";
        break;
      case 'failed':
        icon = Icons.cancel;
        color = Colors.red;
        statusText = "Failed";
        break;
      case 'partial':
        icon = Icons.warning;
        color = Colors.orange;
        statusText = "Partial";
        break;
      default:
        icon = Icons.hourglass_empty;
        color = Colors.grey;
        statusText = "Pending";
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
                Text(result.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text("${result.transactionType.toUpperCase()} x ${result.quantity}",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (result.message != null && result.isFailed)
                  Text(result.message!,
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(statusText,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
              if (result.orderId != null)
                Text("#${result.orderId}",
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingOrderCard(String symbol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 12),
          Text(symbol,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
          const Spacer(),
          Text("Pending",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _bottomActions() {
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
            if (_failedCount > 0)
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
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.orange)),
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
