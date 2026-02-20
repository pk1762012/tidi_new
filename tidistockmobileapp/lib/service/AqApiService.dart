import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'AqCryptoService.dart';
import 'BrokerCryptoService.dart';
import 'CacheService.dart';
import 'UserIdentityService.dart';

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
    final hdrs = _headers();
    debugPrint('[AqApiService] getCachedPortfolios url=$uri');
    debugPrint('[AqApiService] headers: subdomain=${hdrs['X-Advisor-Subdomain']}, key=${hdrs['aq-encrypted-key']?.substring(0, 20.clamp(0, hdrs['aq-encrypted-key']?.length ?? 0))}...');
    return CacheService.instance.fetchWithCache(
      key: 'aq/admin/plan/portfolios',
      fetcher: () => http.get(uri, headers: hdrs),
      onData: onData,
    );
  }

  /// Quick health check — GET portfolios with 'guest', 5s timeout.
  /// Returns HTTP status code, or -1 on timeout/error.
  Future<int> healthCheck() async {
    try {
      final uri = Uri.parse(
        '${baseUrl}api/admin/plan/$advisorName/model%20portfolio/guest',
      );
      final response = await http.get(uri, headers: _headers())
          .timeout(const Duration(seconds: 5));
      debugPrint('[AqApiService] healthCheck status=${response.statusCode}');
      return response.statusCode;
    } catch (e) {
      debugPrint('[AqApiService] healthCheck error: $e');
      return -1;
    }
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
      ).timeout(const Duration(seconds: 10)),
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
      fetcher: () => http.get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10)),
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

  // ── User ObjectId lookup ────────────────────────────────────────────
  String? _cachedObjectId;

  /// Get the user's AQ MongoDB ObjectId from their email.
  /// Required by broker-specific endpoints (update-key, connect-broker).
  Future<String?> getUserObjectId(String email) async {
    if (_cachedObjectId != null) return _cachedObjectId;
    try {
      final resp = await http.post(
        Uri.parse('${baseUrl}api/user/getUser'),
        headers: _headers(),
        body: jsonEncode({'email': email}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _cachedObjectId = data['_id'] as String?;
        debugPrint('[AqApiService] getUserObjectId: $_cachedObjectId');
        return _cachedObjectId;
      }
    } catch (e) {
      debugPrint('[AqApiService] getUserObjectId error: $e');
    }
    return null;
  }

  // ── Multi-broker connect (email-based fallback) ───────────────────
  /// Fallback: connect via multi-broker endpoint using email.
  /// This stores credentials without server-side validation.
  Future<http.Response> connectBrokerByEmail({
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

  // ── Credential broker connect (uid-based, validates via CCXT) ─────
  /// PUT api/user/connect-broker — validates credentials via CCXT.
  /// Used by: Dhan, AliceBlue, Groww, Angel One callback.
  Future<http.Response> connectCredentialBroker({
    required String uid,
    required String userBroker,
    required Map<String, dynamic> credentials,
  }) async {
    return http.put(
      Uri.parse('${baseUrl}api/user/connect-broker'),
      headers: _headers(),
      body: jsonEncode({'uid': uid, 'user_broker': userBroker, ...credentials}),
    );
  }

  // ── Zerodha (Publisher Login / OAuth) ─────────────────────────────
  /// POST ccxt/zerodha/login-url — gets Kite login URL using company API key.
  Future<http.Response> getZerodhaLoginUrl() async {
    return http.post(
      Uri.parse('${ccxtUrl}zerodha/login-url'),
      headers: _headers(),
      body: jsonEncode({
        'site': advisorSubdomain,
      }),
    );
  }

  /// POST ccxt/zerodha/gen-access-token — exchanges request_token for access_token.
  Future<http.Response> exchangeZerodhaToken({
    required String requestToken,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}zerodha/gen-access-token'),
      headers: _headers(),
      body: jsonEncode({
        'requestToken': requestToken,
      }),
    );
  }

  /// PUT api/zerodha/update-key — sends encrypted credentials, returns OAuth URL.
  /// (Used for non-publisher/personal API key flow.)
  Future<http.Response> connectZerodha({
    required String uid,
    required String apiKey,
    required String secretKey,
    required String redirectUrl,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.put(
      Uri.parse('${baseUrl}api/zerodha/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'apiKey': crypto.encryptCredential(apiKey),
        'secretKey': crypto.encryptCredential(secretKey),
        'user_broker': 'Zerodha',
        'redirect_url': redirectUrl,
      }),
    );
  }

  // ── Upstox ────────────────────────────────────────────────────────
  /// POST api/upstox/update-key — sends encrypted credentials, returns OAuth URL.
  Future<http.Response> connectUpstox({
    required String uid,
    required String apiKey,
    required String secretKey,
    required String redirectUri,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.post(
      Uri.parse('${baseUrl}api/upstox/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'apiKey': crypto.encryptCredential(apiKey),
        'secretKey': crypto.encryptCredential(secretKey),
        'redirect_uri': redirectUri,
      }),
    );
  }

  // ── Fyers ─────────────────────────────────────────────────────────
  /// POST api/fyers/update-key — sends credentials, returns OAuth URL.
  Future<http.Response> connectFyers({
    required String uid,
    required String clientCode,
    required String secretKey,
    required String redirectUrl,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.post(
      Uri.parse('${baseUrl}api/fyers/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'redirect_url': redirectUrl,
        'clientCode': clientCode,
        'secretKey': crypto.encryptCredential(secretKey),
      }),
    );
  }

  // ── HDFC Securities ───────────────────────────────────────────────
  /// POST api/hdfc/update-key — sends encrypted credentials, returns OAuth URL.
  Future<http.Response> connectHdfc({
    required String uid,
    required String apiKey,
    required String secretKey,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.post(
      Uri.parse('${baseUrl}api/hdfc/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'apiKey': crypto.encryptCredential(apiKey),
        'secretKey': crypto.encryptCredential(secretKey),
      }),
    );
  }

  // ── ICICI Direct ──────────────────────────────────────────────────
  /// PUT api/icici/update-key — sends encrypted credentials.
  /// After success, redirects to ICICI login page.
  Future<http.Response> connectIcici({
    required String uid,
    required String apiKey,
    required String secretKey,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.put(
      Uri.parse('${baseUrl}api/icici/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'user_broker': 'ICICI Direct',
        'apiKey': crypto.encryptCredential(apiKey),
        'secretKey': crypto.encryptCredential(secretKey),
      }),
    );
  }

  // ── Motilal Oswal ─────────────────────────────────────────────────
  /// PUT api/motilal-oswal/update-key — sends encrypted credentials, returns OAuth URL.
  Future<http.Response> connectMotilal({
    required String uid,
    required String apiKey,
    required String clientCode,
    required String redirectUrl,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.put(
      Uri.parse('${baseUrl}api/motilal-oswal/update-key'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'apiKey': crypto.encryptCredential(apiKey),
        'user_broker': 'Motilal Oswal',
        'redirect_url': redirectUrl,
        'clientCode': clientCode,
      }),
    );
  }

  // ── Kotak ─────────────────────────────────────────────────────────
  /// PUT api/kotak/connect-broker — full credential auth with TOTP.
  Future<http.Response> connectKotak({
    required String uid,
    required String apiKey,
    required String secretKey,
    required String mobileNumber,
    required String mpin,
    required String ucc,
    required String totp,
  }) async {
    final crypto = BrokerCryptoService.instance;
    return http.put(
      Uri.parse('${baseUrl}api/kotak/connect-broker'),
      headers: _headers(),
      body: jsonEncode({
        'uid': uid,
        'apiKey': crypto.encryptCredential(apiKey),
        'secretKey': crypto.encryptCredential(secretKey),
        'mobileNumber': mobileNumber,
        'mpin': mpin,
        'ucc': ucc,
        'totp': totp,
      }),
    );
  }

  // ── Groww OAuth ───────────────────────────────────────────────────
  /// GET ccxt/groww/login/oauth — returns OAuth redirect URL.
  Future<http.Response> getGrowwOAuthUrl() async {
    final redirectUri = advisorSubdomain == 'prod'
        ? 'prod.alphaquark.in/stock-recommendation'
        : 'dev.alphaquark.in/stock-recommendation';
    return http.get(
      Uri.parse('${ccxtUrl}groww/login/oauth?redirectUri=$redirectUri'),
      headers: _headers(),
    );
  }

  /// Generic connectBroker kept for backward compat (delegates to email fallback)
  Future<http.Response> connectBroker({
    required String email,
    required String broker,
    required Map<String, dynamic> brokerData,
  }) async {
    return connectBrokerByEmail(
        email: email, broker: broker, brokerData: brokerData);
  }

  /// Generic getBrokerLoginUrl kept for backward compat
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

  /// Disconnect a broker
  Future<http.Response> disconnectBroker({
    required String email,
    required String broker,
  }) async {
    final brokerPath = broker.toLowerCase().replaceAll(' ', '');
    final uri = Uri.parse('${baseUrl}api/user/brokers/$brokerPath')
        .replace(queryParameters: {'email': email});
    return http.delete(uri, headers: _headers());
  }

  /// Switch the primary (active) broker
  Future<http.Response> switchPrimaryBroker({
    required String email,
    required String broker,
  }) async {
    final brokerPath = broker.toLowerCase().replaceAll(' ', '');
    return http.put(
      Uri.parse('${baseUrl}api/user/brokers/$brokerPath/primary'),
      headers: _headers(),
      body: jsonEncode({'email': email}),
    );
  }

  /// Change broker for model portfolio (after switching primary)
  Future<http.Response> changeBrokerModelPortfolio({
    required String email,
    required String broker,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/change_broker_model_pf'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_email': email, 'new_broker': broker}),
    );
  }

  // ---------------------------------------------------------------------------
  // Order APIs
  // ---------------------------------------------------------------------------

  /// Process trades via CCXT rebalance/process-trade — the correct endpoint
  /// used by the RGX web app for ALL broker order execution.
  Future<http.Response> processTrade({
    required String email,
    required String broker,
    required String modelName,
    required String modelId,
    required String advisor,
    required String uniqueId,
    required List<Map<String, dynamic>> trades,
    // Broker-specific credential fields
    String? apiKey,
    String? secretKey,
    String? jwtToken,
    String? clientCode,
    String? accessToken,
    String? viewToken,
    String? sid,
    String? serverId,
    String? consumerKey,
    String? consumerSecret,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/process-trade'),
      headers: _headers(),
      body: jsonEncode({
        'user_broker': broker,
        'user_email': email,
        'trades': trades,
        'model_id': modelId,
        'modelName': modelName,
        'advisor': advisor,
        'unique_id': uniqueId,
        if (apiKey != null) 'apiKey': apiKey,
        if (secretKey != null) 'secretKey': secretKey,
        if (jwtToken != null) 'jwtToken': jwtToken,
        if (clientCode != null) 'clientId': clientCode,
        if (accessToken != null) 'accessToken': accessToken,
        if (viewToken != null) 'viewToken': viewToken,
        if (sid != null) 'sid': sid,
        if (serverId != null) 'serverId': serverId,
        if (consumerKey != null) 'consumerKey': consumerKey,
        if (consumerSecret != null) 'consumerSecret': consumerSecret,
      }),
    ).timeout(const Duration(seconds: 120));
  }

  /// Zerodha publisher: update DB before WebView basket redirect.
  /// POST api/zerodha/model-portfolio/update-reco-with-zerodha-model-pf
  Future<http.Response> updateZerodhaRecoBeforeBasket({
    required List<Map<String, dynamic>> stockDetails,
    required String email,
    required String advisor,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/zerodha/model-portfolio/update-reco-with-zerodha-model-pf'),
      headers: _headers(),
      body: jsonEncode({
        'stockDetails': stockDetails,
        'leaving_datetime': DateTime.now().toIso8601String(),
        'email': email,
        'trade_given_by': advisor,
      }),
    );
  }

  /// Zerodha publisher: record order results after basket redirect success.
  /// POST api/zerodha/publisher/record-orders
  Future<http.Response> recordZerodhaOrders({
    required List<Map<String, dynamic>> stockDetails,
    required String email,
    required String modelId,
    required String modelName,
    required String advisor,
    required String uniqueId,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/zerodha/publisher/record-orders'),
      headers: _headers(),
      body: jsonEncode({
        'stockDetails': stockDetails,
        'publisherResults': [{'status': 'success', 'batchIndex': 0}],
        'userEmail': email,
        'broker': 'Zerodha',
        'model_id': modelId,
        'modelName': modelName,
        'advisor': advisor,
        'unique_id': uniqueId,
      }),
    );
  }

  /// Record publisher execution results (for all brokers).
  /// POST ccxt/rebalance/record-publisher-results
  Future<http.Response> recordPublisherResults({
    required String modelName,
    required String modelId,
    required String uniqueId,
    required String advisor,
    required List<Map<String, dynamic>> orderResults,
    required String email,
    required String broker,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/record-publisher-results'),
      headers: _headers(),
      body: jsonEncode({
        'modelName': modelName,
        'model_id': modelId,
        'unique_id': uniqueId,
        'advisor': advisor,
        'order_results': orderResults,
        'user_email': email,
        'user_broker': broker,
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

  // ---------------------------------------------------------------------------
  // Payment APIs (Razorpay via AQ backend)
  // ---------------------------------------------------------------------------

  /// Create a Razorpay order for a one-time model portfolio subscription
  Future<http.Response> createModelPortfolioOrder({
    required String planId,
    required String planName,
    required String userEmail,
    required String userName,
    required String phone,
    required String pricingTier,
    required int amount,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/admin/subscription/one-time-payment/subscription'),
      headers: _headers(),
      body: jsonEncode({
        'plan_id': planId,
        'user_email': userEmail,
        'name': userName,
        'mobileNumber': phone,
        'advisor': advisorName,
        'amount': amount,
        'duration': _tierToDays(pricingTier),
      }),
    );
  }

  /// Complete a one-time payment after Razorpay checkout succeeds
  Future<http.Response> completeModelPortfolioPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required String userEmail,
    required String planId,
    required int amount,
    required String endDate,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/admin/subscription/one-time-payment/subscription/complete-one-time-payment'),
      headers: _headers(),
      body: jsonEncode({
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
        'user_email': userEmail,
        'plan_id': planId,
        'amount': amount,
        'end_date': endDate,
      }),
    );
  }

  /// Submit lead user data (called before plan selection/payment)
  Future<http.Response> submitLeadUser(Map<String, dynamic> payload) async {
    return http.post(
      Uri.parse('${baseUrl}api/all-users/lead_user'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
  }

  // ---------------------------------------------------------------------------
  // DummyBroker / ccxt Direct APIs
  // ---------------------------------------------------------------------------

  /// Process trades for DummyBroker — calls ccxt-india directly.
  /// Reference: prod_alphaquark_github DummyBrokerHoldingConfirmation.js
  Future<http.Response> processDummyBrokerTrade({
    required String email,
    required String modelName,
    required String modelId,
    required String advisor,
    required List<Map<String, dynamic>> trades,
  }) async {
    return processTrade(
      email: email,
      broker: 'DummyBroker',
      modelName: modelName,
      modelId: modelId,
      advisor: advisor,
      uniqueId: '${modelId}_${DateTime.now().millisecondsSinceEpoch}_$email',
      trades: trades,
    );
  }

  /// Update subscriber execution status (generic — works for all brokers).
  Future<http.Response> updateSubscriberExecution({
    required String email,
    required String modelName,
    required String advisor,
    required String broker,
    String executionStatus = 'executed',
  }) async {
    return http.put(
      Uri.parse('${ccxtUrl}rebalance/update/subscriber-execution'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_email': email,
        'user_broker': broker,
        'modelName': modelName,
        'advisor': advisor,
        'executionStatus': executionStatus,
      }),
    );
  }

  /// Add user to status-check queue (generic — works for all brokers).
  Future<http.Response> addToStatusCheckQueue({
    required String email,
    required String modelName,
    required String advisor,
    required String broker,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/add-user/status-check-queue'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userEmail': email,
        'modelName': modelName,
        'advisor': advisor,
        'broker': broker,
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Notification APIs
  // ---------------------------------------------------------------------------

  /// Fetch all notifications for a user
  Future<http.Response> getUserNotifications(String email) async {
    final encodedEmail = Uri.encodeComponent(email);
    final uri = Uri.parse('${baseUrl}api/sendnotification/get-user-notifications/$encodedEmail');
    return http.get(uri, headers: _headers());
  }

  /// Fetch rebalance notifications only
  Future<http.Response> getRebalanceNotifications(String email) async {
    final response = await getUserNotifications(email);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final List<dynamic> allNotifications = json.decode(response.body);
        final rebalanceNotifications = allNotifications
            .where((n) => n is Map && (n['type'] == 'rebalance' || n['modelName'] != null))
            .toList();
        return http.Response(json.encode(rebalanceNotifications), 200);
      } catch (e) {
        return http.Response(json.encode({'error': 'Failed to parse notifications'}), 500);
      }
    }
    return response;
  }

  /// Mark notification as read
  Future<http.Response> markNotificationRead(String notificationId) async {
    // This endpoint may need to be implemented on the backend
    // For now, return a success response
    return http.Response('{"status": "success"}', 200);
  }

  // ---------------------------------------------------------------------------
  // User Registration & Email Management APIs
  // ---------------------------------------------------------------------------

  /// Register or update a user on AQ backend (upserts into users + clientlistdatas)
  Future<http.Response> registerOrUpdateUser({
    required String email,
    String? phone,
    String? name,
  }) async {
    return http.put(
      Uri.parse('${baseUrl}api/user/update/user-details'),
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'phoneNumber': phone,
        'userName': name ?? email.split('@')[0],
        'advisorName': advisorName,
      }),
    );
  }

  /// Create a model_portfolio_user document on ccxt-india
  /// (replicates what rgx_app does via POST /rebalance/insert-user-doc)
  Future<http.Response> insertUserDoc({
    required String email,
    required String model,
    required String advisor,
    required String broker,
    List<Map<String, dynamic>>? subscriptionAmountRaw,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/insert-user-doc'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userEmail': email,
        'model': model,
        'advisor': advisor,
        'userBroker': broker,
        'subscriptionAmountRaw': subscriptionAmountRaw ?? [],
      }),
    );
  }

  /// Admin email migration — updates all 6 collections without OTP
  Future<http.Response> adminUpdateEmail({
    required String oldEmail,
    required String newEmail,
  }) async {
    return http.post(
      Uri.parse('${baseUrl}api/user/admin-update-email'),
      headers: _headers(),
      body: jsonEncode({'oldEmail': oldEmail, 'newEmail': newEmail}),
    );
  }

  /// Look up existing user email by phone number on AQ backend
  Future<String?> findEmailByPhone(String phone) async {
    try {
      final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
      final resp = await http.get(
        Uri.parse('${baseUrl}api/user/find-by-phone/$cleanPhone'),
        headers: _headers(),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['email'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Email resolution helper
  // ---------------------------------------------------------------------------

  /// Resolve the user email from secure storage, generating a synthetic email
  /// from the stored phone number if necessary.  Returns `null` only when
  /// neither email nor phone is stored (should not happen after login).
  static Future<String?> resolveUserEmail() async {
    const storage = FlutterSecureStorage();
    String? email = await storage.read(key: 'user_email');
    if (email != null && email.isNotEmpty) return email;

    final phone = await storage.read(key: 'phone_number');
    if (phone != null && phone.isNotEmpty) {
      email = UserIdentityService.generateSyntheticEmail(phone);
      await storage.write(key: 'user_email', value: email);
      debugPrint('[AqApiService] resolveUserEmail: generated synthetic $email');
      return email;
    }
    return null;
  }

  /// Convert pricing tier name to duration in days
  static int _tierToDays(String tier) {
    switch (tier.toLowerCase()) {
      case 'monthly':
        return 30;
      case 'quarterly':
        return 90;
      case 'half_yearly':
      case 'halfyearly':
        return 180;
      case 'yearly':
        return 365;
      case 'onetime':
      case 'one_time':
        return 365;
      default:
        return 30;
    }
  }
}
