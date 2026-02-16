import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
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
  String? errorMsg;

  List<dynamic> openIpos = [];
  List<dynamic> upcomingIpos = [];
  List<dynamic> recentlyClosedIpos = [];
  int totalFromApi = -1; // -1 = not yet loaded, 0 = server returned empty

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
    // Invalidate cached IPO data so we get a fresh network fetch
    CacheService.instance.invalidate('api/ipo');

    if (loading == false && openIpos.isEmpty && upcomingIpos.isEmpty) {
      setState(() => loading = true);
    } else if (openIpos.isEmpty && upcomingIpos.isEmpty) {
      setState(() => loading = true);
    }

    try {
      await ApiService().getCachedIPO(
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final List list = data is List ? data : [];
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final recentCutoff = today.subtract(const Duration(days: 15));

          debugPrint('[IPO] Raw data type: ${data.runtimeType}, items: ${list.length}, fromCache: $fromCache');
          if (list.isNotEmpty) {
            debugPrint('[IPO] Statuses: ${list.map((e) => e['status']).toSet()}');
            debugPrint('[IPO] First item keys: ${list.first is Map ? (list.first as Map).keys.toList() : 'N/A'}');
          } else {
            debugPrint('[IPO] WARNING: API returned empty list! data=$data');
          }

          const openStatuses = {'open', 'active', 'live'};

          final filteredOpen = list.where((e) {
            final status = (e['status'] ?? '').toString().toLowerCase();
            if (!openStatuses.contains(status)) return false;
            final endDateStr = e['endDate'];
            if (endDateStr != null) {
              final endDate = DateTime.tryParse(endDateStr);
              if (endDate != null && endDate.isBefore(today)) return false;
            }
            return true;
          }).toList();

          final filteredUpcoming = list.where((e) {
            final status = (e['status'] ?? '').toString().toLowerCase();
            if (status != 'upcoming') return false;
            // Exclude upcoming IPOs whose endDate has already passed
            final endDateStr = e['endDate'];
            if (endDateStr != null) {
              final endDate = DateTime.tryParse(endDateStr);
              if (endDate != null && endDate.isBefore(today)) return false;
            }
            return true;
          }).toList();

          // Recently closed: status is closed/listed, OR was open/upcoming but endDate has passed
          final filteredClosed = list.where((e) {
            final status = (e['status'] ?? '').toString().toLowerCase();
            // Skip anything already shown in open or upcoming
            if (openStatuses.contains(status)) {
              // If it's "open" but endDate passed, show in recently closed
              final endDateStr = e['endDate'];
              if (endDateStr != null) {
                final endDate = DateTime.tryParse(endDateStr);
                if (endDate != null && endDate.isBefore(today)) {
                  // Only show if within recent cutoff
                  return !endDate.isBefore(recentCutoff);
                }
              }
              return false;
            }
            if (status == 'upcoming') {
              final endDateStr = e['endDate'];
              if (endDateStr != null) {
                final endDate = DateTime.tryParse(endDateStr);
                if (endDate != null && endDate.isBefore(today)) {
                  return !endDate.isBefore(recentCutoff);
                }
              }
              return false;
            }
            // Explicitly closed/listed
            final endDateStr = e['endDate'] ?? e['listingDate'];
            if (endDateStr != null) {
              final endDate = DateTime.tryParse(endDateStr);
              if (endDate != null && endDate.isBefore(recentCutoff)) return false;
            }
            return true;
          }).toList();

          setState(() {
            errorMsg = null;
            totalFromApi = list.length;
            openIpos = filteredOpen;
            upcomingIpos = filteredUpcoming;
            recentlyClosedIpos = filteredClosed;
            loading = false;
          });

          debugPrint('[IPO] Open: ${openIpos.length}, Upcoming: ${upcomingIpos.length}, RecentlyClosed: ${recentlyClosedIpos.length}');
        },
      );
    } catch (e) {
      debugPrint('[IPO] Fetch error: $e');
      if (mounted) {
        setState(() {
          errorMsg = 'Unable to load IPOs. Pull down to retry.';
          loading = false;
        });
      }
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
          : RefreshIndicator(
        onRefresh: fetchIpos,
        child: errorMsg != null && openIpos.isEmpty && upcomingIpos.isEmpty
            ? _buildErrorState()
            : _buildIpoList(),
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          errorMsg ?? 'Something went wrong',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: fetchIpos,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry"),
            style: ElevatedButton.styleFrom(
              backgroundColor: lightColorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIpoList() {
    // API returned 0 items — server has no data at all
    if (totalFromApi == 0) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.info_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            "IPO data unavailable",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            "Pull down to refresh",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      );
    }

    final sections = <Widget>[];

    // Open IPOs
    sections.add(Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _sectionTitle("Open IPOs"),
    ));
    if (openIpos.isEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          "No open IPOs right now",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ));
    } else {
      for (final ipo in openIpos) {
        sections.add(_ipoCard(ipo));
      }
    }

    sections.add(const SizedBox(height: 32));

    // Upcoming IPOs
    sections.add(Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _sectionTitle("Upcoming IPOs"),
    ));
    if (upcomingIpos.isEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          "No upcoming IPOs right now",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ));
    } else {
      for (final ipo in upcomingIpos) {
        sections.add(_ipoCard(ipo));
      }
    }

    // Recently Closed/Listed IPOs
    if (recentlyClosedIpos.isNotEmpty) {
      sections.add(const SizedBox(height: 32));
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _sectionTitle("Recently Listed"),
      ));
      for (final ipo in recentlyClosedIpos) {
        sections.add(_ipoCard(ipo));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: sections,
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
                          child: CachedNetworkImage(
                            imageUrl: ipo['logo'],
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 44, height: 44,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.image, size: 20, color: Colors.grey),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 44, height: 44,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
                            ),
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

                  if ((ipo['status'] ?? '').toString().toLowerCase() == 'open')
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
    final s = status.toLowerCase();
    final Color color;
    if (s == 'open' || s == 'active' || s == 'live') {
      color = Colors.green;
    } else if (s == 'upcoming') {
      color = Colors.orange;
    } else {
      color = Colors.blueGrey;
    }
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


