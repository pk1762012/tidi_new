import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/OrderExecutionService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

/// Confirmation page for the DummyBroker flow.
///
/// Instead of placing orders through a connected broker, this page:
///   1. Shows the user the list of trades they need to execute manually
///   2. On confirmation, records the trades in ccxt-india via
///      OrderExecutionService.executeDummyBrokerOrders()
///   3. Shows execution status
///
/// Reference: prod_alphaquark_github DummyBrokerHoldingConfirmation.js
class DummyBrokerConfirmationPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;
  final List<Map<String, dynamic>> orders;
  final double totalAmount;

  const DummyBrokerConfirmationPage({
    super.key,
    required this.portfolio,
    required this.email,
    required this.orders,
    required this.totalAmount,
  });

  @override
  State<DummyBrokerConfirmationPage> createState() =>
      _DummyBrokerConfirmationPageState();
}

class _DummyBrokerConfirmationPageState
    extends State<DummyBrokerConfirmationPage> {
  final _currencyFormat = NumberFormat('#,##,###');
  bool _confirming = false;
  bool _confirmed = false;
  List<OrderResult> _results = [];
  String? _errorMessage;

  Future<void> _confirmExecution() async {
    setState(() {
      _confirming = true;
      _errorMessage = null;
    });

    try {
      // Determine modelId from the latest rebalance or portfolio id
      String modelId = widget.portfolio.id;
      if (widget.portfolio.rebalanceHistory.isNotEmpty) {
        final latestRebalance = widget.portfolio.rebalanceHistory.last;
        if (latestRebalance.modelId != null) {
          modelId = latestRebalance.modelId!;
        }
      }

      final results =
          await OrderExecutionService.instance.executeDummyBrokerOrders(
        orders: widget.orders,
        email: widget.email,
        modelName: widget.portfolio.modelName,
        modelId: modelId,
        advisor: widget.portfolio.advisor,
        onOrderUpdate: (completed, total, latest) {
          if (!mounted) return;
          setState(() => _results = [..._results, latest]);
        },
      );

      if (mounted) {
        setState(() {
          _confirming = false;
          _confirmed = true;
          _results = results;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _confirming = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  int get _successCount => _results.where((r) => r.isSuccess).length;
  int get _failedCount => _results.where((r) => r.isFailed).length;

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: !_confirming,
      displayActions: false,
      imageUrl: null,
      menu: "Confirm Orders",
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // Info banner
                _infoBanner(),
                const SizedBox(height: 16),

                // Portfolio header
                _portfolioHeader(),
                const SizedBox(height: 16),

                // Orders list
                _ordersSection(),
                const SizedBox(height: 16),

                // Error message
                if (_errorMessage != null) _errorCard(),

                // Results (after confirmation)
                if (_confirmed) ...[
                  _resultsSummary(),
                  const SizedBox(height: 16),
                  _instructionsCard(),
                ],
              ],
            ),
          ),
          _bottomActions(),
        ],
      ),
    );
  }

  Widget _infoBanner() {
    if (_confirmed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Orders Recorded",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800)),
                  const SizedBox(height: 4),
                  Text(
                      "Please execute these orders manually in your broker app.",
                      style: TextStyle(
                          fontSize: 13, color: Colors.green.shade700)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Manual Execution Mode",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade800)),
                const SizedBox(height: 4),
                Text(
                    "No broker is connected. Orders will be recorded in your portfolio. "
                    "You need to execute them manually in your broker app.",
                    style:
                        TextStyle(fontSize: 13, color: Colors.blue.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _portfolioHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.portfolio.modelName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text("${widget.orders.length} orders",
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("Total",
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                  "\u20B9${_currencyFormat.format(widget.totalAmount.round())}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ordersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              _confirmed
                  ? "Orders to execute in your broker"
                  : "Orders to be recorded",
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                  flex: 3,
                  child: Text("Symbol",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey))),
              Expanded(
                  flex: 1,
                  child: Text("Side",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey),
                      textAlign: TextAlign.center)),
              Expanded(
                  flex: 1,
                  child: Text("Qty",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey),
                      textAlign: TextAlign.center)),
              Expanded(
                  flex: 2,
                  child: Text("Status",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey),
                      textAlign: TextAlign.right)),
            ],
          ),
          const Divider(height: 16),
          ...widget.orders.asMap().entries.map((entry) {
            final i = entry.key;
            final order = entry.value;
            final result = i < _results.length ? _results[i] : null;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order['symbol'],
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(order['exchange'] ?? 'NSE',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: order['transactionType'] == 'BUY'
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        order['transactionType'],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: order['transactionType'] == 'BUY'
                              ? Colors.green
                              : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text("${order['quantity']}",
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 2,
                    child: result != null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                result.isSuccess
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 16,
                                color: result.isSuccess
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                result.isSuccess ? "Recorded" : "Failed",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: result.isSuccess
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _confirming ? "Recording..." : "Pending",
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500),
                            textAlign: TextAlign.right,
                          ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(_errorMessage!,
          style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
    );
  }

  Widget _resultsSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem("Total", "${_results.length}", Colors.blue),
          _summaryItem("Recorded", "$_successCount", Colors.green),
          _summaryItem("Failed", "$_failedCount", Colors.red),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _instructionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 20, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Text("Next Steps",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber.shade900)),
            ],
          ),
          const SizedBox(height: 10),
          _instructionStep("1", "Open your broker app (Zerodha, Groww, etc.)"),
          _instructionStep("2",
              "Place each order listed above with the exact quantities"),
          _instructionStep("3",
              "Your portfolio will automatically sync within a few hours"),
        ],
      ),
    );
  }

  Widget _instructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.amber.shade900,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _bottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _confirmed
            ? SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context)
                        .popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text("Done",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              )
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _confirming ? null : _confirmExecution,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _confirming
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          "Confirm & Record Orders",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                ),
              ),
      ),
    );
  }
}
