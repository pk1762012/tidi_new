import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../theme/theme.dart';

class PolicyScreen extends StatelessWidget {
  final String title;
  final String markdownData;

  const PolicyScreen({
    super.key,
    required this.title,
    required this.markdownData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: lightColorScheme.onSecondary,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Markdown(
          data: markdownData,
        ),
      ),
    );
  }
}
