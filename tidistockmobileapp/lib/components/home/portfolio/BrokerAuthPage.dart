import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/BrokerSessionService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrokerAuthPage extends StatefulWidget {
  final String email;
  final String brokerName;

  const BrokerAuthPage({
    super.key,
    required this.email,
    required this.brokerName,
  });

  @override
  State<BrokerAuthPage> createState() => _BrokerAuthPageState();
}

class _BrokerAuthPageState extends State<BrokerAuthPage> {
  String _status = 'loading'; // loading, webview, success, error
  String? _errorMessage;
  late WebViewController _webViewController;
  bool _callbackHandled = false;

  bool get _isZerodha =>
      widget.brokerName.toLowerCase() == 'zerodha';

  @override
  void initState() {
    super.initState();
    _initiateBrokerAuth();
  }

  Future<void> _initiateBrokerAuth() async {
    try {
      String? loginUrl;

      if (_isZerodha) {
        // Zerodha publisher login: get login URL from CCXT server
        loginUrl = await _getZerodhaLoginUrl();
      } else {
        // Other OAuth brokers: use aq_backend generic flow
        loginUrl = await _getGenericLoginUrl();
      }

      if (loginUrl != null && loginUrl.startsWith('http')) {
        setState(() => _status = 'webview');
        _setupWebView(loginUrl);
      } else {
        setState(() {
          _status = 'error';
          _errorMessage = 'Invalid login URL received from server.';
        });
      }
    } catch (e) {
      debugPrint('[BrokerAuth] ERROR: $e');
      setState(() {
        _status = 'error';
        _errorMessage = 'Network error. Please check your connection.';
      });
    }
  }

  /// Zerodha: calls CCXT POST /zerodha/login-url with company API key.
  Future<String?> _getZerodhaLoginUrl() async {
    final response = await AqApiService.instance.getZerodhaLoginUrl();
    debugPrint('[BrokerAuth:Zerodha] login-url status=${response.statusCode} body=${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // CCXT returns: { loginUrl: "https://kite.zerodha.com/connect/login?..." }
      return data['loginUrl'] ??
          data['login_url'] ??
          data['response']?['loginUrl'] ??
          data['response']?['login_url'] ??
          (data['response'] is String ? data['response'] : null);
    }

    debugPrint('[BrokerAuth:Zerodha] FAILED: ${response.statusCode}');
    return null;
  }

  /// Other OAuth brokers: generic aq_backend flow.
  Future<String?> _getGenericLoginUrl() async {
    final response = await AqApiService.instance.getBrokerLoginUrl(
      broker: widget.brokerName,
      uid: widget.email,
      apiKey: '',
      secretKey: '',
      redirectUrl: 'https://tidiwealth.app/broker-callback',
    );

    debugPrint('[BrokerAuth] getBrokerLoginUrl status=${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response']?['loginUrl'] ??
          data['response']?['login_url'] ??
          data['loginUrl'] ??
          (data['response'] is String ? data['response'] : null);
    }

    debugPrint('[BrokerAuth] FAILED: ${response.statusCode}');
    return null;
  }

  void _setupWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isCallbackUrl(request.url)) {
              _handleAuthCallback(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            if (_isCallbackUrl(url)) {
              _handleAuthCallback(url);
            }
          },
          onWebResourceError: (error) {
            if (error.url != null && _isCallbackUrl(error.url!)) {
              _handleAuthCallback(error.url!);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  bool _isCallbackUrl(String url) {
    return url.contains('broker-callback') ||
        url.contains('request_token') ||
        url.contains('auth_code') ||
        url.contains('status=success') ||
        url.contains('stock-recommendation') ||
        url.contains('zerodha/callback') ||
        url.contains('motilal-oswal/callback') ||
        url.contains('icici/auth-callback');
  }

  Future<void> _handleAuthCallback(String callbackUrl) async {
    // Guard against duplicate callback handling
    if (_callbackHandled) return;
    _callbackHandled = true;

    setState(() => _status = 'loading');

    try {
      final uri = Uri.parse(callbackUrl);
      final requestToken = uri.queryParameters['request_token'] ??
          uri.queryParameters['auth_code'] ??
          uri.queryParameters['code'];

      if (_isZerodha && requestToken != null) {
        // Zerodha: exchange request_token via CCXT, then save connection
        await _handleZerodhaCallback(requestToken);
        return;
      }

      if (requestToken != null) {
        // Other brokers: send request_token to aq_backend
        await _handleGenericCallback(requestToken);
        return;
      }

      // Check for status=success in URL params
      if (uri.queryParameters['status'] == 'success') {
        await _onConnectionSuccess();
        return;
      }

      setState(() {
        _status = 'error';
        _errorMessage = 'Authentication failed. Please try again.';
      });
    } catch (e) {
      debugPrint('[BrokerAuth] callback error: $e');
      setState(() {
        _status = 'error';
        _errorMessage = 'Failed to complete broker authentication.';
      });
    }
  }

  /// Zerodha: exchange request_token → gen-access-token → save to DB.
  Future<void> _handleZerodhaCallback(String requestToken) async {
    debugPrint('[BrokerAuth:Zerodha] exchanging request_token...');

    // Step 1: Exchange request_token for access_token via CCXT
    final tokenResp = await AqApiService.instance.exchangeZerodhaToken(
      requestToken: requestToken,
    );

    debugPrint('[BrokerAuth:Zerodha] gen-access-token status=${tokenResp.statusCode}');

    if (tokenResp.statusCode == 200) {
      final tokenData = jsonDecode(tokenResp.body);
      final accessToken = tokenData['access_token'] ??
          tokenData['jwtToken'] ??
          tokenData['response']?['access_token'];

      // Step 2: Save broker connection via aq_backend
      // Try ObjectId-based connect first, fall back to email-based
      final uid = await AqApiService.instance.getUserObjectId(widget.email);
      if (uid != null) {
        final saveResp = await AqApiService.instance.connectCredentialBroker(
          uid: uid,
          userBroker: 'Zerodha',
          credentials: {
            'jwtToken': accessToken ?? requestToken,
          },
        );
        debugPrint('[BrokerAuth:Zerodha] connect-broker status=${saveResp.statusCode}');
      }

      // Also save via email-based connect as fallback
      await AqApiService.instance.connectBrokerByEmail(
        email: widget.email,
        broker: 'Zerodha',
        brokerData: {
          'jwtToken': accessToken ?? requestToken,
          'request_token': requestToken,
          'status': 'connected',
        },
      );

      await _onConnectionSuccess();
    } else {
      // Token exchange failed — try saving the request_token directly
      debugPrint('[BrokerAuth:Zerodha] token exchange failed, saving request_token directly');
      await AqApiService.instance.connectBrokerByEmail(
        email: widget.email,
        broker: 'Zerodha',
        brokerData: {
          'request_token': requestToken,
          'status': 'connected',
        },
      );
      await _onConnectionSuccess();
    }
  }

  /// Other brokers: send request_token to aq_backend.
  Future<void> _handleGenericCallback(String requestToken) async {
    final response = await AqApiService.instance.connectBroker(
      email: widget.email,
      broker: widget.brokerName,
      brokerData: {
        'request_token': requestToken,
        'status': 'connected',
      },
    );

    if (response.statusCode == 200) {
      await _onConnectionSuccess();
    } else {
      setState(() {
        _status = 'error';
        _errorMessage = 'Failed to save broker connection. Please try again.';
      });
    }
  }

  Future<void> _onConnectionSuccess() async {
    CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
    await BrokerSessionService.instance.saveSessionTime(widget.brokerName);
    // Non-critical: sync model portfolio broker
    AqApiService.instance.changeBrokerModelPortfolio(
      email: widget.email,
      broker: widget.brokerName,
    ).catchError((_) {});
    setState(() => _status = 'success');
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Connect ${widget.brokerName}",
      child: _buildContent(),
    );
  }

  Widget _buildBrokerLogo({double size = 48}) {
    final config = BrokerRegistry.getByName(widget.brokerName);
    if (config == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        config.logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case 'loading':
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Connecting to broker...",
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        );

      case 'webview':
        return WebViewWidget(controller: _webViewController);

      case 'success':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBrokerLogo(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle, size: 60, color: Colors.green.shade400),
              ),
              const SizedBox(height: 20),
              const Text("Broker Connected!",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text("${widget.brokerName} has been connected successfully.",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center),
            ],
          ),
        );

      case 'error':
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBrokerLogo(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, size: 60, color: Colors.red.shade400),
                ),
                const SizedBox(height: 20),
                const Text("Connection Failed",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_errorMessage ?? "Something went wrong.",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    _callbackHandled = false;
                    setState(() => _status = 'loading');
                    _initiateBrokerAuth();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Retry", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
