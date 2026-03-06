import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';

/// Horizontal scrollable broker holdings cards matching alphab2b BrokerHoldingsCards.js.
///
/// Shows "ALL" card + per-broker cards with holdings count, total value, P&L.
class BrokerHoldingsCards extends StatelessWidget {
  final List<BrokerConnection> connectedBrokers;
  final String selectedBroker;
  final ValueChanged<String> onBrokerSelect;
  final List<Map<String, dynamic>> holdingsFromDB;
  final bool holdingsLoading;
  final double Function(String symbol)? getLTPForSymbol;

  const BrokerHoldingsCards({
    super.key,
    required this.connectedBrokers,
    required this.selectedBroker,
    required this.onBrokerSelect,
    required this.holdingsFromDB,
    this.holdingsLoading = false,
    this.getLTPForSymbol,
  });

  static final _currencyFormat = NumberFormat('#,##,###');

  int _getHoldingsCount(String broker) {
    if (broker == 'ALL') return holdingsFromDB.length;
    return holdingsFromDB.where((h) => h['broker'] == broker).length;
  }

  double _getTotalValue(String broker) {
    final holdings = broker == 'ALL'
        ? holdingsFromDB
        : holdingsFromDB.where((h) => h['broker'] == broker).toList();

    return holdings.fold(0.0, (total, h) {
      final symbol = (h['symbol'] ?? '').toString();
      final ltp = getLTPForSymbol != null ? getLTPForSymbol!(symbol) : (h['ltp'] as num?)?.toDouble();
      final avgPrice = (h['avgPrice'] as num?)?.toDouble() ?? 0;
      final priceToUse = (ltp != null && ltp != 0) ? ltp : avgPrice;
      final qty = (h['quantity'] as num?)?.toDouble() ?? 0;
      return total + priceToUse * qty;
    });
  }

  double _getTotalInvested(String broker) {
    final holdings = broker == 'ALL'
        ? holdingsFromDB
        : holdingsFromDB.where((h) => h['broker'] == broker).toList();

    return holdings.fold(0.0, (total, h) {
      final avgPrice = (h['avgPrice'] as num?)?.toDouble() ?? 0;
      final qty = (h['quantity'] as num?)?.toDouble() ?? 0;
      return total + avgPrice * qty;
    });
  }

  double? _getTotalPnL(String broker) {
    final holdings = broker == 'ALL'
        ? holdingsFromDB
        : holdingsFromDB.where((h) => h['broker'] == broker).toList();

    final validHoldings = holdings.where((h) {
      final symbol = (h['symbol'] ?? '').toString();
      final ltp = getLTPForSymbol != null ? getLTPForSymbol!(symbol) : (h['ltp'] as num?)?.toDouble();
      return ltp != null && ltp != 0;
    }).toList();

    if (validHoldings.isEmpty) return null;

    double totalValue = 0;
    double totalInvested = 0;
    for (final h in validHoldings) {
      final symbol = (h['symbol'] ?? '').toString();
      final ltp = getLTPForSymbol != null ? getLTPForSymbol!(symbol) : (h['ltp'] as num?)?.toDouble() ?? 0;
      final avgPrice = (h['avgPrice'] as num?)?.toDouble() ?? 0;
      final qty = (h['quantity'] as num?)?.toDouble() ?? 0;
      totalValue += (ltp ?? 0) * qty;
      totalInvested += avgPrice * qty;
    }
    return totalValue - totalInvested;
  }

  double? _getPnLPercent(String broker) {
    final pnl = _getTotalPnL(broker);
    if (pnl == null) return null;
    final invested = _getTotalInvested(broker);
    if (invested <= 0) return null;
    return (pnl / invested) * 100;
  }

  Color _brokerColor(String broker) {
    switch (broker.toLowerCase()) {
      case 'zerodha': return const Color(0xFF387ED1);
      case 'angel one': return const Color(0xFFFF6B00);
      case 'groww': return const Color(0xFF5367FF);
      case 'upstox': return const Color(0xFF6C3CE0);
      case 'dhan': return const Color(0xFF00B386);
      case 'fyers': return const Color(0xFF1DB954);
      case 'icici direct': return const Color(0xFFB82E1F);
      case 'kotak': return const Color(0xFFED1C24);
      case 'hdfc securities': return const Color(0xFF004C8F);
      default: return const Color(0xFF1A237E);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (holdingsFromDB.isEmpty && !holdingsLoading) return const SizedBox.shrink();

    // Collect unique broker names from holdings
    final brokerNames = <String>{'ALL'};
    for (final h in holdingsFromDB) {
      final b = h['broker']?.toString();
      if (b != null && b.isNotEmpty) brokerNames.add(b);
    }
    // Also add from connected brokers
    for (final b in connectedBrokers) {
      brokerNames.add(b.broker);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text("Broker Holdings",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 120,
          child: holdingsLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: brokerNames.length,
                  itemBuilder: (ctx, i) {
                    final broker = brokerNames.elementAt(i);
                    return _BrokerCard(
                      broker: broker,
                      isSelected: selectedBroker == broker,
                      holdingsCount: _getHoldingsCount(broker),
                      totalValue: _getTotalValue(broker),
                      pnl: _getTotalPnL(broker),
                      pnlPercent: _getPnLPercent(broker),
                      color: broker == 'ALL' ? const Color(0xFF1A237E) : _brokerColor(broker),
                      isExpired: broker != 'ALL' &&
                          connectedBrokers.any((b) => b.broker == broker && !b.isEffectivelyConnected),
                      onTap: () => onBrokerSelect(broker),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BrokerCard extends StatelessWidget {
  final String broker;
  final bool isSelected;
  final int holdingsCount;
  final double totalValue;
  final double? pnl;
  final double? pnlPercent;
  final Color color;
  final bool isExpired;
  final VoidCallback onTap;

  const _BrokerCard({
    required this.broker,
    required this.isSelected,
    required this.holdingsCount,
    required this.totalValue,
    required this.pnl,
    required this.pnlPercent,
    required this.color,
    required this.isExpired,
    required this.onTap,
  });

  static final _currencyFormat = NumberFormat('#,##,###');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    broker == 'ALL' ? 'All Brokers' : broker,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : Colors.grey.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isExpired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text("Expired",
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$holdingsCount holdings",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text("\u20B9${_currencyFormat.format(totalValue.round())}",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
              ],
            ),
            if (pnl != null)
              Row(
                children: [
                  Icon(
                    pnl! >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: pnl! >= 0 ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  Text(
                    "${pnl! >= 0 ? '+' : ''}\u20B9${_currencyFormat.format(pnl!.abs().round())}",
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: pnl! >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  if (pnlPercent != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      "(${pnlPercent!.toStringAsFixed(1)}%)",
                      style: TextStyle(
                        fontSize: 10,
                        color: pnl! >= 0 ? Colors.green.shade600 : Colors.red.shade600,
                      ),
                    ),
                  ],
                ],
              )
            else
              Text("—", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}
