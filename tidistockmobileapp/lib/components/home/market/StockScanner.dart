import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import '../../../widgets/customScaffold.dart';
import 'StockChartPage.dart';

class StockScanner extends StatefulWidget {

  final List<dynamic> preloadedStocks;

  const StockScanner({super.key, required this.preloadedStocks});

  @override
  State<StockScanner> createState() => _StockScannerState();
}

class _StockScannerState extends State<StockScanner> {
  List<dynamic> allStocks = [];
  List<dynamic> filteredStocks = [];
  String selectedTrend = 'All';
  int? expandedIndex;
  bool showFilters = true;
  List<String> availablePatterns = []; // all patterns available from stocks
  List<String> selectedPatterns = [];  // patterns user selected

  // Technical filters
  bool rsiOverbought = false;
  bool rsiOversold = false;
  bool macdPositive = false;
  bool macdNegative = false;
  bool smaBullish = false;
  bool smaBearish = false;
  bool emaBullish = false;
  bool emaBearish = false;

  final List<String> trendOptions = [
    'All',
    'Strong Bullish',
    'Bullish',
    'Neutral',
    'Bearish',
    'Strong Bearish'
  ];

  final Map<int, bool> expandedStatus = {};

  final Map<String, Color> trendColors = {
    'Strong Bullish': Colors.green.shade800,
    'Bullish': Colors.green,
    'Neutral': Colors.grey,
    'Bearish': Colors.red,
    'Strong Bearish': Colors.red.shade800,
  };

  @override
  void initState() {
    super.initState();
    allStocks = widget.preloadedStocks;
    fetchData();
  }

  Future<void> fetchData() async {
      setState(() {
        allStocks = widget.preloadedStocks;
        filteredStocks = widget.preloadedStocks;
        for (int i = 0; i < filteredStocks.length; i++) {
          expandedStatus[i] = false;
        }
      });
      availablePatterns.clear();
      for (var stock in allStocks) {
        if (stock['Patterns'] != null) {
          availablePatterns.addAll((stock['Patterns'] as Map<String, dynamic>).keys.cast<String>());
        }
      }
      availablePatterns = availablePatterns.toSet().toList(); // remove duplicates
  }

  void applyFilters() {
    setState(() {
      filteredStocks = allStocks.where((stock) {
        bool matchTrend =
            selectedTrend == 'All' || stock['Trend'] == selectedTrend;

        // RSI Filter
        bool matchRSI = true;
        double rsi = double.tryParse(stock['RSI_14'].toString()) ?? 0;
        if (rsiOverbought && rsi <= 70) matchRSI = false;
        if (rsiOversold && rsi >= 30) matchRSI = false;
        if (!rsiOverbought && !rsiOversold) matchRSI = true;

        // MACD Filter
        bool matchMACD = true;
        double macd = double.tryParse(stock['MACD'].toString()) ?? 0;
        if (macdPositive && macd <= 0) matchMACD = false;
        if (macdNegative && macd >= 0) matchMACD = false;
        if (!macdPositive && !macdNegative) matchMACD = true;

        // SMA Crossover
        bool matchSMA = true;
        double sma20 = double.tryParse(stock['SMA_20'].toString()) ?? 0;
        double sma50 = double.tryParse(stock['SMA_50'].toString()) ?? 0;
        if (smaBullish && sma20 <= sma50) matchSMA = false;
        if (smaBearish && sma20 >= sma50) matchSMA = false;
        if (!smaBullish && !smaBearish) matchSMA = true;

        // EMA Crossover
        bool matchEMA = true;
        double ema20 = double.tryParse(stock['EMA_20'].toString()) ?? 0;
        double ema50 = double.tryParse(stock['EMA_50'].toString()) ?? 0;
        if (emaBullish && ema20 <= ema50) matchEMA = false;
        if (emaBearish && ema20 >= ema50) matchEMA = false;
        if (!emaBullish && !emaBearish) matchEMA = true;

        // Pattern Filter
        bool matchPattern = true;
        if (selectedPatterns.isNotEmpty) {
          if (stock['Patterns'] != null) {
            Map<String, dynamic> patterns = Map<String, dynamic>.from(stock['Patterns']);
            matchPattern = selectedPatterns.any((p) => patterns.containsKey(p));
          } else {
            matchPattern = false;
          }
        }


        return matchTrend && matchRSI && matchMACD && matchSMA && matchEMA && matchPattern;
      }).toList();

      expandedStatus.clear();
      for (int i = 0; i < filteredStocks.length; i++) {
        expandedStatus[i] = false;
      }
    });
  }

  Color metricColor(String label, dynamic value) {
    if (value == null) return Colors.grey;

    double val = double.tryParse(value.toString()) ?? 0;

    switch (label) {
      case 'RSI 14':
        if (val < 30) return Colors.green; // Oversold → Bullish
        if (val > 70) return Colors.red;   // Overbought → Bearish
        return Colors.orange;               // Neutral
      case 'MACD':
      case 'MACD Signal':
        if (val > 0) return Colors.green;
        if (val < 0) return Colors.red;
        return Colors.orange;
      case 'SMA 20':
      case 'SMA 50':
      case 'SMA 100':
      case 'EMA 20':
      case 'EMA 50':
      case 'BB Upper':
      case 'BB Lower':
        return Colors.blueAccent;
      case 'Volume':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget stockInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label: $value',
          style: const TextStyle(color: Colors.black87, fontSize: 14)),
    );
  }

  Widget metricCard(String label, dynamic value, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200, minWidth: 100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              value.toString(),
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget metricsGroup(String groupName, List<Widget> metrics) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(groupName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: metrics,
          ),
        ],
      ),
    );
  }

  Widget stockCard(int index, dynamic stock) {
    // defensive getters
    final String name = (stock['name'] ?? stock['symbol'] ?? 'Unknown').toString();
    final String symbol = (stock['Symbol'] ?? '').toString();
    final String shortSymbol = symbol.replaceAll('.NS', '');
    final String trendStr = (stock['Trend'] ?? 'Unknown').toString();
    final double lastClose = (stock['Last_Close'] is num) ? (stock['Last_Close'] as num).toDouble() : (double.tryParse(stock['Last_Close']?.toString() ?? '') ?? 0.0);
    final double pctChange = (stock['percentage_change'] is num) ? (stock['percentage_change'] as num).toDouble() : (double.tryParse(stock['percentage_change']?.toString() ?? '') ?? 0.0);
    final String dateStr = (stock['date'] ?? '').toString();

    final bool isExpanded = expandedIndex == index;
    final Color trendColor = trendColors[trendStr] ?? Colors.grey;
    final Color pctColor = pctChange >= 0 ? Colors.green.shade700 : Colors.red.shade700;

    // formatted text helpers
    String formattedPrice() => lastClose == 0.0 ? '-' : lastClose.toStringAsFixed(2);
    String formattedPct() => pctChange.isNaN ? '-' : '${pctChange >= 0 ? '+' : ''}${pctChange.toStringAsFixed(2)}%';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95), // white card on white background looks clean
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              expandedIndex = isExpanded ? null : index;
            });
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      // Trend color bar
                      Container(
                        width: 8,
                        height: 44,
                        decoration: BoxDecoration(
                          color: trendColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Symbol + Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // symbol on top (smaller) and name below
                            Text(
                              shortSymbol.isEmpty ? name : shortSymbol,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Price & % change
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formattedPrice(),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: pctColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pctColor.withOpacity(0.25)),
                            ),
                            child: Text(
                              formattedPct(),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: pctColor),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(width: 12),

                      // Trend badge + chevron
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: trendColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: trendColor.withOpacity(0.25)),
                            ),
                            child: Text(
                              trendStr,
                              style: TextStyle(
                                  color: trendColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedRotation(
                            turns: isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // small info row
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(child: Text(dateStr, style: TextStyle(color: Colors.grey[700], fontSize: 12))),
                      const SizedBox(width: 8),
                      // quick actions: chart and AI
                      InkWell(
                        onTap: () {
                          final s = shortSymbol;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => StockChartPage(symbol: s)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.2)),
                          ),
                          child: const Icon(Icons.show_chart, size: 18, color: Colors.black54),
                        ),
                      ),

                    ],
                  ),

                  // Expanded content
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    // Patterns as chips (if present)
                    if (stock['Patterns'] != null && (stock['Patterns'] as Map).isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: (stock['Patterns'] as Map<String, dynamic>).entries.map<Widget>((entry) {
                          final String patternName = entry.key;
                          final String patternVal = entry.value.toString();
                          final Color chipColor = patternVal.toLowerCase().contains('bull')
                              ? Colors.green
                              : patternVal.toLowerCase().contains('bear')
                              ? Colors.red
                              : Colors.orange;
                          return Chip(
                            label: Text(patternName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            backgroundColor: chipColor.withOpacity(0.12),
                            side: BorderSide(color: chipColor.withOpacity(0.25)),
                            labelStyle: TextStyle(color: chipColor),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Metrics grid (responsive)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 52-week, Pivot, SMA/EMA, Indicators etc — use metricCard helper
                        metricCard('52W High', stock['52_Week_High'] ?? '-', Colors.blueAccent),
                        metricCard('52W Low', stock['52_Week_Low'] ?? '-', Colors.lightBlueAccent),
                        metricCard('Pivot', stock['Pivot'] ?? '-', Colors.orangeAccent),
                        metricCard('R1', stock['R1'] ?? '-', Colors.cyan),
                        metricCard('S1', stock['S1'] ?? '-', Colors.deepOrangeAccent),
                        metricCard('RSI 14', stock['RSI_14'] ?? '-', metricColor('RSI 14', stock['RSI_14'])),
                        metricCard('MACD', stock['MACD'] ?? '-', metricColor('MACD', stock['MACD'])),
                        metricCard('EMA 20', stock['EMA_20'] ?? '-', metricColor('EMA 20', stock['EMA_20'])),
                        metricCard('SMA 20', stock['SMA_20'] ?? '-', metricColor('SMA 20', stock['SMA_20'])),
                        metricCard('BB Upper', stock['BB_upper'] ?? '-', metricColor('BB Upper', stock['BB_upper'])),
                        metricCard('Volume', stock['Volume'] ?? '-', metricColor('Volume', stock['Volume'])),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Extras: Fibonacci / ATR / Buttons grouped
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.bar_chart, size: 18),
                            label: const Text('View Full Chart'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => StockChartPage(symbol: shortSymbol)),
                              );
                            },
                          ),
                        ),

                      ],
                    ),

                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }



  Widget technicalFilters() {
    final List<Map<String, dynamic>> filters = [
      {'label': 'RSI Overbought (>70)', 'value': rsiOverbought, 'type': 'RSI', 'onChanged': (val) => setState(() { rsiOverbought = val; applyFilters(); })},
      {'label': 'RSI Oversold (<30)', 'value': rsiOversold, 'type': 'RSI', 'onChanged': (val) => setState(() { rsiOversold = val; applyFilters(); })},
      {'label': 'MACD Positive', 'value': macdPositive, 'type': 'MACD', 'onChanged': (val) => setState(() { macdPositive = val; applyFilters(); })},
      {'label': 'MACD Negative', 'value': macdNegative, 'type': 'MACD', 'onChanged': (val) => setState(() { macdNegative = val; applyFilters(); })},
      {'label': 'SMA Bullish (20>50)', 'value': smaBullish, 'type': 'SMA', 'onChanged': (val) => setState(() { smaBullish = val; applyFilters(); })},
      {'label': 'SMA Bearish (20<50)', 'value': smaBearish, 'type': 'SMA', 'onChanged': (val) => setState(() { smaBearish = val; applyFilters(); })},
      {'label': 'EMA Bullish (20>50)', 'value': emaBullish, 'type': 'EMA', 'onChanged': (val) => setState(() { emaBullish = val; applyFilters(); })},
      {'label': 'EMA Bearish (20<50)', 'value': emaBearish, 'type': 'EMA', 'onChanged': (val) => setState(() { emaBearish = val; applyFilters(); })},
    ];

    Color filterColor(Map<String, dynamic> filter) {
      bool selected = filter['value'] as bool;
      switch (filter['type']) {
        case 'RSI':
          return Colors.orangeAccent;
        case 'MACD':
          return filter['label'].contains('Positive') ? Colors.greenAccent : Colors.redAccent;
        case 'SMA':
        case 'EMA':
          return filter['label'].contains('Bullish') ? Colors.greenAccent : Colors.redAccent;
        default:
          return Colors.grey;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Filter by Technical Indicator:',
            style: TextStyle(
              color: lightColorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = filters[index];
              bool isSelected = filter['value'] as bool;
              Color color = filterColor(filter);

              return GestureDetector(
                onTap: () => filter['onChanged'](!isSelected),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: isSelected ? 1.05 : 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? color.withOpacity(0.8) : lightColorScheme.secondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withOpacity(isSelected ? 1.0 : 0.6), width: 1.2),
                        ),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: TextStyle(
                              color: isSelected ? Colors.white : color,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            child: Text(filter['label']),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }




  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Center(
              child: Text(
                'TIDI Stock Technical Scanner',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: lightColorScheme.primary),
              ),
            ),
            const SizedBox(height: 16),

            // ---------------- COLLAPSIBLE FILTERS ----------------
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() => showFilters = !showFilters),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        showFilters ? Icons.expand_less : Icons.expand_more,
                        color: lightColorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        showFilters ? 'Hide Filters' : 'Show Filters',
                        style: TextStyle(
                            color: lightColorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      trendFilter(),
                      const SizedBox(height: 12),
                      technicalFilters(),
                      const SizedBox(height: 12),
                      patternFilters(),
                      const SizedBox(height: 16),
                      resetFilterButton(),
                    ],
                  ),
                  crossFadeState: showFilters
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---------------- STOCK LIST ----------------
            Expanded(
              child: filteredStocks.isEmpty
                  ? const Text('')
                  : ListView.builder(
                itemCount: filteredStocks.length,
                itemBuilder: (context, index) =>
                    stockCard(index, filteredStocks[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ---------------- TREND FILTER UI ----------------
  Widget trendFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Filter by Trend:',
            style: TextStyle(
              color: lightColorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: trendOptions.length,
            itemBuilder: (context, index) {
              String trend = trendOptions[index];
              Color color = trendColors[trend] ?? Colors.grey;
              bool isSelected = selectedTrend == trend;

              return Padding(
                padding: const EdgeInsets.only(right: 8), // margin between capsules
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedTrend = trend;
                      applyFilters();
                    });
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: isSelected ? 1.05 : 1.0),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // inner padding
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? LinearGradient(
                              colors: [
                                color.withOpacity(0.8),
                                color.withOpacity(0.5)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                                : null,
                            color: isSelected ? null : lightColorScheme.secondary.withValues(alpha: .3),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: color.withOpacity(1.0), // visible border always
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              style: TextStyle(
                                color: isSelected ? Colors.white : color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              child: Text(trend),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget resetFilterButton() {
    return Center(
      child: IntrinsicWidth(
        child: GestureDetector(
          onTap: resetFilters,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: 1.0),
            duration: const Duration(milliseconds: 250),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: const Center(
                    child: Text(
                      'Reset Filters',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget patternFilters() {
    if (availablePatterns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Filter by Candlestick Pattern:',
            style: TextStyle(
              color: lightColorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: availablePatterns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final pattern = availablePatterns[index];
              final isSelected = selectedPatterns.contains(pattern);

              Color color = Colors.orangeAccent; // default
              // Optional: show green/red depending on bullish/bearish if you want
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      selectedPatterns.remove(pattern);
                    } else {
                      selectedPatterns.add(pattern);
                    }
                    applyFilters();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.8) : lightColorScheme.secondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(isSelected ? 1.0 : 0.6), width: 1.2),
                  ),
                  child: Center(
                    child: Text(
                      pattern,
                      style: TextStyle(
                        color: isSelected ? Colors.white : color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }





  void resetFilters() {
    setState(() {
      // Reset trend
      selectedTrend = 'All';

      // Reset technical filters
      rsiOverbought = false;
      rsiOversold = false;
      macdPositive = false;
      macdNegative = false;
      smaBullish = false;
      smaBearish = false;
      emaBullish = false;
      emaBearish = false;
      selectedPatterns = [];

      // Reapply filters to show all stocks
      applyFilters();
    });
  }


}
