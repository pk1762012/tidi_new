import 'dart:async';
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

  /// When true, renders as modal content (no scaffold).
  /// When false (default), renders as a full page with CustomScaffold.
  final bool asModal;

  /// When true, shows "Continue without connecting broker" option
  /// matching AllBrokerList.js withoutBrokerModal behaviour.
  final bool showContinueWithoutBroker;

  /// Callback when user chooses to continue without broker (DummyBroker flow).
  final VoidCallback? onContinueWithoutBroker;

  const BrokerSelectionPage({
    super.key,
    required this.email,
    this.portfolio,
    this.asModal = false,
    this.showContinueWithoutBroker = true,
    this.onContinueWithoutBroker,
  });

  /// Opens broker selection as a modal bottom sheet (matching rgx_app style).
  /// Returns a [BrokerConnection] if the user successfully connects, or null.
  static Future<BrokerConnection?> show(BuildContext context, {required String email, ModelPortfolio? portfolio}) {
    return showModalBottomSheet<BrokerConnection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => BrokerSelectionPage(
          email: email,
          portfolio: portfolio,
          asModal: true,
        ),
      ),
    );
  }

  @override
  State<BrokerSelectionPage> createState() => _BrokerSelectionPageState();
}

class _BrokerSelectionPageState extends State<BrokerSelectionPage> {
  List<BrokerConnection> connectedBrokers = [];
  bool loading = true;
  bool _withoutBrokerLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchConnectedBrokers();
  }

  Future<void> _fetchConnectedBrokers() async {
    try {
      final response = await AqApiService.instance
          .getConnectedBrokers(widget.email)
          .timeout(const Duration(seconds: 15));
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

  void _onBrokerTap(BrokerConfig brokerConfig) async {
    HapticFeedback.mediumImpact();
    final connection = _getConnection(brokerConfig.name);

    if (connection != null && connection.isEffectivelyConnected) {
      // Connected with valid token — proceed to investment or return
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

  /// Handle "Continue without connecting broker" — saves DummyBroker preference.
  /// Matching AllBrokerList.js handleContinueWithoutBrokerSave logic.
  Future<void> _handleContinueWithoutBroker() async {
    setState(() => _withoutBrokerLoading = true);
    try {
      await AqApiService.instance.changeBrokerModelPortfolio(
        email: widget.email,
        broker: 'DummyBroker',
      );
      if (widget.onContinueWithoutBroker != null) {
        widget.onContinueWithoutBroker!();
      } else if (mounted) {
        // Return a special "DummyBroker" connection to the caller
        Navigator.pop(context, BrokerConnection(
          id: '',
          broker: 'DummyBroker',
          clientCode: '',
          status: 'connected',
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _withoutBrokerLoading = false);
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

  @override
  Widget build(BuildContext context) {
    if (widget.asModal) return _buildModalContent();
    return _buildFullPage();
  }

  // ---------------------------------------------------------------------------
  // Full-page version (used from profile page / direct navigation)
  // ---------------------------------------------------------------------------

  Widget _buildFullPage() {
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
                // Manage Connected Brokers link
                if (connectedBrokers.any((b) => b.isConnected))
                  GestureDetector(
                    onTap: _openManageBrokers,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.settings, size: 18, color: Colors.blue.shade600),
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
                          Icon(Icons.chevron_right, size: 20, color: Colors.blue.shade400),
                        ],
                      ),
                    ),
                  ),

                // SEBI disclaimer (matching AllBrokerList.js BrokerDisclaimer)
                _brokerDisclaimer(),

                // Header text (matching AllBrokerList.js)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    "Select your broker for connection",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    "For seamless execution post your approval, please connect your broker",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                    textAlign: TextAlign.center,
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
                  itemCount: BrokerRegistry.brokers.length,
                  itemBuilder: (context, index) {
                    final config = BrokerRegistry.brokers[index];
                    return _brokerCard(config, darkMode: false);
                  },
                ),

                // "Continue without connecting broker" button (matching AllBrokerList.js)
                if (widget.showContinueWithoutBroker) ...[
                  const SizedBox(height: 20),
                  _continueWithoutBrokerButton(),
                ],
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Modal bottom sheet version (matching rgx_app BrokerSelectionModal)
  // ---------------------------------------------------------------------------

  Widget _buildModalContent() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF002651),
            Color(0xFF003572),
            Color(0xFF0053B1),
          ],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : Column(
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                      ),
                      const Expanded(
                        child: Text(
                          "Select your broker for connection",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      // Important notice box (amber border)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFB800), width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Important:",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFFB800),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...[
                              "Actions and decisions are solely yours.",
                              "RA doesn't control or influence your action.",
                              "RA isn't responsible for your outcome.",
                              "You act independently on the broker platform.",
                            ].map((text) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    "• $text",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white,
                                      height: 1.5,
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ),

                      // 4-column broker grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: BrokerRegistry.brokers.length,
                        itemBuilder: (context, index) {
                          final config = BrokerRegistry.brokers[index];
                          return _brokerCard(config, darkMode: true);
                        },
                      ),

                      // "Continue without connecting broker" (matching AllBrokerList.js)
                      if (widget.showContinueWithoutBroker) ...[
                        const SizedBox(height: 24),
                        _continueWithoutBrokerButton(darkMode: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Broker card widget
  // ---------------------------------------------------------------------------

  /// SEBI Disclaimer matching AllBrokerList.js BrokerDisclaimer component.
  Widget _brokerDisclaimer() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade50, Colors.yellow.shade50],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Important Disclaimer",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.amber.shade900)),
                const SizedBox(height: 6),
                ...["Actions and decisions are solely yours",
                    "RA does not control or influence your action",
                    "RA isn't responsible for any outcome",
                    "You act independently on the broker platform",
                ].map((text) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("• ", style: TextStyle(fontSize: 12, color: Colors.amber.shade800)),
                      Expanded(
                        child: Text(text,
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade800, height: 1.4)),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    // Open SEBI RA Regulations link
                    // Note: url_launcher would be used in production
                  },
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text("View SEBI Research Analyst Regulations",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade700,
                        )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Continue without connecting broker" button matching AllBrokerList.js.
  Widget _continueWithoutBrokerButton({bool darkMode = false}) {
    return GestureDetector(
      onTap: _withoutBrokerLoading ? null : _handleContinueWithoutBroker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: darkMode ? Colors.white.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: darkMode ? Colors.white.withOpacity(0.3) : Colors.grey.shade200,
            width: 2,
          ),
          boxShadow: darkMode ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _withoutBrokerLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: darkMode ? Colors.white : Colors.grey.shade700,
                  ),
                )
              : Text(
                  "Continue without connecting broker",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: darkMode ? Colors.white : Colors.grey.shade700,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _brokerCard(BrokerConfig config, {bool darkMode = false}) {
    final connection = _getConnection(config.name);
    final isConnected = connection?.isEffectivelyConnected ?? false;

    return GestureDetector(
      onTap: () => _onBrokerTap(config),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(darkMode ? 16 : 14),
          border: darkMode
              ? null
              : Border.all(
                  color: isConnected ? Colors.green.shade300 : Colors.grey.shade200,
                  width: 1.5,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(darkMode ? 0.15 : 0.04),
              blurRadius: darkMode ? 6 : 8,
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
                width: darkMode ? 36 : 42,
                height: darkMode ? 36 : 42,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: darkMode ? 36 : 42,
                  height: darkMode ? 36 : 42,
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
                        fontSize: darkMode ? 16 : 20,
                        fontWeight: FontWeight.w800,
                        color: isConnected ? Colors.green : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: darkMode ? 6 : 8),
            Text(
              config.name,
              style: TextStyle(
                fontSize: darkMode ? 10 : 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (!darkMode) ...[
              const SizedBox(height: 4),
              Text(
                isConnected
                    ? "Connected"
                    : (connection != null &&
                            connection.isConnected &&
                            connection.isTokenExpired)
                        ? "Reconnect"
                        : "Connect",
                style: TextStyle(
                  fontSize: 10,
                  color: isConnected
                      ? Colors.green
                      : (connection != null &&
                              connection.isConnected &&
                              connection.isTokenExpired)
                          ? Colors.orange
                          : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
