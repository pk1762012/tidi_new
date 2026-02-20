import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerAuthPage.dart';
import 'BrokerCredentialPage.dart';
import 'InvestmentModal.dart';
import 'ManageBrokersPage.dart';

class BrokerSelectionPage extends StatefulWidget {
  final String email;
  final ModelPortfolio? portfolio;

  const BrokerSelectionPage({
    super.key,
    required this.email,
    this.portfolio,
  });

  @override
  State<BrokerSelectionPage> createState() => _BrokerSelectionPageState();
}

class _BrokerSelectionPageState extends State<BrokerSelectionPage> {
  List<BrokerConnection> connectedBrokers = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchConnectedBrokers();
  }

  Future<void> _fetchConnectedBrokers() async {
    try {
      final response = await AqApiService.instance.getConnectedBrokers(widget.email);
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

  BrokerConnection? _getConnection(String brokerName) {
    try {
      return connectedBrokers.firstWhere(
        (b) => b.broker.toLowerCase() == brokerName.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  bool get _hasExpiredBrokers =>
      connectedBrokers.any((b) => b.isExpired || b.isTokenExpired);

  bool get _hasConnectedBrokers =>
      connectedBrokers.any((b) => b.isConnected);

  void _onBrokerTap(BrokerConfig brokerConfig) async {
    HapticFeedback.mediumImpact();
    final connection = _getConnection(brokerConfig.name);

    if (connection != null && connection.isEffectivelyConnected) {
      // Connected with valid token — proceed to investment
      if (widget.portfolio != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InvestmentModal(
              portfolio: widget.portfolio!,
              email: widget.email,
            ),
          ),
        );
      } else {
        Navigator.pop(context, connection);
      }
      return;
    }

    // If connected but token expired, show reconnect message
    if (connection != null && connection.isConnected && connection.isTokenExpired) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${brokerConfig.name} session expired. Please reconnect.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    }

    // Route based on auth type (for new connection or reconnect)
    bool? result;
    if (brokerConfig.authType == BrokerAuthType.oauth) {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerAuthPage(
            email: widget.email,
            brokerName: brokerConfig.name,
          ),
        ),
      );
    } else {
      result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BrokerCredentialPage(
            email: widget.email,
            brokerConfig: brokerConfig,
          ),
        ),
      );
    }

    if (result == true) {
      await _fetchConnectedBrokers();
      if (widget.portfolio != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InvestmentModal(
              portfolio: widget.portfolio!,
              email: widget.email,
            ),
          ),
        );
      } else if (mounted) {
        final connected = connectedBrokers.where((b) =>
            b.broker.toLowerCase() == brokerConfig.name.toLowerCase() && b.isConnected).toList();
        if (connected.isNotEmpty) {
          Navigator.pop(context, connected.first);
        } else {
          final anyConnected = connectedBrokers.where((b) => b.isConnected).toList();
          if (anyConnected.isNotEmpty) {
            Navigator.pop(context, anyConnected.first);
          }
        }
      }
    }
  }

  void _openManageBrokers() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageBrokersPage(email: widget.email),
      ),
    );
    // Refresh after returning from manage page
    _fetchConnectedBrokers();
  }

  void _continueWithoutBroker() {
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Connect Broker",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Token expired warning banner
                if (_hasExpiredBrokers)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20, color: Colors.orange.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Some broker sessions have expired. Please reconnect to continue trading.",
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                                height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Manage Connected Brokers link
                if (_hasConnectedBrokers)
                  GestureDetector(
                    onTap: _openManageBrokers,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.settings,
                              size: 18, color: Colors.blue.shade600),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Manage Connected Brokers",
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 20, color: Colors.blue.shade400),
                        ],
                      ),
                    ),
                  ),

                // SEBI disclaimer
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Connect your trading account to execute model portfolio trades. "
                          "Your credentials are encrypted and stored securely.",
                          style: TextStyle(fontSize: 13, color: Colors.blue.shade700, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                // Broker grid using BrokerRegistry
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: BrokerRegistry.brokers.length,
                  itemBuilder: (context, index) {
                    final config = BrokerRegistry.brokers[index];
                    return _brokerCard(config);
                  },
                ),

                // Continue without broker button (portfolio flow only)
                if (widget.portfolio != null) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _continueWithoutBroker,
                      child: const Text(
                        "Continue without broker",
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _brokerCard(BrokerConfig config) {
    final connection = _getConnection(config.name);
    final isConnected = connection?.isEffectivelyConnected ?? false;
    final isExpired = connection?.isExpired ?? false;
    final isTokenExpired = connection != null &&
        connection.isConnected &&
        connection.isTokenExpired;

    Color borderColor = Colors.grey.shade200;
    Color statusColor = Colors.grey;
    String statusText = "Connect";
    if (isConnected) {
      borderColor = Colors.green.shade300;
      statusColor = Colors.green;
      statusText = "Connected";
    } else if (isExpired || isTokenExpired) {
      borderColor = Colors.orange.shade300;
      statusColor = Colors.orange;
      statusText = "Reconnect";
    }

    return GestureDetector(
      onTap: () => _onBrokerTap(config),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
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
                width: 42,
                height: 42,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      config.iconLetter,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isConnected ? Colors.green : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              config.name,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
