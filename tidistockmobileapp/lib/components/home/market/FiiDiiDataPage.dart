import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';

class FiiDiiDataPage extends StatefulWidget {
  const FiiDiiDataPage({super.key});

  @override
  State<FiiDiiDataPage> createState() => _FiiDiiDataPageState();
}

class _FiiDiiDataPageState extends State<FiiDiiDataPage> {
  List<dynamic> data = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;

  int limit = 10;
  int offset = 0;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    fetchData();

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
    scrollController.dispose();
    super.dispose();
  }

  String formatDate(String rawDate) {
    DateTime dt = DateTime.parse(rawDate);
    return DateFormat("dd MMM yyyy").format(dt);
  }

  String formatAmount(double value) {
    return "${NumberFormat.compact(locale: 'en_IN').format(value)} Cr";
  }

  Future<void> fetchData() async {
    try {
      await ApiService().getCachedFiiData(
        limit: limit,
        offset: offset,
        onData: (responseData, {required fromCache}) {
          if (!mounted) return;
          final json = responseData is Map ? responseData : jsonDecode(responseData.toString());
          final List<dynamic> newItems = json["data"] ?? [];

          setState(() {
            data = newItems;
            loading = false;
            offset = limit; // After first page, offset is limit

            int totalCount = json["totalCount"] ?? newItems.length;
            hasMore = data.length < totalCount;
          });
        },
      );
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    setState(() => loadingMore = true);

    ApiService api = ApiService();
    final response = await api.getFiiData(limit, offset);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final List<dynamic> newItems = json["data"] ?? [];

      setState(() {
        data.addAll(newItems);
        offset += limit;

        int totalCount = json["totalCount"] ?? data.length;
        hasMore = data.length < totalCount;

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
      menu: "FII / DII Activity",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          offset = 0;
          data.clear();
          loading = true;
          await fetchData();
        },
        child: ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: data.length + 1 + (loadingMore ? 1 : 0),
          itemBuilder: (context, index) {

            /// ---------------- HEADER ----------------
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "FII/FPI & DII Trading Activity",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "On NSE, BSE and MSEI in Capital Market Segment",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(height: 12),
                    Divider(thickness: 1),
                  ],
                ),
              );
            }

            /// Adjust index because of header
            final dataIndex = index - 1;

            /// Loading more indicator
            if (dataIndex == data.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final item = data[dataIndex];
            final double fiiNet =
                (item["fiiBuy"] ?? 0) - (item["fiiSell"] ?? 0);
            final double diiNet =
                (item["diiBuy"] ?? 0) - (item["diiSell"] ?? 0);

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 500 + (dataIndex * 60)),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                child: Stack(
                  children: [
                    /// SVG Background
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Opacity(
                          opacity: 0.05,
                          child: SvgPicture.asset(
                            "assets/images/tidi_fii.svg",
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),

                    /// Foreground Content
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.black,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatDate(item["date"]),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),

                          _buildRow(
                              "FII",
                              item["fiiBuy"] ?? 0,
                              item["fiiSell"] ?? 0,
                              fiiNet),
                          const SizedBox(height: 8),
                          _netBar(fiiNet),

                          const SizedBox(height: 16),

                          _buildRow(
                              "DII",
                              item["diiBuy"] ?? 0,
                              item["diiSell"] ?? 0,
                              diiNet),
                          const SizedBox(height: 8),
                          _netBar(diiNet),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(String label, double buy, double sell, double net) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87),
        ),
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "Buy: ${formatAmount(buy)}",
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.w600),
                ),
                Text(
                  "Sell: ${formatAmount(sell)}",
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Text(
              "Net: ${formatAmount(net)}",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: net >= 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _netBar(double net) {
    final positive = net >= 0;
    final widthFactor = (net.abs() / 20000).clamp(0.0, 1.0);

    return Stack(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        FractionallySizedBox(
          alignment:
          positive ? Alignment.centerLeft : Alignment.centerRight,
          widthFactor: widthFactor,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: positive ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
