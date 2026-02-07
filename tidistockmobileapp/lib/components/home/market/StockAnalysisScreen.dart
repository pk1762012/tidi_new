import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../service/ApiService.dart';
import '../../../theme/theme.dart';
import '../../../widgets/SubscriptionPromptDialog.dart';
import '../../../widgets/customScaffold.dart';

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
    String? trialActive = await secureStorage.read(key: 'is_stock_analysis_trial_active');
    setState(() => isSubscribed = value == 'true' || trialActive == 'true');
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: lightColorScheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: lightColorScheme.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.compare_arrows,
                              size: 20, color: lightColorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            "Compare Stocks (${compareStocks.length}/3)",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: lightColorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: compareStocks.map((stock) {
                          return Chip(
                            backgroundColor:
                                lightColorScheme.primary.withOpacity(0.1),
                            label: Text(
                              stock['name'] ?? stock['symbol'] ?? '',
                              style: TextStyle(
                                color: lightColorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            deleteIcon: Icon(Icons.close,
                                size: 18, color: lightColorScheme.primary),
                            onDeleted: () => _toggleCompareStock(stock),
                          );
                        }).toList(),
                      ),
                      if (compareStocks.length >= 2) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await loadSubscriptionStatus();
                              if (!isSubscribed) {
                                SubscriptionPromptDialog.show(context);
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MultiStockChatScreen(
                                      symbols: compareStocks),
                                ),
                              );
                            },
                            icon: const Icon(Icons.compare_arrows, size: 20),
                            label: Text(
                              "Compare ${compareStocks.length} Stocks",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: lightColorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(
                          "Add at least 2 stocks to compare",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
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
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stock name & symbol
                          Text(
                            stock['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stock['symbol'] ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Action buttons row
                          Row(
                            children: [
                              // Analyze button
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => StockDetailScreen(
                                              symbol: stock['symbol']),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.analytics_outlined,
                                        size: 18),
                                    label: const Text('Analyze'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          lightColorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Compare toggle button
                              SizedBox(
                                height: 38,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _toggleCompareStock(stock),
                                  icon: Icon(
                                    inCompare
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                    size: 18,
                                    color: inCompare
                                        ? Colors.green
                                        : lightColorScheme.primary,
                                  ),
                                  label: Text(
                                    inCompare ? 'Added' : 'Compare',
                                    style: TextStyle(
                                      color: inCompare
                                          ? Colors.green
                                          : lightColorScheme.primary,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: inCompare
                                          ? Colors.green
                                          : lightColorScheme.primary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
