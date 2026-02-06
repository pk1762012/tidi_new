import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import '../../../widgets/SubscriptionPromptDialog.dart';
import 'StockDetailsScreen.dart';


class UnifiedScan {
  final String title;
  final int count;
  final Color color;
  final bool isLongTerm;

  UnifiedScan({
    required this.title,
    required this.count,
    required this.color,
    required this.isLongTerm,
  });
}

class StockScannerSection extends StatefulWidget {
  final List<dynamic> preloadedStocks;

  const StockScannerSection({super.key, required this.preloadedStocks});

  @override
  State<StockScannerSection> createState() => _StockScannerSectionState();
}

class _StockScannerSectionState extends State<StockScannerSection>
    with SingleTickerProviderStateMixin {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  List<dynamic> stockData = [];

  late final AnimationController _controller;
  int visibleIndex = 0;


  @override
  void initState() {
    super.initState();
    stockData = widget.preloadedStocks;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose(); // Dispose the AnimationController
    super.dispose();
  }

  // ------------------- Market Strength -------------------
  double calculateMarketStrength() {
    if (stockData.isEmpty) return 0;
    double score = 0;
    for (var stock in stockData) {
      switch (stock['Trend']) {
        case 'Strong Bullish':
          score += 2;
          break;
        case 'Bullish':
          score += 1;
          break;
        case 'Neutral':
          score += 0;
          break;
        case 'Bearish':
          score -= 1;
          break;
        case 'Strong Bearish':
          score -= 2;
          break;
      }
    }
    double maxScore = stockData.length * 2;
    double minScore = stockData.length * -2;
    return ((score - minScore) / (maxScore - minScore)) * 100;
  }

  // ------------------- Build -------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 1),
            child: Text(
              "Data Date: ${getLatestStockDate()}",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black),
            ),
          ),
          _buildTrendDashboard(),
          const SizedBox(height: 16),
          _buildUnifiedTechnicalSections(),
          const SizedBox(height: 16),
          _buildPatternSection(),
          const SizedBox(height: 16),
          _buildTopGainersSection(),
          const SizedBox(height: 12),
          _buildTopLosersSection(),

          const SizedBox(height: 16),
          _build52WeekHighStocks(),
          const SizedBox(height: 12),
          _build52WeekLowStocks(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String getLatestStockDate() {
    if (stockData.isEmpty) return "-";

    // Assuming stockData has a 'Date' key in format 'yyyy-MM-dd' or DateTime
    List<DateTime> dates = [];
    for (var stock in stockData) {
      final dateRaw = stock['date'];
      if (dateRaw != null) {
        if (dateRaw is DateTime) {
          dates.add(dateRaw);
        } else if (dateRaw is String) {
          try {
            dates.add(DateTime.parse(dateRaw));
          } catch (_) {}
        }
      }
    }

    if (dates.isEmpty) return "-";

    dates.sort((a, b) => b.compareTo(a)); // latest first
    final latest = dates.first;
    return "${latest.day.toString().padLeft(2,'0')}-${latest.month.toString().padLeft(2,'0')}-${latest.year}";
  }


  // ------------------- Trend Dashboard -------------------
  Widget _buildTrendDashboard() {
    double marketStrength = calculateMarketStrength(); // 0-100

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          "TIDI Market Strength",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Based on F&O stocks EOD data",
          style: TextStyle(
            color: Colors.black54,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: SizedBox(
            width: 120,
            height: 60,
            child: CustomPaint(
              painter: _MiniSpeedometerPainter(marketStrength),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text("Strong Bearish", style: TextStyle(fontSize: 9, color: Colors.redAccent)),
            Text("Bearish", style: TextStyle(fontSize: 9, color: Colors.orangeAccent)),
            Text("Neutral", style: TextStyle(fontSize: 9, color: Colors.grey)),
            Text("Bullish", style: TextStyle(fontSize: 9, color: Colors.lightGreen)),
            Text("Strong Bullish", style: TextStyle(fontSize: 9, color: Colors.green)),
          ],
        ),
      ],
    );
  }

  List<UnifiedScan> getUnifiedTechnicalScans() {
    int rsiOver = 0, rsiUnder = 0;
    int rsiOverWeekly = 0, rsiUnderWeekly = 0;
    int macdBullish = 0, macdBearish = 0;
    int smaAbove = 0, smaBelow = 0;
    int rule180Bull = 0, rule180Bear = 0;
    int openLow = 0, openHigh = 0;
    int weeklyHigh = 0, weeklyLow = 0;

    for (var s in stockData) {
      // -------- DAILY / SHORT TERM --------
      double rsi = (s['RSI_14'] ?? 50).toDouble();
      if (rsi > 70) rsiOver++;
      if (rsi < 30) rsiUnder++;

      double macd = (s['MACD'] ?? 0).toDouble();
      double signal = (s['MACD_signal'] ?? 0).toDouble();
      if (macd > signal) macdBullish++;
      if (macd < signal) macdBearish++;

      double sma20 = (s['SMA_20'] ?? 0).toDouble();
      double sma50 = (s['SMA_50'] ?? sma20).toDouble();
      if (sma20 > sma50) smaAbove++;
      if (sma20 < sma50) smaBelow++;

      final technicalScans = s['Technical_Scans'] as Map<String, dynamic>?;
      final rule180 = technicalScans?['180_Rule']?.toString().toLowerCase();
      if (rule180 != null) {
        if (rule180.contains('bull')) rule180Bull++;
        if (rule180.contains('bear')) rule180Bear++;
      }

      if (s['Open_Low'] != null && s['Open_Low'] != 'None') openLow++;
      if (s['Open_High'] != null && s['Open_High'] != 'None') openHigh++;

      // -------- WEEKLY / LONG TERM --------
      double rsiW = (s['Weekly_RSI_14'] ?? 50).toDouble();
      if (rsiW > 70) rsiOverWeekly++;
      if (rsiW < 30) rsiUnderWeekly++;

      final weekly = s['Weekly'] as Map<String, dynamic>?;
      if (weekly != null && weekly['Weekly_High_Breakout'] != null && weekly['Weekly_High_Breakout'] != 'None') {
        weeklyHigh++;
      }
      if (weekly != null && weekly['Weekly_Low_Breakdown'] != null && weekly['Weekly_Low_Breakdown'] != 'None') {
        weeklyLow++;
      }
    }

    return [
      // ---------- SHORT TERM ----------
      UnifiedScan(title: "180 Bullish", count: rule180Bull, color: Colors.green, isLongTerm: false),
      UnifiedScan(title: "180 Bearish", count: rule180Bear, color: Colors.redAccent, isLongTerm: false),
      UnifiedScan(title: "RSI Overbought", count: rsiOver, color: Colors.redAccent, isLongTerm: false),
      UnifiedScan(title: "RSI Oversold", count: rsiUnder, color: Colors.green, isLongTerm: false),
      UnifiedScan(title: "SMA 20 Above 50", count: smaAbove, color: Colors.green, isLongTerm: false),
      UnifiedScan(title: "SMA 20 Below 50", count: smaBelow, color: Colors.redAccent, isLongTerm: false),
      UnifiedScan(title: "MACD Bullish", count: macdBullish, color: Colors.blue, isLongTerm: false),
      UnifiedScan(title: "MACD Bearish", count: macdBearish, color: Colors.orange, isLongTerm: false),


      // ---------- LONG TERM ----------
      UnifiedScan(title: "RSI Overbought Weekly", count: rsiOverWeekly, color: Colors.red, isLongTerm: true),
      UnifiedScan(title: "RSI Oversold Weekly", count: rsiUnderWeekly, color: Colors.green, isLongTerm: true),
      UnifiedScan(title: "Weekly High Breakouts", count: weeklyHigh, color: Colors.green, isLongTerm: true),
      UnifiedScan(title: "Weekly Low Breakdowns", count: weeklyLow, color: Colors.redAccent, isLongTerm: true),
    ];
  }

  Widget _buildUnifiedTechnicalSections() {
    final scans = getUnifiedTechnicalScans();

    final shortTerm = scans.where((s) => !s.isLongTerm).toList();
    final longTerm = scans.where((s) => s.isLongTerm).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildScanSection("Swing / Short-Term Technical Scans", shortTerm),
        const SizedBox(height: 16),
        _buildScanSection("Medium / Long-Term Technical Scans", longTerm),
      ],
    );
  }

  Widget _buildScanSection(String title, List<UnifiedScan> scans) {
    if (scans.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: scans.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final s = scans[index];
              return _scanButton(
                title: s.title,
                count: s.count,
                color: s.color,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _scanButton({
    required String title,
    required int count,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: count == 0 ? null : () => _showScanStocksDialog(title),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        side: BorderSide(color: color.withOpacity(0.45)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),

          /// Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ------------------- Top Gainers / Losers -------------------
  List<Map<String, dynamic>> getTopGainers({int limit = 10}) {
    List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(stockData);
    sorted.sort((a, b) {
      double percA = (a['percentage_change'] ?? 0).toDouble();
      double percB = (b['percentage_change'] ?? 0).toDouble();
      return percB.compareTo(percA); // descending
    });
    return sorted.take(limit).toList();
  }

  List<Map<String, dynamic>> getTopLosers({int limit = 10}) {
    List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(stockData);
    sorted.sort((a, b) {
      double percA = (a['percentage_change'] ?? 0).toDouble();
      double percB = (b['percentage_change'] ?? 0).toDouble();
      return percA.compareTo(percB); // ascending
    });
    return sorted.take(limit).toList();
  }

  Widget _buildTopGainersSection() {
    final gainers = getTopGainers();
    if (gainers.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Top Gainers",
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _buildMoverRow(gainers, isGainer: true),
      ],
    );
  }

  Widget _buildTopLosersSection() {
    final losers = getTopLosers();
    if (losers.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Top Losers",
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _buildMoverRow(losers, isGainer: false),
      ],
    );
  }


  Widget _buildMoverRow(List stocks, {required bool isGainer}) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stocks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final stock = stocks[index];
          return _moverButton(
            symbol: stock['Symbol'] ?? '—',
            change: (stock['percentage_change'] ?? 0).toDouble(),
            isGainer: isGainer,
          );
        },
      ),
    );
  }

  Widget _moverButton({
    required String symbol,
    required double change,
    required bool isGainer,
  }) {
    final Color color = isGainer ? Colors.green : Colors.redAccent;
    final IconData icon = isGainer ? Icons.trending_up : Icons.trending_down;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StockDetailScreen(symbol: symbol),
          ),
        );
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.15),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            /// Direction icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: color),
            ),

            const SizedBox(width: 10),

            /// Symbol + %
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${change.toStringAsFixed(2)}%",
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  void _showScanStocksDialog(String scanName) {
    final List<Map<String, dynamic>> filtered = [];

    for (var raw in stockData) {
      final s = raw as Map<String, dynamic>? ?? {};

      // helper to get value with fallbacks
      dynamic getScan(String topKey, [String? nestedKey]) {
        if (s.containsKey(topKey)) return s[topKey];
        if (nestedKey != null && s.containsKey('Technical_Scans') && s['Technical_Scans'] != null) {
          return s['Technical_Scans'][nestedKey];
        }
        if (nestedKey != null && s.containsKey('Weekly') && s['Weekly'] != null) {
          return s['Weekly'][nestedKey];
        }
        return null;
      }

      final val180 = getScan('180Rule', '180_Rule')?.toString().toLowerCase();
      final weeklyHigh = getScan('Weekly_High_Breakout', 'Weekly_High_Breakout')?.toString().toLowerCase();
      final weeklyLow = getScan('Weekly_Low_Breakdown', 'Weekly_Low_Breakdown')?.toString().toLowerCase();

      bool matches = false;
      switch (scanName) {

      // ---------- RSI ----------
        case 'RSI Overbought':
          if ((s['RSI_14'] ?? 50) > 70) matches = true;
          break;

        case 'RSI Oversold':
          if ((s['RSI_14'] ?? 50) < 30) matches = true;
          break;

        case 'RSI Overbought Weekly':
          if ((s['Weekly_RSI_14'] ?? 50) > 70) matches = true;
          break;

        case 'RSI Oversold Weekly':
          if ((s['Weekly_RSI_14'] ?? 50) < 30) matches = true;
          break;

      // ---------- MACD ----------
        case 'MACD Bullish':
          if ((s['MACD'] ?? 0) > (s['MACD_signal'] ?? 0)) matches = true;
          break;

        case 'MACD Bearish':
          if ((s['MACD'] ?? 0) < (s['MACD_signal'] ?? 0)) matches = true;
          break;

      // ---------- SMA ----------
        case 'SMA 20 Above 50':
          if ((s['SMA_20'] ?? 0) > (s['SMA_50'] ?? 0)) matches = true;
          break;

        case 'SMA 20 Below 50':
          if ((s['SMA_20'] ?? 0) < (s['SMA_50'] ?? 0)) matches = true;
          break;

      // ---------- 180 RULE ----------
        case '180 Bullish':
          if (val180 != null && val180.contains('bull')) matches = true;
          break;

        case '180 Bearish':
          if (val180 != null && val180.contains('bear')) matches = true;
          break;

      // ---------- WEEKLY ----------
        case 'Weekly High Breakouts':
          if (weeklyHigh != null && weeklyHigh != 'none') matches = true;
          break;

        case 'Weekly Low Breakdowns':
          if (weeklyLow != null && weeklyLow != 'none') matches = true;
          break;
      }


      if (matches) {
        filtered.add(s);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Container(
          height: 520,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 🔹 Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // 🔹 Title Row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scanName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${filtered.length} Stocks",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  )
                ],
              ),

              const SizedBox(height: 8),
              Divider(color: Colors.grey.shade300),

              // 🔹 Content
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                  child: Text(
                    "No stocks found",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
                    : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final stock = filtered[index];

                    final symbol = stock['Symbol'] ?? '—';
                    final price = stock['Last_Close']?.toString() ?? '-';
                    final rsi = stock['RSI_14'];
                    final weekly = stock['Weekly_RSI_14'];

                    final bool bullish =
                        scanName.toLowerCase().contains('bull') ||
                            scanName.toLowerCase().contains('above') ||
                            scanName.toLowerCase().contains('low');

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StockDetailScreen(symbol: symbol),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            // 🔹 Symbol Avatar
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: bullish
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              child: Text(
                                symbol.substring(0, 1),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: bullish ? Colors.green : Colors.red,
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            // 🔹 Stock Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    symbol,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Last: $price",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  // 🔹 Indicator Chips
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: -6,
                                    children: [
                                      if (rsi != null)
                                        _miniChip("Daily RSI ${rsi.toStringAsFixed(1)}"),
                                      if (weekly != null)
                                        _miniChip("Weekly RSI ${weekly.toStringAsFixed(1)}"),
                                    ],
                                  )
                                ],
                              ),
                            ),

                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }


  Map<String, List<String>> getPatternsBySignal() {
    final Map<String, Set<String>> bullish = {};
    final Map<String, Set<String>> bearish = {};

    for (var stock in stockData) {
      if (stock['Patterns'] != null) {
        final patterns = stock['Patterns'] as Map<String, dynamic>;
        patterns.forEach((key, value) {
          if (value.toString().toLowerCase() == 'bullish') {
            bullish.putIfAbsent(key, () => {}).add(stock['Symbol']);
          } else if (value.toString().toLowerCase() == 'bearish') {
            bearish.putIfAbsent(key, () => {}).add(stock['Symbol']);
          }
        });
      }
    }

    return {
      'Bullish': bullish.keys.toList(),
      'Bearish': bearish.keys.toList(),
    };
  }

  Map<String, int> getPatternCounts(String signal) {
    final Map<String, int> counts = {};
    for (var stock in stockData) {
      if (stock['Patterns'] != null) {
        final patterns = stock['Patterns'] as Map<String, dynamic>;
        patterns.forEach((key, value) {
          if (value.toString().toLowerCase() == signal.toLowerCase()) {
            counts[key] = (counts[key] ?? 0) + 1;
          }
        });
      }
    }
    return counts;
  }


  Widget _buildPatternSection() {
    final Map<String, int> bullishCounts = getPatternCounts('Bullish');
    final Map<String, int> bearishCounts = getPatternCounts('Bearish');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bullishCounts.isNotEmpty) ...[
          const Text(
            "Bullish Patterns • Daily",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 8),
          _buildPatternButtons(bullishCounts, Colors.green),
        ],

        const SizedBox(height: 16),

        if (bearishCounts.isNotEmpty) ...[
          const Text(
            "Bearish Patterns • Daily",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          const SizedBox(height: 8),
          _buildPatternButtons(bearishCounts, Colors.redAccent),
        ],
      ],
    );
  }

  Widget _buildPatternButtons(Map<String, int> patterns, Color color) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: patterns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pattern = patterns.keys.elementAt(index);
          final count = patterns[pattern]!;
          return _patternButton(pattern, count, color);
        },
      ),
    );
  }


  Widget _patternButton(String pattern, int count, Color color) {
    return ElevatedButton(
      onPressed: count == 0 ? null : () => _showPatternStocksDialog(pattern),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        side: BorderSide(color: color.withOpacity(0.4)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              pattern,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),

          /// Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _showPatternStocksDialog(String pattern) {
    final filteredStocks = stockData.where((s) =>
    s['Patterns'] != null &&
        (s['Patterns'] as Map<String, dynamic>).containsKey(pattern)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Drag Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    /// Header
                    Text(
                      pattern,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${filteredStocks.length} stocks",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),

                    /// Content
                    Expanded(
                      child: filteredStocks.isEmpty
                          ? const Center(
                        child: Text(
                          "No stocks found",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      )
                          : ListView.separated(
                        controller: scrollController,
                        itemCount: filteredStocks.length,
                        separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final stock = filteredStocks[index];
                          final signal =
                          (stock['Patterns'] as Map<String, dynamic>)[
                          pattern];

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StockDetailScreen(
                                    symbol: stock['Symbol'],
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.black12,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  /// Symbol
                                  Text(
                                    stock['Symbol'] ?? '—',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  /// Details
                                  Row(
                                    children: [
                                      Text(
                                        "Signal: $signal",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "Last: ${stock['Last_Close'] ?? '-'}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }


  // ------------------- 52 Week Stocks -------------------
  List<Map<String, dynamic>> getStocksNear52WeekHigh() {
    return stockData.where((stock) {
      final s = stock as Map<String, dynamic>;
      double lastClose = (s['Last_Close'] ?? 0).toDouble();
      double high52 = (s['52_Week_High'] ?? 0).toDouble();
      return high52 != 0 && lastClose / high52 >= 0.95;
    }).map((stock) => stock as Map<String, dynamic>).toList();
  }

  List<Map<String, dynamic>> getStocksNear52WeekLow() {
    return stockData.where((stock) {
      final s = stock as Map<String, dynamic>;
      double lastClose = (s['Last_Close'] ?? 0).toDouble();
      double low52 = (s['52_Week_Low'] ?? 0).toDouble();
      return low52 != 0 && lastClose / low52 <= 1.05 && lastClose / low52 >= 0.95;
    }).map((stock) => stock as Map<String, dynamic>).toList();
  }

  Widget _build52WeekHighStocks() {
    final highStocks = getStocksNear52WeekHigh();
    if (highStocks.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Near 52-Week High", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: highStocks.length,
            itemBuilder: (context, index) {
              final stock = highStocks[index];
              double lastClose = (stock['Last_Close'] ?? 0).toDouble();
              double high52 = (stock['52_Week_High'] ?? 0).toDouble();

              return _build52WeekStockCard(stock['Symbol'], lastClose, high52, isHigh: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _build52WeekLowStocks() {
    final lowStocks = getStocksNear52WeekLow();
    if (lowStocks.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Near 52-Week Low", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: lowStocks.length,
            itemBuilder: (context, index) {
              final stock = lowStocks[index];
              double lastClose = (stock['Last_Close'] ?? 0).toDouble();
              double low52 = (stock['52_Week_Low'] ?? 0).toDouble();

              return _build52WeekStockCard(stock['Symbol'], lastClose, low52, isHigh: false);
            },
          ),
        ),
      ],
    );
  }

  Widget _build52WeekStockCard(String symbol, double lastClose, double level, {required bool isHigh}) {
    double progress = (level == 0) ? 0 : (lastClose / level);
    progress = progress.clamp(0.0, 1.0);
    Color accentColor = isHigh ? Colors.green : Colors.red;

    return GestureDetector(
      onTap: () async {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StockDetailScreen(symbol: symbol),
          ),
        );
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(symbol,
                      style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(isHigh ? "HIGH" : "LOW",
                      style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10)),
                )
              ],
            ),
            const SizedBox(height: 6),
            Text("Last: $lastClose",
                style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(isHigh ? "52W High: $level" : "52W Low: $level",
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}


// ------------------- Mini Speedometer Painter -------------------
class _MiniSpeedometerPainter extends CustomPainter {
  final double percentage;
  _MiniSpeedometerPainter(this.percentage);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.height;

    final rect = Rect.fromCircle(center: center, radius: radius);

    final segments = [
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.grey,
      Colors.lightGreen,
      Colors.green,
    ];

    final segmentSweep = pi / segments.length;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < segments.length; i++) {
      paint.color = segments[i];
      canvas.drawArc(rect, pi + i * segmentSweep, segmentSweep, false, paint);
    }

    final arrowPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    double angle = pi + (percentage / 100) * pi;
    final arrowLength = radius - 6;
    final arrowX = center.dx + arrowLength * cos(angle);
    final arrowY = center.dy + arrowLength * sin(angle);

    canvas.drawLine(center, Offset(arrowX, arrowY), arrowPaint);
    canvas.drawCircle(center, 4, Paint()..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
