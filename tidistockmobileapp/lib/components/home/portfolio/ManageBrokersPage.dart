import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'BrokerAuthPage.dart';
import 'BrokerCredentialPage.dart';

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

  /// Get set of connected broker names (lowercase) for filtering
  Set<String> get _connectedBrokerNames =>
      connectedBrokers.map((b) => b.broker.toLowerCase()).toSet();

  /// All brokers from registry that are NOT currently connected
  List<BrokerConfig> get _availableBrokers => BrokerRegistry.brokers
      .where((config) => !_connectedBrokerNames.contains(config.name.toLowerCase()))
      .toList();

  Future<void> _switchPrimary(BrokerConnection broker) async {
    HapticFeedback.mediumImpact();
    setState(() => _actionBroker = broker.broker);

    try {
      final resp = await AqApiService.instance.switchPrimaryBroker(
        email: widget.email,
        broker: broker.broker,
      );
      debugPrint('[ManageBrokers] switchPrimary ${broker.broker} status=${resp.statusCode} body=${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
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
            SnackBar(content: Text('Failed to switch broker (${resp.statusCode})')),
          );
        }
      }
    } catch (e) {
      debugPrint('[ManageBrokers] switchPrimary error: $e');
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
      debugPrint('[ManageBrokers] disconnect ${broker.broker} status=${resp.statusCode} body=${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
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
            SnackBar(content: Text('Failed to remove broker (${resp.statusCode})')),
          );
        }
      }
    } catch (e) {
      debugPrint('[ManageBrokers] disconnect error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    } finally {
      setState(() => _actionBroker = null);
    }
  }

  void _reconnectBroker(BrokerConnection broker) async {
    final config = BrokerRegistry.getByName(broker.broker);
    if (config == null) return;
    await _navigateToBrokerAuth(config);
  }

  /// Connect a new broker from the available list
  void _connectNewBroker(BrokerConfig config) async {
    HapticFeedback.mediumImpact();
    await _navigateToBrokerAuth(config);
  }

  /// Shared navigation to broker auth/credential page
  Future<void> _navigateToBrokerAuth(BrokerConfig config) async {
    bool? result;
    if (config.authType == BrokerAuthType.oauth) {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerAuthPage(
            email: widget.email,
            brokerName: config.name,
          ),
        ),
      );
    } else {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerCredentialPage(
            email: widget.email,
            brokerConfig: config,
          ),
        ),
      );
    }

    if (result == true) {
      CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
      _fetchBrokers();
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
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final available = _availableBrokers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── Connected Brokers Section ──
        if (connectedBrokers.isNotEmpty) ...[
          _sectionHeader("Connected Brokers", Icons.check_circle_outline, Colors.green),
          const SizedBox(height: 8),
          ...connectedBrokers.map((broker) => _connectedBrokerCard(broker)),
          const SizedBox(height: 24),
        ],

        // ── Available Brokers Section ──
        _sectionHeader("Add New Broker", Icons.add_circle_outline, Colors.blue.shade700),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            "Connect a new broker to start trading",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        if (available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                "All brokers are already connected",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.85,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            itemCount: available.length,
            itemBuilder: (context, index) =>
                _availableBrokerCard(available[index]),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Connected broker card (existing functionality)
  // ---------------------------------------------------------------------------

  Widget _buildBrokerLogo(String brokerName, {double size = 42}) {
    final config = BrokerRegistry.getByName(brokerName);
    if (config != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          config.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _letterIcon(brokerName, size: size),
        ),
      );
    }
    return _letterIcon(brokerName, size: size);
  }

  Widget _letterIcon(String name, {double size = 42}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: TextStyle(
              fontSize: size * 0.48,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _connectedBrokerCard(BrokerConnection broker) {
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
                  broker.isEffectivelyConnected
                      ? "Connected"
                      : broker.isTokenExpired
                          ? "Session expired — reconnect required"
                          : broker.isExpired
                              ? "Session expired"
                              : broker.status,
                  style: TextStyle(
                    fontSize: 12,
                    color: broker.isEffectivelyConnected
                        ? Colors.green
                        : (broker.isTokenExpired || broker.isExpired)
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
            if (broker.isTokenExpired || broker.isExpired)
              TextButton(
                onPressed: () => _reconnectBroker(broker),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.orange.shade700,
                ),
                child: const Text("Reconnect",
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              )
            else if (!isActive)
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

  // ---------------------------------------------------------------------------
  // Available (not connected) broker card
  // ---------------------------------------------------------------------------

  Widget _availableBrokerCard(BrokerConfig config) {
    return GestureDetector(
      onTap: () => _connectNewBroker(config),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                config.logoAsset,
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _letterIcon(config.name, size: 36),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              config.name,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              "Connect",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
