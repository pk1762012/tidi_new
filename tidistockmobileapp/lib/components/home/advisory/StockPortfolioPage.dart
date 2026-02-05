// Enhanced UI for StockPortfolioPage
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/components/home/market/StockDetailsScreen.dart';

import 'PortfolioHistoryPage.dart';

class StockPortfolioPage extends StatefulWidget {
  const StockPortfolioPage({super.key});

  @override
  State<StockPortfolioPage> createState() => _StockPortfolioPageState();
}

class _StockPortfolioPageState extends State<StockPortfolioPage> {
  List<dynamic> portfolio = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchPortfolio();
  }

  Future<void> fetchPortfolio() async {
    try {
      ApiService apiService = ApiService();
      final response = await apiService.getPortfolio();

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        setState(() {
          portfolio = jsonData ?? [];
          loading = false;
        });
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      menu: "Wealth Portfolio",
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      child: Column(
        children: [

          Row(
            children: [
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(
                  right: 16,
                  top: 8,
                  bottom: 8,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.black, width: 1.5),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PortfolioHistoryPage()),
                    );
                  },
                  child: const Text(
                    "History",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: () async => await fetchPortfolio(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: portfolio.length,
                itemBuilder: (context, index) {
                  final item = portfolio[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StockDetailScreen(symbol: item['stockSymbol']),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.add_chart, color: Colors.green,),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['stockSymbol'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['stockName'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 26),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}