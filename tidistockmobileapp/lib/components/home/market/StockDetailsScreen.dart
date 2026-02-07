import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import '../../../service/ApiService.dart';
import '../../../widgets/SubscriptionPromptDialog.dart';
import '../../../widgets/customScaffold.dart';
import 'StockChartPage.dart';
import 'package:tidistockmobileapp/components/home/ai/StockChatScreen.dart';
import 'dart:ui';


enum TrendSignal { Bullish, Bearish, Neutral }
enum Verdict { Bullish, Bearish, Neutral, SlightlyBullish, SlightlyBearish, HighPE }

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _stockSummary;
  Map<String, dynamic>? _fundamentalData;
  Map<String, dynamic>? _technicalData;
  bool _loading = true;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  bool isSubscribed = false;

  late AnimationController _controller;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fetchStockAnalysis();
    loadSubscriptionStatus();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> loadSubscriptionStatus() async {
    String? subscribed = await secureStorage.read(key: 'is_subscribed');
    String? isPaid = await secureStorage.read(key: 'is_paid');
    setState(() {
      isSubscribed = ((subscribed == 'true') && (isPaid == 'true'));
    });
  }

  Future<void> _fetchStockAnalysis() async {
    try {
      await ApiService().getCachedStockAnalysis(
        symbol: widget.symbol,
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final parsed = data is Map<String, dynamic> ? data : json.decode(data.toString());
          setState(() {
            _stockSummary = parsed['summary'] ?? {};
            _fundamentalData = _stockSummary?['fundamental_data'] ?? {};
            _technicalData = _stockSummary?['technical_data'] ?? {};
            _loading = false;
          });
          _controller.forward();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  TrendSignal parseTrend(String? value) {
    if (value == null) return TrendSignal.Neutral;
    switch (value.toLowerCase()) {
      case 'bullish': return TrendSignal.Bullish;
      case 'bearish': return TrendSignal.Bearish;
      default: return TrendSignal.Neutral;
    }
  }

  Verdict parseVerdict(String? value) {
    if (value == null) return Verdict.Neutral;
    switch (value.toLowerCase()) {
      case 'bullish': return Verdict.Bullish;
      case 'bearish': return Verdict.Bearish;
      case 'slightly bullish': return Verdict.SlightlyBullish;
      case 'slightly bearish': return Verdict.SlightlyBearish;
      case 'caution: high p/e': return Verdict.HighPE;
      default: return Verdict.Neutral;
    }
  }

  Color trendColor(TrendSignal trend) {
    switch (trend) {
      case TrendSignal.Bullish: return Colors.green;
      case TrendSignal.Bearish: return Colors.red;
      case TrendSignal.Neutral: return Colors.grey;
    }
  }

  Color verdictColor(Verdict verdict) {
    switch (verdict) {
      case Verdict.Bullish:
      case Verdict.SlightlyBullish: return Colors.green;
      case Verdict.Bearish:
      case Verdict.SlightlyBearish: return Colors.red;
      case Verdict.HighPE: return Colors.orange;
      case Verdict.Neutral: return Colors.grey;
    }
  }

  Color metricColor(String key, dynamic value) {
    if (value == null) return Colors.black87;
    try {
      switch (key) {
        case 'PE Ratio':
          final pe = value as num;
          if (pe > 25) return Colors.red;
          if (pe < 10) return Colors.green;
          return Colors.black87;
        case 'RSI(14)':
          final rsi = value as num;
          if (rsi > 70) return Colors.red;
          if (rsi < 30) return Colors.green;
          return Colors.black87;
        case 'MACD':
          final macd = value as num;
          return macd >= 0 ? Colors.green : Colors.red;
        default:
          return Colors.black87;
      }
    } catch (_) {
      return Colors.black87;
    }
  }

  String _formatMarketCap(dynamic value) {
    if (value == null) return 'N/A';
    final numVal = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
    final inCrores = numVal / 10000000;
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
        .format(inCrores) + ' Cr';
  }

  Widget _glassCard(String title, Map<String, dynamic> metrics) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),
          ...metrics.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.key, style: TextStyle(fontSize: 14, color: Colors.black54)),
                Flexible(child: Text(
                  fmt(e.value),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: metricColor(e.key, e.value),
                  ),))
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // 👈 shrink to content
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $text',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.1, // 👈 tighter line height
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Patterns Section ----------------
  Map<String, int> _getPatternCounts(String signal) {
    final Map<String, int> counts = {};
    for (var stock in _technicalData?['patterns'] ?? []) {
      final patterns = stock as Map<String, dynamic>;
      patterns.forEach((key, value) {
        if (value.toString().toLowerCase() == signal.toLowerCase()) {
          counts[key] = (counts[key] ?? 0) + 1;
        }
      });
    }
    return counts;
  }

  Widget _buildPatternSection() {
    final bullishCounts = _getPatternCounts('Bullish');
    final bearishCounts = _getPatternCounts('Bearish');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bullishCounts.isNotEmpty) ...[
          const Text('Bullish Patterns', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          const SizedBox(height: 6),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: bullishCounts.length,
              itemBuilder: (context, index) {
                final key = bullishCounts.keys.elementAt(index);
                final count = bullishCounts[key]!;
                return _patternCard(key, count, Colors.green);
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (bearishCounts.isNotEmpty) ...[
          const Text('Bearish Patterns', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          const SizedBox(height: 6),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: bearishCounts.length,
              itemBuilder: (context, index) {
                final key = bearishCounts.keys.elementAt(index);
                final count = bearishCounts[key]!;
                return _patternCard(key, count, Colors.red);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _patternCard(String pattern, int count, Color color) {
    return GestureDetector(
      onTap: () {
        // show list of stocks with this pattern
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(pattern, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(count.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  final Map<String, String> termExplanations = {
    "CMP": "Current Market Price of the stock.",
    "52 Week High": "The highest price the stock reached in the last 52 weeks.",
    "52 Week Low": "The lowest price the stock reached in the last 52 weeks.",
    "PE Ratio": "Price to Earnings Ratio = Current price ÷ Earnings per share.",
    "Forward PE": "Estimated Price to Earnings Ratio based on forecasted earnings.",
    "EPS": "Earnings Per Share.",
    "Market Cap": "Total market value of the company’s outstanding shares.",
    "Dividend Yield": "Annual dividends per share ÷ Price per share.",
    "Beta": "Measure of stock volatility relative to the market.",
    "RSI(14)": "Relative Strength Index over 14 days. Over 70 = overbought, below 30 = oversold.",
    "MACD": "Moving Average Convergence Divergence. Trend momentum indicator.",
    "MACD Signal": "Signal line used with MACD.",
    "SMA 20": "Simple Moving Average over 20 days.",
    "SMA 50": "Simple Moving Average over 50 days.",
    "SMA 100": "Simple Moving Average over 100 days.",
    "EMA 20": "Exponential Moving Average over 20 days.",
    "EMA 50": "Exponential Moving Average over 50 days.",
    "Support (BB Lower)": "Lower Bollinger Band — potential support level.",
    "Resistance (BB Upper)": "Upper Bollinger Band — potential resistance level.",
    "Volume": "Number of shares traded today.",
    "Average Volume": "Average shares traded per day.",
    "Pivot": "Pivot point — used to determine overall market trend.",
    "R1": "Resistance level 1.",
    "R2": "Resistance level 2.",
    "R3": "Resistance level 3.",
    "S1": "Support level 1.",
    "S2": "Support level 2.",
    "S3": "Support level 3.",
    "Fib 38.2%": "38.2% Fibonacci retracement level.",
    "Fib 61.8%": "61.8% Fibonacci retracement level.",
    "ATR Stop Long": "Average True Range stop for long positions.",
    "ATR Stop Short": "Average True Range stop for short positions.",
    "All Time High": "The highest price the stock has ever reached.",
    "Percentage Change": "Daily percentage change of the stock price.",
  };

  Widget _lockedSection({
    required Widget child,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    if (!isLocked) return child;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          // 🚫 Original content (blocked from interaction)
          AbsorbPointer(
            child: Opacity(
              opacity: 0.15, // faint structure only
              child: child,
            ),
          ),

          // 🔒 FULL LOCK OVERLAY
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, // 🔥 complete block
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock_rounded, size: 42, color: Colors.black),
                  SizedBox(height: 12),
                  Text(
                    'Access to Analyst Recommendations is limited to TIDI Wealth members. Please join to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  }




  Color analystSentimentColor(String? label) {
    if (label == null) return Colors.grey;
    switch (label.toLowerCase()) {
      case 'strong buy':
      case 'buy':
        return Colors.green;
      case 'hold':
        return Colors.orange;
      case 'sell':
      case 'strong sell':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _analystSection() {
    final analyst = _fundamentalData?['analyst'];
    if (analyst == null || analyst is! Map) {
      return const SizedBox();
    }

    final target = analyst['target_price'] is Map
        ? analyst['target_price']
        : <String, dynamic>{};

    final double score = analyst['recommendation_score'] is num
        ? (analyst['recommendation_score'] as num).toDouble()
        : 0.0;

    final double upside = analyst['upside_percent'] is num
        ? (analyst['upside_percent'] as num).toDouble()
        : 0.0;

    final int analystCount = analyst['analyst_count'] is int
        ? analyst['analyst_count']
        : 0;

    final double currentPrice =
        (_technicalData?['last_close'] as num?)?.toDouble() ?? 0.0;

    final double targetPrice =
        (target['mean'] as num?)?.toDouble() ??
            (target['high'] as num?)?.toDouble() ??
            0.0;

    final double meanTarget =
        (target['mean'] as num?)?.toDouble() ?? 0.0;

    Color scoreColor(double v) {
      if (v <= 2) return Colors.green;
      if (v <= 3) return Colors.orange;
      return Colors.red;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// HEADER
          const Text(
            'Analyst Opinion',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Icon(Icons.trending_up, color: scoreColor(score)),
              const SizedBox(width: 8),
              Text(
                analyst['recommendation_label']?.toString() ?? 'N/A',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scoreColor(score),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (currentPrice > 0 && targetPrice > 0)
            _targetPriceHero(
              currentPrice: currentPrice,
              targetPrice: targetPrice,
            ),

          const SizedBox(height: 10),

          /// Recommendation



          /// Rating bar
          Text('Analyst Rating Score (${score > 0 ? fmt(score) : 'N/A'})'),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: score > 0 ? ((5 - score) / 5).clamp(0.0, 1.0) : 0,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation(scoreColor(score)),
          ),

          const SizedBox(height: 16),

          /// Targets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat('Low', target['low'], Colors.red),
              _miniStat('Mean', target['mean'], Colors.blue),
              _miniStat('High', target['high'], Colors.green),
            ],
          ),

          /// NEW: Target progress highlight
          if (currentPrice > 0 && meanTarget > 0) ...[
            const SizedBox(height: 14),
            _targetProgress(
              currentPrice: currentPrice,
              targetPrice: meanTarget,
            ),
          ],

          const SizedBox(height: 14),

          /// Upside + analyst count
          Row(
            children: [
              Icon(
                upside >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                color: upside >= 0 ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                upside != 0
                    ? (upside >= 0
                    ? 'Upside: ${fmt(upside)}%'
                    : 'Downside: ${fmt(upside.abs())}%')
                    : 'Upside: N/A',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: upside >= 0 ? Colors.green : Colors.red,
                ),
              ),
              const Spacer(),
              Text(
                analystCount > 0
                    ? 'Analysts: $analystCount'
                    : 'Analysts: N/A',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetPriceHero({
    required double currentPrice,
    required double targetPrice,
  }) {
    final double diff = targetPrice - currentPrice;
    final bool isUpside = diff >= 0;

    final double percent =
    currentPrice > 0 ? (diff / currentPrice) * 100 : 0;

    final Color color = isUpside ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.12),
            color.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          /// Icon bubble
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isUpside ? Icons.trending_up : Icons.trending_down,
              color: color,
              size: 26,
            ),
          ),

          const SizedBox(width: 14),

          /// Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analyst Target Price',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${fmt(targetPrice)}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isUpside
                      ? '+${fmt(percent)}% potential upside'
                      : '${fmt(percent.abs())}% potential downside',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),

          /// CMP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'CMP',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                '₹${fmt(currentPrice)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _targetProgress({
    required double currentPrice,
    required double targetPrice,
  }) {
    if (currentPrice <= 0 || targetPrice <= 0) return const SizedBox();

    final bool upside = targetPrice >= currentPrice;
    final double progress =
    (currentPrice / targetPrice).clamp(0.0, 1.0);

    final Color color = upside ? Colors.green : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Current: ₹${fmt(currentPrice)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              'Target: ₹${fmt(targetPrice)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation(color),
        ),
        const SizedBox(height: 4),
        Text(
          upside
              ? '${fmt(((targetPrice - currentPrice) / currentPrice) * 100)}% upside to target'
              : '${fmt(((currentPrice - targetPrice) / currentPrice) * 100)}% above target',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }


  Widget _miniStat(String label, dynamic value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 4),
        Text(
          fmt(value),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }



  Widget _analystBreakdownSection() {
    final analyst = _fundamentalData?['analyst'];
    final monthly = analyst is Map ? analyst['monthly_breakdown'] : null;

    if (monthly == null || monthly is! Map) {
      return const SizedBox();
    }

    int safeInt(dynamic v) => v is num ? v.toInt() : 0;
    double safeDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

    final int strongBuy = safeInt(monthly['strong_buy']);
    final int buy = safeInt(monthly['buy']);
    final int hold = safeInt(monthly['hold']);
    final int sell = safeInt(monthly['sell']);
    final int strongSell = safeInt(monthly['strong_sell']);
    final int total = safeInt(monthly['total_analysts']);

    final double sentiment =
    safeDouble(monthly['sentiment_score']).clamp(0.0, 1.0);

    Color sentimentColor(double v) {
      if (v >= 0.7) return Colors.green;
      if (v >= 0.4) return Colors.orange;
      return Colors.red;
    }

    String sentimentLabel(double v) {
      if (v >= 0.7) return 'Bullish';
      if (v >= 0.4) return 'Neutral';
      return 'Bearish';
    }

    Widget capsuleBar(
        String label, int value, Color color, IconData icon) {
      final double percent =
      total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    value.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: percent),
              duration: const Duration(milliseconds: 700),
              builder: (context, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Header with sentiment chip
          Row(
            children: [
              const Text(
                'Analyst Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sentimentColor(sentiment).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  sentimentLabel(sentiment),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: sentimentColor(sentiment),
                    fontSize: 12,
                  ),
                ),
              )
            ],
          ),

          const SizedBox(height: 14),

          capsuleBar(
              'Strong Buy', strongBuy, Colors.green, Icons.trending_up),
          capsuleBar('Buy', buy, Colors.green.shade700, Icons.arrow_upward),
          capsuleBar('Hold', hold, Colors.orange, Icons.pause),
          capsuleBar('Sell', sell, Colors.red, Icons.arrow_downward),
          capsuleBar(
              'Strong Sell', strongSell, Colors.red.shade700, Icons.trending_down),

          const SizedBox(height: 18),

          /// Sentiment meter
          Text(
            'Sentiment Score',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: sentiment,
              minHeight: 12,
              backgroundColor: Colors.grey.shade300,
              valueColor:
              AlwaysStoppedAnimation(sentimentColor(sentiment)),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              sentiment > 0 ? sentiment.toStringAsFixed(2) : 'N/A',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sentimentColor(sentiment),
              ),
            ),
          ),
        ],
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    final trend = parseTrend(_stockSummary?['trend_signal']?.toString());
    final verdict = parseVerdict(_stockSummary?['verdict']?.toString());

    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: _loading
          ? Center(child: CircularProgressIndicator(color: lightColorScheme.primary))
          : (_stockSummary == null || _stockSummary!.isEmpty)
          ? const Center(child: Text('No data found', style: TextStyle(color: Colors.black)))
          : Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(child: Text(_stockSummary!['stock_name'] ?? 'N/A',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black))),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.black54),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) {
                            return DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.7,
                              minChildSize: 0.4,
                              maxChildSize: 0.95,
                              builder: (_, controller) {
                                return Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[400],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text("Term Explanations",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Colors.black87)),
                                            IconButton(
                                              icon: const Icon(Icons.close, color: Colors.black54),
                                              onPressed: () => Navigator.of(context).pop(),
                                            )
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1, color: Colors.grey),
                                      Expanded(
                                        child: ListView.builder(
                                          controller: controller,
                                          itemCount: termExplanations.length,
                                          itemBuilder: (_, index) {
                                            final entry = termExplanations.entries.elementAt(index);
                                            return ListTile(
                                              title: Text(entry.key,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.bold, color: Colors.black87)),
                                              subtitle: Text(entry.value,
                                                  style: const TextStyle(color: Colors.black87)),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    )

                  ],
                ),
                const SizedBox(height: 4),
                Text('${_stockSummary!['sector'] ?? 'N/A'} • ${_stockSummary!['industry'] ?? 'N/A'}',
                    style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 10),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// Ask AI (TOP)
                        GestureDetector(
                          onTap: () async {
                            await loadSubscriptionStatus();
                            if (!isSubscribed) {
                              SubscriptionPromptDialog.show(context);
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    StockChatScreen(symbol: widget.symbol),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipOval(
                                child: Image.asset(
                                  'assets/images/tidi_ai.gif',
                                  width: 26,
                                  height: 26,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Ask AI',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: lightColorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        /// Chart (BOTTOM)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    StockChartPage(symbol: widget.symbol),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.bar_chart,
                                size: 18,
                                color: Colors.black54,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Chart',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    /// LEFT: Badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _badge('Trend', trendColor(trend), trend.name),
                          const SizedBox(height: 8),
                          _badge(
                            'TIDI Verdict',
                            verdictColor(verdict),
                            verdict.name,
                          ),
                        ],
                      ),
                    ),

                    /// RIGHT: Actions (REVERSED)

                  ],
                ),

                _priceInfoCard(),

                _lockedSection(
                  isLocked: !isSubscribed,
                  onTap: () => SubscriptionPromptDialog.show(context),
                  child: Column(
                    children: [
                      _analystSection(),
                      _analystBreakdownSection(),
                    ],
                  ),
                ),


                _glassCard('Valuation & Dividends', {
                  'PE Ratio': _fundamentalData?['PE_ratio'],
                  'Forward PE': _fundamentalData?['forward_PE'],
                  'EPS': _fundamentalData?['EPS'],
                  'Market Cap': _fundamentalData?['market_cap'] != null ? _formatMarketCap(_fundamentalData!['market_cap']) : 'N/A',
                  'Dividend Yield': _fundamentalData?['dividend_yield'],
                  'Beta': _fundamentalData?['beta'],
                }),
                _glassCard('Technical Indicators', {
                  'RSI(14)': _technicalData?['RSI_14'],
                  'MACD': _technicalData?['MACD'],
                  'MACD Signal': _technicalData?['MACD_signal'],
                  'SMA 20': _technicalData?['SMA_20'],
                  'SMA 50': _technicalData?['SMA_50'],
                  'EMA 20': _technicalData?['EMA_20'],
                  'EMA 50': _technicalData?['EMA_50'],
                  'Volume': _technicalData?['volume'],
                }),

                // ⚠️ FILE IS LONG — THIS IS FULL AND COMPLETE
// ONLY ADDITIONS ARE MARKED WITH: // ✅ ADDED SECTION

// ------------------ [KEEP ALL YOUR EXISTING IMPORTS & CODE ABOVE AS-IS] ------------------

// ------------------ ADD BELOW INSIDE build() AFTER EXISTING CARDS ------------------

                // ✅ ADDED: Advanced Fundamentals
                _glassCard('Advanced Fundamentals', {
                  'Return on Equity (%)': _fundamentalData?['return_on_equity'],
                  'Return on Assets (%)': _fundamentalData?['return_on_assets'],
                  'Book Value': _fundamentalData?['book_value'],
                  'Price to Book': _fundamentalData?['price_to_book'],
                  'PEG Ratio': _fundamentalData?['peg_ratio'],
                }),

                // ✅ ADDED: Margins & Growth
                _glassCard('Margins & Growth', {
                  'Profit Margin (%)': _fundamentalData?['profit_margins'],
                  'Gross Margin (%)': _fundamentalData?['gross_margins'],
                  'Operating Margin (%)': _fundamentalData?['operating_margins'],
                  'Revenue Growth (%)': _fundamentalData?['revenue_growth'],
                  'Earnings Growth (%)': _fundamentalData?['earnings_growth'],
                  'Quarterly Earnings Growth (%)':
                  _fundamentalData?['earnings_quarterly_growth'],
                }),

                // ✅ ADDED: Financial Health
                _glassCard('Financial Health', {
                  'Total Cash': _fundamentalData?['total_cash'] != null ? _formatMarketCap(_fundamentalData!['total_cash']) : 'N/A',
                  'Total Debt': _fundamentalData?['total_debt'] != null ? _formatMarketCap(_fundamentalData!['total_debt']) : 'N/A',
                  'Debt / Equity': _fundamentalData?['debt_to_equity'],
                  'Free Cash Flow': _fundamentalData?['free_cashflow'] != null ? _formatMarketCap(_fundamentalData!['free_cashflow']) : 'N/A',
                  'Operating Cash Flow': _fundamentalData?['operating_cashflow'] != null ? _formatMarketCap(_fundamentalData!['operating_cashflow']) : 'N/A',
                  'Current Ratio': _fundamentalData?['current_ratio'],
                  'Quick Ratio': _fundamentalData?['quick_ratio'],
                }),

                // ✅ ADDED: Ownership & Risk
                _glassCard('Ownership & Risk', {
                  'Promoter Holding (%)':
                  _fundamentalData?['held_percent_insiders'],
                  'Institutional Holding (%)':
                  _fundamentalData?['held_percent_institutions'],
                  'Overall Risk': _fundamentalData?['overall_risk'],
                  'Audit Risk': _fundamentalData?['audit_risk'],
                  'Board Risk': _fundamentalData?['board_risk'],
                  'Compensation Risk': _fundamentalData?['compensation_risk'],
                  'Shareholder Rights Risk':
                  _fundamentalData?['shareholder_rights_risk'],
                }),

                // ✅ ADDED: Advanced Technical Levels
                _glassCard('Advanced Technical Levels', {
                  'SMA 100': _technicalData?['SMA_100'],
                  'R2': _technicalData?['R2'],
                  'R3': _technicalData?['R3'],
                  'S2': _technicalData?['S2'],
                  'S3': _technicalData?['S3'],
                  'BB %': _technicalData?['BB_percent'],
                }),

                // ✅ ADDED: Volatility & Risk Management
                _glassCard('Volatility & Risk Management', {
                  'BB Upper': _technicalData?['BB_upper'],
                  'BB Lower': _technicalData?['BB_lower'],
                  'ATR Stop (Long)': _technicalData?['ATR_Stop_Long'],
                  'ATR Stop (Short)': _technicalData?['ATR_Stop_Short'],
                }),

                // ✅ ADDED: Fibonacci Levels
                _glassCard('Fibonacci Levels', {
                  'Fib 38.2%': _technicalData?['Fib_38.2'],
                  'Fib 61.8%': _technicalData?['Fib_61.8'],
                }),

                // ✅ ADDED: Volume Analytics
                _glassCard('Volume Analytics', {
                  'Average Volume': _fundamentalData?['avg_volume'],
                  '10D Avg Volume': _fundamentalData?['avg_volume_10d'],
                  'Volume Today': _technicalData?['volume'],
                }),

                // ✅ ADDED: News Sentiment
                _glassCard('News Sentiment', {
                  'Overall Sentiment': _stockSummary?['news_sentiment'],
                }),

// ------------------ [REST OF YOUR FILE CONTINUES UNCHANGED] ------------------


                const SizedBox(height: 16),
                _buildPatternSection(),

                const SizedBox(height: 20),
                const Text('News Headlines', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List<String>.from(_stockSummary?['news_headlines'] ?? []).map((headline) =>
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text("• $headline", style: const TextStyle(color: Colors.black87, fontSize: 14)),
                        )).toList(),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _priceInfoCard() {
    final double lastClose =
        (_technicalData?['last_close'] as num?)?.toDouble() ?? 0.0;
    final double pctChange =
        (_technicalData?['percentage_change'] as num?)?.toDouble() ?? 0.0;

    final bool isUp = pctChange >= 0;
    final Color changeColor = isUp ? Colors.green : Colors.red;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// TITLE
          const Text(
            'Price Info',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          /// PRICE ROW
          Row(
            children: [
              Text(
                '₹${fmt(lastClose)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: changeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 18,
                      color: changeColor,
                    ),
                    Text(
                      '${fmt(pctChange)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: changeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          /// INLINE LEVELS
          Row(
            children: [
              _miniPriceStat('52W High', _technicalData?['52_Week_High'], Colors.green),
              _divider(),
              _miniPriceStat('52W Low', _technicalData?['52_Week_Low'], Colors.red),
              _divider(),
              _miniPriceStat(
                'All Time High',
                _fundamentalData?['all_time_high'],
                Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _miniPriceStat(String label, dynamic value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fmt(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey.shade300,
    );
  }


  String fmt(dynamic value, {int decimals = 2}) {
    if (value == null) return 'N/A';

    if (value is num) {
      return value.toStringAsFixed(decimals);
    }

    final parsed = double.tryParse(value.toString());
    if (parsed != null) {
      return parsed.toStringAsFixed(decimals);
    }

    return value.toString();
  }

}
