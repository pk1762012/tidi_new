import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';

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

  /// Execute a list of orders through the connected broker via CCXT
  /// rebalance/process-trade endpoint (matching the RGX web app flow).
  ///
  /// For Zerodha: throws [ZerodhaBasketRequiredException] — caller must
  /// handle the WebView basket flow.
  ///
  /// For other brokers: calls CCXT rebalance/process-trade and returns results.
  ///
  /// After successful execution, calls:
  ///   1. rebalance/add-user/status-check-queue
  ///   2. rebalance/update/subscriber-execution
  Future<List<OrderResult>> executeOrders({
    required List<Map<String, dynamic>> orders,
    required String email,
    required String modelName,
    required String modelId,
    required String advisor,
    required void Function(int completed, int total, OrderResult latest) onOrderUpdate,
  }) async {
    // 1. Get user's connected broker credentials
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
    if (brokerData is! Map) {
      throw Exception('Unexpected broker response format');
    }
    final brokers = brokerData['data'] ?? brokerData['connected_brokers'] ?? [];
    if (brokers is! List || brokers.isEmpty) {
      throw Exception('No connected broker found');
    }

    // Use the first connected broker
    final broker = brokers.firstWhere(
      (b) => b['status'] == 'connected',
      orElse: () => brokers[0],
    );

    final brokerName = broker['broker'] ?? '';
    _lastUsedBrokerName = brokerName;
    final apiKey = broker['apiKey'] ?? '';
    final jwtToken = broker['jwtToken'] ?? '';
    final clientCode = broker['clientCode'];
    final secretKey = broker['secretKey'];
    final accessToken = broker['accessToken'];
    final viewToken = broker['viewToken'];
    final sid = broker['sid'];
    final serverId = broker['serverId'];

    // Generate unique_id matching RGX pattern
    final uniqueId = '${modelId}_${DateTime.now().millisecondsSinceEpoch}_$email';

    // 2. Build trade list in CCXT format (matching RGX RebalanceModal.js)
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

      // Company API key for publisher login
      final zerodhaApiKey = broker['zerodhaApiKey'] ?? apiKey;

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
      accessToken: accessToken,
      viewToken: viewToken,
      sid: sid,
      serverId: serverId,
    );

    // 5. Parse results
    final results = <OrderResult>[];
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final tradeDetails = data['tradeDetails'] ??
          data['response'] ??
          data['order_results'] ??
          data['results'] ??
          [];

      if (tradeDetails is List && tradeDetails.isNotEmpty) {
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
        // No detailed results — mark all as success if HTTP 200
        for (int i = 0; i < orders.length; i++) {
          final result = OrderResult(
            symbol: orders[i]['symbol'] ?? orders[i]['tradingSymbol'] ?? '',
            transactionType: orders[i]['transactionType'] ?? 'BUY',
            quantity: orders[i]['quantity'] ?? 0,
            price: (orders[i]['price'] as num?)?.toDouble(),
            status: 'success',
            message: 'Order placed successfully',
          );
          results.add(result);
          onOrderUpdate(i + 1, orders.length, result);
        }
      }
    } else {
      debugPrint('[OrderExecution] process-trade failed: ${response.statusCode} ${response.body}');
      for (int i = 0; i < orders.length; i++) {
        final result = OrderResult(
          symbol: orders[i]['symbol'] ?? orders[i]['tradingSymbol'] ?? '',
          transactionType: orders[i]['transactionType'] ?? 'BUY',
          quantity: orders[i]['quantity'] ?? 0,
          status: 'failed',
          message: 'Order placement failed (HTTP ${response.statusCode})',
        );
        results.add(result);
        onOrderUpdate(i + 1, orders.length, result);
      }
    }

    // 6. Post-execution: update subscriber execution status
    final successCount = results.where((r) => r.isSuccess).length;
    final executionStatus = successCount == results.length
        ? 'executed'
        : (successCount > 0 ? 'partial' : 'pending');

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

    // 7. Post-execution: add to status check queue
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
