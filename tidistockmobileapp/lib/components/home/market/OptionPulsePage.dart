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
  bool _initialLoading = true;
  String? errorMessage;
  Map<String, dynamic>? niftyData;
  Map<String, dynamic>? bankNiftyData;
  Timer? _autoRefreshTimer;

  bool get _hasData => niftyData != null || bankNiftyData != null;

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
      // Wrap each call individually so one failure doesn't cancel the other.
      await Future.wait([
        api.getCachedOptionPulsePCR(
          symbol: 'NIFTY',
          onData: (data, {required fromCache}) {
            if (!mounted) return;
            setState(() {
              niftyData = data is Map<String, dynamic> ? data : null;
              if (_hasData) errorMessage = null;
            });
          },
        ).catchError((_) {}),
        api.getCachedOptionPulsePCR(
          symbol: 'BANKNIFTY',
          onData: (data, {required fromCache}) {
            if (!mounted) return;
            setState(() {
              bankNiftyData = data is Map<String, dynamic> ? data : null;
              if (_hasData) errorMessage = null;
            });
          },
        ).catchError((_) {}),
      ]);

      if (!mounted) return;
      if (!_hasData) {
        setState(() {
          errorMessage = 'Failed to load option data. Pull down to refresh.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!_hasData) {
        setState(() {
          errorMessage = 'Network error. Pull down to refresh.';
        });
      }
    } finally {
      if (mounted && _initialLoading) {
        setState(() {
          _initialLoading = false;
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
    // Show skeleton shimmer only on very first load with no data
    if (_initialLoading && !_hasData) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _skeletonCard(),
          const SizedBox(height: 16),
          _skeletonCard(),
        ],
      );
    }

    if (errorMessage != null && !_hasData) {
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
                    _initialLoading = true;
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

  // ── Skeleton shimmer card ──

  Widget _skeletonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              _shimmerBox(width: 80, height: 22),
              const Spacer(),
              _shimmerBox(width: 70, height: 28, radius: 20),
            ],
          ),
          const SizedBox(height: 14),
          // Metrics row
          Row(
            children: [
              Expanded(child: _shimmerBox(height: 56, radius: 14)),
              const SizedBox(width: 10),
              Expanded(child: _shimmerBox(height: 56, radius: 14)),
              const SizedBox(width: 10),
              Expanded(child: _shimmerBox(height: 56, radius: 14)),
            ],
          ),
          const SizedBox(height: 18),
          // Bar 1
          _shimmerBox(width: 100, height: 14),
          const SizedBox(height: 8),
          _shimmerBox(height: 14, radius: 6),
          const SizedBox(height: 14),
          // Bar 2
          _shimmerBox(width: 60, height: 14),
          const SizedBox(height: 8),
          _shimmerBox(height: 14, radius: 6),
          const SizedBox(height: 18),
          // Strike rows
          Row(
            children: [
              Expanded(child: _shimmerBox(height: 70, radius: 12)),
              const SizedBox(width: 10),
              Expanded(child: _shimmerBox(height: 70, radius: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _shimmerBox(height: 70, radius: 12)),
              const SizedBox(width: 10),
              Expanded(child: _shimmerBox(height: 70, radius: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox({double? width, required double height, double radius = 8}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        // Repeat the pulse by rebuilding
        return AnimatedOpacity(
          opacity: value,
          duration: const Duration(milliseconds: 800),
          child: child,
        );
      },
      child: _PulseShimmer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }

  // ── Data cards ──

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

/// Pulsing shimmer effect widget.
class _PulseShimmer extends StatefulWidget {
  final Widget child;
  const _PulseShimmer({required this.child});

  @override
  State<_PulseShimmer> createState() => _PulseShimmerState();
}

class _PulseShimmerState extends State<_PulseShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.3, end: 1.0)),
      child: widget.child,
    );
  }
}
