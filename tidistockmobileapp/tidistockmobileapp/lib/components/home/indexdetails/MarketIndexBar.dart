import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidistockmobileapp/theme/theme.dart';

import '../market/StockChartPage.dart';

class MarketIndexBar extends StatefulWidget {
  final double nifty;
  final double niftyChange;
  final double bankNifty;
  final double bankNiftyChange;
  final Map<String, Map<String, double>> otherIndices;

  const MarketIndexBar({
    super.key,
    required this.nifty,
    required this.niftyChange,
    required this.bankNifty,
    required this.bankNiftyChange,
    required this.otherIndices,
  });

  @override
  State<MarketIndexBar> createState() => _MarketIndexBarState();
}

class _MarketIndexBarState extends State<MarketIndexBar>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 4, end: 12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getChangeColor(double change) {
    if (change > 0) return Colors.green.shade800;
    if (change < 0) return Colors.red.shade800;
    return Colors.grey;
  }

  void _openTradingView(String symbol) {
    HapticFeedback.selectionClick(); // 🔥 HAPTIC FEEDBACK
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockChartPage(symbol: symbol),
      ),
    );
  }

  // ================= Bottom Sheet for Other Indices =================
  void _openOtherIndicesSheet() {
    HapticFeedback.selectionClick(); // 🔥 HAPTIC FEEDBACK
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: Column(
                  children: [

                    // ───────── DRAG HANDLE + TITLE ─────────
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 12),
                      child: Column(
                        children: [
                          Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.grey.shade400,
                                  Colors.grey.shade300,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Other Indices",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ───────── COLUMN HINT ROW (NEW) ─────────

                    const Divider(height: 1),

                    // ───────── LIST ─────────
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        physics: const BouncingScrollPhysics(),
                        itemCount: widget.otherIndices.length,
                        separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final key =
                          widget.otherIndices.keys.elementAt(index);
                          final displayKey =
                          key.replaceAll('_', ' ');
                          final value =
                          widget.otherIndices[key]!;

                          return TweenAnimationBuilder<double>(
                            duration:
                            Duration(milliseconds: 250 + (index * 40)),
                            tween: Tween(begin: 0.94, end: 1),
                            curve: Curves.easeOut,
                            builder: (context, scale, child) {
                              return Opacity(
                                opacity: scale,
                                child: Transform.scale(
                                  scale: scale,
                                  child: child,
                                ),
                              );
                            },
                            child: _buildOtherIndexCard(
                              title: displayKey,
                              value: value['cmp']!,
                              change: value['change']!,
                              symbol: key,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }





  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ================= Top Nifty / BankNifty Bar =================
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,//lightColorScheme.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _openTradingView("NIFTY"),
                child: _buildIndexCard(
                  title: "NIFTY 50",
                  value: widget.nifty,
                  change: widget.niftyChange,
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  return Container(
                    width: _pulse.value,
                    height: _pulse.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: _pulse.value * 2,
                        ),
                      ],
                    ),
                  );
                },
              ),
              InkWell(
                onTap: () => _openTradingView("BANKNIFTY"),
                child: _buildIndexCard(
                  title: "BANK NIFTY",
                  value: widget.bankNifty,
                  change: widget.bankNiftyChange,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 10),
        // ================= Other Indices Trigger =================
        if (widget.otherIndices.isNotEmpty)
          GestureDetector(
            onTap: _openOtherIndicesSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 26,
                  ),
                  SizedBox(width: 3),
                  Text(
                    "Other Indices",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ================= Nifty / Bank Nifty Card =================
  Widget _buildIndexCard({
    required String title,
    required double value,
    required double change,
  }) {
    final percentageChange =
    (value - change != 0) ? (change / (value - change)) * 100 : 0;
    final changeColor = _getChangeColor(change);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: changeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} '
                '(${percentageChange.toStringAsFixed(2)}%)',
            style: TextStyle(
              color: changeColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherIndexCard({
    required String title,
    required double value,
    required double change,
    required String symbol,
  }) {
    final double previous = value - change;
    final double percentageChange =
    previous != 0 ? (change / previous) * 100 : 0;

    final Color changeColor = _getChangeColor(change);
    final bool isPositive = change >= 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openTradingView(symbol), // ✅ whole card clickable
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              // ───── LEFT : INDEX NAME ─────
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ───── RIGHT : PRICE + CHANGE ─────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [

                  // PRICE
                  Text(
                    value.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // CHANGE
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        size: 20,
                        color: changeColor,
                      ),
                      Text(
                        "${isPositive ? '+' : ''}${change.toStringAsFixed(2)} "
                            "(${percentageChange.toStringAsFixed(2)}%)",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: changeColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }




}
