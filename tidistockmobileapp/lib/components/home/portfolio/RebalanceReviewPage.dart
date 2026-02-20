import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_stock.dart';
import 'package:tidistockmobileapp/models/rebalance_entry.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'ExecutionStatusPage.dart';

class RebalanceReviewPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;

  const RebalanceReviewPage({
    super.key,
    required this.portfolio,
    required this.email,
  });

  @override
  State<RebalanceReviewPage> createState() => _RebalanceReviewPageState();
}

class _RebalanceReviewPageState extends State<RebalanceReviewPage> {
  List<_RebalanceAction> actions = [];
  bool loading = true;
  bool termsAccepted = false;
  RebalanceHistoryEntry? latestRebalance;
  RebalanceHistoryEntry? previousRebalance;

  // Execution status tracking
  bool _alreadyExecuted = false;
  bool _partiallyExecuted = false;
  String? _researchReportLink;

  @override
  void initState() {
    super.initState();
    _computeRebalanceActions();
  }

  Future<void> _computeRebalanceActions() async {
    final history = widget.portfolio.rebalanceHistory;
    if (history.isEmpty) {
      setState(() => loading = false);
      return;
    }

    latestRebalance = history.last;
    previousRebalance = history.length > 1 ? history[history.length - 2] : null;

    // Check execution status for the latest rebalance
    final execForUser = latestRebalance!.getExecutionForUser(widget.email);
    if (execForUser != null) {
      if (execForUser.isExecuted) {
        _alreadyExecuted = true;
      } else if (execForUser.status.toLowerCase() == 'partial') {
        _partiallyExecuted = true;
      }
    }

    // Check for research report link
    _researchReportLink = latestRebalance!.researchReportLink;

    // Build map of previous holdings
    final Map<String, PortfolioStock> previousStocks = {};
    if (previousRebalance != null) {
      for (final s in previousRebalance!.adviceEntries) {
        previousStocks[s.symbol] = s;
      }
    }

    // Also try to get user's actual current holdings
    Map<String, double> currentHoldings = {};
    try {
      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: widget.email,
        modelName: widget.portfolio.modelName,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final subData = data['data'];
        if (subData != null) {
          final userNetPf = subData['user_net_pf_model'] ?? [];
          if (userNetPf is List && userNetPf.isNotEmpty) {
            final latest = userNetPf.last;
            List<dynamic> stockList = [];
            if (latest is List) stockList = latest;
            if (latest is Map) stockList = latest['stocks'] ?? latest['holdings'] ?? [];
            for (final s in stockList) {
              if (s is Map<String, dynamic>) {
                final symbol = s['symbol'] ?? s['tradingSymbol'] ?? '';
                final qty = (s['quantity'] ?? s['qty'] ?? 0).toDouble();
                if (symbol.isNotEmpty) currentHoldings[symbol] = qty;
              }
            }
          }
        }
      }
    } catch (_) {}

    // Compute actions
    final List<_RebalanceAction> computed = [];
    final allSymbols = <String>{};

    // Add all symbols from latest rebalance
    for (final s in latestRebalance!.adviceEntries) {
      allSymbols.add(s.symbol);
    }
    // Add all symbols from previous (to detect removals)
    allSymbols.addAll(previousStocks.keys);
    allSymbols.addAll(currentHoldings.keys);

    final latestMap = <String, PortfolioStock>{};
    for (final s in latestRebalance!.adviceEntries) {
      latestMap[s.symbol] = s;
    }

    for (final symbol in allSymbols) {
      final inLatest = latestMap.containsKey(symbol);
      final inPrevious = previousStocks.containsKey(symbol) || currentHoldings.containsKey(symbol);
      final currentQty = currentHoldings[symbol] ?? 0;

      if (inLatest && !inPrevious) {
        // New stock to BUY
        computed.add(_RebalanceAction(
          symbol: symbol,
          exchange: latestMap[symbol]!.exchange ?? 'NSE',
          type: _ActionType.buy,
          newWeight: latestMap[symbol]!.weight,
          oldWeight: 0,
          currentQty: 0,
          price: latestMap[symbol]!.price ?? 0,
        ));
      } else if (!inLatest && inPrevious) {
        // Stock removed — SELL
        computed.add(_RebalanceAction(
          symbol: symbol,
          exchange: previousStocks[symbol]?.exchange ?? 'NSE',
          type: _ActionType.sell,
          newWeight: 0,
          oldWeight: previousStocks[symbol]?.weight ?? 0,
          currentQty: currentQty,
          price: previousStocks[symbol]?.price ?? 0,
        ));
      } else if (inLatest && inPrevious) {
        // Existing stock — check weight change
        final newWeight = latestMap[symbol]!.weight;
        final oldWeight = previousStocks[symbol]?.weight ?? 0;
        final weightDiff = newWeight - oldWeight;

        _ActionType type;
        if (weightDiff > 0.01) {
          type = _ActionType.buy;
        } else if (weightDiff < -0.01) {
          type = _ActionType.sell;
        } else {
          type = _ActionType.hold;
        }

        computed.add(_RebalanceAction(
          symbol: symbol,
          exchange: latestMap[symbol]!.exchange ?? 'NSE',
          type: type,
          newWeight: newWeight,
          oldWeight: oldWeight,
          currentQty: currentQty,
          price: latestMap[symbol]!.price ?? 0,
        ));
      }
    }

    // Sort: sells first, then buys, then holds
    computed.sort((a, b) {
      final order = {_ActionType.sell: 0, _ActionType.buy: 1, _ActionType.hold: 2};
      return (order[a.type] ?? 3).compareTo(order[b.type] ?? 3);
    });

    setState(() {
      actions = computed;
      loading = false;
    });
  }

  void _executeRebalance() {
    if (!termsAccepted) return;

    // Generate orders: sells first, then buys
    final orders = <Map<String, dynamic>>[];

    for (final action in actions) {
      if (action.type == _ActionType.hold) continue;

      orders.add({
        'symbol': action.symbol,
        'exchange': action.exchange,
        'transactionType': action.type == _ActionType.buy ? 'BUY' : 'SELL',
        'quantity': action.currentQty > 0 ? action.currentQty.toInt() : 1,
        'orderType': 'MARKET',
        'productType': 'CNC',
        'price': action.price,
      });
    }

    if (orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No trades required for this rebalance.")),
      );
      return;
    }

    // Resolve modelId from latest rebalance history
    String? modelId;
    if (widget.portfolio.rebalanceHistory.isNotEmpty) {
      modelId = widget.portfolio.rebalanceHistory.last.modelId;
    }
    modelId ??= widget.portfolio.id;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ExecutionStatusPage(
          portfolio: widget.portfolio,
          email: widget.email,
          orders: orders,
          modelId: modelId,
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
      menu: "Rebalance",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      // Rebalance header
                      _rebalanceHeader(),

                      // Execution status badges
                      if (_alreadyExecuted)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "This rebalance has already been executed.",
                                  style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_partiallyExecuted)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded, color: Colors.amber.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Partially executed. You can resume execution below.",
                                  style: TextStyle(fontSize: 13, color: Colors.amber.shade800, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Research report link
                      if (_researchReportLink != null && _researchReportLink!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: InkWell(
                            onTap: () {
                              // Open research report — could use url_launcher
                              debugPrint('[RebalanceReview] Research report: $_researchReportLink');
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.description_outlined, color: Colors.blue.shade700, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "View Research Report",
                                      style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Icon(Icons.open_in_new, color: Colors.blue.shade400, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Summary
                      _summary(),
                      const SizedBox(height: 16),

                      // Actions list
                      _actionsSection(),
                      const SizedBox(height: 16),

                      // Rebalance history
                      _historySection(),
                      const SizedBox(height: 16),

                      // Terms
                      GestureDetector(
                        onTap: () => setState(() => termsAccepted = !termsAccepted),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: termsAccepted,
                              onChanged: (v) => setState(() => termsAccepted = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  "I have reviewed the rebalance changes and authorize "
                                  "the execution of these trades via my connected broker.",
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                        blurRadius: 10, offset: const Offset(0, -4))],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: termsAccepted ? _executeRebalance : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          _alreadyExecuted
                              ? "Already Executed"
                              : _partiallyExecuted
                                  ? "Resume Execution"
                                  : "Accept & Execute Rebalance",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _rebalanceHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, color: Colors.orange.shade700, size: 22),
              const SizedBox(width: 10),
              Text(widget.portfolio.modelName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800)),
            ],
          ),
          if (latestRebalance?.rebalanceDate != null) ...[
            const SizedBox(height: 8),
            Text(
              "Rebalance date: ${DateFormat("dd MMM yyyy").format(latestRebalance!.rebalanceDate!)}",
              style: TextStyle(fontSize: 13, color: Colors.orange.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary() {
    final buyCount = actions.where((a) => a.type == _ActionType.buy).length;
    final sellCount = actions.where((a) => a.type == _ActionType.sell).length;
    final holdCount = actions.where((a) => a.type == _ActionType.hold).length;

    return Row(
      children: [
        _summaryChip("BUY", buyCount, Colors.green),
        const SizedBox(width: 10),
        _summaryChip("SELL", sellCount, Colors.red),
        const SizedBox(width: 10),
        _summaryChip("HOLD", holdCount, Colors.grey),
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

  Widget _actionsSection() {
    if (actions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("No rebalance actions available.",
            style: TextStyle(fontSize: 15, color: Colors.grey)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Proposed Changes",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...actions.map((action) => _actionRow(action)),
        ],
      ),
    );
  }

  Widget _actionRow(_RebalanceAction action) {
    Color color;
    IconData icon;
    String label;
    switch (action.type) {
      case _ActionType.buy:
        color = Colors.green;
        icon = Icons.add_circle;
        label = "BUY";
        break;
      case _ActionType.sell:
        color = Colors.red;
        icon = Icons.remove_circle;
        label = "SELL";
        break;
      case _ActionType.hold:
        color = Colors.grey;
        icon = Icons.horizontal_rule;
        label = "HOLD";
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.symbol,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text("${action.exchange} | ${action.oldWeight.toStringAsFixed(1)} → ${action.newWeight.toStringAsFixed(1)} wt",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _historySection() {
    final history = widget.portfolio.rebalanceHistory;
    if (history.length <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Rebalance History",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...history.reversed.take(5).map((entry) {
            final exec = entry.getExecutionForUser(widget.email);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: exec?.isExecuted == true ? Colors.green : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.rebalanceDate != null
                          ? DateFormat("dd MMM yyyy").format(entry.rebalanceDate!)
                          : "Unknown date",
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    "${entry.adviceEntries.length} stocks",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    exec?.status ?? "—",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: exec?.isExecuted == true ? Colors.green : Colors.grey,
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
}

enum _ActionType { buy, sell, hold }

class _RebalanceAction {
  final String symbol;
  final String exchange;
  final _ActionType type;
  final double newWeight;
  final double oldWeight;
  final double currentQty;
  final double price;

  _RebalanceAction({
    required this.symbol,
    required this.exchange,
    required this.type,
    required this.newWeight,
    required this.oldWeight,
    required this.currentQty,
    required this.price,
  });
}
