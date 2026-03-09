import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tidistockmobileapp/models/broker_connection.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';
import 'package:tidistockmobileapp/service/BrokerSessionService.dart';

/// Exception thrown when broker is Zerodha and requires WebView basket flow.
/// ExecutionStatusPage catches this and switches to WebView mode.
class ZerodhaBasketRequiredException implements Exception {
  final String apiKey;
  final List<Map<String, dynamic>> basketItems;
  final List<Map<String, dynamic>> stockDetails;

  ZerodhaBasketRequiredException({
    required this.apiKey,
    required this.basketItems,
    required this.stockDetails,
  });
}

class OrderExecutionService {
  OrderExecutionService._();
  static final OrderExecutionService instance = OrderExecutionService._();

  String _lastUsedBrokerName = '';
  String get lastUsedBrokerName => _lastUsedBrokerName;

  /// Canonical broker name map — ensures consistent naming across the app.
  /// Matches RGX connectBroker.js broker identifiers.
  static const Map<String, String> _brokerAliases = {
    'zerodha': 'Zerodha',
    'angel one': 'Angel One',
    'angelone': 'Angel One',
    'groww': 'Groww',
    'upstox': 'Upstox',
    'icicidirect': 'ICICI Direct',
    'icici direct': 'ICICI Direct',
    'icici': 'ICICI Direct',
    'hdfc': 'Hdfc Securities',
    'hdfc securities': 'Hdfc Securities',
    'fyers': 'Fyers',
    'motilal': 'Motilal Oswal',
    'motilal oswal': 'Motilal Oswal',
    'dhan': 'Dhan',
    'aliceblue': 'AliceBlue',
    'alice blue': 'AliceBlue',
    'kotak': 'Kotak',
    'iifl': 'IIFL Securities',
    'iifl securities': 'IIFL Securities',
    'dummybroker': 'DummyBroker',
  };

  /// Normalize broker name to canonical form for consistent API calls.
  static String normalizeBrokerName(String name) {
    final lower = name.toLowerCase().trim();
    return _brokerAliases[lower] ?? name;
  }

  /// Select the best broker for execution.
  /// Priority: primary + effectively connected > effectively connected > connected.
  BrokerConnection? _selectBroker(List<BrokerConnection> connections) {
    for (final c in connections) {
      if (c.isPrimary && c.isEffectivelyConnected) return c;
    }
    for (final c in connections) {
      if (c.isEffectivelyConnected) return c;
    }
    for (final c in connections) {
      if (c.isConnected) return c;
    }
    return null;
  }

  /// Pre-flight broker session validation (matching RGX validateBrokerSession).
  /// Checks if the broker token is still valid and session is fresh.
  Future<void> _validateBrokerSession(BrokerConnection broker) async {
    // Check token expiry
    if (broker.isTokenExpired) {
      throw Exception('session expired for ${broker.broker}. Please reconnect.');
    }

    // Check if session was established today (IST) — brokers like Angel One,
    // AliceBlue, Dhan require daily re-authentication
    final brokerLower = broker.broker.toLowerCase();
    final needsDailyAuth = ['angel one', 'angelone', 'aliceblue', 'alice blue', 'dhan']
        .contains(brokerLower);

    if (needsDailyAuth) {
      final isFresh = await BrokerSessionService.instance.isSessionFresh(broker.broker);
      if (!isFresh) {
        debugPrint('[OrderExecution] Session for ${broker.broker} is stale (not today)');
        // Don't block execution — the CCXT server will validate the actual token
        // Just log a warning for debugging
      }
    }

    // Validate that essential credentials exist
    final hasToken = (broker.jwtToken != null && broker.jwtToken!.isNotEmpty) ||
        (broker.apiKey != null && broker.apiKey!.isNotEmpty);
    if (!hasToken) {
      throw Exception('No credentials found for ${broker.broker}. Please reconnect.');
    }
  }

  /// Execute a list of orders through the connected broker via CCXT
  /// rebalance/process-trade endpoint (matching the RGX web app flow).
  ///
  /// For Zerodha: throws [ZerodhaBasketRequiredException] — caller must
  /// handle the WebView basket flow.
  ///
  /// For other brokers: calls CCXT rebalance/process-trade and returns results.
  ///
  /// Post-execution pipeline (matching RGX):
  ///   1. model-portfolio-db-update
  ///   2. rebalance/update/subscriber-execution
  ///   3. rebalance/record-publisher-results (Fyers only)
  ///   4. rebalance/add-user/status-check-queue
  Future<List<OrderResult>> executeOrders({
    required List<Map<String, dynamic>> orders,
    required String email,
    required String modelName,
    required String modelId,
    required String advisor,
    required void Function(int completed, int total, OrderResult latest) onOrderUpdate,
  }) async {
    // 1. Get user's connected broker info
    AqApiService.instance.invalidateUserCache(); // ensure fresh credentials
    final brokerResp = await AqApiService.instance.getConnectedBrokers(email);
    if (brokerResp.statusCode != 200) {
      throw Exception('Failed to fetch broker credentials');
    }

    dynamic brokerData;
    try {
      brokerData = jsonDecode(brokerResp.body);
    } catch (e) {
      debugPrint('[OrderExecution] Failed to parse broker response: $e');
      throw Exception('Invalid broker response from server');
    }
    if (brokerData is! Map<String, dynamic>) {
      throw Exception('Unexpected broker response format');
    }

    // 2. Parse connections and select PRIMARY broker
    final connections = BrokerConnection.parseApiResponse(brokerData);
    if (connections.isEmpty) {
      throw Exception('No connected broker found');
    }

    final selected = _selectBroker(connections);
    if (selected == null) {
      throw Exception('No connected broker found. Please reconnect your broker.');
    }

    debugPrint('[OrderExecution] Selected broker: ${selected.broker} (primary=${selected.isPrimary})');

    // Fetch full user details to get credentials (matching RGX flow).
    // The GET /api/user/brokers endpoint intentionally strips credentials,
    // so we use GET /api/user/getUser/:email (like prod web app) to obtain
    // jwtToken, apiKey, secretKey, etc.
    final userDetails = await AqApiService.instance.getUserDetails(email);
    BrokerConnection credBroker = selected;
    if (userDetails != null) {
      final connectedBrokers = userDetails['connected_brokers'] as List<dynamic>? ?? [];
      final match = connectedBrokers.cast<Map<String, dynamic>>().where(
        (b) => (b['broker'] as String? ?? '').toLowerCase() == selected.broker.toLowerCase(),
      );
      if (match.isNotEmpty) {
        credBroker = BrokerConnection.fromJson(match.first);
      } else {
        // Fallback: use legacy top-level credentials from user document
        credBroker = BrokerConnection(
          broker: selected.broker,
          clientCode: userDetails['clientCode'] as String? ?? selected.clientCode,
          apiKey: userDetails['apiKey'] as String? ?? selected.apiKey,
          secretKey: userDetails['secretKey'] as String? ?? selected.secretKey,
          jwtToken: userDetails['jwtToken'] as String? ?? selected.jwtToken,
          viewToken: userDetails['viewToken'] as String? ?? selected.viewToken,
          sid: userDetails['sid'] as String? ?? selected.sid,
          serverId: userDetails['serverId'] as String? ?? selected.serverId,
          status: selected.status,
          tokenExpire: selected.tokenExpire,
          isPrimary: selected.isPrimary,
        );
      }
    }

    // Pre-flight session validation (matching RGX validateBrokerSession)
    await _validateBrokerSession(credBroker);

    // Normalize broker name for consistent API calls
    final brokerName = normalizeBrokerName(credBroker.broker);
    _lastUsedBrokerName = brokerName;
    final apiKey = credBroker.apiKey ?? '';
    final jwtToken = credBroker.jwtToken ?? '';
    final clientCode = credBroker.clientCode;
    final secretKey = credBroker.secretKey;
    final viewToken = credBroker.viewToken;
    final sid = credBroker.sid;
    final serverId = credBroker.serverId;

    // Generate unique_id matching RGX pattern
    final uniqueId = '${modelId}_${DateTime.now().millisecondsSinceEpoch}_$email';

    // 3. Build trade list in CCXT format (matching RGX RebalanceModal.js)
    final trades = orders.map((o) => <String, dynamic>{
      'user_email': email,
      'tradingSymbol': o['symbol'] ?? o['tradingSymbol'] ?? '',
      'transactionType': (o['transactionType'] ?? 'BUY').toString().toUpperCase(),
      'exchange': o['exchange'] ?? 'NSE',
      'segment': 'EQUITY',
      'productType': 'DELIVERY',
      'orderType': o['orderType'] ?? 'MARKET',
      'price': o['price'] ?? 0,
      'quantity': o['quantity'] ?? 0,
      'token': o['token'] ?? '',
      'priority': 0,
      'user_broker': brokerName,
    }).toList();

    // 3. Zerodha uses WebView basket — throw exception for caller to handle
    if (brokerName.toLowerCase() == 'zerodha') {
      // Build Kite basket items
      final basketItems = orders.map((o) => <String, dynamic>{
        'variety': 'regular',
        'tradingsymbol': o['symbol'] ?? o['tradingSymbol'] ?? '',
        'exchange': o['exchange'] ?? 'NSE',
        'transaction_type': (o['transactionType'] ?? 'BUY').toString().toUpperCase(),
        'order_type': 'MARKET',
        'quantity': o['quantity'] ?? 0,
        'product': 'CNC',
        'readonly': false,
        'price': 0,
      }).toList();

      // Prepare stock details for record-orders call after basket
      final stockDetails = orders.map((o) => <String, dynamic>{
        'user_email': email,
        'trade_given_by': advisor,
        'tradingSymbol': o['symbol'] ?? o['tradingSymbol'] ?? '',
        'transactionType': (o['transactionType'] ?? 'BUY').toString().toUpperCase(),
        'exchange': o['exchange'] ?? 'NSE',
        'segment': 'EQUITY',
        'productType': 'DELIVERY',
        'orderType': 'MARKET',
        'price': o['price'] ?? 0,
        'quantity': o['quantity'] ?? 0,
        'priority': 0,
        'user_broker': 'Zerodha',
      }).toList();

      // Update DB before showing basket
      try {
        await AqApiService.instance.updateZerodhaRecoBeforeBasket(
          stockDetails: stockDetails,
          email: email,
          advisor: advisor,
        );
      } catch (e) {
        debugPrint('[OrderExecution] updateZerodhaReco failed (non-fatal): $e');
      }

      // Company API key for publisher login — fall back to .env if not in broker record
      final zerodhaApiKey = apiKey.isNotEmpty
          ? apiKey
          : (dotenv.env['ZERODHA_API_KEY'] ?? dotenv.env['REACT_APP_ZERODHA_API_KEY'] ?? '');

      throw ZerodhaBasketRequiredException(
        apiKey: zerodhaApiKey,
        basketItems: basketItems,
        stockDetails: stockDetails,
      );
    }

    // 4. Non-Zerodha: call CCXT rebalance/process-trade
    final response = await AqApiService.instance.processTrade(
      email: email,
      broker: brokerName,
      modelName: modelName,
      modelId: modelId,
      advisor: advisor,
      uniqueId: uniqueId,
      trades: trades,
      apiKey: apiKey.isNotEmpty ? apiKey : null,
      secretKey: secretKey,
      jwtToken: jwtToken.isNotEmpty ? jwtToken : null,
      clientCode: clientCode,
      viewToken: viewToken,
      sid: sid,
      serverId: serverId,
    );

    // 5. Parse results — save raw details for post-execution API calls
    final results = <OrderResult>[];
    List<Map<String, dynamic>> rawTradeDetails = [];

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint('[OrderExecution] process-trade response keys: ${data is Map ? data.keys.toList() : 'not-map'}');

      // Check nested data wrapper (API may return { data: { tradeDetails: [...] } })
      final innerData = data is Map ? data['data'] : null;
      final tradeDetails = data['tradeDetails'] ??
          data['response'] ??
          data['order_results'] ??
          data['results'] ??
          (innerData is Map ? (innerData['tradeDetails'] ?? innerData['order_results'] ?? innerData['results']) : null) ??
          (innerData is Map && innerData['user_net_pf_model'] is Map ? innerData['user_net_pf_model']['order_results'] : null) ??
          [];

      if (tradeDetails is List && tradeDetails.isNotEmpty) {
        rawTradeDetails = tradeDetails
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();

        for (int i = 0; i < tradeDetails.length; i++) {
          final result = OrderResult.fromJson(
            tradeDetails[i] is Map
                ? Map<String, dynamic>.from(tradeDetails[i])
                : <String, dynamic>{},
          );
          results.add(result);
          onOrderUpdate(i + 1, orders.length, result);
        }
      } else {
        // No detailed results — mark as pending (not success) since we
        // have no trade confirmation from the broker.
        for (int i = 0; i < orders.length; i++) {
          final result = OrderResult(
            symbol: orders[i]['symbol'] ?? orders[i]['tradingSymbol'] ?? '',
            transactionType: orders[i]['transactionType'] ?? 'BUY',
            quantity: orders[i]['quantity'] ?? 0,
            price: (orders[i]['price'] as num?)?.toDouble(),
            status: 'pending',
            message: 'Order submitted — awaiting confirmation',
          );
          results.add(result);
          onOrderUpdate(i + 1, orders.length, result);
        }
      }
    } else {
      // Extract error message from response body if possible
      String errorMsg = 'Order placement failed (HTTP ${response.statusCode})';
      try {
        final errData = jsonDecode(response.body);
        final serverMsg = errData['message'] ?? errData['error'] ?? errData['msg'];
        if (serverMsg != null) errorMsg = serverMsg.toString();
      } catch (_) {}

      debugPrint('[OrderExecution] process-trade failed: ${response.statusCode} ${response.body}');
      for (int i = 0; i < orders.length; i++) {
        final result = OrderResult(
          symbol: orders[i]['symbol'] ?? orders[i]['tradingSymbol'] ?? '',
          transactionType: orders[i]['transactionType'] ?? 'BUY',
          quantity: orders[i]['quantity'] ?? 0,
          status: 'failed',
          message: errorMsg,
        );
        results.add(result);
        onOrderUpdate(i + 1, orders.length, result);
      }
    }

    // ── Post-execution pipeline (matching RGX RebalanceModal.js) ──

    final successCount = results.where((r) => r.isSuccess).length;
    final executionStatus = successCount == results.length
        ? 'executed'
        : (successCount > 0 ? 'partial' : 'pending');

    // 6. model-portfolio-db-update (RGX calls this first)
    try {
      final orderResultsForDb = rawTradeDetails.isNotEmpty
          ? rawTradeDetails
          : results.map((r) => r.toApiJson()).toList();
      await AqApiService.instance.updatePortfolioAfterExecution(
        modelId: modelId,
        orderResults: orderResultsForDb,
        userEmail: email,
        userBroker: brokerName,
      );
    } catch (e) {
      debugPrint('[OrderExecution] updatePortfolioAfterExecution failed: $e');
    }

    // 7. update/subscriber-execution
    try {
      await AqApiService.instance.updateSubscriberExecution(
        email: email,
        modelName: modelName,
        advisor: advisor,
        broker: brokerName,
        executionStatus: executionStatus,
      );
    } catch (e) {
      debugPrint('[OrderExecution] updateSubscriberExecution failed: $e');
    }

    // 8. record-publisher-results (Fyers publisher flow — matches RGX)
    if (brokerName.toLowerCase() == 'fyers') {
      try {
        await AqApiService.instance.recordPublisherResults(
          modelName: modelName,
          modelId: modelId,
          uniqueId: uniqueId,
          advisor: advisor,
          orderResults: rawTradeDetails.isNotEmpty
              ? rawTradeDetails
              : results.map((r) => r.toApiJson()).toList(),
          email: email,
          broker: brokerName,
        );
        debugPrint('[OrderExecution] recordPublisherResults success (Fyers)');
      } catch (e) {
        debugPrint('[OrderExecution] recordPublisherResults failed: $e');
      }
    }

    // 9. add-user/status-check-queue (always last)
    try {
      await AqApiService.instance.addToStatusCheckQueue(
        email: email,
        modelName: modelName,
        advisor: advisor,
        broker: brokerName,
      );
    } catch (e) {
      debugPrint('[OrderExecution] addToStatusCheckQueue failed: $e');
    }

    return results;
  }

  /// Execute orders via DummyBroker flow — records trades in ccxt-india
  /// without actually placing broker orders. The user manually executes
  /// orders in their own broker app.
  ///
  /// Mirrors the web frontend's DummyBrokerHoldingConfirmation.js pattern:
  ///   1. POST /rebalance/process-trade
  ///   2. PUT  /rebalance/update/subscriber-execution
  ///   3. POST /rebalance/add-user/status-check-queue
  Future<List<OrderResult>> executeDummyBrokerOrders({
    required List<Map<String, dynamic>> orders,
    required String email,
    required String modelName,
    required String modelId,
    required String advisor,
    required void Function(int completed, int total, OrderResult latest) onOrderUpdate,
  }) async {
    _lastUsedBrokerName = 'DummyBroker';

    // Build trades in the CCXT format (matching RGX DummyBrokerHoldingConfirmation.js)
    final trades = orders.map((o) => <String, dynamic>{
      'user_email': email,
      'tradingSymbol': o['symbol'] ?? o['tradingSymbol'] ?? '',
      'transactionType': (o['transactionType'] ?? 'BUY').toString().toUpperCase(),
      'exchange': o['exchange'] ?? 'NSE',
      'segment': 'EQUITY',
      'productType': 'DELIVERY',
      'orderType': o['orderType'] ?? 'MARKET',
      'price': o['price'] ?? 0,
      'quantity': o['quantity'] ?? 0,
      'token': o['token'] ?? '',
      'priority': 0,
      'user_broker': 'DummyBroker',
    }).toList();

    final results = <OrderResult>[];

    // Step 1: Process trades
    final tradeResp = await AqApiService.instance.processDummyBrokerTrade(
      email: email,
      modelName: modelName,
      modelId: modelId,
      advisor: advisor,
      trades: trades,
    );

    if (tradeResp.statusCode == 200) {
      for (int i = 0; i < orders.length; i++) {
        final result = OrderResult(
          symbol: orders[i]['symbol'] ?? orders[i]['tradingSymbol'] ?? '',
          transactionType: orders[i]['transactionType'] ?? 'BUY',
          quantity: orders[i]['quantity'] ?? 0,
          price: (orders[i]['price'] as num?)?.toDouble(),
          status: 'success',
          message: 'Recorded (execute manually in your broker)',
        );
        results.add(result);
        onOrderUpdate(i + 1, orders.length, result);
      }
    } else {
      debugPrint('[OrderExecution] DummyBroker process-trade failed: ${tradeResp.statusCode} ${tradeResp.body}');
      for (int i = 0; i < orders.length; i++) {
        final result = OrderResult(
          symbol: orders[i]['symbol'] ?? orders[i]['tradingSymbol'] ?? '',
          transactionType: orders[i]['transactionType'] ?? 'BUY',
          quantity: orders[i]['quantity'] ?? 0,
          status: 'failed',
          message: 'Trade recording failed (HTTP ${tradeResp.statusCode})',
        );
        results.add(result);
        onOrderUpdate(i + 1, orders.length, result);
      }
      return results;
    }

    // Step 2: Update subscriber execution status
    try {
      await AqApiService.instance.updateSubscriberExecution(
        email: email,
        modelName: modelName,
        advisor: advisor,
        broker: 'DummyBroker',
      );
    } catch (e) {
      debugPrint('[OrderExecution] DummyBroker updateSubscriberExecution failed: $e');
    }

    // Step 3: Add to status check queue
    try {
      await AqApiService.instance.addToStatusCheckQueue(
        email: email,
        modelName: modelName,
        advisor: advisor,
        broker: 'DummyBroker',
      );
    } catch (e) {
      debugPrint('[OrderExecution] DummyBroker addToStatusCheckQueue failed: $e');
    }

    return results;
  }

  /// Update the model portfolio database after execution
  Future<void> updatePortfolioAfterExecution({
    required String modelId,
    required List<OrderResult> results,
    required String email,
    required String broker,
  }) async {
    final orderResults = results.map((r) => r.toApiJson()).toList();
    await AqApiService.instance.updatePortfolioAfterExecution(
      modelId: modelId,
      orderResults: orderResults,
      userEmail: email,
      userBroker: broker,
    );
  }
}
