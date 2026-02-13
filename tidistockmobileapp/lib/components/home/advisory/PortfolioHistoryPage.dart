import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

class PortfolioHistoryPage extends StatefulWidget {
  const PortfolioHistoryPage({super.key});

  @override
  State<PortfolioHistoryPage> createState() => _PortfolioHistoryPageState();
}

class _PortfolioHistoryPageState extends State<PortfolioHistoryPage>
    with SingleTickerProviderStateMixin {
  // TIDI portfolio history
  List<dynamic> history = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;

  int limit = 20;
  int offset = 0;

  // Model portfolio rebalance history
  List<_ModelRebalanceItem> modelRebalances = [];
  bool loadingModel = true;
  String? userEmail;

  final ScrollController scrollController = ScrollController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchHistory();
    _loadModelRebalances();

    scrollController.addListener(() {
      if (!loadingMore &&
          hasMore &&
          scrollController.position.pixels ==
              scrollController.position.maxScrollExtent) {
        loadMore();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadModelRebalances() async {
    userEmail = await const FlutterSecureStorage().read(key: 'user_email');
    if (userEmail == null) {
      setState(() => loadingModel = false);
      return;
    }

    try {
      final response = await AqApiService.instance.getSubscribedStrategies(userEmail!);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> list = data is List ? data : (data['data'] ?? []);

        final items = <_ModelRebalanceItem>[];
        for (final raw in list) {
          final portfolio = ModelPortfolio.fromJson(raw);
          for (final rebalance in portfolio.rebalanceHistory) {
            final exec = rebalance.getExecutionForUser(userEmail!);
            items.add(_ModelRebalanceItem(
              portfolioName: portfolio.modelName,
              rebalanceDate: rebalance.rebalanceDate,
              stockCount: rebalance.adviceEntries.length,
              status: exec?.status ?? 'pending',
            ));
          }
        }

        // Sort by date descending
        items.sort((a, b) => (b.rebalanceDate ?? DateTime(2000))
            .compareTo(a.rebalanceDate ?? DateTime(2000)));

        setState(() {
          modelRebalances = items;
          loadingModel = false;
        });
      } else {
        setState(() => loadingModel = false);
      }
    } catch (_) {
      setState(() => loadingModel = false);
    }
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
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.black87,
            tabs: const [
              Tab(text: "TIDI Portfolio"),
              Tab(text: "Model Portfolios"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _tidiHistoryTab(),
                _modelHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tidiHistoryTab() {
    if (loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: () async {
        offset = 0;
        history.clear();
        await fetchHistory();
      },
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
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
                      color: item["action"] == "ADDED" ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${item['stockSymbol']} (${item['action']})",
                          style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        Text(item["stockName"] ?? "",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        Text(formatDate(item["dateCreated"]),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (loadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _modelHistoryTab() {
    if (loadingModel) return const Center(child: CircularProgressIndicator());

    if (modelRebalances.isEmpty) {
      return const Center(
        child: Text("No model portfolio rebalances yet.",
          style: TextStyle(fontSize: 15, color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: modelRebalances.length,
      itemBuilder: (context, index) {
        final item = modelRebalances[index];
        return _modelRebalanceCard(item);
      },
    );
  }

  Widget _modelRebalanceCard(_ModelRebalanceItem item) {
    Color statusColor;
    IconData statusIcon;
    switch (item.status) {
      case 'executed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
      case 'toExecute':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusIcon, size: 22, color: statusColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.portfolioName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  item.rebalanceDate != null
                      ? DateFormat("dd MMM yyyy").format(item.rebalanceDate!)
                      : "—",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("${item.stockCount} stocks",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(item.status,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelRebalanceItem {
  final String portfolioName;
  final DateTime? rebalanceDate;
  final int stockCount;
  final String status;

  _ModelRebalanceItem({
    required this.portfolioName,
    this.rebalanceDate,
    required this.stockCount,
    required this.status,
  });
}
