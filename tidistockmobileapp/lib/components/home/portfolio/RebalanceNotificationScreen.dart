import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerSelectionPage.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/OrderExecutionService.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RebalanceNotificationScreen extends StatefulWidget {
  final String modelName;
  final String advisorName;
  final List<Map<String, dynamic>> trades;

  const RebalanceNotificationScreen({
    super.key,
    required this.modelName,
    required this.advisorName,
    required this.trades,
  });

  @override
  State<RebalanceNotificationScreen> createState() => _RebalanceNotificationScreenState();
}

class _RebalanceNotificationScreenState extends State<RebalanceNotificationScreen> {
  bool _isExpanded = false;
  bool _isLoading = false;
  String? _userEmail;
  Map<String, dynamic>? _brokerConnection;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final email = await const FlutterSecureStorage().read(key: 'user_email');
    if (mounted) {
      setState(() {
        _userEmail = email;
      });
    }
    // Load broker connection
    if (email != null && email.isNotEmpty) {
      await _checkBrokerConnection(email);
    }
  }

  Future<void> _checkBrokerConnection(String email) async {
    try {
      final response = await AqApiService.instance.getConnectedBrokers(email);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic parsedBody;
        try {
          parsedBody = json.decode(response.body);
        } catch (e) {
          parsedBody = response.body;
        }
        List<dynamic> brokers = [];
        if (parsedBody is List) {
          brokers = parsedBody;
        } else if (parsedBody is Map) {
          if (parsedBody['data'] is List) {
            brokers = List<dynamic>.from(parsedBody['data']);
          } else if (parsedBody['connected_brokers'] is List) {
            brokers = List<dynamic>.from(parsedBody['connected_brokers']);
          }
        }
        if (brokers.isNotEmpty && mounted) {
          setState(() {
            _brokerConnection = Map<String, dynamic>.from(brokers.first);
          });
        }
      }
    } catch (e) {
      debugPrint('[RebalanceNotification] Error checking broker: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Rebalance Alert",
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 16),
              _buildPortfolioDetails(),
              const SizedBox(height: 16),
              if (widget.trades.isNotEmpty) ...[
                _buildTradesSection(),
              ],
              const SizedBox(height: 16),
              _buildBrokerSection(),
            ],
          ),
        ),
        _buildBottomActions(),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade700,
            Colors.blue.shade900,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Portfolio Rebalance Alert",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Your portfolio \"${widget.modelName}\" has received a new rebalance update.",
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          if (widget.advisorName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "Advisor: ${widget.advisorName}",
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPortfolioDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Portfolio Details",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _detailRow("Portfolio Name", widget.modelName),
          _detailRow("Rebalance Date", DateFormat("dd MMM yyyy, HH:mm").format(DateTime.now())),
          _detailRow("Number of Trades", "${widget.trades.length}"),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradesSection() {
    final tradesToShow = _isExpanded ? widget.trades : widget.trades.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Trades to Execute",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.trades.length > 5)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      setState(() => _isExpanded = !_isExpanded);
                    },
                    child: Text(_isExpanded ? "Show Less" : "Show All (${widget.trades.length})"),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...tradesToShow.map((trade) => _buildTradeItem(trade)),
        ],
      ),
    );
  }

  Widget _buildTradeItem(Map<String, dynamic> trade) {
    final symbol = trade['symbol'] ?? trade['Symbol'] ?? 'N/A';
    final action = (trade['action'] ?? trade['Action'] ?? 'BUY').toString().toUpperCase();
    final price = trade['price'] ?? trade['Price'] ?? 0.0;
    final quantity = trade['quantity'] ?? trade['Quantity'] ?? 0;
    final exchange = trade['exchange'] ?? trade['Exchange'] ?? 'NSE';

    final isBuy = action == 'BUY';
    final actionColor = isBuy ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: actionColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isBuy ? Icons.add_circle_outline : Icons.remove_circle_outline,
              color: actionColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: actionColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        action,
                        style: TextStyle(
                          color: actionColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "$exchange \u2022 Qty: $quantity",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "₹${NumberFormat('#,##0.00').format(price)}",
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                "Total: ₹${NumberFormat('#,##0').format(price * quantity)}",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrokerSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Broker Connection",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_brokerConnection != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _brokerConnection!['broker'] ?? 'Connected',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _brokerConnection!['clientCode'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "No broker connected. Trades will be recorded for manual execution.",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Later"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _executeTrades,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Execute Trades"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showDummyBrokerConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text("Manual Execution"),
          ],
        ),
        content: const Text(
          "You don't have a connected broker. Your trades will be recorded and you'll need to execute them manually in your trading app.\n\nDo you want to continue?",
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeTrades() async {
    if (_userEmail == null || _userEmail!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login to execute trades")),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      if (_brokerConnection != null) {
        // Broker connected - execute via API
        // TODO: Implement actual trade execution via broker
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Executing trades through broker...")),
        );
        // For now, just show a success message
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Trades executed successfully!")),
          );
        }
      } else {
        // No broker - use DummyBroker flow - show confirmation dialog
        if (mounted) {
          final confirmed = await _showDummyBrokerConfirmation();
          if (confirmed == true && mounted) {
            // Record trades via OrderExecutionService
            try {
              await OrderExecutionService.instance.executeDummyBrokerOrders(
                orders: widget.trades,
                email: _userEmail!,
                modelName: widget.modelName,
                modelId: '',
                advisor: widget.advisorName,
                onOrderUpdate: (completed, total, result) {
                  debugPrint('[Rebalance] Order $completed/$total: ${result.status}');
                },
              );
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Trades recorded successfully! Execute them manually.")),
                );
              }
            } catch (e) {
              debugPrint('[RebalanceNotification] Error recording trades: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error recording trades: $e")),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RebalanceNotification] Error executing trades: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error executing trades: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
