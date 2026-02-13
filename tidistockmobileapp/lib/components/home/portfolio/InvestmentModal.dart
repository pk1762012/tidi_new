import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_stock.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'OrderReviewPage.dart';

class InvestmentModal extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;

  const InvestmentModal({
    super.key,
    required this.portfolio,
    required this.email,
  });

  @override
  State<InvestmentModal> createState() => _InvestmentModalState();
}

class _InvestmentModalState extends State<InvestmentModal> {
  final TextEditingController _amountController = TextEditingController();
  final _currencyFormat = NumberFormat('#,##,###');
  List<_AllocationItem> allocations = [];
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.portfolio.minInvestment.toString();
    _calculateAllocation();
    _amountController.addListener(_calculateAllocation);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _calculateAllocation() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() {
        allocations = [];
        errorMessage = null;
      });
      return;
    }

    if (amount < widget.portfolio.minInvestment) {
      setState(() {
        errorMessage = "Minimum investment is \u20B9${_currencyFormat.format(widget.portfolio.minInvestment)}";
        allocations = [];
      });
      return;
    }

    final stocks = widget.portfolio.stocks;
    if (stocks.isEmpty) {
      setState(() {
        errorMessage = "No stocks in this portfolio.";
        allocations = [];
      });
      return;
    }

    final totalWeight = stocks.fold(0.0, (sum, s) => sum + s.weight);
    if (totalWeight <= 0) return;

    final items = <_AllocationItem>[];

    for (final stock in stocks) {
      final weightPct = stock.weight / totalWeight;
      final allocatedAmt = amount * weightPct;
      final price = stock.price ?? 0;
      final qty = price > 0 ? (allocatedAmt / price).floor() : 0;
      final estCost = qty * price;

      items.add(_AllocationItem(
        stock: stock,
        weightPercent: weightPct * 100,
        allocatedAmount: allocatedAmt,
        estimatedQty: qty,
        estimatedPrice: price,
        estimatedCost: estCost,
      ));
    }

    setState(() {
      allocations = items;
      errorMessage = null;
    });
  }

  double get _totalEstimatedCost =>
      allocations.fold(0.0, (sum, a) => sum + a.estimatedCost);

  int get _totalStocksWithQty =>
      allocations.where((a) => a.estimatedQty > 0).length;

  void _proceedToReview() {
    final validAllocations = allocations.where((a) => a.estimatedQty > 0).toList();
    if (validAllocations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No stocks can be purchased with this amount.")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderReviewPage(
          portfolio: widget.portfolio,
          email: widget.email,
          allocations: validAllocations.map((a) => {
            'symbol': a.stock.symbol,
            'exchange': a.stock.exchange ?? 'NSE',
            'quantity': a.estimatedQty,
            'price': a.estimatedPrice,
            'transactionType': 'BUY',
            'productType': 'CNC',
            'orderType': 'MARKET',
            'weight': a.weightPercent,
          }).toList(),
          totalAmount: _totalEstimatedCost,
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
      menu: "Invest",
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // Portfolio name
                Text(widget.portfolio.modelName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text("Min: \u20B9${_currencyFormat.format(widget.portfolio.minInvestment)}",
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(height: 20),

                // Amount input
                _amountInput(),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(errorMessage!,
                      style: TextStyle(fontSize: 13, color: Colors.red.shade400)),
                  ),
                const SizedBox(height: 20),

                // Allocation preview
                if (allocations.isNotEmpty) ...[
                  _allocationSummary(),
                  const SizedBox(height: 16),
                  _allocationTable(),
                ],
              ],
            ),
          ),
          _bottomCta(),
        ],
      ),
    );
  }

  Widget _amountInput() {
    return Container(
      padding: const EdgeInsets.all(18),
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
          const Text("Investment Amount",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: "\u20B9 ",
              prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          // Quick amount buttons
          Row(
            children: [25000, 50000, 100000, 500000]
                .map((amt) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: OutlinedButton(
                      onPressed: () => _amountController.text = amt.toString(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text("${amt >= 100000 ? '${amt ~/ 100000}L' : '${amt ~/ 1000}K'}",
                        style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _allocationSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem("Est. Cost", "\u20B9${_currencyFormat.format(_totalEstimatedCost.round())}"),
          Container(width: 1, height: 30, color: Colors.blue.shade200),
          _summaryItem("Stocks", "$_totalStocksWithQty / ${allocations.length}"),
          Container(width: 1, height: 30, color: Colors.blue.shade200),
          _summaryItem("Unused",
              "\u20B9${_currencyFormat.format((double.tryParse(_amountController.text) ?? 0) - _totalEstimatedCost > 0 ? ((double.tryParse(_amountController.text) ?? 0) - _totalEstimatedCost).round() : 0)}"),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _allocationTable() {
    return Container(
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
          const Text("Allocation Preview",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // Header
          Row(
            children: const [
              Expanded(flex: 3, child: Text("Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey))),
              Expanded(flex: 2, child: Text("Wt%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey), textAlign: TextAlign.center)),
              Expanded(flex: 1, child: Text("Qty", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey), textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text("Est. Cost", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey), textAlign: TextAlign.right)),
            ],
          ),
          const Divider(height: 16),
          ...allocations.map((a) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(a.stock.symbol,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: a.estimatedQty > 0 ? Colors.black87 : Colors.grey.shade400))),
                Expanded(flex: 2, child: Text("${a.weightPercent.toStringAsFixed(1)}%",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text("${a.estimatedQty}",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: a.estimatedQty > 0 ? Colors.black87 : Colors.red.shade300),
                  textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(
                  a.estimatedQty > 0 ? "\u20B9${_currencyFormat.format(a.estimatedCost.round())}" : "—",
                  style: TextStyle(fontSize: 13, color: a.estimatedQty > 0 ? Colors.black87 : Colors.grey.shade400),
                  textAlign: TextAlign.right)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _bottomCta() {
    final hasValid = allocations.any((a) => a.estimatedQty > 0);
    return Container(
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
            onPressed: hasValid && errorMessage == null ? _proceedToReview : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text("Review & Invest",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _AllocationItem {
  final PortfolioStock stock;
  final double weightPercent;
  final double allocatedAmount;
  final int estimatedQty;
  final double estimatedPrice;
  final double estimatedCost;

  _AllocationItem({
    required this.stock,
    required this.weightPercent,
    required this.allocatedAmount,
    required this.estimatedQty,
    required this.estimatedPrice,
    required this.estimatedCost,
  });
}
