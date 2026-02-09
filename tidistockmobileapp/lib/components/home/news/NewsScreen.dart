import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:xml/xml.dart' as xml;
import 'package:url_launcher/url_launcher.dart';
import 'package:tidistockmobileapp/widgets/customScaffold.dart';
import 'package:tidistockmobileapp/theme/theme.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  List<_NewsItem> _newsItems = [];
  bool _isLoading = true;
  String? _errorMessage;

  final String rssUrl =
      'https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms';

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  List<_NewsItem> _parseRssResponse(http.Response response) {
    final document = xml.XmlDocument.parse(response.body);
    final items = document.findAllElements('item');

    final List<_NewsItem> news = [];
    for (final item in items) {
      try {
        final title = item.findElements('title').firstOrNull?.innerText.trim();
        final link = item.findElements('link').firstOrNull?.innerText.trim();
        if (title == null || title.isEmpty || link == null || link.isEmpty) continue;

        final pubDateStr = item.findElements('pubDate').firstOrNull?.innerText;
        DateTime dateTime;
        try {
          dateTime = HttpDate.parse(pubDateStr ?? '');
        } catch (_) {
          try {
            dateTime = DateFormat('EEE, dd MMM yyyy HH:mm:ss Z')
                .parse(pubDateStr ?? '', true);
          } catch (_) {
            dateTime = DateTime.now();
          }
        }
        final formattedDate =
            '${DateFormat('d MMM, h:mm a').format(dateTime.toLocal())} IST';

        final media = item.findElements('media:content');
        String? imageUrl =
            media.isNotEmpty ? media.first.getAttribute('url') : null;
        if (imageUrl == null) {
          final enclosure = item.findElements('enclosure');
          if (enclosure.isNotEmpty) {
            final type = enclosure.first.getAttribute('type') ?? '';
            if (type.startsWith('image')) {
              imageUrl = enclosure.first.getAttribute('url');
            }
          }
        }

        news.add(_NewsItem(
          title: title,
          link: link,
          pubDate: formattedDate,
          dateTime: dateTime,
          imageUrl: imageUrl,
        ));
      } catch (_) {
        // Skip malformed items
      }
    }

    news.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return news;
  }

  void _applyNewsData(List<Map<String, dynamic>> rawItems) {
    final news = rawItems.map((m) => _NewsItem(
      title: m['title'] ?? '',
      link: m['link'] ?? '',
      pubDate: m['pubDate'] ?? '',
      dateTime: DateTime.tryParse(m['dateTime'] ?? '') ?? DateTime.now(),
      imageUrl: m['imageUrl'],
    )).toList();

    setState(() {
      _newsItems = news;
      _isLoading = false;
    });
  }

  static const String _cacheKey = 'rss_news_parsed';
  static const Duration _cacheTtl = Duration(minutes: 5);

  Future<void> _fetchNews() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // 1. Try reading parsed JSON from disk cache
      final box = Hive.box<String>('tidi_cache');
      final cached = box.get(_cacheKey);
      if (cached != null) {
        try {
          final map = jsonDecode(cached) as Map<String, dynamic>;
          final cachedAt = DateTime.parse(map['cachedAt'] as String);
          if (DateTime.now().difference(cachedAt) < _cacheTtl) {
            final items = (map['items'] as List).cast<Map<String, dynamic>>();
            _applyNewsData(items);
            return;
          }
        } catch (_) {
          // Stale or corrupt cache — fetch fresh
        }
      }

      // 2. Fetch RSS feed
      final response = await http.get(
        Uri.parse(rssUrl),
        headers: {'User-Agent': 'TidiStock/1.0'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      // 3. Parse XML into structured data
      final newsItems = _parseRssResponse(response);
      final jsonItems = newsItems.map((n) => {
        'title': n.title,
        'link': n.link,
        'pubDate': n.pubDate,
        'dateTime': n.dateTime.toIso8601String(),
        'imageUrl': n.imageUrl,
      }).toList();

      // 4. Cache the PARSED JSON (not raw XML)
      try {
        box.put(_cacheKey, jsonEncode({
          'cachedAt': DateTime.now().toIso8601String(),
          'items': jsonItems,
        }));
      } catch (_) {}

      // 5. Apply
      if (!mounted) return;
      _applyNewsData(jsonItems.cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint("News fetch error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load news. Please try again.';
        });
      }
    }
  }

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open article')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      menu: 'Latest Financial News',
      child: Scaffold(
        backgroundColor: Colors.transparent, // use theme background
        body: _isLoading
            ? Center(
          child: CircularProgressIndicator(
            color: lightColorScheme.primary,
          ),
        )
            : (_errorMessage != null && _newsItems.isEmpty)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54, fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _fetchNews,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: lightColorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
          onRefresh: _fetchNews,
          color: lightColorScheme.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _newsItems.length,
                  itemBuilder: (context, index) {
                    final news = _newsItems[index];
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _launchURL(news.link),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter:
                            ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.black, // 👈 border color
                                  width: 1,           // optional, default is 1
                                ),
                              ),                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  if (news.imageUrl != null)
                                    ClipRRect(
                                      borderRadius:
                                      const BorderRadius.vertical(
                                          top: Radius.circular(20)),
                                      child: CachedNetworkImage(
                                        imageUrl: news.imageUrl!,
                                        height: 160,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Container(
                                          height: 160,
                                          color: Colors.grey.shade200,
                                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                        ),
                                        errorWidget: (context, url, error) => Container(
                                          height: 160,
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.broken_image, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          news.title,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.schedule,
                                                size: 14,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.7)),
                                            const SizedBox(width: 4),
                                            Text(
                                              news.pubDate,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.7),
                                              ),
                                            ),
                                            const Spacer(),
                                            Icon(
                                              Icons.open_in_new,
                                              size: 18,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.7),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

class _NewsItem {
  final String title;
  final String link;
  final String pubDate;
  final DateTime dateTime;
  final String? imageUrl;

  _NewsItem({
    required this.title,
    required this.link,
    required this.pubDate,
    required this.dateTime,
    this.imageUrl,
  });
}
