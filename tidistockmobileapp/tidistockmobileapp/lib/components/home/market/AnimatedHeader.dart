import 'dart:async';
import 'package:flutter/material.dart';

class HorizontalTickerHeader extends StatefulWidget {
  const HorizontalTickerHeader({super.key});

  @override
  State<HorizontalTickerHeader> createState() => _HorizontalTickerHeaderState();
}

class _HorizontalTickerHeaderState extends State<HorizontalTickerHeader> {
  final List<String> headers = [
    "Stock Analysis",
    "Analyst Opinion",
    "Technical Signals",
    "Market Trends",
  ];

  final ScrollController _scrollController = ScrollController();
  late Timer _timer;
  double _scrollPosition = 0;

  // Tweak these to adjust scroll speed
  final double _scrollSpeed = 1.0; // pixels per tick
  final int _tickDurationMs = 20;

  @override
  void initState() {
    super.initState();
    _startScrolling();
  }

  void _startScrolling() {
    _timer = Timer.periodic(Duration(milliseconds: _tickDurationMs), (timer) {
      if (!_scrollController.hasClients) return;

      _scrollPosition += _scrollSpeed;

      if (_scrollPosition >= _scrollController.position.maxScrollExtent) {
        _scrollPosition = 0;
      }

      _scrollController.jumpTo(_scrollPosition);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horizontal ticker
        SizedBox(
          height: 40,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: headers.length * 2, // duplicate for smooth loop
            itemBuilder: (context, index) {
              final text = headers[index % headers.length];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 5),

        // Subtitle (fixed)
        const Text(
          "Get deep insights into trends, signals and technical outlooks.",
          style: TextStyle(
            fontSize: 14.2,
            height: 1.35,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
