import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/BrokerSessionService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Handles OAuth / publisher-login broker connections via WebView.
///
/// Broker-specific flows:
///   - Zerodha:       CCXT POST /zerodha/login-url → Kite login → exchange token
///   - Angel One:     SmartAPI publisher-login URL → callback with auth_token
///   - IIFL:          markets.iiflcapital.com login → callback auth_token → ccxt exchange
///   - Groww:         CCXT GET /groww/login/oauth → OAuth redirect → callback with access_token
///   - Others:        aq_backend POST /api/{broker}/update-key → OAuth → callback
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

  String get _brokerLower => widget.brokerName.toLowerCase();
  bool get _isZerodha => _brokerLower == 'zerodha';
  bool get _isAngelOne => _brokerLower == 'angel one' || _brokerLower == 'angelone';
  bool get _isGroww => _brokerLower == 'groww';
  bool get _isIifl => _brokerLower == 'iifl securities' || _brokerLower == 'iifl';

  @override
  void initState() {
    super.initState();
    _initiateBrokerAuth();
  }

  Future<void> _initiateBrokerAuth() async {
    try {
      String? loginUrl;

      if (_isZerodha) {
        loginUrl = await _getZerodhaLoginUrl();
      } else if (_isAngelOne) {
        loginUrl = _getAngelOneLoginUrl();
      } else if (_isIifl) {
        loginUrl = _getIiflLoginUrl();
      } else if (_isGroww) {
        loginUrl = await _getGrowwLoginUrl();
      } else {
        loginUrl = await _getGenericLoginUrl();
      }

      debugPrint('[BrokerAuth] loginUrl for ${widget.brokerName}: ${loginUrl?.substring(0, (loginUrl?.length ?? 0).clamp(0, 100))}...');

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

  // ---------------------------------------------------------------------------
  // Broker-specific login URL generators
  // ---------------------------------------------------------------------------

  /// Zerodha: CCXT POST /zerodha/login-url with company API key.
  Future<String?> _getZerodhaLoginUrl() async {
    final response = await AqApiService.instance.getZerodhaLoginUrl();
    debugPrint('[BrokerAuth:Zerodha] login-url status=${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['loginUrl'] ??
          data['login_url'] ??
          data['response']?['loginUrl'] ??
          data['response']?['login_url'] ??
          (data['response'] is String ? data['response'] : null);
    }
    debugPrint('[BrokerAuth:Zerodha] FAILED: ${response.statusCode} ${response.body}');
    return null;
  }

  /// Angel One: SmartAPI publisher login — direct URL with company API key.
  /// No backend call needed; the URL is constructed client-side.
  String _getAngelOneLoginUrl() {
    final apiKey = dotenv.env['ANGEL_ONE_API_KEY'] ?? 'MSthREMz';
    final nonce = '${DateTime.now().millisecondsSinceEpoch}_${widget.email.hashCode}';
    return 'https://smartapi.angelbroking.com/publisher-login?api_key=$apiKey&state=$nonce';
  }

  /// IIFL Securities: client-side URL with company appkey.
  /// Matches RGX connectBroker.js IIFL flow:
  ///   https://markets.iiflcapital.com/?v=1&appkey={appkey}&redirect_url={redirect}
  String _getIiflLoginUrl() {
    const appKey = 'nHjYctmzvrHrYWA';
    final redirectUrl = AqApiService.instance.advisorSubdomain == 'prod'
        ? 'prod.alphaquark.in/stock-recommendation'
        : 'dev.alphaquark.in/stock-recommendation';
    return 'https://markets.iiflcapital.com/?v=1&appkey=$appKey&redirect_url=$redirectUrl';
  }

  /// Groww: CCXT GET /groww/login/oauth → returns redirect URL.
  Future<String?> _getGrowwLoginUrl() async {
    final response = await AqApiService.instance.getGrowwOAuthUrl();
    debugPrint('[BrokerAuth:Groww] OAuth status=${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['loginUrl'] ??
          data['login_url'] ??
          data['redirectUrl'] ??
          data['redirect_url'] ??
          data['response']?['loginUrl'] ??
          (data['response'] is String ? data['response'] : null);
    }
    // Groww CCXT may return a 302 redirect — check Location header
    final location = response.headers['location'];
    if (location != null && location.startsWith('http')) return location;

    debugPrint('[BrokerAuth:Groww] FAILED: ${response.statusCode} ${response.body}');
    return null;
  }

  /// Generic: aq_backend POST /api/{broker}/update-key.
  Future<String?> _getGenericLoginUrl() async {
    final uid = await AqApiService.instance.getUserObjectId(widget.email) ?? widget.email;
    final response = await AqApiService.instance.getBrokerLoginUrl(
      broker: widget.brokerName,
      uid: uid,
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
    debugPrint('[BrokerAuth] FAILED: ${response.statusCode} ${response.body}');
    return null;
  }

  // ---------------------------------------------------------------------------
  // WebView setup & callback detection
  // ---------------------------------------------------------------------------

  void _setupWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            debugPrint('[BrokerAuth:WebView] nav → ${request.url.substring(0, request.url.length.clamp(0, 120))}');
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
        url.contains('auth_token') ||
        url.contains('auth_code') ||
        url.contains('access_token') ||
        url.contains('status=success') ||
        url.contains('stock-recommendation') ||
        url.contains('zerodha/callback') ||
        url.contains('motilal-oswal/callback') ||
        url.contains('icici/auth-callback') ||
        url.contains('api/deploy/broker/callback');
  }

  // ---------------------------------------------------------------------------
  // Callback handling
  // ---------------------------------------------------------------------------

  Future<void> _handleAuthCallback(String callbackUrl) async {
    if (_callbackHandled) return;
    _callbackHandled = true;

    setState(() => _status = 'loading');

    try {
      final uri = Uri.parse(callbackUrl);

      // IIFL returns auth_token + clientid from markets.iiflcapital.com
      if (_isIifl) {
        final authToken = uri.queryParameters['auth_token'];
        final clientId = uri.queryParameters['clientid'] ??
            uri.queryParameters['client_id'];
        if (authToken != null) {
          await _handleIiflCallback(authToken, clientId ?? '');
          return;
        }
      }

      // Angel One returns auth_token directly
      if (_isAngelOne) {
        final authToken = uri.queryParameters['auth_token'] ??
            uri.queryParameters['jwtToken'] ??
            uri.queryParameters['token'];
        if (authToken != null) {
          await _handleAngelOneCallback(authToken);
          return;
        }
      }

      // Zerodha returns request_token
      final requestToken = uri.queryParameters['request_token'] ??
          uri.queryParameters['auth_code'] ??
          uri.queryParameters['code'];

      if (_isZerodha && requestToken != null) {
        await _handleZerodhaCallback(requestToken);
        return;
      }

      // Groww returns access_token (RGX uses queryParams.access_token)
      if (_isGroww) {
        final accessToken = uri.queryParameters['access_token'] ??
            uri.queryParameters['jwtToken'] ??
            requestToken;
        final status = uri.queryParameters['status'];
        if (accessToken != null && (status == null || status == '0')) {
          await _handleGrowwCallback(accessToken);
          return;
        }
        if (status != null && status != '0') {
          setState(() {
            _status = 'error';
            _errorMessage = 'Groww authentication was denied or failed.';
          });
          return;
        }
      }

      // Generic: request_token or auth_code
      if (requestToken != null) {
        await _handleGenericCallback(requestToken);
        return;
      }

      // Check for auth_token in URL (Angel One fallback)
      final authToken = uri.queryParameters['auth_token'];
      if (authToken != null) {
        await _handleAngelOneCallback(authToken);
        return;
      }

      // Check for status=success
      if (uri.queryParameters['status'] == 'success') {
        await _onConnectionSuccess();
        return;
      }

      setState(() {
        _status = 'error';
        _errorMessage = 'Authentication failed. No token received.';
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

    final tokenResp = await AqApiService.instance.exchangeZerodhaToken(
      requestToken: requestToken,
    );

    debugPrint('[BrokerAuth:Zerodha] gen-access-token status=${tokenResp.statusCode}');

    if (tokenResp.statusCode == 200) {
      final tokenData = jsonDecode(tokenResp.body);
      final accessToken = tokenData['access_token'] ??
          tokenData['jwtToken'] ??
          tokenData['response']?['access_token'];

      // Save via ObjectId-based connect
      final uid = await AqApiService.instance.getUserObjectId(widget.email);
      if (uid != null) {
        await AqApiService.instance.connectCredentialBroker(
          uid: uid,
          userBroker: 'Zerodha',
          credentials: {'jwtToken': accessToken ?? requestToken},
        );
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
      // Token exchange failed — still save the request_token
      debugPrint('[BrokerAuth:Zerodha] token exchange failed, saving request_token');
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

  /// Angel One: save auth_token via PUT /api/user/connect-broker.
  /// Matches RGX connectBroker.js Angel One flow.
  Future<void> _handleAngelOneCallback(String authToken) async {
    debugPrint('[BrokerAuth:AngelOne] saving auth_token...');
    final apiKey = dotenv.env['ANGEL_ONE_API_KEY'] ?? 'MSthREMz';

    // Save via ObjectId-based connect (primary method)
    final uid = await AqApiService.instance.getUserObjectId(widget.email);
    if (uid != null) {
      final saveResp = await AqApiService.instance.connectCredentialBroker(
        uid: uid,
        userBroker: 'Angel One',
        credentials: {
          'jwtToken': authToken,
          'apiKey': apiKey,
        },
      );
      debugPrint('[BrokerAuth:AngelOne] connect-broker status=${saveResp.statusCode}');
    }

    // Also save via email-based connect as fallback
    await AqApiService.instance.connectBrokerByEmail(
      email: widget.email,
      broker: 'Angel One',
      brokerData: {
        'jwtToken': authToken,
        'apiKey': apiKey,
        'status': 'connected',
      },
    );

    await _onConnectionSuccess();
  }

  /// IIFL: exchange auth_token via ccxt/iifl/login/client → save sessionToken.
  /// Matches RGX connectBroker.js IIFL flow.
  Future<void> _handleIiflCallback(String authToken, String clientId) async {
    debugPrint('[BrokerAuth:IIFL] exchanging auth_token (clientId=$clientId)...');

    final tokenResp = await AqApiService.instance.exchangeIiflToken(
      authToken: authToken,
      clientCode: clientId,
    );

    debugPrint('[BrokerAuth:IIFL] iifl/login/client status=${tokenResp.statusCode}');

    if (tokenResp.statusCode == 200) {
      final tokenData = jsonDecode(tokenResp.body);
      final sessionToken = tokenData['sessionToken'] ??
          tokenData['session_token'] ??
          tokenData['jwtToken'] ??
          authToken;

      // Save via ObjectId-based connect
      final uid = await AqApiService.instance.getUserObjectId(widget.email);
      if (uid != null) {
        await AqApiService.instance.connectCredentialBroker(
          uid: uid,
          userBroker: 'IIFL Securities',
          credentials: {
            'jwtToken': sessionToken,
            'clientCode': clientId,
          },
        );
      }

      // Also save via email-based connect as fallback
      await AqApiService.instance.connectBrokerByEmail(
        email: widget.email,
        broker: 'IIFL Securities',
        brokerData: {
          'jwtToken': sessionToken,
          'clientCode': clientId,
          'status': 'connected',
        },
      );

      await _onConnectionSuccess();
    } else {
      debugPrint('[BrokerAuth:IIFL] token exchange failed: ${tokenResp.body}');
      setState(() {
        _status = 'error';
        _errorMessage = 'IIFL authentication failed. Please try again.';
      });
    }
  }

  /// Groww: save access token via connect-broker.
  Future<void> _handleGrowwCallback(String authCode) async {
    debugPrint('[BrokerAuth:Groww] saving auth_code...');

    final uid = await AqApiService.instance.getUserObjectId(widget.email);
    if (uid != null) {
      await AqApiService.instance.connectCredentialBroker(
        uid: uid,
        userBroker: 'Groww',
        credentials: {
          'jwtToken': authCode,
        },
      );
    }

    await AqApiService.instance.connectBrokerByEmail(
      email: widget.email,
      broker: 'Groww',
      brokerData: {
        'jwtToken': authCode,
        'status': 'connected',
      },
    );

    await _onConnectionSuccess();
  }

  /// Generic: send request_token to aq_backend.
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
    AqApiService.instance.changeBrokerModelPortfolio(
      email: widget.email,
      broker: widget.brokerName,
    ).catchError((_) {});
    setState(() => _status = 'success');
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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
