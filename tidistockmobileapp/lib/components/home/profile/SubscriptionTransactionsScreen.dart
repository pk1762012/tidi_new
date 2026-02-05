import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/theme/theme.dart';

import '../../../service/ApiService.dart';

class SubscriptionTransactionsScreen extends StatefulWidget {
  const SubscriptionTransactionsScreen({super.key});

  @override
  State<SubscriptionTransactionsScreen> createState() => _SubscriptionTransactionsScreenState();
}

class _SubscriptionTransactionsScreenState extends State<SubscriptionTransactionsScreen> {
  bool isLoading = true;
  List<dynamic> transactions = [];
  int offset = 0;
  final int limit = 20;
  bool hasMore = true;
  final ScrollController _scrollController = ScrollController();

  final dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    fetchTransactions();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent &&
          !isLoading &&
          hasMore) {
        fetchTransactions();
      }
    });
  }

  Future<void> fetchTransactions({bool reset = false}) async {
    if (reset) {
      setState(() {
        offset = 0;
        transactions.clear();
        hasMore = true;
      });
    }

    setState(() => isLoading = true);

    try {
      final apiService = ApiService();
      final response = await apiService.getSubscriptionTransactions(limit, offset);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> newData = data['data'] ?? [];

        setState(() {
          offset += limit;
          transactions.addAll(newData);
          hasMore = newData.length == limit;
        });
      } else {
        showError("Failed to load transactions");
      }
    } catch (e) {
      showError("Error occurred");
    }

    setState(() => isLoading = false);
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildTransactionTile(dynamic tx) {
    final startDate = tx['startDate'];
    final formattedDate = startDate != null ? dateFormat.format(DateTime.parse(startDate)) : 'N/A';
    final rawType = tx['subscriptionType'];
    final plan = switch (rawType) {
      'MONTHLY' => '1 Month',
      'SEMI_YEARLY' => '6 Months',
      'HALF_YEARLY' => '6 Months',
      'YEARLY' => '1 Year',
      _ => 'Unknown',
    };

    final amount = tx['amount'] ?? '0';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.subscriptions, color: Colors.black87, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Plan: $plan",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "Start Date: $formattedDate",
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            "₹$amount",
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: lightColorScheme.primary,
            backgroundColor: Colors.black87,
            onRefresh: () async => await fetchTransactions(reset: true),
            child: transactions.isEmpty && !isLoading
                ? Center(
              child: Text(
                "No subscription transactions yet.",
                style: TextStyle(color: lightColorScheme.primary, fontSize: 16),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: transactions.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < transactions.length) {
                  return _buildTransactionTile(transactions[index]);
                } else {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
