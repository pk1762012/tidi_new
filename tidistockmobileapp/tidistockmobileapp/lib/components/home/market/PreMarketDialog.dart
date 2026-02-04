import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../service/ApiService.dart';

class PreMarketDialog {
  static Future<void> show(BuildContext context) async {
    try {
      ApiService api = ApiService();
      final response = await api.getPreMarketSummary();

      if (response.statusCode == 200) {
        final data = json.decode(response.body)["data"];

        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => _PreMarketDialogFrame(data: data),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to fetch pre-market data")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }
}

// ---------------- FRAME ----------------
class _PreMarketDialogFrame extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PreMarketDialogFrame({required this.data});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: Colors.transparent,
      child: _PreMarketDialogContent(data: data),
    );
  }
}

// ---------------- CONTENT ----------------
class _PreMarketDialogContent extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PreMarketDialogContent({required this.data});

  // ---------------- COLOR LOGIC ----------------
  Color _statusColor(String? value) {
    if (value == null) return Colors.white70;
    final t = value.toLowerCase();
    if (t.contains("+") || t.contains("up") || t.contains("positive")) {
      return Colors.greenAccent.shade400;
    }
    if (t.contains("-") || t.contains("down") || t.contains("negative")) {
      return Colors.redAccent.shade400;
    }
    if (t.contains("neutral") || t.contains("flat")) {
      return Colors.amberAccent.shade400;
    }
    return Colors.white70;
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 18),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: child,
    );
  }

  Widget _rowItem(
      String title,
      String value,
      String pct, {
        Color? color,
      }) {
    final c = color ?? _statusColor(pct);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
          Text(
            "$value  •  $pct",
            style: TextStyle(color: c, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardValue = const TextStyle(
        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);

    return Stack(
        children: [ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.75),
                Colors.black.withOpacity(0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------------- Header ----------------
                Text(
                  "Pre-Market Overview",
                  style: cardValue.copyWith(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),

                // ---------------- Gift Nifty ----------------
                _sectionTitle("Gift Nifty"),
                _glassCard(
                  child: Builder(builder: (_) {
                    final g = data["gift_nifty"] ?? {};
                    final gd = g["data"] ?? {};
                    final last = gd["last"]?.toString() ?? "-";
                    final pct = gd["pct_change"]?.toString() ?? "-";
                    final gap = g["gap_text"]?.toString() ?? "-";
                    final bias = g["market_bias"]?.toString() ?? "Neutral";

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "₹ $last  •  $pct",
                              style: cardValue.copyWith(
                                  fontSize: 18,
                                  color: _statusColor(pct)),
                            ),
                            _pill(bias.toUpperCase(), _statusColor(bias)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          gap,
                          style: TextStyle(
                              color: _statusColor(gap),
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    );
                  }),
                ),

                // ---------------- Market Summary ----------------
                _sectionTitle("Market Summary"),
                _glassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.auto_graph_rounded,
                          color: Colors.blueAccent.shade200),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          data["detailed_summary"] ?? "-",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---------------- Nifty Spot ----------------
                _glassCard(
                  child: _rowItem(
                    "Nifty Spot",
                    "${data["nifty_spot"]["last"]}",
                    "${data["nifty_spot"]["pct_change"]}",
                  ),
                ),

                // ---------------- Global Cues ----------------
                _sectionTitle("Global Cues"),
                _glassCard(
                  child: Column(
                    children: (data["global_cues"] as Map).entries.map((e) {
                      return _rowItem(
                        e.key,
                        "${e.value["last"]}",
                        "${e.value["pct_change"]}",
                      );
                    }).toList(),
                  ),
                ),

                // ---------------- FX & Commodities ----------------
                _sectionTitle("FX & Commodities"),
                _glassCard(
                  child: Column(
                    children:
                    (data["fx_and_commodities"] as Map).entries.map((e) {
                      final v = e.value;
                      String val = "${v["last"]}";
                      if (v.containsKey("last_inr")) {
                        val += "  •  ₹${v["last_inr"]}";
                      }
                      return _rowItem(
                        e.key,
                        val,
                        "${v["pct_change"]}",
                      );
                    }).toList(),
                  ),
                ),

                // ---------------- Volatility & Sectors ----------------
                _sectionTitle("Volatility & Sectors"),
                _glassCard(
                  child: Column(
                    children:
                    (data["volatility_sectors"] as Map).entries.map((e) {
                      return _rowItem(
                        e.key,
                        "${e.value["last"]}",
                        "${e.value["pct_change"]}",
                      );
                    }).toList(),
                  ),
                ),

                // ---------------- Headlines ----------------
                _sectionTitle("Top Headlines"),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List<String>.from(data["headlines"])
                        .map((h) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        "• $h",
                        style: const TextStyle(
                            color: Colors.white70, height: 1.35),
                      ),
                    ))
                        .toList(),
                  ),
                ),

                // ---------------- Strategy Tip ----------------
                _glassCard(
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          color: Colors.amberAccent.shade200),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Strategy Tip: Low VIX + strong gap may support trending moves. Watch first 15–30 mins for confirmation.",
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              iconSize: 22,
              color: Colors.white70,
              splashRadius: 20,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),]);
  }
}
