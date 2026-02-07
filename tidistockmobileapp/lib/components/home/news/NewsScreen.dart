import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:xml/xml.dart' as xml;
import 'package:url_launcher/url_launcher.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
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

    final news = items.map((item) {
      final pubDateStr = item.findElements('pubDate').firstOrNull?.text;
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

      return _NewsItem(
        title: item.findElements('title').first.text.trim(),
        link: item.findElements('link').first.text.trim(),
        pubDate: formattedDate,
        dateTime: dateTime,
        imageUrl: imageUrl,
      );
    }).toList();

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

  Future<void> _fetchNews() async {
    try {
      await CacheService.instance.fetchWithCache(
        key: 'rss_news',
        fetcher: () => http.get(Uri.parse(rssUrl)),
        parseResponse: (response) {
          final items = _parseRssResponse(response);
          return items.map((n) => {
            'title': n.title,
            'link': n.link,
            'pubDate': n.pubDate,
            'dateTime': n.dateTime.toIso8601String(),
            'imageUrl': n.imageUrl,
          }).toList();
        },
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final items = (data as List).cast<Map<String, dynamic>>();
          _applyNewsData(items);
        },
      );
    } catch (e) {
      debugPrint("News fetch error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Failed to load news")));
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
