import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class AqWebViewPage extends StatefulWidget {
  final String url;
  final String title;

  const AqWebViewPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<AqWebViewPage> createState() => _AqWebViewPageState();
}

class _AqWebViewPageState extends State<AqWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (message) {
          _onEmailCaptured(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            _tryExtractEmail();
          },
          onNavigationRequest: (request) {
            final url = request.url;
            // Allow navigation within the AQ web app and Firebase auth domains
            if (url.contains('alphaquark.in') ||
                url.contains('firebaseapp.com') ||
                url.contains('googleapis.com') ||
                url.contains('localhost')) {
              return NavigationDecision.navigate;
            }
            // Open external links in the system browser
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      );

    // Enable third-party cookies on Android so Firebase auth session persists
    // across app restarts (Firebase uses cross-domain cookies for auth)
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, true);
    }

    _controller.loadRequest(Uri.parse(widget.url));
  }

  /// After each page load, try to read the logged-in user's email from
  /// the AQ web app's localStorage (key: "userDetails").
  void _tryExtractEmail() {
    _controller.runJavaScript('''
      (function() {
        try {
          var raw = localStorage.getItem("userDetails");
          if (raw) {
            var obj = JSON.parse(raw);
            var email = obj.email || obj.user_email || "";
            if (email) FlutterBridge.postMessage(email);
          }
        } catch(e) {}
      })();
    ''');
  }

  Future<void> _onEmailCaptured(String email) async {
    if (email.isEmpty) return;
    debugPrint('[AqWebView] captured email: $email');
    const storage = FlutterSecureStorage();
    await storage.write(key: 'user_email', value: email);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: widget.title,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
