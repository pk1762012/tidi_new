import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TradingViewUrlChart extends StatelessWidget {
  final String symbol;

  const TradingViewUrlChart({
    super.key,
    required this.symbol
  });

  @override
  Widget build(BuildContext context) {
    // Build TradingView URL dynamically
    final encodedSymbol = Uri.encodeComponent("NSE:$symbol");
    final url = "https://www.tradingview.com/chart/?symbol=$encodedSymbol";

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
