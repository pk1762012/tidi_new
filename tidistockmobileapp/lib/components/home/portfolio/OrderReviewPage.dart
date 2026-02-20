import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'DummyBrokerConfirmationPage.dart';
import 'ExecutionStatusPage.dart';

class OrderReviewPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;
  final String? brokerName;
  final List<Map<String, dynamic>> allocations;
  final double totalAmount;

  const OrderReviewPage({
    super.key,
    required this.portfolio,
    required this.email,
    this.brokerName,
    required this.allocations,
    required this.totalAmount,
  });

  @override
  State<OrderReviewPage> createState() => _OrderReviewPageState();
}

class _OrderReviewPageState extends State<OrderReviewPage> {
  bool _termsAccepted = false;
  final _currencyFormat = NumberFormat('#,##,###');

  void _placeOrders() {
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please accept the terms before proceeding.")),
      );
      return;
    }

    final isDummyBroker = widget.brokerName == 'DummyBroker';

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isDummyBroker
            ? DummyBrokerConfirmationPage(
                portfolio: widget.portfolio,
                email: widget.email,
                orders: widget.allocations,
                totalAmount: widget.totalAmount,
              )
            : ExecutionStatusPage(
                portfolio: widget.portfolio,
                email: widget.email,
                orders: widget.allocations,
                modelName: widget.portfolio.modelName,
                advisor: widget.portfolio.advisor,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Review Orders",
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // Portfolio header
                Container(
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
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text("${widget.allocations.length} orders",
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Total",
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text("\u20B9${_currencyFormat.format(widget.totalAmount.round())}",
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Orders table
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Orders to be placed",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),

                      // Header row
                      Row(
                        children: const [
                          Expanded(flex: 3, child: Text("Symbol",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey))),
                          Expanded(flex: 1, child: Text("Side",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                            textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text("Qty",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                            textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text("Type",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                            textAlign: TextAlign.right)),
                        ],
                      ),
                      const Divider(height: 16),

                      ...widget.allocations.map((order) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(order['symbol'],
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text(order['exchange'] ?? 'NSE',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                    color: order['transactionType'] == 'BUY' ? Colors.green : Colors.red,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text("${order['quantity']}",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(order['orderType'] ?? 'MARKET',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  Text(order['productType'] ?? 'CNC',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Disclaimer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text("Important",
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.brokerName == 'DummyBroker'
                            ? "Orders will be recorded in your portfolio. "
                              "You will need to execute them manually in your broker app. "
                              "Investment in securities is subject to market risks."
                            : "Orders will be placed at MARKET price via your connected broker. "
                              "Actual execution price may differ slightly from estimates. "
                              "Investment in securities is subject to market risks.",
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade800, height: 1.4),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Terms checkbox
                GestureDetector(
                  onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _termsAccepted,
                        onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            widget.brokerName == 'DummyBroker'
                                ? "I understand that these orders will be recorded in my portfolio "
                                  "and I will execute them manually in my broker app. "
                                  "I have reviewed the allocation and order details above."
                                : "I understand and accept that these orders will be executed "
                                  "via my connected broker account. I have reviewed the allocation "
                                  "and order details above.",
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom CTA
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _termsAccepted ? _placeOrders : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.brokerName == 'DummyBroker'
                        ? "Record ${widget.allocations.length} Orders"
                        : "Place ${widget.allocations.length} Orders",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
