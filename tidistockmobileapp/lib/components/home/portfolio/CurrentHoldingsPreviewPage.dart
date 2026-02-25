import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/portfolio_holding.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/DataRepository.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'RebalanceReviewPage.dart';

/// Shows the user's current holdings in this portfolio before they proceed
/// to review and execute the rebalance orders.
class CurrentHoldingsPreviewPage extends StatefulWidget {
  final ModelPortfolio portfolio;
  final String email;

  const CurrentHoldingsPreviewPage({
    super.key,
    required this.portfolio,
    required this.email,
  });

  @override
  State<CurrentHoldingsPreviewPage> createState() =>
      _CurrentHoldingsPreviewPageState();
}

class _CurrentHoldingsPreviewPageState
    extends State<CurrentHoldingsPreviewPage> {
  List<PortfolioHolding> _holdings = [];
  bool _loading = true;
  double _totalInvested = 0;
  double _totalCurrent = 0;

  final _currencyFmt = NumberFormat('#,##,###');

  @override
  void initState() {
    super.initState();
    _fetchHoldings();
  }

  Future<void> _fetchHoldings() async {
    try {
      final response = await AqApiService.instance.getSubscriptionRawAmount(
        email: widget.email,
        modelName: widget.portfolio.modelName,
      );

      if (response.statusCode == 200 && mounted) {
        final data = await DataRepository.parseJsonMap(response.body);
        final subData = data['data'];
        if (subData != null) {
          _parseHoldings(subData);
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  void _parseHoldings(Map<String, dynamic> subData) {
    final userNetPf = subData['user_net_pf_model'] ??
        subData['userNetPfModel'] ??
        subData['net_pf_model'] ??
        subData['holdings'] ??
        [];

    final List<PortfolioHolding> parsed = [];

    if (userNetPf is List && userNetPf.isNotEmpty) {
      final latest = userNetPf.last;
      List<dynamic> stockList = [];
      if (latest is List) {
        stockList = latest;
      } else if (latest is Map) {
        stockList = latest['stocks'] ?? latest['holdings'] ?? [];
      }
      for (final s in stockList) {
        if (s is Map<String, dynamic>) {
          parsed.add(PortfolioHolding.fromJson(s));
        }
      }
    }

    double invested = 0;
    double current = 0;
    final rawAmounts = subData['subscription_amount_raw'] ??
        subData['subscriptionAmountRaw'] ??
        [];

    if (rawAmounts is List && rawAmounts.isNotEmpty) {
      final latest = rawAmounts.last;
      if (latest is Map) {
        invested = (latest['totalInvestment'] ?? latest['invested'] ?? 0).toDouble();
        current = (latest['currentValue'] ?? latest['current'] ?? invested).toDouble();
      }
    }

    if (invested == 0 && parsed.isNotEmpty) {
      for (final h in parsed) {
        invested += h.investedValue;
        current += h.currentValue;
      }
    }

    setState(() {
      _holdings = parsed;
      _totalInvested = invested;
      _totalCurrent = current;
    });
  }

  void _proceedToRebalance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RebalanceReviewPage(
          portfolio: widget.portfolio,
          email: widget.email,
        ),
      ),
    );
  }

  double get _totalPnl => _totalCurrent - _totalInvested;
  double get _totalPnlPct =>
      _totalInvested > 0 ? (_totalPnl / _totalInvested) * 100 : 0;

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: null,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchHoldings,
                    child: _holdings.isEmpty
                        ? _buildEmptyState()
                        : _buildHoldingsList(),
                  ),
          ),
          _buildBottomCta(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Holdings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      widget.portfolio.modelName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF757575),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_loading && _totalInvested > 0) ...[
            const SizedBox(height: 16),
            _buildSummaryCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final isProfit = _totalPnl >= 0;
    final pnlColor = isProfit ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryItem(
              'Invested',
              '₹${_currencyFmt.format(_totalInvested.round())}',
              const Color(0xFF424242),
            ),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFE0E0E0)),
          Expanded(
            child: _summaryItem(
              'Current',
              '₹${_currencyFmt.format(_totalCurrent.round())}',
              const Color(0xFF424242),
            ),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFE0E0E0)),
          Expanded(
            child: _summaryItem(
              'P&L',
              '${isProfit ? '+' : ''}${_totalPnlPct.toStringAsFixed(1)}%',
              pnlColor,
              subtitle: '${isProfit ? '+' : ''}₹${_currencyFmt.format(_totalPnl.abs().round())}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color valueColor,
      {String? subtitle}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: valueColor),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 36,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Holdings Yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'This will be your initial investment in this portfolio. Review the recommended stocks below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF757575),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHoldingsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _holdings.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildListHeader();
        return _buildHoldingCard(_holdings[index - 1]);
      },
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '${_holdings.length} Holding${_holdings.length != 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF424242),
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'Qty',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
            ),
          ),
          const Expanded(
            flex: 3,
            child: Text(
              'Invested',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
            ),
          ),
          const Expanded(
            flex: 3,
            child: Text(
              'P&L',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldingCard(PortfolioHolding h) {
    final pnl = h.pnl ?? 0;
    final pnlPct = h.pnlPercent ?? 0;
    final isProfit = pnl >= 0;
    final pnlColor =
        isProfit ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Symbol + exchange
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.symbol,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                if (h.exchange != null)
                  Text(
                    h.exchange!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
              ],
            ),
          ),
          // Quantity
          Expanded(
            flex: 2,
            child: Text(
              '${h.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF424242),
              ),
            ),
          ),
          // Invested value
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${_currencyFmt.format(h.investedValue.round())}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF424242),
                  ),
                ),
                Text(
                  '@ ₹${h.avgPrice.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
          ),
          // P&L
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  h.ltp != null
                      ? '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(1)}%'
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pnlColor,
                  ),
                ),
                if (h.ltp != null)
                  Text(
                    '${isProfit ? '+' : '-'}₹${_currencyFmt.format(pnl.abs().round())}',
                    style: TextStyle(fontSize: 10, color: pnlColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCta() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFEEEEEE))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Info note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Color(0xFFF9A825)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _holdings.isEmpty
                          ? 'Review the rebalance recommendations on the next screen.'
                          : 'Review and confirm the buy/sell orders on the next screen.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5D4037),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _proceedToRebalance,
                icon: const Icon(Icons.sync_rounded, size: 20),
                label: const Text(
                  'Proceed to Review Rebalance',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: const Color(0xFFBDBDBD),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
