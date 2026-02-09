import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

class OptionPulsePage extends StatefulWidget {
  const OptionPulsePage({super.key});

  @override
  State<OptionPulsePage> createState() => _OptionPulsePageState();
}

class _OptionPulsePageState extends State<OptionPulsePage> {
  bool loading = true;
  String? errorMessage;
  Map<String, dynamic>? niftyData;
  Map<String, dynamic>? bankNiftyData;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    fetchData();
    _autoRefreshTimer = Timer.periodic(
      const Duration(minutes: 4),
      (_) => fetchData(),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchData() async {
    final api = ApiService();
    try {
      await Future.wait([
        api.getCachedOptionPulsePCR(
          symbol: 'NIFTY',
          onData: (data, {required fromCache}) {
            if (!mounted) return;
            setState(() {
              niftyData = data is Map<String, dynamic> ? data : null;
              loading = false;
              if (niftyData != null || bankNiftyData != null) errorMessage = null;
            });
          },
        ),
        api.getCachedOptionPulsePCR(
          symbol: 'BANKNIFTY',
          onData: (data, {required fromCache}) {
            if (!mounted) return;
            setState(() {
              bankNiftyData = data is Map<String, dynamic> ? data : null;
              loading = false;
              if (niftyData != null || bankNiftyData != null) errorMessage = null;
            });
          },
        ),
      ]);

      if (!mounted) return;
      if (niftyData == null && bankNiftyData == null) {
        setState(() {
          errorMessage = 'Failed to load option data. Pull down to refresh.';
          loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (niftyData == null && bankNiftyData == null) {
        setState(() {
          errorMessage = 'Network error. Pull down to refresh.';
          loading = false;
        });
      }
    }
  }

  String formatCompact(dynamic value) {
    if (value == null) return '-';
    return NumberFormat.compact(locale: 'en_IN').format(value);
  }

  String formatPrice(dynamic value) {
    if (value == null) return '-';
    return NumberFormat('#,##0.00', 'en_IN').format(value);
  }

  String formatStrike(dynamic value) {
    if (value == null) return '-';
    return NumberFormat('#,##0', 'en_IN').format(value);
  }

  Color sentimentColor(String? sentiment) {
    switch (sentiment) {
      case 'Bullish':
      case 'Strong Bullish':
        return Colors.green;
      case 'Bearish':
      case 'Strong Bearish':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  double parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Option Pulse",
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (errorMessage != null && niftyData == null && bankNiftyData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    loading = true;
                    errorMessage = null;
                  });
                  fetchData();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.black,
      onRefresh: fetchData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (niftyData != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _indexCard(niftyData!),
            ),
          if (niftyData != null) const SizedBox(height: 16),
          if (bankNiftyData != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _indexCard(bankNiftyData!),
            ),
        ],
      ),
    );
  }

  Widget _indexCard(Map<String, dynamic> data) {
    final sentiment = data['sentiment'] as String? ?? 'Neutral';
    final sColor = sentimentColor(sentiment);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Symbol + Sentiment
          Row(
            children: [
              Text(
                data['symbol'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: sColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sColor, width: 1),
                ),
                child: Text(
                  sentiment,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: sColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Key Metrics Row
          _keyMetricsRow(data),
          const SizedBox(height: 18),

          // OI Comparison
          _comparisonBar(
            label: 'Open Interest',
            leftValue: parseNum(data['totalCallOI']),
            rightValue: parseNum(data['totalPutOI']),
          ),
          const SizedBox(height: 14),

          // Volume Comparison
          _comparisonBar(
            label: 'Volume',
            leftValue: parseNum(data['totalCallVolume']),
            rightValue: parseNum(data['totalPutVolume']),
          ),
          const SizedBox(height: 18),

          // Highest OI
          _strikeRow(
            title: 'Highest OI',
            callData: data['highestCallOI'],
            putData: data['highestPutOI'],
            valueKey: 'oi',
          ),
          const SizedBox(height: 12),

          // Highest OI Change
          _strikeRow(
            title: 'OI Change',
            callData: data['highestCallOIChange'],
            putData: data['highestPutOIChange'],
            valueKey: 'change',
          ),
        ],
      ),
    );
  }

  Widget _keyMetricsRow(Map<String, dynamic> data) {
    final pcr = parseNum(data['pcr']);
    Color pcrColor = Colors.orange;
    if (pcr > 1.0) pcrColor = Colors.green;
    if (pcr < 0.7) pcrColor = Colors.red;

    return Row(
      children: [
        _metricBox(
          'Spot',
          formatPrice(data['underlyingValue']),
          Colors.black,
        ),
        const SizedBox(width: 10),
        _metricBox(
          'PCR',
          pcr.toStringAsFixed(3),
          pcrColor,
        ),
        const SizedBox(width: 10),
        _metricBox(
          'Max Pain',
          formatStrike(data['maxPain']),
          Colors.deepPurple,
        ),
      ],
    );
  }

  Widget _metricBox(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonBar({
    required String label,
    required double leftValue,
    required double rightValue,
  }) {
    final total = leftValue + rightValue;
    final leftRatio = total > 0 ? leftValue / total : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              formatCompact(leftValue),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (leftRatio * 100).round().clamp(1, 99),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                          ),
                        ),
                      ),
                      Flexible(
                        flex: ((1 - leftRatio) * 100).round().clamp(1, 99),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCompact(rightValue),
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Calls', style: TextStyle(color: Colors.red.shade400, fontSize: 11)),
            Text('Puts', style: TextStyle(color: Colors.green.shade400, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _strikeRow({
    required String title,
    required dynamic callData,
    required dynamic putData,
    required String valueKey,
  }) {
    final callStrike = callData is Map ? callData['strike'] : null;
    final callValue = callData is Map ? callData[valueKey] : null;
    final putStrike = putData is Map ? putData['strike'] : null;
    final putValue = putData is Map ? putData[valueKey] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _strikeBox(
                'Call',
                formatStrike(callStrike),
                formatCompact(callValue),
                Colors.red,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _strikeBox(
                'Put',
                formatStrike(putStrike),
                formatCompact(putValue),
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _strikeBox(String type, String strike, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strike,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
