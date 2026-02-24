import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// DDPI / TPIN authorization page for Zerodha sell orders.
///
/// Flow:
///   1. Show info about why DDPI authorization is needed
///   2. On "Proceed": POST zerodha/auth-sell → get auth_url
///   3. Open auth_url in WebView
///   4. Monitor navigation for callback_url → pop with true
///   5. Back/cancel → pop with false
class DdpiAuthPage extends StatefulWidget {
  final String accessToken;

  const DdpiAuthPage({
    super.key,
    required this.accessToken,
  });

  @override
  State<DdpiAuthPage> createState() => _DdpiAuthPageState();
}

class _DdpiAuthPageState extends State<DdpiAuthPage> {
  String _state = 'info'; // info, loading, webview, success, error
  String? _errorMessage;
  WebViewController? _webViewController;
  bool _callbackHandled = false;

  Future<void> _startAuthorization() async {
    setState(() => _state = 'loading');

    try {
      final response = await AqApiService.instance.zerodhaAuthSell(
        accessToken: widget.accessToken,
      );

      debugPrint('[DdpiAuth] auth-sell status=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final authUrl = data['auth_url'] as String?;

        if (authUrl != null && authUrl.isNotEmpty) {
          _setupWebView(authUrl);
        } else {
          setState(() {
            _state = 'error';
            _errorMessage = 'No authorization URL received from server.';
          });
        }
      } else {
        setState(() {
          _state = 'error';
          _errorMessage = 'Failed to initiate DDPI authorization (${response.statusCode}).';
        });
      }
    } catch (e) {
      debugPrint('[DdpiAuth] error: $e');
      setState(() {
        _state = 'error';
        _errorMessage = 'Failed to initiate authorization: $e';
      });
    }
  }

  void _setupWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
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
      ))
      ..loadRequest(Uri.parse(url));

    setState(() => _state = 'webview');
  }

  bool _isCallbackUrl(String url) {
    return url.contains('callback_url') ||
        url.contains('postback') ||
        url.contains('connect/finish') ||
        url.contains('status=success') ||
        url.contains('broker-callback');
  }

  void _handleAuthComplete() {
    if (_callbackHandled) return;
    _callbackHandled = true;

    debugPrint('[DdpiAuth] Authorization complete');
    setState(() => _state = 'success');

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_state == 'webview' && _webViewController != null) {
      return CustomScaffold(
        allowBackNavigation: true,
        displayActions: false,
        imageUrl: null,
        menu: "DDPI Authorization",
        child: Column(
          children: [
            Expanded(
              child: WebViewWidget(controller: _webViewController!),
            ),
            // Manual complete button in case callback detection fails
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
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
            ),
          ],
        ),
      );
    }

    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "DDPI Authorization",
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_state == 'loading') {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Initiating DDPI authorization...",
                style: TextStyle(fontSize: 15, color: Colors.grey)),
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

    // info state — explain DDPI and offer "Proceed"
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
                  Text("Share Authorization Required",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade900)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "To sell shares from your Zerodha demat account, you need to "
                "authorize them via CDSL's DDPI/TPIN process.\n\n"
                "This is a one-time authorization mandated by SEBI for the "
                "safety of your holdings. You will be redirected to CDSL's "
                "secure portal to complete the verification.",
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.5),
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
              _stepRow("1", "You'll be redirected to CDSL's TPIN portal"),
              _stepRow("2", "Enter your TPIN to authorize your shares"),
              _stepRow("3", "Once done, you'll be brought back here"),
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
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
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
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.3)),
          ),
        ],
      ),
    );
  }
}
