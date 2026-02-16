import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

// =============================================================================
// Cache Tier Classification
// =============================================================================

/// Defines how critical the data is and what caching strategy to use.
enum CacheTier {
  /// Money, auth, irreversible actions — NEVER cached.
  /// Every request hits the server. Errors shown immediately.
  critical,

  /// Should be recent (15-60s stale OK) — memory-only cache.
  /// Always revalidates in background. No disk persistence.
  semiCritical,

  /// Staleness acceptable — full memory + disk cache.
  /// Memory: 5-10 min. Disk: hours to days. Works offline.
  nonCritical,
}

/// Configuration for a specific cache key's tier behavior.
class _TierConfig {
  final CacheTier tier;
  final Duration memoryTtl;
  final Duration diskTtl;

  const _TierConfig({
    required this.tier,
    required this.memoryTtl,
    this.diskTtl = Duration.zero,
  });
}

// =============================================================================
// Exceptions
// =============================================================================

/// Thrown when device is offline and no cached data is available.
class OfflineException implements Exception {
  final String message;
  OfflineException([this.message = 'No internet connection and no cached data available']);
  @override
  String toString() => message;
}

/// Thrown for non-200 HTTP responses.
class HttpException implements Exception {
  final int statusCode;
  final String body;
  HttpException(this.statusCode, this.body);
  @override
  String toString() => 'HttpException($statusCode): $body';
}

// =============================================================================
// CacheEntry — stores raw HTTP response body + metadata
// =============================================================================

class CacheEntry {
  final String body;
  final int statusCode;
  final DateTime cachedAt;
  final Duration ttl;

  CacheEntry({
    required this.body,
    required this.statusCode,
    required this.cachedAt,
    required this.ttl,
  });

  bool get isFresh => DateTime.now().difference(cachedAt) < ttl;
  bool get isStale => !isFresh;

  Map<String, dynamic> toJson() => {
    'body': body,
    'statusCode': statusCode,
    'cachedAt': cachedAt.toIso8601String(),
    'ttlMs': ttl.inMilliseconds,
  };

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    // Handle legacy entries that stored parsed 'data' instead of raw 'body'
    String body;
    if (json.containsKey('body') && json['body'] is String) {
      body = json['body'] as String;
    } else if (json.containsKey('data')) {
      body = jsonEncode(json['data']);
    } else {
      throw const FormatException('CacheEntry missing body');
    }

    return CacheEntry(
      body: body,
      statusCode: json['statusCode'] as int? ?? 200,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      ttl: Duration(milliseconds: json['ttlMs'] as int),
    );
  }
}

// =============================================================================
// Offline write queue item
// =============================================================================

class _OfflineQueueItem {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String? body;
  final int retries;

  _OfflineQueueItem({
    required this.url,
    required this.method,
    required this.headers,
    this.body,
    this.retries = 0,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'method': method,
    'headers': headers,
    'body': body,
    'retries': retries,
  };

  factory _OfflineQueueItem.fromJson(Map<String, dynamic> json) => _OfflineQueueItem(
    url: json['url'] as String,
    method: json['method'] as String,
    headers: Map<String, String>.from(json['headers'] as Map),
    body: json['body'] as String?,
    retries: json['retries'] as int? ?? 0,
  );
}

// =============================================================================
// CacheService — multi-layer caching with tier-based behavior
// =============================================================================

class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  static const int _maxMemoryEntries = 50;
  static const int _maxOfflineRetries = 5;
  static const String _cacheBoxName = 'tidi_cache';
  static const String _offlineQueueBoxName = 'tidi_offline_queue';
  static const Map<String, String> _syntheticHeaders = {
    'content-type': 'application/json; charset=utf-8',
  };

  /// In-memory LRU cache.
  final LinkedHashMap<String, CacheEntry> _memoryCache = LinkedHashMap();

  late Box<String> _diskCache;
  late Box<String> _offlineQueue;

  bool _initialized = false;
  bool _isOnline = true;
  StreamSubscription? _connectivitySub;

  // ---------------------------------------------------------------------------
  // Tier configurations — maps cache key prefixes to their tier + TTLs
  // ---------------------------------------------------------------------------

  static final Map<String, _TierConfig> _tierConfigs = {
    // ── NON-CRITICAL: memory 10 min + disk hours/days ──────────────────────
    'api/market/holiday':          const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(days: 30)),
    'api/branch':                  const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(days: 30)),
    'api/course':                  const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(days: 30)),
    'api/ipo':                     const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 5),  diskTtl: Duration(hours: 6)),
    'api/fii':                     const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(hours: 12)),
    'stock_analysis':              const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(hours: 12)),
    'nifty_50_stock_analysis':     const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(hours: 12)),
    'rss_news':                    const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 5),  diskTtl: Duration(hours: 1)),
    'option-chain':                const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 2), diskTtl: Duration(hours: 1)),

    // ── NON-CRITICAL: aq_backend model portfolio data ──────────────────
    'aq/admin/plan/portfolios':        const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 5), diskTtl: Duration(hours: 6)),
    'aq/model-portfolio/portfolios':   const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 5), diskTtl: Duration(hours: 6)),
    'aq/model-portfolio/strategy':     const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 5), diskTtl: Duration(hours: 6)),

    // ── NON-CRITICAL: aq_ccxt performance data ──────────────────────
    'aq/ccxt/performance':             const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(hours: 6)),
    'aq/ccxt/index-data':              const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 10), diskTtl: Duration(hours: 6)),

    // ── SEMI-CRITICAL: aq_backend user-specific data ──
    'aq/model-portfolio/subscribed':   const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 60)),
    'aq/user/brokers':                 const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'aq/subscription-raw':             const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 60)),

    // ── SEMI-CRITICAL: memory only, short TTL (no disk persistence) ──
    'api/user':                        const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 60)),
    'api/admin/stock/recommend/get':   const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'api/portfolio':                   const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 60)),
    'pre_market_summary':              const _TierConfig(tier: CacheTier.nonCritical, memoryTtl: Duration(minutes: 5), diskTtl: Duration(hours: 3)),
    'api/stock/search':                const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'api/workshop/register':           const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'api/user/fcm':                    const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'index/quote':                     const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 15)),
    'api/history/portfolio':           const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'api/user/get_subscription_transactions': const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),
    'api/user/get_course_transactions':       const _TierConfig(tier: CacheTier.semiCritical, memoryTtl: Duration(seconds: 30)),

    // ── CRITICAL: never cached — auth, payments, mutations, AI chat ──
    'api/user/create':                     const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/login':                      const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/verify':                     const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/validate':                   const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/validate':                        const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/update':                     const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/update_pan':                 const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/update_profile_picture':     const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/update_device_details':      const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/delete':                     const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/create_subscription_order':  const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/user/create_course_order':        const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
    'api/workshop/register/create':        const _TierConfig(tier: CacheTier.critical, memoryTtl: Duration.zero),
  };

  /// Default config for keys that don't match any prefix.
  /// Fail-closed: unknown endpoints are treated as critical (never cached).
  static const _TierConfig _defaultConfig = _TierConfig(
    tier: CacheTier.critical,
    memoryTtl: Duration.zero,
  );

  /// Resolve tier config for a cache key via longest prefix match.
  /// Longer prefixes win (e.g. 'api/user/create' beats 'api/user').
  _TierConfig _getConfig(String key) {
    _TierConfig? best;
    int bestLen = -1;
    for (final entry in _tierConfigs.entries) {
      if (key.startsWith(entry.key) && entry.key.length > bestLen) {
        best = entry.value;
        bestLen = entry.key.length;
      }
    }
    return best ?? _defaultConfig;
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _diskCache = await Hive.openBox<String>(_cacheBoxName);
    _offlineQueue = await Hive.openBox<String>(_offlineQueueBoxName);
    _initialized = true;

    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline = !result.contains(ConnectivityResult.none);
      if (_isOnline && wasOffline) {
        _processOfflineQueue();
      }
    });

    final result = await Connectivity().checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);
  }

  bool get isOnline => _isOnline;

  /// Legacy TTL resolver — returns memoryTtl for backward compatibility.
  Duration getTtl(String key) => _getConfig(key).memoryTtl;

  // ---------------------------------------------------------------------------
  // Core: fetchWithCache (callback pattern — used by getCached* wrappers)
  // ---------------------------------------------------------------------------

  /// Fetches data with tier-aware caching.
  ///
  /// [key]             — unique cache key (e.g. `'api/ipo'`).
  /// [fetcher]         — function that performs the actual HTTP call.
  /// [onData]          — callback receiving parsed data; may fire twice (stale, then fresh).
  /// [parseResponse]   — custom parser; defaults to `jsonDecode(response.body)`.
  Future<void> fetchWithCache({
    required String key,
    required Future<http.Response> Function() fetcher,
    required void Function(dynamic data, {required bool fromCache}) onData,
    Duration? ttl,
    dynamic Function(http.Response response)? parseResponse,
  }) async {
    final config = _getConfig(key);
    final parser = parseResponse ?? (http.Response r) => jsonDecode(r.body);

    // ── CRITICAL tier: never cache, always fetch ──
    if (config.tier == CacheTier.critical) {
      final response = await fetcher();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onData(parser(response), fromCache: false);
      } else {
        debugPrint('[CacheService] HTTP ${response.statusCode} for key=$key body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
        throw HttpException(response.statusCode, response.body);
      }
      return;
    }

    // ── 1. Check memory cache ──
    CacheEntry? memEntry = _memoryCache[key];

    // ── 2. Check disk cache (NON-CRITICAL only) ──
    CacheEntry? diskEntry;
    if (memEntry == null && config.tier == CacheTier.nonCritical) {
      diskEntry = _readFromDisk(key);
    }

    // Determine the best available cached entry
    CacheEntry? cached = memEntry ?? diskEntry;
    bool isFresh = false;

    if (memEntry != null && memEntry.isFresh) {
      // Memory is fresh — use it directly
      isFresh = true;
    } else if (diskEntry != null && diskEntry.isFresh) {
      // Disk is fresh — promote to memory with memoryTtl, mark fresh
      final promoted = CacheEntry(
        body: diskEntry.body,
        statusCode: diskEntry.statusCode,
        cachedAt: DateTime.now(),
        ttl: config.memoryTtl,
      );
      _putMemory(key, promoted);
      cached = promoted;
      isFresh = true;
    }

    // ── 3. Fresh cache hit — return immediately, skip network ──
    if (cached != null && isFresh) {
      final syntheticResponse = http.Response(cached.body, cached.statusCode, headers: _syntheticHeaders);
      onData(parser(syntheticResponse), fromCache: true);
      return;
    }

    // ── 4. Stale cache hit — return stale, revalidate in background ──
    if (cached != null) {
      final syntheticResponse = http.Response(cached.body, cached.statusCode, headers: _syntheticHeaders);
      onData(parser(syntheticResponse), fromCache: true);
      _revalidateInBackground(
        key: key,
        fetcher: fetcher,
        parser: parser,
        config: config,
        onData: onData,
      );
      return;
    }

    // ── 4b. For NON-CRITICAL: check disk for fully-stale data to show while fetching ──
    if (config.tier == CacheTier.nonCritical) {
      final staleDisk = _readFromDisk(key);
      if (staleDisk != null) {
        final syntheticResponse = http.Response(staleDisk.body, staleDisk.statusCode, headers: _syntheticHeaders);
        onData(parser(syntheticResponse), fromCache: true);
        _revalidateInBackground(
          key: key,
          fetcher: fetcher,
          parser: parser,
          config: config,
          onData: onData,
        );
        return;
      }
    }

    // ── 5. No cache at all — must go to network ──
    if (!_isOnline) {
      throw OfflineException();
    }

    try {
      final response = await fetcher();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = parser(response);
        // Don't cache empty list responses — avoids persisting "no data" for hours
        final shouldCache = data is! List || data.isNotEmpty;
        if (shouldCache) {
          _putWithConfig(key, response.body, response.statusCode, config);
        }
        onData(data, fromCache: false);
      } else {
        debugPrint('[CacheService] HTTP ${response.statusCode} for key=$key body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
        throw HttpException(response.statusCode, response.body);
      }
    } catch (e) {
      if (e is OfflineException || e is HttpException) rethrow;
      throw OfflineException('Network error and no cached data for $key: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Core: cachedGet (transparent — returns http.Response directly)
  // ---------------------------------------------------------------------------

  /// Transparent HTTP cache wrapper. Returns [http.Response] — either from
  /// cache or network. Callers don't know whether data came from cache.
  ///
  /// Used inside original ApiService methods to add caching without changing
  /// return types or requiring screen-level changes.
  Future<http.Response> cachedGet({
    required String key,
    required Future<http.Response> Function() fetcher,
  }) async {
    final config = _getConfig(key);

    // CRITICAL: always fetch, never cache
    if (config.tier == CacheTier.critical) {
      return fetcher();
    }

    // 1. Check memory
    CacheEntry? memEntry = _memoryCache[key];

    // 2. Check disk (non-critical only)
    CacheEntry? diskEntry;
    if (memEntry == null && config.tier == CacheTier.nonCritical) {
      diskEntry = _readFromDisk(key);
    }

    CacheEntry? cached = memEntry ?? diskEntry;
    bool isFresh = false;

    if (memEntry != null && memEntry.isFresh) {
      isFresh = true;
    } else if (diskEntry != null && diskEntry.isFresh) {
      final promoted = CacheEntry(
        body: diskEntry.body,
        statusCode: diskEntry.statusCode,
        cachedAt: DateTime.now(),
        ttl: config.memoryTtl,
      );
      _putMemory(key, promoted);
      cached = promoted;
      isFresh = true;
    }

    // 3. Fresh hit — return synthetic response
    if (cached != null && isFresh) {
      return http.Response(cached.body, cached.statusCode, headers: _syntheticHeaders);
    }

    // 4. Stale hit — return stale, revalidate in background
    if (cached != null) {
      _revalidateGetInBackground(key, fetcher, config);
      return http.Response(cached.body, cached.statusCode, headers: _syntheticHeaders);
    }

    // 4b. Stale disk data for non-critical
    if (config.tier == CacheTier.nonCritical) {
      final staleDisk = _readFromDisk(key);
      if (staleDisk != null) {
        _revalidateGetInBackground(key, fetcher, config);
        return http.Response(staleDisk.body, staleDisk.statusCode, headers: _syntheticHeaders);
      }
    }

    // 5. No cache — fetch from network
    if (!_isOnline) throw OfflineException();

    final response = await fetcher();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _putWithConfig(key, response.body, response.statusCode, config);
    }
    return response;
  }

  // ---------------------------------------------------------------------------
  // Background revalidation
  // ---------------------------------------------------------------------------

  /// Background revalidation for fetchWithCache (parses response, calls onData).
  void _revalidateInBackground({
    required String key,
    required Future<http.Response> Function() fetcher,
    required dynamic Function(http.Response) parser,
    required _TierConfig config,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    Future(() async {
      try {
        if (!_isOnline) {
          debugPrint('[CacheService] revalidate skipped (offline) key=$key');
          return;
        }
        final response = await fetcher();
        debugPrint('[CacheService] revalidate key=$key status=${response.statusCode} bodyLen=${response.body.length}');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = parser(response);
          // Don't cache empty list responses — avoids persisting "no data" for hours
          final shouldCache = data is! List || data.isNotEmpty;
          if (shouldCache) {
            _putWithConfig(key, response.body, response.statusCode, config);
          }
          onData(data, fromCache: false);
        } else {
          debugPrint('[CacheService] revalidate FAILED key=$key body=${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
        }
      } catch (e) {
        debugPrint('[CacheService] revalidate ERROR key=$key: $e');
      }
    });
  }

  /// Background revalidation for cachedGet (just refreshes cache, no callback).
  void _revalidateGetInBackground(
    String key,
    Future<http.Response> Function() fetcher,
    _TierConfig config,
  ) {
    Future(() async {
      try {
        if (!_isOnline) return;
        final response = await fetcher();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _putWithConfig(key, response.body, response.statusCode, config);
        }
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------------
  // Memory cache (LRU)
  // ---------------------------------------------------------------------------

  void _putMemory(String key, CacheEntry entry) {
    _memoryCache.remove(key); // Re-insert at end for LRU
    _memoryCache[key] = entry;
    while (_memoryCache.length > _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  // ---------------------------------------------------------------------------
  // Tier-aware storage
  // ---------------------------------------------------------------------------

  /// Store response in the appropriate cache layers based on tier config.
  void _putWithConfig(String key, String body, int statusCode, _TierConfig config) {
    final now = DateTime.now();

    // Always write to memory
    _putMemory(key, CacheEntry(
      body: body,
      statusCode: statusCode,
      cachedAt: now,
      ttl: config.memoryTtl,
    ));

    // Write to disk ONLY for non-critical data
    if (config.tier == CacheTier.nonCritical && config.diskTtl > Duration.zero) {
      _writeToDisk(key, CacheEntry(
        body: body,
        statusCode: statusCode,
        cachedAt: now,
        ttl: config.diskTtl,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Disk cache (Hive)
  // ---------------------------------------------------------------------------

  void _writeToDisk(String key, CacheEntry entry) {
    try {
      _diskCache.put(key, jsonEncode(entry.toJson()));
    } catch (e) {
      debugPrint('[CacheService] Disk write failed for key=$key: $e');
    }
  }

  CacheEntry? _readFromDisk(String key) {
    try {
      final raw = _diskCache.get(key);
      if (raw == null) return null;
      return CacheEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[CacheService] Corrupted disk entry for key=$key, removing: $e');
      _diskCache.delete(key);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Invalidation
  // ---------------------------------------------------------------------------

  /// Invalidate a specific cache key (both memory and disk).
  void invalidate(String key) {
    _memoryCache.remove(key);
    _diskCache.delete(key);
  }

  /// Invalidate all keys matching a prefix.
  void invalidateByPrefix(String prefix) {
    _memoryCache.removeWhere((k, _) => k.startsWith(prefix));
    final keysToDelete = _diskCache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToDelete) {
      _diskCache.delete(key);
    }
  }

  /// Clear all cached data (memory + disk + offline queue).
  Future<void> clearAll() async {
    _memoryCache.clear();
    await _diskCache.clear();
    await _offlineQueue.clear();
  }

  // ---------------------------------------------------------------------------
  // Offline write queue
  // ---------------------------------------------------------------------------

  /// Queue a failed POST/PATCH for retry when connectivity resumes.
  Future<void> enqueueOfflineWrite({
    required String url,
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    final item = _OfflineQueueItem(url: url, method: method, headers: headers, body: body);
    await _offlineQueue.add(jsonEncode(item.toJson()));
  }

  Future<void> _processOfflineQueue() async {
    final keys = _offlineQueue.keys.toList();
    for (final key in keys) {
      try {
        final raw = _offlineQueue.get(key);
        if (raw == null) continue;
        final item = _OfflineQueueItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);

        if (item.retries >= _maxOfflineRetries) {
          debugPrint('[CacheService] Offline queue: permanently dropping ${item.method} ${item.url} after $_maxOfflineRetries retries');
          await _offlineQueue.delete(key);
          continue;
        }

        http.Response response;
        final uri = Uri.parse(item.url);
        switch (item.method.toUpperCase()) {
          case 'POST':
            response = await http.post(uri, headers: item.headers, body: item.body);
            break;
          case 'PATCH':
            response = await http.patch(uri, headers: item.headers, body: item.body);
            break;
          case 'PUT':
            response = await http.put(uri, headers: item.headers, body: item.body);
            break;
          default:
            response = await http.post(uri, headers: item.headers, body: item.body);
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await _offlineQueue.delete(key);
        } else {
          final updated = _OfflineQueueItem(
            url: item.url,
            method: item.method,
            headers: item.headers,
            body: item.body,
            retries: item.retries + 1,
          );
          await _offlineQueue.put(key, jsonEncode(updated.toJson()));
        }
      } catch (e) {
        debugPrint('[CacheService] Offline queue retry error for key=$key: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Stats (for settings UI)
  // ---------------------------------------------------------------------------

  int get diskEntryCount => _diskCache.length;

  int get approximateDiskSizeBytes {
    int total = 0;
    for (final key in _diskCache.keys) {
      final value = _diskCache.get(key);
      if (value != null) {
        total += key.toString().length + value.length;
      }
    }
    return total;
  }

  String get formattedDiskSize {
    final bytes = approximateDiskSizeBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}
