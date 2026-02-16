import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'CacheService.dart';

// Top-level functions for compute() — must be top-level (not closures)
dynamic _decodeJson(String source) => jsonDecode(source);
Map<String, dynamic> _decodeJsonMap(String source) =>
    Map<String, dynamic>.from(jsonDecode(source) as Map);
List<dynamic> _decodeJsonList(String source) =>
    List<dynamic>.from(jsonDecode(source) as List);

/// Singleton that wraps [CacheService] and offloads JSON parsing to a
/// separate isolate via [compute()].
class DataRepository {
  DataRepository._();
  static final DataRepository instance = DataRepository._();

  final CacheService _cache = CacheService.instance;

  bool get isOnline => _cache.isOnline;

  // ---------------------------------------------------------------------------
  // Static parse helpers — use compute() to move jsonDecode off the UI thread
  // ---------------------------------------------------------------------------

  static Future<dynamic> parseJson(String source) =>
      compute(_decodeJson, source);

  static Future<Map<String, dynamic>> parseJsonMap(String source) =>
      compute(_decodeJsonMap, source);

  static Future<List<dynamic>> parseJsonList(String source) =>
      compute(_decodeJsonList, source);

  // ---------------------------------------------------------------------------
  // Convenience: fetch via CacheService + parse off-thread
  // ---------------------------------------------------------------------------

  /// Fetches a cached HTTP response and parses the body as a JSON map in an
  /// isolate. Returns the decoded [Map<String, dynamic>].
  Future<Map<String, dynamic>> fetchAndParseMap({
    required String key,
    required Future<http.Response> Function() fetcher,
  }) async {
    final response = await _cache.cachedGet(key: key, fetcher: fetcher);
    return parseJsonMap(response.body);
  }

  /// Fetches a cached HTTP response and parses the body as a JSON list in an
  /// isolate. Returns the decoded [List<dynamic>].
  Future<List<dynamic>> fetchAndParseList({
    required String key,
    required Future<http.Response> Function() fetcher,
  }) async {
    final response = await _cache.cachedGet(key: key, fetcher: fetcher);
    return parseJsonList(response.body);
  }
}
