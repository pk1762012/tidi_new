import 'package:flutter/material.dart';
import '../../../widgets/Browser.dart';
import '../../../widgets/customScaffold.dart';

class BrowserPage extends StatelessWidget {
  final String url;
  const BrowserPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
        allowBackNavigation: true,
        displayActions: false,
        imageUrl: null,
        menu: null,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox.expand(
            child: Browser(url: url),
          ),
        )
    );
  }
}
