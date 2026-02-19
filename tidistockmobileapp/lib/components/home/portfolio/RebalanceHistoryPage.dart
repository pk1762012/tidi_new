import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/models/rebalance_entry.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

/// Chronological list of all past rebalances for a model portfolio.
class RebalanceHistoryPage extends StatelessWidget {
  final ModelPortfolio portfolio;
  final String email;

  const RebalanceHistoryPage({
    super.key,
    required this.portfolio,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final history = portfolio.rebalanceHistory.reversed.toList();

    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Rebalance History",
      child: history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text("No rebalance history available.",
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: history.length,
              itemBuilder: (context, index) {
                return _rebalanceCard(context, history[index], index == 0);
              },
            ),
    );
  }

  Widget _rebalanceCard(BuildContext context, RebalanceHistoryEntry entry, bool isLatest) {
    final exec = entry.getExecutionForUser(email);
    final dateStr = entry.rebalanceDate != null
        ? DateFormat("dd MMM yyyy").format(entry.rebalanceDate!)
        : "Unknown date";
    final stockCount = entry.adviceEntries.length;

    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (exec?.isExecuted == true) {
      statusLabel = "Executed";
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (exec?.status.toLowerCase() == 'partial') {
      statusLabel = "Partial";
      statusColor = Colors.orange;
      statusIcon = Icons.warning_rounded;
    } else if (exec?.isPending == true) {
      statusLabel = "Pending";
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
    } else {
      statusLabel = exec?.status ?? "Unknown";
      statusColor = Colors.grey;
      statusIcon = Icons.help_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isLatest ? Border.all(color: Colors.blue.shade200, width: 1.5) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        leading: Icon(statusIcon, color: statusColor, size: 22),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(dateStr,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      if (isLatest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text("Latest",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                        ),
                      ],
                    ],
                  ),
                  Text("$stockCount stocks",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
            ),
          ],
        ),
        children: [
          // Advice entries details
          if (entry.adviceEntries.isNotEmpty) ...[
            const Divider(height: 16),
            ...entry.adviceEntries.map((stock) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(stock.symbol,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text("${stock.exchange ?? 'NSE'}",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        textAlign: TextAlign.center),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text("Wt: ${stock.weight.toStringAsFixed(1)}",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        textAlign: TextAlign.right),
                    ),
                  ],
                ),
              );
            }),
          ],
          // Execution details
          if (exec != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Broker: ${exec.userBroker ?? 'N/A'}",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  if (exec.executionDate != null)
                    Text("Executed: ${DateFormat('dd MMM').format(exec.executionDate!)}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
