import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/service/OrderExecutionService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerSelectionPage.dart';
import 'PortfolioHoldingsPage.dart';

class ExecutionStatusPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;
  final List<Map<String, dynamic>> orders;

  const ExecutionStatusPage({
    super.key,
    required this.portfolio,
    required this.email,
    required this.orders,
  });

  @override
  State<ExecutionStatusPage> createState() => _ExecutionStatusPageState();
}

class _ExecutionStatusPageState extends State<ExecutionStatusPage> {
  List<OrderResult> results = [];
  int completedCount = 0;
  bool executing = true;
  bool hasError = false;
  bool isBrokerError = false;
  String? errorMessage;

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
        onOrderUpdate: (completed, total, latest) {
          if (!mounted) return;
          setState(() {
            completedCount = completed;
            // Update or add result
            final idx = results.indexWhere((r) => r.symbol == latest.symbol);
            if (idx >= 0) {
              results[idx] = latest;
            } else {
              results.add(latest);
            }
          });
        },
      );
    } catch (e) {
      final errStr = e.toString();
      final brokerErr = errStr.contains('No connected broker') ||
          errStr.contains('broker credentials');
      setState(() {
        executing = false;
        hasError = true;
        isBrokerError = brokerErr;
        errorMessage = brokerErr
            ? 'No broker connected. Please connect a broker first.'
            : errStr;
      });
      return;
    }

    // Update portfolio database — separate try/catch so order results are
    // preserved even if the portfolio update fails.
    try {
      if (widget.portfolio.rebalanceHistory.isNotEmpty) {
        final latestRebalance = widget.portfolio.rebalanceHistory.last;
        if (latestRebalance.modelId != null) {
          await OrderExecutionService.instance.updatePortfolioAfterExecution(
            modelId: latestRebalance.modelId!,
            results: orderResults,
            email: widget.email,
            broker: OrderExecutionService.instance.lastUsedBrokerName,
          );
        }
      }
    } catch (e) {
      debugPrint('[ExecutionStatusPage] Portfolio update failed: $e');
      // Show warning but don't treat as fatal — orders were placed successfully
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

    // Invalidate portfolio caches so next views show fresh data
    CacheService.instance.invalidatePortfolioData(
      widget.email,
      widget.portfolio.modelName,
    );

    if (mounted) {
      setState(() {
        executing = false;
        results = orderResults;
      });
    }
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
      executing = true;
      completedCount = 0;
    });

    try {
      final retryResults = await OrderExecutionService.instance.executeOrders(
        orders: failedOrders,
        email: widget.email,
        onOrderUpdate: (completed, total, latest) {
          if (!mounted) return;
          setState(() => completedCount = completed);
        },
      );

      // Merge retry results
      for (final retry in retryResults) {
        final idx = results.indexWhere((r) => r.symbol == retry.symbol);
        if (idx >= 0) {
          results[idx] = retry;
        }
      }

      setState(() => executing = false);
    } catch (e) {
      setState(() {
        executing = false;
        errorMessage = e.toString();
      });
    }
  }

  int get _successCount => results.where((r) => r.isSuccess).length;
  int get _failedCount => results.where((r) => r.isFailed).length;

  @override
  Widget build(BuildContext context) {
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
                // Progress header
                _progressHeader(),
                const SizedBox(height: 20),

                // Summary card (shown when done)
                if (!executing) _summaryCard(),
                if (!executing) const SizedBox(height: 16),

                // Error message
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
                                    builder: (_) => BrokerSelectionPage(
                                      email: widget.email,
                                    ),
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

                // Order results
                ...results.map((r) => _orderResultCard(r)),

                // Placeholder for pending orders
                if (executing)
                  ...List.generate(
                    widget.orders.length - results.length,
                    (i) => _pendingOrderCard(
                      widget.orders[results.length + i]['symbol'] ?? ''),
                  ),
              ],
            ),
          ),

          // Bottom actions
          if (!executing) _bottomActions(),
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
            Text("Placing orders... ($completedCount/${widget.orders.length})",
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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
            // View Updated Portfolio button
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
            // Back to Portfolios button
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
