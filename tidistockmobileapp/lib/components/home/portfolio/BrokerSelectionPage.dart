import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'BrokerAuthPage.dart';
import 'InvestmentModal.dart';

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

  static const List<Map<String, String>> supportedBrokers = [
    {'name': 'Zerodha', 'icon': 'Z'},
    {'name': 'Angel One', 'icon': 'A'},
    {'name': 'Groww', 'icon': 'G'},
    {'name': 'Upstox', 'icon': 'U'},
    {'name': 'ICICI Direct', 'icon': 'I'},
    {'name': 'Kotak', 'icon': 'K'},
    {'name': 'Dhan', 'icon': 'D'},
    {'name': 'Fyers', 'icon': 'F'},
    {'name': 'AliceBlue', 'icon': 'A'},
    {'name': 'Hdfc Securities', 'icon': 'H'},
    {'name': 'Motilal Oswal', 'icon': 'M'},
    {'name': 'IIFL Securities', 'icon': 'I'},
  ];

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
        final List<dynamic> brokerList = data['data'] ?? data['connected_brokers'] ?? [];
        setState(() {
          connectedBrokers = brokerList
              .map((e) => BrokerConnection.fromJson(e))
              .toList();
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

  void _onBrokerTap(String brokerName) async {
    HapticFeedback.mediumImpact();
    final connection = _getConnection(brokerName);

    if (connection != null && connection.isConnected) {
      // Already connected — proceed to investment
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

    // Navigate to OAuth auth flow
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BrokerAuthPage(
          email: widget.email,
          brokerName: brokerName,
        ),
      ),
    );

    if (result == true) {
      // Broker connected successfully
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
      }
    }
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

                // Broker grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: supportedBrokers.length,
                  itemBuilder: (context, index) {
                    final broker = supportedBrokers[index];
                    return _brokerCard(broker['name']!, broker['icon']!);
                  },
                ),
              ],
            ),
    );
  }

  Widget _brokerCard(String name, String iconLetter) {
    final connection = _getConnection(name);
    final isConnected = connection?.isConnected ?? false;
    final isExpired = connection?.isExpired ?? false;

    Color borderColor = Colors.grey.shade200;
    Color statusColor = Colors.grey;
    String statusText = "Connect";
    if (isConnected) {
      borderColor = Colors.green.shade300;
      statusColor = Colors.green;
      statusText = "Connected";
    } else if (isExpired) {
      borderColor = Colors.orange.shade300;
      statusColor = Colors.orange;
      statusText = "Reconnect";
    }

    return GestureDetector(
      onTap: () => _onBrokerTap(name),
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
            Container(
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
                  iconLetter,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isConnected ? Colors.green : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
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
