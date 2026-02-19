import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'AqCryptoService.dart';
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
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/process-trade'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_email': email,
        'user_broker': 'DummyBroker',
        'model_id': modelId,
        'modelName': modelName,
        'advisor': advisor,
        'trades': trades,
      }),
    );
  }

  /// Update subscriber execution status after DummyBroker confirmation.
  Future<http.Response> updateSubscriberExecution({
    required String email,
    required String modelName,
    required String advisor,
  }) async {
    return http.put(
      Uri.parse('${ccxtUrl}rebalance/update/subscriber-execution'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_email': email,
        'user_broker': 'DummyBroker',
        'modelName': modelName,
        'advisor': advisor,
        'executionStatus': 'executed',
      }),
    );
  }

  /// Add user to status-check queue for DummyBroker.
  Future<http.Response> addToStatusCheckQueue({
    required String email,
    required String modelName,
    required String advisor,
  }) async {
    return http.post(
      Uri.parse('${ccxtUrl}rebalance/add-user/status-check-queue'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_email': email,
        'broker': 'DummyBroker',
        'modelName': modelName,
        'advisor': advisor,
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
