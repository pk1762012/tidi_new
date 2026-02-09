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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _stocks.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey.shade100,
                      indent: 68,
                    ),
                    itemBuilder: (context, index) {
                      final stock = _stocks[index];
                      final name = stock['name'] ?? '';
                      final symbol = stock['symbol'] ?? '';
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StockDetailScreen(symbol: symbol),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              // Stock initial avatar
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Name & symbol
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      symbol,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Arrow icon
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
