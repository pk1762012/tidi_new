import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../service/ApiService.dart';
import '../../../theme/theme.dart';
import '../../../widgets/customScaffold.dart';

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

  List<Map<String, dynamic>> _stocks = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchStock(_searchController.text.trim());
    });
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
                          // Analyze button
                          SizedBox(
                            width: double.infinity,
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
