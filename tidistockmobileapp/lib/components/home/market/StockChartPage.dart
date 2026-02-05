import 'package:flutter/material.dart';
import '../../../widgets/TradingViewChart.dart';
import '../../../widgets/customScaffold.dart';

class StockChartPage extends StatelessWidget {
  final String symbol;
  const StockChartPage({super.key, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: symbol,
      // make sure CustomScaffold internally has Scaffold(resizeToAvoidBottomInset: true)
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.expand(   // fills all remaining space
          child: TradingViewUrlChart(symbol: symbol),
        ),
      )
    );
  }
}
