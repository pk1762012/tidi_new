import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'PortfolioHoldingsPage.dart';

class InvestedPortfoliosPage extends StatefulWidget {
  final String email;

  const InvestedPortfoliosPage({super.key, required this.email});

  @override
  State<InvestedPortfoliosPage> createState() => _InvestedPortfoliosPageState();
}

class _InvestedPortfoliosPageState extends State<InvestedPortfoliosPage> {
  List<ModelPortfolio> subscribedPortfolios = [];
  Map<String, _PortfolioSummary> summaries = {};
  bool loading = true;
  String? error;
  final _currencyFormat = NumberFormat('#,##,###');

  @override
  void initState() {
    super.initState();
    _fetchSubscribedStrategies();
  }

  Future<void> _fetchSubscribedStrategies() async {
    try {
      await AqApiService.instance.getCachedSubscribedStrategies(
        email: widget.email,
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final List<dynamic> list = data is List
              ? data
              : (data is Map && data.containsKey('data') ? data['data'] : []);
          setState(() {
            subscribedPortfolios =
                list.map((e) => ModelPortfolio.fromJson(e)).toList();
            loading = false;
            error = null;
          });
          // Fetch summaries for each portfolio
          for (final p in subscribedPortfolios) {
            _fetchPortfolioSummary(p.modelName);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Unable to load your investments.';
        });
      }
    }
  }

  Future<void> _fetchPortfolioSummary(String modelName) async {
    try {
      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: widget.email,
        modelName: modelName,
      );
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final subData = data['data'];
        if (subData != null) {
          double invested = 0;
          double current = 0;

          // Parse from subscription_amount_raw (latest)
          final rawAmounts = subData['subscription_amount_raw'] ?? [];
          if (rawAmounts is List && rawAmounts.isNotEmpty) {
            final latest = rawAmounts.last;
            if (latest is Map) {
              invested = (latest['totalInvestment'] ?? latest['invested'] ?? 0).toDouble();
              current = (latest['currentValue'] ?? latest['current'] ?? invested).toDouble();
            }
          }

          // Parse from user_net_pf_model for holdings count
          final holdings = subData['user_net_pf_model'] ?? [];
          int holdingsCount = 0;
          if (holdings is List && holdings.isNotEmpty) {
            final latestH = holdings.last;
            if (latestH is List) holdingsCount = latestH.length;
            if (latestH is Map) holdingsCount = (latestH['stocks'] as List?)?.length ?? 0;
          }

          setState(() {
            summaries[modelName] = _PortfolioSummary(
              investedValue: invested,
              currentValue: current,
              holdingsCount: holdingsCount,
              broker: subData['user_broker'] ?? '',
            );
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "My Investments",
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() { loading = true; error = null; });
                  _fetchSubscribedStrategies();
                },
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    if (subscribedPortfolios.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text("No Investments Yet",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text("Browse model portfolios and start investing.",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Calculate overall P&L
    double totalInvested = 0;
    double totalCurrent = 0;
    for (final s in summaries.values) {
      totalInvested += s.investedValue;
      totalCurrent += s.currentValue;
    }
    final totalPnl = totalCurrent - totalInvested;
    final totalPnlPct = totalInvested > 0 ? (totalPnl / totalInvested * 100) : 0.0;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => loading = true);
        await _fetchSubscribedStrategies();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Overall summary card
          if (summaries.isNotEmpty) _overallSummary(totalInvested, totalCurrent, totalPnl, totalPnlPct),
          const SizedBox(height: 16),

          // Individual portfolio cards
          ...subscribedPortfolios.map((p) => _portfolioCard(p)),
        ],
      ),
    );
  }

  Widget _overallSummary(double invested, double current, double pnl, double pnlPct) {
    final isProfit = pnl >= 0;
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
          const Text("Portfolio Overview",
            style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Invested",
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                  Text("\u20B9${_currencyFormat.format(invested.round())}",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("Current",
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                  Text("\u20B9${_currencyFormat.format(current.round())}",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isProfit ? Icons.trending_up : Icons.trending_down,
                  color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  "${isProfit ? '+' : ''}\u20B9${_currencyFormat.format(pnl.abs().round())} (${pnlPct.toStringAsFixed(1)}%)",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _portfolioCard(ModelPortfolio portfolio) {
    final summary = summaries[portfolio.modelName];
    final pnl = summary != null ? summary.currentValue - summary.investedValue : 0.0;
    final isProfit = pnl >= 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PortfolioHoldingsPage(
              portfolio: portfolio,
              email: widget.email,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(portfolio.modelName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (summary != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isProfit ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "${isProfit ? '+' : ''}${(summary.investedValue > 0 ? (pnl / summary.investedValue * 100) : 0).toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isProfit ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              ],
            ),
            if (summary != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat("Invested",
                      "\u20B9${_currencyFormat.format(summary.investedValue.round())}"),
                  _miniStat("Current",
                      "\u20B9${_currencyFormat.format(summary.currentValue.round())}"),
                  _miniStat("P&L",
                      "${isProfit ? '+' : ''}\u20B9${_currencyFormat.format(pnl.abs().round())}",
                      color: isProfit ? Colors.green : Colors.red),
                ],
              ),
              if (summary.broker.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text("via ${summary.broker}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text("Loading...",
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _PortfolioSummary {
  final double investedValue;
  final double currentValue;
  final int holdingsCount;
  final String broker;

  _PortfolioSummary({
    required this.investedValue,
    required this.currentValue,
    required this.holdingsCount,
    required this.broker,
  });
}
