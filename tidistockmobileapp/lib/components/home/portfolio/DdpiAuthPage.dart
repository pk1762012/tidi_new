import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/BrokerCryptoService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Unified EDIS / DDPI / TPIN authorization page for all brokers.
///
/// Broker flows:
///   - Zerodha:   POST zerodha/auth-sell → WebView URL → callback detection
///   - Dhan:      POST dhan/generate-tpin → POST dhan/enter-tpin → WebView HTML form
///   - Fyers:     POST fyers/tpin → POST fyers/submit-holdings → WebView HTML form
///   - Angel One: POST angelone/verify-dis → CDSL HTML form → WebView
///   - Others:    Manual instructions + confirmation checkbox
class DdpiAuthPage extends StatefulWidget {
  final BrokerConnection broker;
  /// Sell order symbols with ISINs/exchanges for EDIS flows that need them.
  final List<Map<String, dynamic>> sellOrders;
  /// User email — needed to persist EDIS status via PUT /api/update-edis-status
  /// (matching prod DdpiModal.js).
  final String? email;

  const DdpiAuthPage({
    super.key,
    required this.broker,
    this.sellOrders = const [],
    this.email,
  });

  @override
  State<DdpiAuthPage> createState() => _DdpiAuthPageState();
}

class _DdpiAuthPageState extends State<DdpiAuthPage> {
  String _state = 'info'; // info, loading, webview, success, error
  String? _errorMessage;
  WebViewController? _webViewController;
  bool _callbackHandled = false;
  bool _manualConfirmed = false;

  String get _brokerLower => widget.broker.broker.toLowerCase();
  String get _brokerName => widget.broker.broker;

  bool get _isZerodha => _brokerLower == 'zerodha';
  bool get _isDhan => _brokerLower == 'dhan';
  bool get _isFyers => _brokerLower == 'fyers';
  bool get _isAngelOne => _brokerLower == 'angel one' || _brokerLower == 'angelone';
  bool get _isManualBroker =>
      !_isZerodha && !_isDhan && !_isFyers && !_isAngelOne;

  String get _pageTitle {
    if (_isZerodha) return "DDPI Authorization";
    return "EDIS Authorization";
  }

  // ---------------------------------------------------------------------------
  // Authorization flows per broker
  // ---------------------------------------------------------------------------

  Future<void> _startAuthorization() async {
    setState(() => _state = 'loading');

    try {
      if (_isZerodha) {
        await _zerodhaFlow();
      } else if (_isDhan) {
        await _dhanFlow();
      } else if (_isFyers) {
        await _fyersFlow();
      } else if (_isAngelOne) {
        await _angelOneFlow();
      }
    } catch (e) {
      debugPrint('[EdisAuth:$_brokerName] error: $e');
      if (mounted) {
        setState(() {
          _state = 'error';
          _errorMessage = 'Authorization failed: $e';
        });
      }
    }
  }

  /// Zerodha: POST auth-sell → get auth_url → open in WebView
  /// Matches prod DdpiModal.js: sends decrypted apiKey + secretKey + accessToken.
  Future<void> _zerodhaFlow() async {
    final accessToken = widget.broker.jwtToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() {
        _state = 'error';
        _errorMessage = 'Zerodha session token is missing. Please reconnect.';
      });
      return;
    }

    // Decrypt apiKey/secretKey (stored encrypted with CryptoJS AES) — matching prod
    String? decryptedApiKey;
    String? decryptedSecretKey;
    try {
      if (widget.broker.apiKey != null && widget.broker.apiKey!.isNotEmpty) {
        decryptedApiKey = BrokerCryptoService.instance
            .decryptCredential(widget.broker.apiKey!);
      }
      if (widget.broker.secretKey != null && widget.broker.secretKey!.isNotEmpty) {
        decryptedSecretKey = BrokerCryptoService.instance
            .decryptCredential(widget.broker.secretKey!);
      }
    } catch (e) {
      debugPrint('[EdisAuth:Zerodha] credential decryption failed (using as-is): $e');
    }

    final response = await AqApiService.instance.zerodhaAuthSell(
      accessToken: accessToken,
      apiKey: decryptedApiKey,
      secretKey: decryptedSecretKey,
    );
    debugPrint('[EdisAuth:Zerodha] auth-sell status=${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final authUrl = data['auth_url'] as String?;
      if (authUrl != null && authUrl.isNotEmpty) {
        _setupWebViewUrl(authUrl);
      } else {
        setState(() {
          _state = 'error';
          _errorMessage = 'No authorization URL received from Zerodha.';
        });
      }
    } else {
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to initiate DDPI authorization (${response.statusCode}).';
      });
    }
  }

  /// Dhan: generate-tpin → enter-tpin (with ISIN) → EDIS HTML form in WebView
  Future<void> _dhanFlow() async {
    final clientId = widget.broker.clientCode ?? '';
    final accessToken = widget.broker.jwtToken ?? '';
    if (clientId.isEmpty || accessToken.isEmpty) {
      setState(() {
        _state = 'error';
        _errorMessage = 'Dhan credentials missing. Please reconnect.';
      });
      return;
    }

    // Step 1: Generate TPIN
    debugPrint('[EdisAuth:Dhan] Step 1: generate-tpin');
    final tpinResp = await AqApiService.instance.dhanGenerateTpin(
      clientId: clientId,
      accessToken: accessToken,
    );
    debugPrint('[EdisAuth:Dhan] generate-tpin status=${tpinResp.statusCode}');

    if (tpinResp.statusCode != 200) {
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to generate TPIN (${tpinResp.statusCode}).';
      });
      return;
    }

    // Step 2: Enter TPIN — needs ISIN of a holding to authorize
    // Use first sell order's details if available
    String isin = '';
    String symbol = '';
    String exchange = 'NSE';
    if (widget.sellOrders.isNotEmpty) {
      final first = widget.sellOrders.first;
      isin = (first['isin'] ?? '').toString();
      symbol = (first['symbol'] ?? first['tradingSymbol'] ?? '').toString();
      exchange = (first['exchange'] ?? 'NSE').toString();
    }

    debugPrint('[EdisAuth:Dhan] Step 2: enter-tpin (isin=$isin, symbol=$symbol)');
    final enterResp = await AqApiService.instance.dhanEnterTpin(
      clientId: clientId,
      accessToken: accessToken,
      isin: isin,
      symbol: symbol,
      exchange: exchange,
    );
    debugPrint('[EdisAuth:Dhan] enter-tpin status=${enterResp.statusCode}');

    if (enterResp.statusCode == 200) {
      final data = jsonDecode(enterResp.body);
      final edisFormHtml = data['data']?['edisFormHtml'] as String?;
      if (edisFormHtml != null && edisFormHtml.isNotEmpty) {
        _setupWebViewHtml(edisFormHtml);
      } else {
        setState(() {
          _state = 'error';
          _errorMessage = 'No EDIS form received from Dhan.';
        });
      }
    } else {
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to get EDIS form (${enterResp.statusCode}).';
      });
    }
  }

  /// Fyers: tpin → submit-holdings → HTML form in WebView
  Future<void> _fyersFlow() async {
    final clientId = widget.broker.clientCode ?? '';
    final accessToken = widget.broker.jwtToken ?? '';
    if (clientId.isEmpty || accessToken.isEmpty) {
      setState(() {
        _state = 'error';
        _errorMessage = 'Fyers credentials missing. Please reconnect.';
      });
      return;
    }

    // Step 1: Generate TPIN
    debugPrint('[EdisAuth:Fyers] Step 1: generate tpin');
    final tpinResp = await AqApiService.instance.fyersGenerateTpin(
      clientId: clientId,
      accessToken: accessToken,
    );
    debugPrint('[EdisAuth:Fyers] tpin status=${tpinResp.statusCode}');

    if (tpinResp.statusCode != 200) {
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to generate TPIN (${tpinResp.statusCode}).';
      });
      return;
    }

    // Step 2: Submit holdings
    debugPrint('[EdisAuth:Fyers] Step 2: submit-holdings');
    final submitResp = await AqApiService.instance.fyersSubmitHoldings(
      clientId: clientId,
      accessToken: accessToken,
    );
    debugPrint('[EdisAuth:Fyers] submit-holdings status=${submitResp.statusCode}');

    if (submitResp.statusCode == 200) {
      final data = jsonDecode(submitResp.body);
      final htmlData = data['data'];
      if (htmlData is String && htmlData.isNotEmpty) {
        _setupWebViewHtml(htmlData);
      } else {
        setState(() {
          _state = 'error';
          _errorMessage = 'No EDIS form received from Fyers.';
        });
      }
    } else {
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to get holdings form (${submitResp.statusCode}).';
      });
    }
  }

  /// Angel One: verify-dis → CDSL form with DPId/ReqId/TransDtls → WebView
  Future<void> _angelOneFlow() async {
    final clientId = widget.broker.clientCode ?? '';
    final jwtToken = widget.broker.jwtToken ?? '';
    if (clientId.isEmpty || jwtToken.isEmpty) {
      setState(() {
        _state = 'error';
        _errorMessage = 'Angel One credentials missing. Please reconnect.';
      });
      return;
    }

    debugPrint('[EdisAuth:AngelOne] verify-dis');
    final verifyResp = await AqApiService.instance.angelOneVerifyDis(
      clientId: clientId,
      jwtToken: jwtToken,
    );
    debugPrint('[EdisAuth:AngelOne] verify-dis status=${verifyResp.statusCode}');

    if (verifyResp.statusCode == 200) {
      final data = jsonDecode(verifyResp.body);

      // If already EDIS-authorized, no need for form
      if (data['edis'] == true) {
        if (mounted) {
          setState(() => _state = 'success');
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.pop(context, true);
          });
        }
        return;
      }

      // Build CDSL form HTML
      final formData = data['data'] ?? {};
      final dpId = formData['DPId'] ?? '';
      final reqId = formData['ReqId'] ?? '';
      final transDtls = formData['TransDtls'] ?? '';

      if (dpId.isEmpty && reqId.isEmpty) {
        setState(() {
          _state = 'error';
          _errorMessage = 'CDSL form data not available. ${data['error'] ?? ''}';
        });
        return;
      }

      final advisorSubdomain = dotenv.env['AQ_ADVISOR_SUBDOMAIN'] ?? 'prod';
      final returnUrl = advisorSubdomain == 'prod'
          ? 'https://prod.alphaquark.in/stock-recommendation'
          : 'https://test.alphaquark.in/stock-recommendation';

      final html = '''
<!DOCTYPE html>
<html>
<script>window.onload = function() { document.getElementById("submitBtn").click(); }</script>
<body>
  <form name="frmDIS" method="post" action="https://edis.cdslindia.com/eDIS/VerifyDIS/" style="display:none;">
    <input type="hidden" name="DPId" value="$dpId" />
    <input type="hidden" name="ReqId" value="$reqId" />
    <input type="hidden" name="Version" value="1.1" />
    <input type="hidden" name="TransDtls" value="$transDtls" />
    <input type="hidden" name="returnURL" value="$returnUrl" />
    <input id="submitBtn" type="submit" />
  </form>
</body>
</html>
''';
      _setupWebViewHtml(html);
    } else {
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to verify EDIS status (${verifyResp.statusCode}).';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // WebView setup
  // ---------------------------------------------------------------------------

  void _setupWebViewUrl(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(_buildNavigationDelegate())
      ..loadRequest(Uri.parse(url));
    setState(() => _state = 'webview');
  }

  void _setupWebViewHtml(String html) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(_buildNavigationDelegate())
      ..loadHtmlString(html);
    setState(() => _state = 'webview');
  }

  NavigationDelegate _buildNavigationDelegate() {
    return NavigationDelegate(
      onNavigationRequest: (request) {
        if (_isCallbackUrl(request.url)) {
          _handleAuthComplete();
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onPageFinished: (url) {
        if (_isCallbackUrl(url)) {
          _handleAuthComplete();
        }
      },
      onWebResourceError: (error) {
        if (error.url != null && _isCallbackUrl(error.url!)) {
          _handleAuthComplete();
        }
      },
    );
  }

  bool _isCallbackUrl(String url) {
    // Zerodha-specific
    if (url.contains('callback_url') ||
        url.contains('postback') ||
        url.contains('connect/finish')) {
      return true;
    }
    // Dhan: looks for ReturnUrl or failure
    if (_isDhan && (url.contains('ReturnUrl') || url.contains('returnurl'))) {
      return true;
    }
    // Fyers: success page
    if (_isFyers && url.contains('success')) return true;
    // Angel One: stock-recommendation return URL
    if (_isAngelOne && url.contains('stock-recommendation')) return true;
    // Generic patterns
    if (url.contains('status=success') || url.contains('broker-callback')) {
      return true;
    }
    return false;
  }

  void _handleAuthComplete() {
    if (_callbackHandled) return;
    _callbackHandled = true;

    debugPrint('[EdisAuth:$_brokerName] Authorization complete');
    setState(() => _state = 'success');

    // Persist is_authorized_for_sell in DB (matching prod DdpiModal.js handleProceed)
    _persistEdisStatus();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pop(context, true);
    });
  }

  /// Persist EDIS authorization status to DB matching prod DdpiModal.js:
  ///   PUT /api/update-edis-status { uid, is_authorized_for_sell: true, user_broker }
  Future<void> _persistEdisStatus() async {
    if (widget.email == null || widget.email!.isEmpty) {
      debugPrint('[EdisAuth:$_brokerName] No email provided, skipping EDIS status update');
      return;
    }
    try {
      final userDetails = await AqApiService.instance.getUserDetails(widget.email!);
      final uid = userDetails?['_id']?.toString() ?? '';
      if (uid.isEmpty) {
        debugPrint('[EdisAuth:$_brokerName] No user UID found, skipping EDIS status update');
        return;
      }

      await AqApiService.instance.updateEdisStatus(
        uid: uid,
        isAuthorizedForSell: true,
        userBroker: _brokerName,
      );
      debugPrint('[EdisAuth:$_brokerName] EDIS status persisted: is_authorized_for_sell=true');
    } catch (e) {
      debugPrint('[EdisAuth:$_brokerName] Failed to persist EDIS status: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Build UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_state == 'webview' && _webViewController != null) {
      return CustomScaffold(
        allowBackNavigation: true,
        displayActions: false,
        imageUrl: null,
        menu: _pageTitle,
        child: Column(
          children: [
            Expanded(
              child: WebViewWidget(controller: _webViewController!),
            ),
            _manualCompleteButton(),
          ],
        ),
      );
    }

    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: _pageTitle,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildContent(),
      ),
    );
  }

  Widget _manualCompleteButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _handleAuthComplete,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "I've completed authorization",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_state == 'loading') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _isZerodha
                  ? "Initiating DDPI authorization..."
                  : "Initiating EDIS authorization...",
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_state == 'success') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade600),
            const SizedBox(height: 16),
            const Text("Authorization Complete",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text("Your shares are now authorized for selling.",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    if (_state == 'error') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text("Authorization Failed",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error',
                style: TextStyle(fontSize: 14, color: Colors.red.shade600),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    _callbackHandled = false;
                    _startAuthorization();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Retry"),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // info state — show broker-appropriate info and "Proceed" button
    if (_isManualBroker) return _buildManualAuthContent();
    return _buildApiAuthContent();
  }

  /// Info screen for brokers with API-based EDIS (Zerodha, Dhan, Fyers, Angel One)
  Widget _buildApiAuthContent() {
    final brokerLabel = _isZerodha ? 'DDPI/TPIN' : 'EDIS/TPIN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security, color: Colors.amber.shade800, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text("Share Authorization Required",
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "To sell shares from your $_brokerName demat account, you need to "
                "authorize them via CDSL's $brokerLabel process.\n\n"
                "This is a one-time authorization mandated by SEBI for the "
                "safety of your holdings. You will be redirected to "
                "${_isAngelOne ? "CDSL's" : "$_brokerName's"} secure portal "
                "to complete the verification.",
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade700, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("What happens next:",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800)),
              const SizedBox(height: 10),
              if (_isDhan || _isFyers) ...[
                _stepRow("1", "We'll generate a TPIN on your $_brokerName account"),
                _stepRow("2", "You'll be redirected to CDSL's portal"),
                _stepRow("3", "Enter your TPIN to authorize your shares"),
                _stepRow("4", "Once done, you'll be brought back here"),
              ] else if (_isAngelOne) ...[
                _stepRow("1", "We'll verify your EDIS status with Angel One"),
                _stepRow("2", "You'll be redirected to CDSL's TPIN portal"),
                _stepRow("3", "Enter your TPIN to authorize your shares"),
                _stepRow("4", "Once done, you'll be brought back here"),
              ] else ...[
                _stepRow("1", "You'll be redirected to the authorization portal"),
                _stepRow("2", "Enter your TPIN to authorize your shares"),
                _stepRow("3", "Once done, you'll be brought back here"),
              ],
            ],
          ),
        ),
        const Spacer(),
        SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _startAuthorization,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text("Proceed with Authorization",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text("Skip for now",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Info screen for brokers with manual EDIS (IIFL, ICICI, Upstox, Kotak, HDFC, AliceBlue)
  Widget _buildManualAuthContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security, color: Colors.amber.shade800, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text("Manual Authorization Required",
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "To sell shares via $_brokerName, you need to authorize "
                "them through your broker's EDIS/TPIN process.\n\n"
                "Please open the $_brokerName app or website and complete "
                "the CDSL TPIN authorization for your holdings before proceeding.",
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade700, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Steps to authorize:",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800)),
              const SizedBox(height: 10),
              _stepRow("1", "Open the $_brokerName app on your phone"),
              _stepRow("2", "Go to Holdings / Portfolio section"),
              _stepRow("3", "Look for EDIS / TPIN / Authorize option"),
              _stepRow("4", "Complete CDSL TPIN verification"),
              _stepRow("5", "Come back here and confirm below"),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Confirmation checkbox
        GestureDetector(
          onTap: () => setState(() => _manualConfirmed = !_manualConfirmed),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _manualConfirmed,
                onChanged: (v) =>
                    setState(() => _manualConfirmed = v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    "I have completed EDIS/TPIN authorization on the "
                    "$_brokerName app and my shares are now authorized for selling.",
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _manualConfirmed
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text("I've Authorized — Continue",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text("Skip for now",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(num,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade700, height: 1.3)),
          ),
        ],
      ),
    );
  }
}
