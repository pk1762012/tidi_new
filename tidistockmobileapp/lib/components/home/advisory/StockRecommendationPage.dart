import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/components/home/advisory/pan_collect_dialog.dart';
import 'package:tidistockmobileapp/components/home/market/StockDetailsScreen.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';

import '../../../widgets/SubscriptionPromptDialog.dart';

class StockRecommendationsPage extends StatefulWidget {
  const StockRecommendationsPage({super.key});

  @override
  State<StockRecommendationsPage> createState() => _StockRecommendationsPageState();
}

class _StockRecommendationsPageState extends State<StockRecommendationsPage> {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  List<dynamic> recommendations = [];

  // Subscription
  bool isSubscribed = false;

  // Pagination
  final ScrollController _scrollController = ScrollController();
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  int limit = 10;
  int offset = 0;

  // Filters
  String selectedStatus = "LIVE";
  final List<String> filters = ["LIVE", "BOOKED_PROFIT", "BOOKED_LOSS"];

  // Term Filters
  String? selectedTerm;
  final List<String> termFilters = [
    "ALL",
    "SHORT_TERM",
    "MEDIUM_TERM",
    "LONG_TERM",
  ];


  @override
  void initState() {
    super.initState();
    loadSubscriptionStatus();
    ensurePanAvailable(context);
    fetchRecommendations();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!loadingMore && hasMore) {
          fetchRecommendations();
        }
      }
    });
  }

  Future<void> loadSubscriptionStatus() async {
    String? subscribed = await secureStorage.read(key: 'is_subscribed');
    String? isPaid = await secureStorage.read(key: 'is_paid');
    setState(() {
      isSubscribed = ((subscribed == 'true') && (isPaid == 'true'));
    });
  }

  Future<void> ensurePanAvailable(BuildContext context) async {
    final pan = await secureStorage.read(key: 'pan');

    if (pan == null || pan.isEmpty) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PanCollectDialog(),
      );
    }
  }


  Future<void> fetchRecommendations({bool reset = false}) async {
    if (reset) {
      setState(() {
        loading = true;
        loadingMore = false;
        offset = 0;
        hasMore = true;
        recommendations.clear();
      });
    } else {
      setState(() => loadingMore = true);
    }

    try {
      // Use cached version for first page, uncached for pagination
      if (offset == 0) {
        await ApiService().getCachedStockRecommendations(
          limit: limit,
          offset: offset,
          status: selectedStatus,
          type: selectedTerm,
          onData: (newData, {required fromCache}) {
            if (!mounted) return;
            final List data = newData is List ? newData : [];
            setState(() {
              loading = false;
              loadingMore = false;
              if (data.length < limit) hasMore = false;
              recommendations = List.from(data);
              offset = limit;
            });
          },
        );
      } else {
        final response = await ApiService()
            .getStockRecommendations(limit, offset, selectedStatus, selectedTerm);

        if (response.statusCode == 200) {
          final jsonData = jsonDecode(response.body);
          List newData = jsonData["data"] ?? [];

          setState(() {
            loadingMore = false;
            if (newData.length < limit) hasMore = false;
            recommendations.addAll(newData);
            offset += limit;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (reset || offset == 0) loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case "LIVE":
        return Colors.green.shade600;
      case "BOOKED_PROFIT":
        return Colors.blue.shade600;
      case "BOOKED_LOSS":
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ==============================
  // UI STARTS HERE
  // ==============================

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      menu: "Stock Recommendation",
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            /// FILTER BUTTONS
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: filters.map((status) {
                  bool active = selectedStatus == status;

                  return GestureDetector(
                    onTap: () {
                      setState(() => selectedStatus = status);
                      fetchRecommendations(reset: true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.black45.withValues(alpha: 0.9)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active
                              ? Colors.black45
                              : Colors.black54.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        status.replaceAll("_", " "),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: active
                              ? Colors.white
                              : Colors.black54.withOpacity(1),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: termFilters.map((term) {
                  final bool active =
                      (term == "ALL" && selectedTerm == null) ||
                          (selectedTerm == term);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedTerm = term == "ALL" ? null : term;
                      });
                      fetchRecommendations(reset: true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? lightColorScheme.primary.withOpacity(0.9)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? lightColorScheme.primary
                              : Colors.black26,
                        ),
                      ),
                      child: Text(
                        term.replaceAll("_", " "),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),


            const SizedBox(height: 12),

            /// CONTENT
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                color: lightColorScheme.primary,
                onRefresh: () async => fetchRecommendations(reset: true),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: recommendations.length + 1,
                  itemBuilder: (context, index) {
                    if (index == recommendations.length) {
                      return loadingMore
                          ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                          : hasMore
                          ? const SizedBox()
                          : const Center(child: Text(""));
                    }
                    return _buildRecommendationCard(recommendations[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // =====================================================================
  // CARD
  // =====================================================================

  Widget _buildRecommendationCard(dynamic item) {
    final date = item["startDate"];
    final formatted =
    date != null ? DateFormat('dd-MMM-yyyy').format(DateTime.parse(date)) : "";

    final locked = !isSubscribed && item['stockRecommendationStatus'] == "LIVE";

    final upside = _upsidePercent(
      item["triggerPrice"],
      item["targetPrice"],
    );


    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            /// ✅ SVG BACKGROUND (does NOT control height)
            Positioned.fill(
              child: Opacity(
                opacity: .5, // 👈 visible but subtle
                child: SvgPicture.asset(
                  "assets/images/tidi_recommend.svg",
                  fit: BoxFit.fill, // 👈 squeeze + fit
                ),
              ),
            ),

            /// ✅ CONTENT (controls height)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // 👈 CRITICAL
                children: [
                  if (!locked) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "${item['stockSymbol']} • ${item['stockName']}",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: lightColorScheme.primary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor(
                                item['stockRecommendationStatus'])
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            item['stockRecommendationStatus']
                                .replaceAll("_", " "),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Recommended Date: $formatted",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 8),

                      if (item["type"] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _typeColor(item["type"]).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _typeColor(item["type"]),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            item["type"]
                                .toString()
                                .replaceAll("_", " "),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _typeColor(item["type"]),
                            ),
                          ),
                        ),
                    ],
                  ),


                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _priceBox("Buying Price", item["triggerPrice"]),
                      _priceBox(
                        "Target",
                        item["targetPrice"],
                        upside: upside, // 👈 only target
                      ),
                      _priceBox("Stop Loss", item["stopLoss"]),
                    ],
                  ),



                  const SizedBox(height: 14),

                  if (!locked)
                    Row(
                      children: [
                        _action(
                          "Details",
                          Icons.info,
                          Colors.white,
                              () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StockDetailScreen(
                                    symbol: item['stockSymbol']),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                  if (locked)
                    GestureDetector(
                      onTap: () {
                        SubscriptionPromptDialog.show(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: const [
                            Icon(Icons.lock, color: Colors.black54),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Become a Member & Access LIVE Recommendations",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case "SHORT_TERM":
        return Colors.orange.shade700;
      case "MEDIUM_TERM":
        return Colors.blue.shade700;
      case "LONG_TERM":
        return Colors.green.shade700;
      default:
        return Colors.grey.shade600;
    }
  }


  double _upsidePercent(dynamic buy, dynamic target) {
    final double? b = double.tryParse(buy.toString());
    final double? t = double.tryParse(target.toString());

    if (b == null || t == null || b == 0) return 0;
    return ((t - b) / b) * 100;
  }


  Widget _action(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: Colors.black),
      label: Text(
        label,
        style: const TextStyle(color: Colors.black),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.85),
        side: BorderSide(
          color: Colors.black.withOpacity(0.6), // 👈 border color
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0, // optional: cleaner look
      ),
    ),

    );
  }

  Widget _priceBox(String title, dynamic price, {double? upside}) {
    return Column(
      children: [
        upside != null
            ? RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
            children: [
              TextSpan(text: "Target ("),
              TextSpan(
                text: "↑ ${upside.toStringAsFixed(1)}%",
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: ")"),
            ],
          ),
        )
            : Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          price.toString(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
