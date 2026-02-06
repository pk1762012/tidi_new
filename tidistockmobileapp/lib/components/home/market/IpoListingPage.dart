import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';

import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/SubscriptionPromptDialog.dart';

class IpoListingPage extends StatefulWidget {
  const IpoListingPage({super.key});

  @override
  State<IpoListingPage> createState() => _IpoListingPageState();
}

class _IpoListingPageState extends State<IpoListingPage> {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  bool loading = true;
  bool isSubscribed = false;

  List<dynamic> openIpos = [];
  List<dynamic> upcomingIpos = [];

  @override
  void initState() {
    super.initState();
    fetchIpos();
    loadSubscriptionStatus();
  }

  Future<void> loadSubscriptionStatus() async {
    final value = await secureStorage.read(key: 'is_subscribed');
    setState(() {
      isSubscribed = value == 'true';
    });
  }

  Future<void> fetchIpos() async {
    setState(() => loading = true);

    final response = await ApiService().getIPO();
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      setState(() {
        openIpos = data.where((e) {
          if (e['status'] != 'open') return false;
          final endDateStr = e['endDate'];
          if (endDateStr != null) {
            final endDate = DateTime.tryParse(endDateStr);
            if (endDate != null && endDate.isBefore(today)) return false;
          }
          return true;
        }).toList();
        upcomingIpos = data.where((e) => e['status'] == 'upcoming').toList();
        loading = false;
      });
    }
  }

  // ==========================================================
  // GMP %
  // ==========================================================

  String gmpPercent(dynamic ipo) {
    final gmp = ipo['gmp']?['aggregations']?['mean'];
    final priceRange = ipo['priceRange'];

    if (gmp == null || priceRange == null) return "-";

    final parts = priceRange.toString().split("-");
    final upper = double.tryParse(parts.last.trim());

    if (upper == null || upper == 0) return "-";

    final percent = (gmp / upper) * 100;
    return "${percent.toStringAsFixed(1)}%";
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: "IPO",
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle("Open IPOs"),
          const SizedBox(height: 12),
          ...openIpos.map(_ipoCard),
          const SizedBox(height: 32),
          _sectionTitle("Upcoming IPOs"),
          const SizedBox(height: 12),
          ...upcomingIpos.map(_ipoCard),
        ],
      ),
    );
  }

  // ==========================================================
  // IPO CARD
  // ==========================================================

  Widget _ipoCard(dynamic ipo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            /// ✅ SVG BACKGROUND
            Positioned.fill(
              child: Opacity(
                opacity: .1, // 👈 visible but subtle
                child: SvgPicture.asset(
                  "assets/images/tidi_ipo.svg",
                  fit: BoxFit.fill, // 👈 squeeze + fit
                ),
              ),
            ),

            /// ✅ GLASS OVERLAY (VERY IMPORTANT)
            Positioned.fill(
              child: Container(
                color: ipo['type'] == "SME"
                    ? Colors.transparent
                    : Colors.transparent,
              ),
            ),

            /// ✅ CONTENT (UNCHANGED)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// HEADER
                  Row(
                    children: [
                      if (ipo['logo'] != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            ipo['logo'],
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ipo['name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      /// ⚠️ SME WARNING ICON
                      if (ipo['type'] == 'SME')
                        Tooltip(
                          message: "SME IPO – Higher risk & lower liquidity",
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                          ),
                        ),

                      _statusChip(ipo['status']),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "${ipo['symbol']} • ${ipo['type']}",
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(child: _infoBox("Price", ipo['priceRange'] ?? "-")),
                      Expanded(child: _gmpBox(ipo)),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "Issue: ${_fmt(ipo['startDate'])} → ${_fmt(ipo['endDate'])}",
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),

                  if (ipo['status'] == 'open')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _openIpoDetailsSheet(ipo),
                        icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                        label: const Text("Details"),
                        style: TextButton.styleFrom(
                          foregroundColor: lightColorScheme.primary,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ==========================================================
  // GMP LOCKED WIDGET
  // ==========================================================

  Widget _gmpBox(dynamic ipo) {
    final gmp = ipo['gmp']?['aggregations']?['mean'];
    if (gmp == null) return const SizedBox();

    final text = "₹$gmp (${gmpPercent(ipo)})";

    return _infoBox("GMP", text);
  }

  // ==========================================================
  // BOTTOM SHEET
  // ==========================================================

  void _openIpoDetailsSheet(dynamic ipo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.92,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color:
                Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius:
                      BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ipo['name'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _statusChip(ipo['status']),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _infoRow("Price Range",
                            ipo['priceRange'] ?? "-"),
                        /// GMP (LOCKED)
                        if (ipo['gmp']?['aggregations']?['mean'] != null)
                          _infoRow(
                            "GMP",
                            "₹${ipo['gmp']['aggregations']['mean']} (${gmpPercent(ipo)})",
                          ),

                        if (ipo['issueSize'] != null)
                          _infoRow("Issue Size",
                              ipo['issueSize']
                          ),

                        if (ipo['minQty'] != null)
                          _infoRow(
                              "Minimum Quantity",
                              "${ipo['minQty']} shares"),
                        if (ipo['listingDate'] != null)
                          _infoRow(
                              "Listing Date",
                              _fmt(ipo['listingDate'])),

                        _textSection("About", ipo['about']),
                        _listSection(
                            "Strengths", ipo['strengths']),
                        _listSection("Risks", ipo['risks']),
                        _scheduleSection(ipo['schedule']),
                      ],
                    ),
                  ),

                  /// ACTION BUTTONS
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Row(
                      children: [
                        if (ipo['prospectusUrl'] != null)
                          _bottomButton(
                              "Prospectus", ipo['prospectusUrl']),
                        const SizedBox(width: 12),
                        if (ipo['nseInfoUrl'] != null)
                          _bottomButton("NSE", ipo['nseInfoUrl']),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  // ==========================================================
  // HELPERS
  // ==========================================================



  Widget _sectionTitle(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: lightColorScheme.primary,
    ),
  );

  Widget _infoBox(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.black.withOpacity(0.6),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style:
        const TextStyle(fontWeight: FontWeight.bold),
      ),
    ],
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(color: Colors.black.withOpacity(0.6)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  Widget _statusChip(String status) {
    final color =
    status == 'open' ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _bottomButton(String label, String url) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        style: ElevatedButton.styleFrom(
          backgroundColor: lightColorScheme.primary,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _textSection(String title, String? content) =>
      content == null || content.isEmpty
          ? const SizedBox()
          : Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: lightColorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(content),
          const SizedBox(height: 16),
        ],
      );



  Widget _listSection(String title, List? items) =>
      items == null || items.isEmpty
          ? const SizedBox()
          : Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: lightColorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((e) => Text("• $e")),
          const SizedBox(height: 16),
        ],
      );

  Widget _scheduleSection(List? schedule) =>
      schedule == null || schedule.isEmpty
          ? const SizedBox()
          : Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            "IPO Schedule",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: lightColorScheme.primary,
            ),
          ),
          ...schedule.map(
                (e) => ListTile(
              title: Text(e['event']),
              trailing:
              Text(_fmt(e['date'])),
            ),
          ),
        ],
      );

  String _fmt(String? date) =>
      date == null
          ? "-"
          : DateFormat('dd MMM yyyy')
          .format(DateTime.parse(date));
}


