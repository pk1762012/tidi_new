import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

class PortfolioHistoryPage extends StatefulWidget {
  const PortfolioHistoryPage({super.key});

  @override
  State<PortfolioHistoryPage> createState() => _PortfolioHistoryPageState();
}

class _PortfolioHistoryPageState extends State<PortfolioHistoryPage> {
  List<dynamic> history = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;

  int limit = 20;
  int offset = 0;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    fetchHistory();

    scrollController.addListener(() {
      if (!loadingMore &&
          hasMore &&
          scrollController.position.pixels ==
              scrollController.position.maxScrollExtent) {
        loadMore();
      }
    });
  }

  String formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";

    DateTime dt = DateTime.tryParse(rawDate) ?? DateTime.now();

    return DateFormat("dd MMM yyyy, hh:mm a").format(dt);
  }

  Future<void> fetchHistory() async {
    try {
      ApiService api = ApiService();
      final response = await api.getPortfolioHistory(limit, offset);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> newItems = json["data"] ?? [];

        setState(() {
          history = newItems;
          loading = false;
          offset += limit;

          int totalCount = json["totalCount"] ?? newItems.length;
          hasMore = history.length < totalCount;
        });
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    setState(() => loadingMore = true);

    ApiService api = ApiService();
    final response = await api.getPortfolioHistory(limit, offset);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final List<dynamic> newItems = json["data"] ?? [];

      setState(() {
        history.addAll(newItems);
        offset += limit;

        int totalCount = json["totalCount"] ?? history.length;
        hasMore = history.length < totalCount;

        loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "Rebalance history",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          offset = 0;
          history.clear();
          await fetchHistory();
        },
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [


            // HISTORY LIST
            ...List.generate(history.length, (index) {
              final item = history[index];

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: item["action"] == "ADDED"
                            ? Colors.green.withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        item["action"] == "ADDED"
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        size: 22,
                        color: item["action"] == "ADDED"
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Main Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${item['stockSymbol']} (${item['action']})",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item["stockName"] ?? "",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatDate(item["dateCreated"]),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            // LOADING MORE
            if (loadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
