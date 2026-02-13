import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
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

  @override
  void initState() {
    super.initState();
    _initiateBrokerAuth();
  }

  Future<void> _initiateBrokerAuth() async {
    try {
      // Request login URL from aq_backend
      final response = await AqApiService.instance.getBrokerLoginUrl(
        broker: widget.brokerName,
        uid: widget.email,
        apiKey: '', // Broker API keys are managed server-side for TIDI
        secretKey: '',
        redirectUrl: 'https://tidiwealth.app/broker-callback',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = data['response']?['loginUrl'] ??
            data['response']?['login_url'] ??
            data['loginUrl'] ??
            data['response'];

        if (url != null && url is String && url.startsWith('http')) {
          setState(() {
            _status = 'webview';
          });
          _setupWebView(url);
        } else {
          setState(() {
            _status = 'error';
            _errorMessage = 'Invalid login URL received from server.';
          });
        }
      } else {
        setState(() {
          _status = 'error';
          _errorMessage = 'Failed to get broker login URL. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Network error. Please check your connection.';
      });
    }
  }

  void _setupWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Intercept the callback URL
            if (request.url.contains('broker-callback') ||
                request.url.contains('request_token') ||
                request.url.contains('auth_code')) {
              _handleAuthCallback(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            // Also check the final URL after page load
            if (url.contains('broker-callback') ||
                url.contains('request_token') ||
                url.contains('status=success')) {
              _handleAuthCallback(url);
            }
          },
          onWebResourceError: (error) {
            // Check if it's actually a redirect to our callback
            if (error.url != null &&
                (error.url!.contains('broker-callback') ||
                 error.url!.contains('request_token'))) {
              _handleAuthCallback(error.url!);
              return;
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  Future<void> _handleAuthCallback(String callbackUrl) async {
    setState(() => _status = 'loading');

    try {
      // Extract auth parameters from callback URL
      final uri = Uri.parse(callbackUrl);
      final requestToken = uri.queryParameters['request_token'] ??
          uri.queryParameters['auth_code'] ??
          uri.queryParameters['code'];

      if (requestToken != null) {
        // Send auth code to aq_backend to generate session
        final response = await AqApiService.instance.connectBroker(
          email: widget.email,
          broker: widget.brokerName,
          brokerData: {
            'request_token': requestToken,
            'status': 'connected',
          },
        );

        if (response.statusCode == 200) {
          // Invalidate broker cache
          setState(() => _status = 'success');
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) Navigator.pop(context, true);
          return;
        }
      }

      // Check for status=success in URL params
      if (uri.queryParameters['status'] == 'success') {
        setState(() => _status = 'success');
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context, true);
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
