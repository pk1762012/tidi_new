import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'AqCryptoService.dart';
import 'CacheService.dart';

class AqApiService {
  AqApiService._();
  static final AqApiService instance = AqApiService._();

  final String baseUrl = dotenv.env['AQ_BACKEND_URL'] ?? '';
  final String ccxtUrl = dotenv.env['AQ_CCXT_URL'] ?? '';
  final String advisorSubdomain = dotenv.env['AQ_ADVISOR_SUBDOMAIN'] ?? '';
  final String advisorName = dotenv.env['AQ_ADVISOR_NAME'] ?? '';
  final String _apiKey = dotenv.env['AQ_API_KEY'] ?? '';
  final String _apiSecret = dotenv.env['AQ_API_SECRET'] ?? '';

  /// Generates request headers matching prod-alphaquark's pattern:
  ///   Content-Type: application/json
  ///   X-Advisor-Subdomain: <subdomain>
  ///   aq-encrypted-key: <JWT signed with HMAC-SHA256>
  Map<String, String> _headers() {
    final encryptedKey = AqCryptoService.instance.encryptApiKey(_apiKey, _apiSecret);
    return {
      'Content-Type': 'application/json',
      'X-Advisor-Subdomain': advisorSubdomain,
      'aq-encrypted-key': encryptedKey,
    };
  }

  // ---------------------------------------------------------------------------
  // Model Portfolio APIs
  // ---------------------------------------------------------------------------

  /// Fetch all model portfolios via the Plans API (same as web frontend)
  Future<http.Response> getPortfolios({required String email}) async {
    final safeEmail = email.isNotEmpty ? email : 'guest';
    final uri = Uri.parse(
      '${baseUrl}api/admin/plan/$advisorName/model%20portfolio/${Uri.encodeComponent(safeEmail)}',
    );
    return CacheService.instance.cachedGet(
      key: 'aq/admin/plan/portfolios',
      fetcher: () => http.get(uri, headers: _headers()),
    );
  }

  /// Cached portfolios via Plans API with stale-while-revalidate
  Future<void> getCachedPortfolios({
    required String email,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    final safeEmail = email.isNotEmpty ? email : 'guest';
    final uri = Uri.parse(
      '${baseUrl}api/admin/plan/$advisorName/model%20portfolio/${Uri.encodeComponent(safeEmail)}',
    );
    debugPrint('[AqApiService] getCachedPortfolios url=$uri');
    return CacheService.instance.fetchWithCache(
      key: 'aq/admin/plan/portfolios',
      fetcher: () => http.get(uri, headers: _headers()),
      onData: onData,
    );
  }

  /// Fetch strategy details for a specific model portfolio
  Future<http.Response> getStrategyDetails(String modelName) async {
    final encoded = Uri.encodeComponent(modelName);
    return CacheService.instance.cachedGet(
      key: 'aq/model-portfolio/strategy:$modelName',
      fetcher: () => http.get(
        Uri.parse('${baseUrl}api/model-portfolio/portfolios/strategy/$encoded'),
        headers: _headers(),
      ),
    );
  }

  /// Cached strategy details
  Future<void> getCachedStrategyDetails({
    required String modelName,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    final encoded = Uri.encodeComponent(modelName);
    return CacheService.instance.fetchWithCache(
      key: 'aq/model-portfolio/strategy:$modelName',
      fetcher: () => http.get(
        Uri.parse('${baseUrl}api/model-portfolio/portfolios/strategy/$encoded'),
        headers: _headers(),
      ),
      onData: onData,
    );
  }

  /// Get all strategies the user has subscribed to
  Future<http.Response> getSubscribedStrategies(String email) async {
    final encoded = Uri.encodeComponent(email);
    return CacheService.instance.cachedGet(
      key: 'aq/model-portfolio/subscribed:$email',
      fetcher: () => http.get(
        Uri.parse('${baseUrl}api/model-portfolio/subscribed-strategies/$encoded'),
        headers: _headers(),
      ),
    );
  }

  /// Cached subscribed strategies
  Future<void> getCachedSubscribedStrategies({
    required String email,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    final encoded = Uri.encodeComponent(email);
    return CacheService.instance.fetchWithCache(
      key: 'aq/model-portfolio/subscribed:$email',
      fetcher: () => http.get(
        Uri.parse('${baseUrl}api/model-portfolio/subscribed-strategies/$encoded'),
        headers: _headers(),
      ),
      onData: onData,
    );
  }

  /// Subscribe or unsubscribe from a strategy
  Future<http.Response> subscribeStrategy({
    required String strategyId,
    required String email,
    required String action, // 'subscribe' or 'unsubscribe'
  }) async {
    return http.put(
      Uri.parse('${baseUrl}api/model-portfolio/subscribe-strategy/$strategyId'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'action': action}),
    );
  }

  // ---------------------------------------------------------------------------
  // CCXT Performance APIs
  // ---------------------------------------------------------------------------

  /// Fetch portfolio performance time series data
  Future<http.Response> getPortfolioPerformance({
    required String advisor,
    required String modelName,
  }) async {
    return CacheService.instance.cachedGet(
      key: 'aq/ccxt/performance:$advisor:$modelName',
      fetcher: () => http.post(
        Uri.parse('${ccxtUrl}rebalance/v2/get-portfolio-performance'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'advisor': advisor, 'modelName': modelName}),
      ),
    );
  }

  /// Fetch index data for comparison (e.g., ^NSEI, NIFTY_MID_SELECT.NS, ^CRSLDX)
  Future<http.Response> getIndexData({
    required String symbol,
    required String startDate,
    required String endDate,
  }) async {
    final uri = Uri.parse('${ccxtUrl}misc/data-fetcher').replace(
      queryParameters: {
        'symbol': symbol,
        'start_date': startDate,
        'end_date': endDate,
      },
    );
    return CacheService.instance.cachedGet(
      key: 'aq/ccxt/index-data:$symbol:$startDate:$endDate',
      fetcher: () => http.get(uri, headers: {'Content-Type': 'application/json'}),
    );
  }

  // ---------------------------------------------------------------------------
  // Broker APIs
  // ---------------------------------------------------------------------------

  /// Get available brokers for a user + model combo
  Future<http.Response> getAvailableBrokers({
    required String email,
    String? modelName,
  }) async {
    final params = {'email': email};
    if (modelName != null) params['modelName'] = modelName;
    final uri = Uri.parse('${baseUrl}api/model-portfolio-db-update/available-brokers')
        .replace(queryParameters: params);
    return http.get(uri, headers: _headers());
  }

  /// Get all connected brokers for a user
  Future<http.Response> getConnectedBrokers(String email) async {
    final uri = Uri.parse('${baseUrl}api/user/brokers')
        .replace(queryParameters: {'email': email});
    return CacheService.instance.cachedGet(
      key: 'aq/user/brokers:$email',
      fetcher: () => http.get(uri, headers: _headers()),
    );
  }

  /// Connect a broker (send API key / credentials)
  Future<http.Response> connectBroker({
    required String email,
    required String broker,
    required Map<String, dynamic> brokerData,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/user/brokers/connect'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'broker': broker, ...brokerData}),
    );
  }

  /// Send broker API key to get OAuth login URL (Zerodha example)
  Future<http.Response> getBrokerLoginUrl({
    required String broker,
    required String uid,
    required String apiKey,
    required String secretKey,
    required String redirectUrl,
  }) async {
    final brokerPath = broker.toLowerCase().replaceAll(' ', '');
    return http.post(
      Uri.parse('${baseUrl}api/$brokerPath/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'apiKey': apiKey,
        'secretKey': secretKey,
        'redirect_url': redirectUrl,
      }),
    );
  }

  /// Get broker funds
  Future<http.Response> getBrokerFunds({
    required String email,
    String? broker,
  }) async {
    final path = broker != null ? 'api/user/funds/$broker' : 'api/user/funds';
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: {'email': email});
    return http.get(uri, headers: _headers());
  }

  /// Get broker holdings
  Future<http.Response> getBrokerHoldings({
    required String email,
    String? broker,
  }) async {
    final path = broker != null ? 'api/user/holdings/$broker' : 'api/user/holdings';
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: {'email': email});
    return http.get(uri, headers: _headers());
  }

  // ---------------------------------------------------------------------------
  // Order APIs
  // ---------------------------------------------------------------------------

  /// Place orders via the unified order placement endpoint
  Future<http.Response> placeOrders({
    required String userBroker,
    required String apiKey,
    required String jwtToken,
    required List<Map<String, dynamic>> trades,
    String? clientCode,
    String? secretKey,
    String? viewToken,
    String? sid,
    String? serverId,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/process-trades/order-place'),
      headers: _headers(),
      body: jsonEncode({
        'user_broker': userBroker,
        'apiKey': apiKey,
        'jwtToken': jwtToken,
        'trades': trades,
        if (clientCode != null) 'clientCode': clientCode,
        if (secretKey != null) 'secretKey': secretKey,
        if (viewToken != null) 'viewToken': viewToken,
        if (sid != null) 'sid': sid,
        if (serverId != null) 'serverId': serverId,
      }),
    );
  }

  /// Update portfolio after order execution
  Future<http.Response> updatePortfolioAfterExecution({
    required String modelId,
    required List<Map<String, dynamic>> orderResults,
    required String userEmail,
    required String userBroker,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/model-portfolio-db-update/'),
      headers: _headers(),
      body: jsonEncode({
        'modelId': modelId,
        'orderResults': orderResults,
        'userEmail': userEmail,
        'user_broker': userBroker,
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Subscription & Holdings Data APIs
  // ---------------------------------------------------------------------------

  /// Get user subscription data for a specific model + broker
  Future<http.Response> getSubscriptionRawAmount({
    required String email,
    required String modelName,
    String? userBroker,
  }) async {
    final params = <String, String>{
      'email': email,
      'modelName': modelName,
    };
    if (userBroker != null) params['user_broker'] = userBroker;
    final uri = Uri.parse('${baseUrl}api/model-portfolio-db-update/subscription-raw-amount')
        .replace(queryParameters: params);
    return CacheService.instance.cachedGet(
      key: 'aq/subscription-raw:$email:$modelName:${userBroker ?? "all"}',
      fetcher: () => http.get(uri, headers: _headers()),
    );
  }

  /// Get all broker records with holdings for a user
  Future<http.Response> getUserBrokerRecords(String email) async {
    final uri = Uri.parse('${baseUrl}api/model-portfolio-db-update/user-broker-records')
        .replace(queryParameters: {'email': email});
    return http.get(uri, headers: _headers());
  }

  /// Handle broker migration
  Future<http.Response> handleBrokerMigration({
    required String userEmail,
    required String newBroker,
    required List<Map<String, dynamic>> migrations,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/model-portfolio-db-update/handle-broker-migration'),
      headers: _headers(),
      body: jsonEncode({
        'userEmail': userEmail,
        'newBroker': newBroker,
        'migrations': migrations,
      }),
    );
  }
}
