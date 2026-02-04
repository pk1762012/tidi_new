import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Browser extends StatelessWidget {
  final String url;
  const Browser({
    super.key,
    required this.url
  });

  @override
  Widget build(BuildContext context) {
    // Build TradingView URL dynamically

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    return Scaffold(
      body: SafeArea(
        child: SizedBox.expand(
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
