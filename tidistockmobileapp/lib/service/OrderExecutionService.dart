import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tidistockmobileapp/models/order_result.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';

class OrderExecutionService {
  OrderExecutionService._();
  static final OrderExecutionService instance = OrderExecutionService._();

  /// Execute a list of orders through the connected broker.
  ///
  /// [orders] — list of order maps with keys: symbol, exchange, quantity,
  ///            transactionType, productType, orderType, price
  /// [email] — user's email
  /// [onOrderUpdate] — callback fired after each order is processed
  ///
  /// Returns a list of [OrderResult].
  Future<List<OrderResult>> executeOrders({
    required List<Map<String, dynamic>> orders,
    required String email,
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
    final apiKey = broker['apiKey'] ?? '';
    final jwtToken = broker['jwtToken'] ?? '';
    final clientCode = broker['clientCode'];
    final secretKey = broker['secretKey'];
    final viewToken = broker['viewToken'];
    final sid = broker['sid'];
    final serverId = broker['serverId'];

    // 2. Build trade list
    final trades = orders.map((o) => {
      'user_email': email,
      'tradingSymbol': o['symbol'],
      'transactionType': (o['transactionType'] ?? 'BUY').toUpperCase(),
      'quantity': o['quantity'],
      'orderType': o['orderType'] ?? 'MARKET',
      'price': o['price'] ?? 0,
      'productType': o['productType'] ?? 'CNC',
      'exchange': o['exchange'] ?? 'NSE',
      'user_broker': brokerName,
    }).toList();

    // 3. Place all orders in a single API call
    final response = await AqApiService.instance.placeOrders(
      userBroker: brokerName,
      apiKey: apiKey,
      jwtToken: jwtToken,
      trades: trades,
      clientCode: clientCode,
      secretKey: secretKey,
      viewToken: viewToken,
      sid: sid,
      serverId: serverId,
    );

    // 4. Parse results
    final results = <OrderResult>[];
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final tradeDetails = data['tradeDetails'] ?? data['response'] ?? [];

      for (int i = 0; i < (tradeDetails as List).length; i++) {
        final result = OrderResult.fromJson(tradeDetails[i]);
        results.add(result);
        onOrderUpdate(i + 1, orders.length, result);
      }
    } else {
      // All orders failed
      for (int i = 0; i < orders.length; i++) {
        final result = OrderResult(
          symbol: orders[i]['symbol'] ?? '',
          transactionType: orders[i]['transactionType'] ?? 'BUY',
          quantity: orders[i]['quantity'] ?? 0,
          status: 'failed',
          message: 'Order placement failed (HTTP ${response.statusCode})',
        );
        results.add(result);
        onOrderUpdate(i + 1, orders.length, result);
      }
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
