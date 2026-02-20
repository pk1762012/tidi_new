import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerAuthPage.dart';
import 'BrokerCredentialPage.dart';
import 'BrokerSelectionPage.dart';
import 'ExecutionStatusPage.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/service/OrderExecutionService.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RebalanceNotificationScreen extends StatefulWidget {
  final String modelName;
  final String advisorName;
  final List<Map<String, dynamic>> trades;
  final String? modelId;
  final String? uniqueId;

  const RebalanceNotificationScreen({
    super.key,
    required this.modelName,
    required this.advisorName,
    required this.trades,
    this.modelId,
    this.uniqueId,
  });

  @override
  State<RebalanceNotificationScreen> createState() => _RebalanceNotificationScreenState();
}

class _RebalanceNotificationScreenState extends State<RebalanceNotificationScreen> {
  bool _isExpanded = false;
  bool _isLoading = false;
  String? _userEmail;
  BrokerConnection? _brokerConnection;
  String? _resolvedModelId;

  @override
  void initState() {
    super.initState();
    _resolvedModelId = widget.modelId;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final email = await const FlutterSecureStorage().read(key: 'user_email');
    if (mounted) {
      setState(() {
        _userEmail = email;
      });
    }
    // Load broker connection and fetch model_id if needed
    if (email != null && email.isNotEmpty) {
      await Future.wait([
        _checkBrokerConnection(email),
        if (_resolvedModelId == null || _resolvedModelId!.isEmpty)
          _fetchModelId(email),
      ]);
    }
  }

  /// Fetch model_id from strategy API if not provided in notification data.
  Future<void> _fetchModelId(String email) async {
    try {
      final resp = await AqApiService.instance.getStrategyDetails(widget.modelName);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final originalData = data['originalData'] ?? data;
        // Get model_Id from the latest rebalanceHistory entry
        final rebalanceHistory = originalData['model']?['rebalanceHistory'] ??
            originalData['rebalanceHistory'];
        if (rebalanceHistory is List && rebalanceHistory.isNotEmpty) {
          final latest = rebalanceHistory.last;
          if (latest is Map) {
            _resolvedModelId = latest['model_Id'] ?? latest['_id'];
            debugPrint('[RebalanceNotification] Resolved modelId: $_resolvedModelId');
          }
        }
        // Fallback to portfolio _id
        _resolvedModelId ??= originalData['_id'];
      }
    } catch (e) {
      debugPrint('[RebalanceNotification] Failed to fetch modelId: $e');
    }
  }

  Future<void> _checkBrokerConnection(String email) async {
    try {
      final response = await AqApiService.instance.getConnectedBrokers(email);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        final connections = BrokerConnection.parseApiResponse(
          data is Map<String, dynamic> ? data : {'data': data},
        );
        // Find the primary broker, or first connected one
        final primary = connections.where((b) => b.isPrimary).toList();
        final connected = connections.where((b) => b.isConnected).toList();
        final broker = primary.isNotEmpty ? primary.first : (connected.isNotEmpty ? connected.first : null);
        if (broker != null && mounted) {
          setState(() => _brokerConnection = broker);
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
                    color: _brokerConnection!.isTokenExpired
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _brokerConnection!.isTokenExpired
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
                    color: _brokerConnection!.isTokenExpired
                        ? Colors.orange
                        : Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _brokerConnection!.broker,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _brokerConnection!.isTokenExpired
                            ? 'Session expired — please reconnect'
                            : (_brokerConnection!.clientCode ?? 'Connected'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _brokerConnection!.isTokenExpired
                              ? Colors.orange
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_brokerConnection!.isTokenExpired)
                  TextButton(
                    onPressed: _reconnectBroker,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text("Reconnect",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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

  /// Navigate to the appropriate broker auth page for reconnection.
  void _reconnectBroker() async {
    if (_brokerConnection == null || _userEmail == null) return;
    final brokerName = _brokerConnection!.broker;
    final config = BrokerRegistry.getByName(brokerName);

    bool? result;
    if (config != null && config.authType == BrokerAuthType.oauth) {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerAuthPage(
            email: _userEmail!,
            brokerName: config.name,
          ),
        ),
      );
    } else if (config != null) {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerCredentialPage(
            email: _userEmail!,
            brokerConfig: config,
          ),
        ),
      );
    } else {
      // Unknown broker — go to selection page
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerSelectionPage(email: _userEmail!),
        ),
      );
    }

    if (result == true && _userEmail != null) {
      CacheService.instance.invalidate('aq/user/brokers:${_userEmail!}');
      await _checkBrokerConnection(_userEmail!);
    }
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

  /// Normalize trade objects from FCM notification format into
  /// the order format expected by OrderExecutionService/ExecutionStatusPage.
  /// FCM may use 'action'/'Action' while execution expects 'transactionType'.
  List<Map<String, dynamic>> _normalizeTradesForExecution(
      List<Map<String, dynamic>> trades) {
    return trades
        .map((t) {
          final symbol = t['symbol'] ?? t['Symbol'] ?? '';
          final action = (t['action'] ?? t['Action'] ??
                  t['transactionType'] ?? 'BUY')
              .toString()
              .toUpperCase();
          final quantity = t['quantity'] ?? t['Quantity'] ?? 0;
          final price = t['price'] ?? t['Price'] ?? 0;
          final exchange = t['exchange'] ?? t['Exchange'] ?? 'NSE';
          if (symbol.toString().isEmpty || quantity == 0) return null;
          return <String, dynamic>{
            'symbol': symbol,
            'exchange': exchange,
            'transactionType': action,
            'quantity': quantity is int ? quantity : int.tryParse('$quantity') ?? 0,
            'orderType': t['orderType'] ?? 'MARKET',
            'productType': t['productType'] ?? 'CNC',
            'price': price is double ? price : double.tryParse('$price') ?? 0.0,
          };
        })
        .where((t) => t != null)
        .cast<Map<String, dynamic>>()
        .toList();
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
      if (_brokerConnection != null && _brokerConnection!.isTokenExpired) {
        // Token expired — prompt reconnect instead of trying to execute
        if (mounted) {
          final shouldReconnect = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                  SizedBox(width: 8),
                  Text("Session Expired"),
                ],
              ),
              content: Text(
                'Your ${_brokerConnection!.broker} session has expired. Please reconnect to execute trades.',
                style: const TextStyle(fontSize: 14, height: 1.5),
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
                  child: const Text("Reconnect"),
                ),
              ],
            ),
          );
          if (shouldReconnect == true) {
            _reconnectBroker();
          }
        }
        return;
      }

      if (_brokerConnection != null) {
        // Broker connected — navigate to ExecutionStatusPage which handles
        // real order placement via CCXT rebalance/process-trade
        final orders = _normalizeTradesForExecution(widget.trades);
        if (orders.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No valid trades to execute.")),
            );
          }
          return;
        }
        final minimalPortfolio = ModelPortfolio(
          id: _resolvedModelId ?? '',
          advisor: widget.advisorName,
          modelName: widget.modelName,
          minInvestment: 0,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ExecutionStatusPage(
                portfolio: minimalPortfolio,
                email: _userEmail!,
                orders: orders,
                modelId: _resolvedModelId,
                modelName: widget.modelName,
                advisor: widget.advisorName,
              ),
            ),
          );
        }
      } else {
        // No broker - use DummyBroker flow - show confirmation dialog
        if (mounted) {
          final confirmed = await _showDummyBrokerConfirmation();
          if (confirmed == true && mounted) {
            // Record trades via OrderExecutionService
            try {
              final normalizedTrades = _normalizeTradesForExecution(widget.trades);
              await OrderExecutionService.instance.executeDummyBrokerOrders(
                orders: normalizedTrades,
                email: _userEmail!,
                modelName: widget.modelName,
                modelId: _resolvedModelId ?? '',
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
