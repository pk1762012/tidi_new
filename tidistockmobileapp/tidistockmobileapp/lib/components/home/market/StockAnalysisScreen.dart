import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../service/ApiService.dart';
import '../../../theme/theme.dart';
import '../../../widgets/SubscriptionPromptDialog.dart';
import '../../../widgets/customScaffold.dart';

import '../ai/AIBotButton.dart';
import '../ai/MultiStockChatScreen.dart';
import 'StockDetailsScreen.dart';
import 'StockScannerSection.dart';

class StockAnalysisScreen extends StatefulWidget {
  final List<dynamic> preloadedStocks;

  const StockAnalysisScreen({
    super.key,
    required this.preloadedStocks,
  });

  @override
  State<StockAnalysisScreen> createState() => _StockAnalysisScreenState();
}

class _StockAnalysisScreenState extends State<StockAnalysisScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  List<Map<String, dynamic>> _stocks = [];
  List<Map<String, dynamic>> compareStocks = [];
  bool isSubscribed = false;

  @override
  void initState() {
    super.initState();
    loadSubscriptionStatus();
    _searchController.addListener(() {
      _searchStock(_searchController.text.trim());
    });
  }

  Future<void> loadSubscriptionStatus() async {
    String? value = await secureStorage.read(key: 'is_subscribed');
    setState(() => isSubscribed = value == 'true');
  }

  Future<void> _searchStock(String query) async {
    if (query.isEmpty || query.length < 2) {
      setState(() => _stocks = []);
      return;
    }

    try {
      final response = await ApiService().searchStock(query);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        setState(() {
          _stocks = data.map((e) => e as Map<String, dynamic>).toList();
        });
      } else {
        setState(() => _stocks = []);
      }
    } catch (e) {
      setState(() => _stocks = []);
    }
  }

  void _toggleCompareStock(Map<String, dynamic> stock) {
    setState(() {
      final exists = compareStocks.any((s) => s['symbol'] == stock['symbol']);

      if (exists) {
        compareStocks.removeWhere((s) => s['symbol'] == stock['symbol']);
      } else {
        if (compareStocks.length < 3) {
          compareStocks.add(stock);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can compare up to 3 stocks')),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Stock Analysis",
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              // -------------------------------------------------------
              // SEARCH FIELD
              // -------------------------------------------------------
            Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Discover smarter investments",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Search stocks to get analyst recommendations, target prices, technical & fundamental insights.",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),

              // 🔍 Search Field
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: "Search stocks...",
                  hintStyle: TextStyle(color: lightColorScheme.primary),
                  prefixIcon: const Icon(Icons.search, color: Colors.black),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),


            const SizedBox(height: 20),

              // -------------------------------------------------------
              // COMPARE CHIPS
              // -------------------------------------------------------
              if (compareStocks.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Compare Stocks",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: lightColorScheme.primary.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: compareStocks.map((stock) {
                        return Chip(
                          backgroundColor: Colors.black12,
                          label: Text(stock['name'],
                              style: const TextStyle(color: Colors.black)),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _toggleCompareStock(stock),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 15),
                  ],
                ),

              if (compareStocks.length >= 2)
                AIBotButton(
                  title: "Compare ${compareStocks.length} Stocks",
                  onTap: () async {
                    await loadSubscriptionStatus();
                    if (!isSubscribed) {
                      SubscriptionPromptDialog.show(context);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MultiStockChatScreen(symbols: compareStocks),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // -------------------------------------------------------
              // MAIN CONTENT
              // -------------------------------------------------------
              if (_stocks.isEmpty)
                StockScannerSection(
                    preloadedStocks: widget.preloadedStocks),

              if (_stocks.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _stocks.length,
                  itemBuilder: (context, index) {
                    final stock = _stocks[index];
                    final inCompare = compareStocks
                        .any((s) => s['symbol'] == stock['symbol']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black, // 👈 subtle border
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        title: Text(
                          stock['name'],
                          style: const TextStyle(color: Colors.black),
                        ),
                        subtitle: Text(
                          stock['symbol'],
                          style: const TextStyle(color: Colors.black87),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                inCompare
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: inCompare
                                    ? Colors.greenAccent
                                    : Colors.black87,
                              ),
                              onPressed: () => _toggleCompareStock(stock),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StockDetailScreen(symbol: stock['symbol']),
                            ),
                          );
                        },
                      ),
                    );

                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
