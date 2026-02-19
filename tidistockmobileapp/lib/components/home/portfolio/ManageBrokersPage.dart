import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

class ManageBrokersPage extends StatefulWidget {
  final String email;

  const ManageBrokersPage({super.key, required this.email});

  @override
  State<ManageBrokersPage> createState() => _ManageBrokersPageState();
}

class _ManageBrokersPageState extends State<ManageBrokersPage> {
  List<BrokerConnection> connectedBrokers = [];
  bool loading = true;
  String? _actionBroker; // broker currently being acted on

  @override
  void initState() {
    super.initState();
    _fetchBrokers();
  }

  Future<void> _fetchBrokers() async {
    setState(() => loading = true);
    try {
      final response =
          await AqApiService.instance.getConnectedBrokers(widget.email);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          connectedBrokers = BrokerConnection.parseApiResponse(data);
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (_) {
      setState(() => loading = false);
    }
  }

  Future<void> _switchPrimary(BrokerConnection broker) async {
    HapticFeedback.mediumImpact();
    setState(() => _actionBroker = broker.broker);

    try {
      final resp = await AqApiService.instance.switchPrimaryBroker(
        email: widget.email,
        broker: broker.broker,
      );
      if (resp.statusCode == 200) {
        // Non-critical: sync model portfolio
        AqApiService.instance
            .changeBrokerModelPortfolio(
                email: widget.email, broker: broker.broker)
            .catchError((_) {});
        CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
        await _fetchBrokers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${broker.broker} is now your active broker')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to switch broker')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    } finally {
      setState(() => _actionBroker = null);
    }
  }

  Future<void> _removeBroker(BrokerConnection broker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Broker'),
        content: Text(
            'Are you sure you want to disconnect ${broker.broker}? You will need to reconnect to trade.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _actionBroker = broker.broker);

    try {
      final resp = await AqApiService.instance.disconnectBroker(
        email: widget.email,
        broker: broker.broker,
      );
      if (resp.statusCode == 200) {
        CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
        await _fetchBrokers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${broker.broker} disconnected')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove broker')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    } finally {
      setState(() => _actionBroker = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Manage Connections",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : connectedBrokers.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text("No Brokers Connected",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              "Connect a broker to start trading with model portfolios.",
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: connectedBrokers.length,
      itemBuilder: (context, index) {
        final broker = connectedBrokers[index];
        return _brokerCard(broker);
      },
    );
  }

  Widget _buildBrokerLogo(String brokerName) {
    final config = BrokerRegistry.getByName(brokerName);
    if (config != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          config.logoAsset,
          width: 42,
          height: 42,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _letterIcon(brokerName),
        ),
      );
    }
    return _letterIcon(brokerName);
  }

  Widget _letterIcon(String name) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _brokerCard(BrokerConnection broker) {
    final isActive = broker.isPrimary;
    final isActing = _actionBroker == broker.broker;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? Colors.green.shade300 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildBrokerLogo(broker.broker),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      broker.broker,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Active",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  broker.isConnected
                      ? "Connected"
                      : broker.isExpired
                          ? "Session expired"
                          : broker.status,
                  style: TextStyle(
                    fontSize: 12,
                    color: broker.isConnected
                        ? Colors.green
                        : broker.isExpired
                            ? Colors.orange
                            : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (isActing)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            if (!isActive)
              TextButton(
                onPressed: () => _switchPrimary(broker),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text("Switch",
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            IconButton(
              onPressed: () => _removeBroker(broker),
              icon: const Icon(Icons.close, size: 18),
              color: Colors.red.shade400,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ],
      ),
    );
  }
}
