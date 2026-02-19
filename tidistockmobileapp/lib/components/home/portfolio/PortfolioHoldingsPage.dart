import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_holding.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/DataRepository.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'RebalanceHistoryPage.dart';
import 'RebalanceReviewPage.dart';

class PortfolioHoldingsPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;

  const PortfolioHoldingsPage({
    super.key,
    required this.portfolio,
    required this.email,
  });

  @override
  State<PortfolioHoldingsPage> createState() => _PortfolioHoldingsPageState();
}

class _PortfolioHoldingsPageState extends State<PortfolioHoldingsPage> {
  List<PortfolioHolding> holdings = [];
  bool loading = true;
  String? selectedBroker;
  List<String> availableBrokers = ['ALL'];
  double totalInvested = 0;
  double totalCurrent = 0;
  final _currencyFormat = NumberFormat('#,##,###');

  // Rebalance
  bool hasPendingRebalance = false;

  @override
  void initState() {
    super.initState();
    _fetchHoldings();
    _checkPendingRebalance();
  }

  Future<void> _fetchHoldings() async {
    try {
      // Fetch available brokers for this model
      final brokersResp = await AqApiService.instance.getAvailableBrokers(
        email: widget.email,
        modelName: widget.portfolio.modelName,
      );

      if (brokersResp.statusCode == 200) {
        final bData = await DataRepository.parseJsonMap(brokersResp.body);
        final brokerList = bData['data']?['brokers'] ?? [];
        if (brokerList is List && brokerList.isNotEmpty) {
          availableBrokers = ['ALL', ...brokerList.map((b) => b['broker'].toString())];
        }
      }

      // Fetch subscription data
      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: widget.email,
        modelName: widget.portfolio.modelName,
        userBroker: selectedBroker == 'ALL' ? null : selectedBroker,
      );

      if (response.statusCode == 200 && mounted) {
        final data = await DataRepository.parseJsonMap(response.body);
        final subData = data['data'];

        if (subData != null) {
          _parseHoldings(subData);
        }
      }
      if (mounted) setState(() => loading = false);
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _parseHoldings(Map<String, dynamic> subData) {
    final userNetPf = subData['user_net_pf_model'] ?? [];
    final List<PortfolioHolding> parsed = [];

    if (userNetPf is List && userNetPf.isNotEmpty) {
      // The latest entry contains current holdings
      final latest = userNetPf.last;
      List<dynamic> stockList = [];

      if (latest is List) {
        stockList = latest;
      } else if (latest is Map) {
        stockList = latest['stocks'] ?? latest['holdings'] ?? [];
      }

      for (final stock in stockList) {
        if (stock is Map<String, dynamic>) {
          parsed.add(PortfolioHolding.fromJson(stock));
        }
      }
    }

    // Calculate totals
    double invested = 0;
    double current = 0;
    for (final h in parsed) {
      invested += h.investedValue;
      current += h.currentValue;
    }

    setState(() {
      holdings = parsed;
      totalInvested = invested;
      totalCurrent = current;
    });
  }

  void _checkPendingRebalance() {
    if (widget.portfolio.rebalanceHistory.isNotEmpty) {
      final latest = widget.portfolio.rebalanceHistory.last;
      setState(() {
        hasPendingRebalance = latest.hasPendingExecution(widget.email);
      });
    }
  }

  double get _totalPnl => totalCurrent - totalInvested;
  double get _totalPnlPct =>
      totalInvested > 0 ? (_totalPnl / totalInvested * 100) : 0;

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => loading = true);
                await _fetchHoldings();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),

                  // Last rebalance summary
                  if (widget.portfolio.rebalanceHistory.isNotEmpty)
                    _lastRebalanceSummary(),

                  // Rebalance notification
                  if (hasPendingRebalance) _rebalanceBanner(),

                  // Broker selector
                  if (availableBrokers.length > 2) _brokerSelector(),

                  const SizedBox(height: 12),

                  // Holdings
                  if (holdings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text("No holdings data available.",
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                      ),
                    )
                  else
                    _holdingsSection(),
                ],
              ),
            ),
    );
  }

  Widget _lastRebalanceSummary() {
    final history = widget.portfolio.rebalanceHistory;
    if (history.isEmpty) return const SizedBox.shrink();

    final latest = history.last;
    final exec = latest.getExecutionForUser(widget.email);
    final dateStr = latest.rebalanceDate != null
        ? DateFormat("dd MMM yyyy").format(latest.rebalanceDate!)
        : "Unknown";
    final stockCount = latest.adviceEntries.length;
    final statusLabel = exec?.isExecuted == true ? "Executed" : (exec?.status ?? "Pending");
    final statusColor = exec?.isExecuted == true ? Colors.green : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          initiallyExpanded: false,
          title: Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              const Text("Last Rebalance",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ],
          ),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _rebalStat("Date", dateStr),
                _rebalStat("Stocks", "$stockCount"),
                _rebalStat("History", "${history.length} total"),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RebalanceHistoryPage(
                        portfolio: widget.portfolio,
                        email: widget.email,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.timeline_rounded, size: 16),
                label: const Text("View Full History"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rebalStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _headerCard() {
    final isProfit = _totalPnl >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isProfit
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [Colors.red.shade700, Colors.red.shade500],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.portfolio.modelName,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _headerStat("Invested",
                  "\u20B9${_currencyFormat.format(totalInvested.round())}"),
              _headerStat("Current",
                  "\u20B9${_currencyFormat.format(totalCurrent.round())}"),
              _headerStat("P&L",
                  "${isProfit ? '+' : ''}\u20B9${_currencyFormat.format(_totalPnl.abs().round())}"),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "${isProfit ? '+' : ''}${_totalPnlPct.toStringAsFixed(2)}% returns",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _rebalanceBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RebalanceReviewPage(
              portfolio: widget.portfolio,
              email: widget.email,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.sync, color: Colors.orange.shade700, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Rebalance Available",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: Colors.orange.shade800)),
                  Text("Review and execute the latest changes.",
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.orange.shade400),
          ],
        ),
      ),
    );
  }

  Widget _brokerSelector() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: availableBrokers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final broker = availableBrokers[index];
          final isSelected = (selectedBroker ?? 'ALL') == broker;
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedBroker = broker;
                loading = true;
              });
              _fetchHoldings();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1A237E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300),
              ),
              child: Center(
                child: Text(broker,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _holdingsSection() {
    // Sort by current value descending
    final sorted = List<PortfolioHolding>.from(holdings)
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

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
          Text("Holdings (${holdings.length})",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          // Header
          Row(
            children: const [
              Expanded(flex: 3, child: Text("Symbol",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey))),
              Expanded(flex: 1, child: Text("Qty",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text("Avg / LTP",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text("P&L",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                textAlign: TextAlign.right)),
            ],
          ),
          const Divider(height: 16),

          ...sorted.map((h) {
            final isProfit = (h.pnl ?? 0) >= 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.symbol,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        if (h.exchange != null)
                          Text(h.exchange!,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text("${h.quantity}",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Text("\u20B9${h.avgPrice.toStringAsFixed(1)}",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          textAlign: TextAlign.center),
                        if (h.ltp != null)
                          Text("\u20B9${h.ltp!.toStringAsFixed(1)}",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "${isProfit ? '+' : ''}\u20B9${(h.pnl ?? 0).abs().toStringAsFixed(0)}",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isProfit ? Colors.green : Colors.red,
                          ),
                        ),
                        if (h.pnlPercent != null)
                          Text(
                            "${isProfit ? '+' : ''}${h.pnlPercent!.toStringAsFixed(1)}%",
                            style: TextStyle(
                              fontSize: 11,
                              color: isProfit ? Colors.green : Colors.red,
                            ),
                          ),
                      ],
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
