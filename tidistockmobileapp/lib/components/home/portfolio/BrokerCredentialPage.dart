import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:tidistockmobileapp/models/broker_config.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/BrokerSessionService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrokerCredentialPage extends StatefulWidget {
  final String email;
  final BrokerConfig brokerConfig;

  const BrokerCredentialPage({
    super.key,
    required this.email,
    required this.brokerConfig,
  });

  @override
  State<BrokerCredentialPage> createState() => _BrokerCredentialPageState();
}

class _BrokerCredentialPageState extends State<BrokerCredentialPage> {
  String _status = 'form'; // form, loading, webview, success, error
  String? _errorMessage;
  late WebViewController _webViewController;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _obscured = {};
  bool _instructionsExpanded = true;

  @override
  void initState() {
    super.initState();
    for (final field in widget.brokerConfig.fields) {
      _controllers[field.key] = TextEditingController();
      if (field.isSecret) _obscured[field.key] = true;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectFieldValues() {
    final values = <String, String>{};
    for (final field in widget.brokerConfig.fields) {
      values[field.key] = _controllers[field.key]!.text.trim();
    }
    return values;
  }

  bool _validateFields() {
    for (final field in widget.brokerConfig.fields) {
      if (_controllers[field.key]!.text.trim().isEmpty) {
        setState(() {
          _status = 'error';
          _errorMessage = '${field.label} is required.';
        });
        return false;
      }
    }
    // Kotak-specific validation
    if (widget.brokerConfig.key == 'kotak') {
      final mobile = _controllers['mobileNumber']?.text.trim() ?? '';
      if (mobile.length != 10 || !RegExp(r'^\d{10}$').hasMatch(mobile)) {
        setState(() {
          _status = 'error';
          _errorMessage = 'Mobile number must be exactly 10 digits.';
        });
        return false;
      }
      final mpin = _controllers['mpin']?.text.trim() ?? '';
      if (mpin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(mpin)) {
        setState(() {
          _status = 'error';
          _errorMessage = 'M-PIN must be exactly 6 digits.';
        });
        return false;
      }
      final totp = _controllers['totp']?.text.trim() ?? '';
      if (totp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(totp)) {
        setState(() {
          _status = 'error';
          _errorMessage = 'TOTP must be exactly 6 digits.';
        });
        return false;
      }
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Per-broker connection logic
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _submitCredentials() async {
    if (!_validateFields()) return;
    setState(() => _status = 'loading');

    final values = _collectFieldValues();
    final api = AqApiService.instance;

    try {
      // Get user's MongoDB ObjectId (needed by most endpoints)
      final uid = await api.getUserObjectId(widget.email);
      debugPrint('[BrokerCredential] uid=$uid for email=${widget.email}');

      switch (widget.brokerConfig.key) {
        case 'zerodha':
          await _connectZerodha(uid, values);
          break;
        case 'upstox':
          await _connectUpstox(uid, values);
          break;
        case 'fyers':
          await _connectFyers(uid, values);
          break;
        case 'hdfc':
          await _connectHdfc(uid, values);
          break;
        case 'icicidirect':
          await _connectIcici(uid, values);
          break;
        case 'motilal':
          await _connectMotilal(uid, values);
          break;
        case 'kotak':
          await _connectKotak(uid, values);
          break;
        case 'dhan':
          await _connectDhan(uid, values);
          break;
        case 'aliceblue':
          await _connectAliceBlue(uid, values);
          break;
        // Groww and IIFL are OAuth — handled by BrokerAuthPage, not this page.
        default:
          // Fallback: use email-based multi-broker connect
          await _fallbackConnect(values);
          break;
      }
    } catch (e) {
      debugPrint('[BrokerCredential] Error: $e');
      setState(() {
        _status = 'error';
        _errorMessage = 'Network error. Please check your connection.';
      });
    }
  }

  // ── Zerodha: PUT api/zerodha/update-key → OAuth redirect ──────────
  Future<void> _connectZerodha(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectZerodha(
      uid: uid,
      apiKey: values['apiKey']!,
      secretKey: values['secretKey']!,
      redirectUrl: widget.brokerConfig.redirectUrl ??
          'https://ccxt.alphaquark.in/zerodha/callback',
    );

    if (resp.statusCode == 200) {
      _handleOAuthResponse(resp);
    } else {
      debugPrint('[Zerodha] update-key failed: ${resp.statusCode} ${resp.body}');
      await _fallbackConnect(values);
    }
  }

  // ── Upstox: POST api/upstox/update-key → OAuth redirect ──────────
  Future<void> _connectUpstox(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectUpstox(
      uid: uid,
      apiKey: values['apiKey']!,
      secretKey: values['secretKey']!,
      redirectUri: 'https://prod.alphaquark.in/stock-recommendation',
    );

    if (resp.statusCode == 200) {
      _handleOAuthResponse(resp);
    } else {
      debugPrint('[Upstox] update-key failed: ${resp.statusCode} ${resp.body}');
      await _fallbackConnect(values);
    }
  }

  // ── Fyers: POST api/fyers/update-key → OAuth redirect ────────────
  Future<void> _connectFyers(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectFyers(
      uid: uid,
      clientCode: values['clientCode']!,
      secretKey: values['secretKey']!,
      redirectUrl: 'https://prod.alphaquark.in/stock-recommendation',
    );

    if (resp.statusCode == 200) {
      _handleOAuthResponse(resp);
    } else {
      debugPrint('[Fyers] update-key failed: ${resp.statusCode} ${resp.body}');
      await _fallbackConnect(values);
    }
  }

  // ── HDFC: POST api/hdfc/update-key → OAuth redirect ──────────────
  Future<void> _connectHdfc(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectHdfc(
      uid: uid,
      apiKey: values['apiKey']!,
      secretKey: values['secretKey']!,
    );

    if (resp.statusCode == 200) {
      _handleOAuthResponse(resp);
    } else {
      debugPrint('[HDFC] update-key failed: ${resp.statusCode} ${resp.body}');
      await _fallbackConnect(values);
    }
  }

  // ── ICICI: PUT api/icici/update-key → redirect to ICICI login ─────
  Future<void> _connectIcici(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectIcici(
      uid: uid,
      apiKey: values['apiKey']!,
      secretKey: values['secretKey']!,
    );

    if (resp.statusCode == 200) {
      // Try to extract loginUrl from backend response (like other hybrid brokers)
      try {
        final data = jsonDecode(resp.body);
        final url = data['response']?['loginUrl'] ??
            data['response']?['login_url'] ??
            data['loginUrl'] ??
            (data['response'] is String ? data['response'] : null);
        if (url != null && url is String && url.startsWith('http')) {
          setState(() => _status = 'webview');
          _setupWebView(url);
          return;
        }
      } catch (_) {}
      // Fallback: ICICI login URL constructed with user's API key
      final loginUrl =
          'https://api.icicidirect.com/apiuser/login?api_key=${Uri.encodeComponent(values['apiKey']!)}';
      setState(() => _status = 'webview');
      _setupWebView(loginUrl);
    } else {
      debugPrint('[ICICI] update-key failed: ${resp.statusCode} ${resp.body}');
      await _fallbackConnect(values);
    }
  }

  // ── Motilal: PUT api/motilal-oswal/update-key → OAuth redirect ────
  Future<void> _connectMotilal(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectMotilal(
      uid: uid,
      apiKey: values['apiKey']!,
      clientCode: values['clientCode']!,
      redirectUrl: widget.brokerConfig.redirectUrl ??
          'https://ccxt.alphaquark.in/motilal-oswal/callback',
    );

    if (resp.statusCode == 200) {
      _handleOAuthResponse(resp);
    } else {
      debugPrint('[Motilal] update-key failed: ${resp.statusCode} ${resp.body}');
      await _fallbackConnect(values);
    }
  }

  // ── Kotak: PUT api/kotak/connect-broker → direct auth ─────────────
  Future<void> _connectKotak(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectKotak(
      uid: uid,
      apiKey: values['apiKey']!,
      secretKey: values['secretKey']!,
      mobileNumber: '+91${values['mobileNumber']}',
      mpin: values['mpin']!,
      ucc: values['ucc']!,
      totp: values['totp']!,
    );

    if (resp.statusCode == 200) {
      await _onConnectionSuccess();
    } else {
      debugPrint('[Kotak] connect failed: ${resp.statusCode} ${resp.body}');
      _handleApiError(resp);
    }
  }

  // ── Dhan: PUT api/user/connect-broker with clientCode + jwtToken ──
  Future<void> _connectDhan(String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectCredentialBroker(
      uid: uid,
      userBroker: 'Dhan',
      credentials: {
        'clientCode': values['clientCode'],
        'jwtToken': values['jwtToken'],
      },
    );

    if (resp.statusCode == 200) {
      await _onConnectionSuccess();
    } else {
      debugPrint('[Dhan] connect failed: ${resp.statusCode} ${resp.body}');
      _handleApiError(resp);
    }
  }

  // ── AliceBlue: PUT api/user/connect-broker with clientCode + apiKey
  Future<void> _connectAliceBlue(
      String? uid, Map<String, String> values) async {
    if (uid == null) return _fallbackConnect(values);

    final resp = await AqApiService.instance.connectCredentialBroker(
      uid: uid,
      userBroker: 'AliceBlue',
      credentials: {
        'clientCode': values['clientCode'],
        'apiKey': values['apiKey'],
      },
    );

    if (resp.statusCode == 200) {
      await _onConnectionSuccess();
    } else {
      debugPrint('[AliceBlue] connect failed: ${resp.statusCode} ${resp.body}');
      _handleApiError(resp);
    }
  }

  // ── Fallback: use email-based multi-broker connect ────────────────
  Future<void> _fallbackConnect(Map<String, String> values) async {
    debugPrint('[BrokerCredential] Using email-based fallback for ${widget.brokerConfig.name}');
    try {
      final resp = await AqApiService.instance.connectBrokerByEmail(
        email: widget.email,
        broker: widget.brokerConfig.name,
        brokerData: {...values, 'status': 'connected'},
      );

      if (resp.statusCode == 200) {
        await _onConnectionSuccess();
      } else {
        _handleApiError(resp);
      }
    } catch (_) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Network error. Please check your connection.';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────

  /// Handle OAuth response from hybrid broker update-key endpoints.
  /// Extracts login URL and opens WebView.
  void _handleOAuthResponse(http.Response resp) {
    try {
      final data = jsonDecode(resp.body);
      final url = data['response']?['loginUrl'] ??
          data['response']?['login_url'] ??
          data['loginUrl'] ??
          data['response'];

      if (url != null && url is String && url.startsWith('http')) {
        setState(() => _status = 'webview');
        _setupWebView(url);
      } else {
        // No valid URL in response
        debugPrint('[BrokerCredential] No valid OAuth URL in response: $data');
        setState(() {
          _status = 'error';
          _errorMessage =
              'Could not get login URL. Please check your credentials.';
        });
      }
    } catch (e) {
      debugPrint('[BrokerCredential] Error parsing OAuth response: $e');
      setState(() {
        _status = 'error';
        _errorMessage = 'Unexpected response from server.';
      });
    }
  }

  /// Handle API error responses.
  void _handleApiError(http.Response resp) {
    String msg = 'Failed to connect broker. Please verify your credentials.';
    try {
      final data = jsonDecode(resp.body);
      if (data['message'] != null) {
        msg = data['message'];
      } else if (data['error'] != null) {
        msg = data['error'];
      }
    } catch (_) {}
    setState(() {
      _status = 'error';
      _errorMessage = msg;
    });
  }

  /// Called on successful broker connection.
  Future<void> _onConnectionSuccess() async {
    CacheService.instance.invalidate('aq/user/brokers:${widget.email}');
    await BrokerSessionService.instance
        .saveSessionTime(widget.brokerConfig.name);
    // Non-critical: sync model portfolio broker
    AqApiService.instance
        .changeBrokerModelPortfolio(
          email: widget.email,
          broker: widget.brokerConfig.name,
        )
        .catchError((_) {});
    setState(() => _status = 'success');
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.pop(context, true);
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
        url.contains('stock-recommendation') ||
        url.contains('zerodha/callback') ||
        url.contains('motilal-oswal/callback') ||
        url.contains('icici/auth-callback') ||
        url.contains('status=success');
  }

  Future<void> _handleAuthCallback(String callbackUrl) async {
    setState(() => _status = 'loading');

    try {
      final uri = Uri.parse(callbackUrl);
      final requestToken = uri.queryParameters['request_token'] ??
          uri.queryParameters['auth_code'] ??
          uri.queryParameters['code'];

      if (requestToken != null) {
        // Send the token to the server to complete connection
        final uid = await AqApiService.instance.getUserObjectId(widget.email);
        http.Response response;

        if (uid != null) {
          response = await AqApiService.instance.connectCredentialBroker(
            uid: uid,
            userBroker: widget.brokerConfig.name,
            credentials: {
              'jwtToken': requestToken,
              'request_token': requestToken,
            },
          );
        } else {
          response = await AqApiService.instance.connectBrokerByEmail(
            email: widget.email,
            broker: widget.brokerConfig.name,
            brokerData: {
              'request_token': requestToken,
              'status': 'connected',
            },
          );
        }

        if (response.statusCode == 200) {
          await _onConnectionSuccess();
          return;
        }
      }

      if (uri.queryParameters['status'] == 'success') {
        await _onConnectionSuccess();
        return;
      }

      setState(() {
        _status = 'error';
        _errorMessage = 'Authentication failed. Please try again.';
      });
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Failed to complete broker authentication.';
      });
    }
  }

  void _openYouTubeVideo() async {
    final videoId = widget.brokerConfig.youtubeVideoId;
    if (videoId == null) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Connect ${widget.brokerConfig.name}",
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case 'form':
        return _buildForm();
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
        return _buildSuccess();
      case 'error':
        return _buildError();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBrokerLogo({double size = 56}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        widget.brokerConfig.logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              widget.brokerConfig.iconLetter,
              style: TextStyle(
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final hasVideo = widget.brokerConfig.youtubeVideoId != null;
    final hasSteps = widget.brokerConfig.instructionSteps.isNotEmpty;
    final hasNote = widget.brokerConfig.instructionNote != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // ── Broker logo header ──────────────────────────────────────
        Center(child: _buildBrokerLogo(size: 56)),
        const SizedBox(height: 10),
        Center(
          child: Text(
            widget.brokerConfig.name,
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            widget.brokerConfig.authType == BrokerAuthType.credential
                ? "Enter your credentials to connect"
                : "Enter your API details, then complete login",
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),

        // ── YouTube video link ──────────────────────────────────────
        if (hasVideo) ...[
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _openYouTubeVideo,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
                color: Colors.red.shade50,
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(11)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.network(
                          'https://img.youtube.com/vi/${widget.brokerConfig.youtubeVideoId}/mqdefault.jpg',
                          width: double.infinity,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 160,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.play_circle_outline,
                                  size: 48, color: Colors.grey),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.85),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_filled,
                            size: 18, color: Colors.red.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Watch Setup Tutorial',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700),
                          ),
                        ),
                        Icon(Icons.open_in_new,
                            size: 16, color: Colors.red.shade400),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // ── Instruction steps ───────────────────────────────────────
        if (hasSteps) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12)),
                  onTap: () => setState(
                      () => _instructionsExpanded = !_instructionsExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.list_alt,
                            size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Setup Instructions',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800),
                          ),
                        ),
                        Icon(
                          _instructionsExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 22,
                          color: Colors.blue.shade600,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_instructionsExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        ...widget.brokerConfig.instructionSteps
                            .asMap()
                            .entries
                            .map((entry) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        margin: const EdgeInsets.only(
                                            right: 10, top: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade600,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${entry.key + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          entry.value,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue.shade900,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ── Instruction note / warning ──────────────────────────────
        if (hasNote) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.brokerConfig.instructionNote!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── Credential form fields ──────────────────────────────────
        ...widget.brokerConfig.fields.map((field) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: _controllers[field.key],
                obscureText: _obscured[field.key] ?? false,
                keyboardType: _keyboardTypeForField(field),
                decoration: InputDecoration(
                  labelText: field.label,
                  hintText: field.placeholder,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  suffixIcon: field.isSecret
                      ? IconButton(
                          icon: Icon(
                            (_obscured[field.key] ?? false)
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscured[field.key] =
                                  !(_obscured[field.key] ?? false);
                            });
                          },
                        )
                      : null,
                ),
              ),
            )),

        const SizedBox(height: 8),

        // ── Submit button ───────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _submitCredentials,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              widget.brokerConfig.authType == BrokerAuthType.credential
                  ? "Connect"
                  : "Continue to Login",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  TextInputType _keyboardTypeForField(BrokerFieldConfig field) {
    if (field.key == 'mobileNumber' ||
        field.key == 'mpin' ||
        field.key == 'totp') {
      return TextInputType.number;
    }
    return TextInputType.text;
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBrokerLogo(size: 48),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle,
                size: 60, color: Colors.green.shade400),
          ),
          const SizedBox(height: 20),
          const Text("Broker Connected!",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              "${widget.brokerConfig.name} has been connected successfully.",
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBrokerLogo(size: 48),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline,
                  size: 60, color: Colors.red.shade400),
            ),
            const SizedBox(height: 20),
            const Text("Connection Failed",
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? "Something went wrong.",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => setState(() => _status = 'form'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Try Again",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
