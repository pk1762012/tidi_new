import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/service/AqApiService.dart';

/// Post-execution order status modal matching alphab2b MPStatusModal.js.
///
/// Three modes:
///   - viewing: Show successful orders (default)
///   - editing: Allow quantity/price edits and add/remove stocks
///   - confirmFailed: Require user to confirm failed orders
class MPStatusModal extends StatefulWidget {
  final String email;
  final String modelName;
  final String advisor;
  final String broker;
  final List<Map<String, dynamic>>? initialStockData;
  final String initialMode; // 'viewing', 'editing', 'confirmFailed'

  const MPStatusModal({
    super.key,
    required this.email,
    required this.modelName,
    required this.advisor,
    required this.broker,
    this.initialStockData,
    this.initialMode = 'viewing',
  });

  /// Show as a modal bottom sheet and return updated stock data or null.
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required String email,
    required String modelName,
    required String advisor,
    required String broker,
    List<Map<String, dynamic>>? stockData,
    String mode = 'viewing',
  }) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => MPStatusModal(
          email: email,
          modelName: modelName,
          advisor: advisor,
          broker: broker,
          initialStockData: stockData,
          initialMode: mode,
        ),
      ),
    );
  }

  @override
  State<MPStatusModal> createState() => _MPStatusModalState();
}

class _MPStatusModalState extends State<MPStatusModal> {
  late String _viewMode;
  List<Map<String, dynamic>> _stockList = [];
  bool _isLoading = false;
  String? _error;
  String? _successMessage;
  String? _portfolioDocId;
  Map<String, bool> _confirmedStocks = {};

  // New stock form fields (edit mode)
  final _newSymbolController = TextEditingController();
  final _newQuantityController = TextEditingController();
  final _newPriceController = TextEditingController();
  String _newExchange = 'NSE';
  List<Map<String, dynamic>> _symbolResults = [];
  bool _isSymbolLoading = false;

  @override
  void initState() {
    super.initState();
    _viewMode = widget.initialMode;
    if (widget.initialStockData != null) {
      _stockList = widget.initialStockData!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      _fetchLatestPortfolio();
    }
  }

  @override
  void dispose() {
    _newSymbolController.dispose();
    _newQuantityController.dispose();
    _newPriceController.dispose();
    super.dispose();
  }

  Future<void> _fetchLatestPortfolio() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final resp = await AqApiService.instance.getLatestUserPortfolio(
        email: widget.email,
        modelName: widget.modelName,
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final innerData = data['data'] ?? data;

        // Extract document ID for updates
        if (innerData is Map) {
          final id = innerData['_id'];
          if (id is Map) {
            _portfolioDocId = id['\$oid']?.toString();
          } else if (id is String) {
            _portfolioDocId = id;
          }
        }

        // Extract order_results
        final netPf = innerData['user_net_pf_model'];
        List<dynamic>? orderResults;
        if (netPf is Map) {
          orderResults = netPf['order_results'];
        } else if (netPf is List && netPf.isNotEmpty) {
          // Take latest entry
          final latest = netPf.last;
          if (latest is Map) {
            orderResults = latest['order_results'];
          }
        }

        if (orderResults is List) {
          _stockList = orderResults
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
              .toList();
        }
      } else {
        _error = 'Failed to fetch portfolio (${resp.statusCode})';
      }
    } catch (e) {
      _error = 'Error: $e';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  bool _isStockFailed(Map<String, dynamic> stock) {
    final status = (stock['orderStatus'] ?? stock['rebalance_status'] ?? '').toString().toLowerCase();
    return status == 'rejected' || status == 'cancelled' || status == 'failed';
  }

  List<Map<String, dynamic>> get _successfulStocks =>
      _stockList.where((s) => !_isStockFailed(s)).toList();

  List<Map<String, dynamic>> get _failedStocks =>
      _stockList.where((s) => _isStockFailed(s)).toList();

  Future<void> _saveEdits() async {
    if (_portfolioDocId == null) {
      setState(() => _error = 'Missing portfolio document ID');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final orderResults = _stockList.map((s) => {
        'symbol': s['symbol'] ?? s['tradingsymbol'] ?? '',
        'transactionType': s['transactionType'] ?? 'BUY',
        'quantity': s['quantity']?.toString() ?? '0',
        'filledShares': s['filledShares']?.toString() ?? s['quantity']?.toString() ?? '0',
        'averageEntryPrice': s['averageEntryPrice'] ?? s['averagePrice'] ?? 0,
        'averagePrice': s['averagePrice'] ?? s['averageEntryPrice'] ?? 0,
        'exchange': s['exchange'] ?? 'NSE',
      }).toList();

      await AqApiService.instance.updateLatestUserPortfolio(
        documentId: _portfolioDocId!,
        modelName: widget.modelName,
        userEmail: widget.email,
        orderResults: orderResults,
        userBroker: widget.broker,
      );

      setState(() => _successMessage = 'Portfolio updated successfully');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, _stockList);
    } catch (e) {
      setState(() => _error = 'Update failed: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _confirmFailedOrders() async {
    if (_portfolioDocId == null) {
      setState(() => _error = 'Missing portfolio document ID');
      return;
    }

    final confirmed = _confirmedStocks.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (confirmed.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final updatedPortfolio = _failedStocks
          .where((s) => confirmed.contains(s['symbol'] ?? s['tradingsymbol']))
          .map((s) => {
            'symbol': s['symbol'] ?? s['tradingsymbol'] ?? '',
            'exchange': s['exchange'] ?? 'NSE',
            'transactionType': s['transactionType'] ?? 'BUY',
            'filledShares': int.tryParse(s['quantity']?.toString() ?? '0') ?? 0,
            'averagePrice': s['averagePrice'] ?? s['averageEntryPrice'] ?? 0,
          })
          .toList();

      final allConfirmed = confirmed.length >= _failedStocks.length;

      await AqApiService.instance.confirmFailedOrders(
        userEmail: widget.email,
        modelObjectId: _portfolioDocId!,
        updatedPortfolio: updatedPortfolio,
        advisor: widget.advisor,
        modelName: widget.modelName,
        userBroker: widget.broker,
        allOrdersComplete: allConfirmed,
      );

      setState(() => _successMessage = 'Failed orders confirmed');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, _stockList);
    } catch (e) {
      setState(() => _error = 'Confirm failed: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _searchSymbol(String query) async {
    if (query.length < 2) {
      setState(() => _symbolResults = []);
      return;
    }

    setState(() => _isSymbolLoading = true);

    try {
      final resp = await AqApiService.instance.searchSymbol(query);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List) {
          _symbolResults = data.take(10).map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('[MPStatusModal] symbol search error: $e');
    }

    if (mounted) setState(() => _isSymbolLoading = false);
  }

  void _addStock(String symbol, String exchange) {
    final qty = int.tryParse(_newQuantityController.text) ?? 0;
    final price = double.tryParse(_newPriceController.text) ?? 0;
    if (qty <= 0) return;

    setState(() {
      _stockList.add({
        'symbol': symbol,
        'exchange': exchange,
        'transactionType': 'BUY',
        'quantity': qty,
        'filledShares': qty,
        'averageEntryPrice': price,
        'averagePrice': price,
        'orderStatus': 'COMPLETE',
      });
      _newSymbolController.clear();
      _newQuantityController.clear();
      _newPriceController.clear();
      _symbolResults = [];
    });
  }

  void _removeStock(int index) {
    setState(() => _stockList.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _viewMode == 'confirmFailed'
                        ? "Confirm Failed Orders"
                        : _viewMode == 'editing'
                            ? "Edit Holdings"
                            : "Order Status",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                // Mode toggle buttons
                if (_viewMode == 'viewing') ...[
                  TextButton.icon(
                    onPressed: () => setState(() => _viewMode = 'editing'),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text("Edit"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                ],
                if (_viewMode == 'editing')
                  TextButton.icon(
                    onPressed: () => setState(() => _viewMode = 'viewing'),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text("View"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
              ],
            ),
          ),

          // Success/Error messages
          if (_successMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                  const SizedBox(width: 8),
                  Text(_successMessage!, style: TextStyle(fontSize: 13, color: Colors.green.shade700)),
                ],
              ),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: Colors.red.shade700))),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stockList.isEmpty
                    ? Center(
                        child: Text("No order data available",
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        children: [
                          // Failed orders section (confirmFailed mode)
                          if (_viewMode == 'confirmFailed' && _failedStocks.isNotEmpty) ...[
                            _sectionHeader("Failed Orders", Colors.red),
                            ..._failedStocks.map((stock) => _confirmFailedRow(stock)),
                            const SizedBox(height: 16),
                          ],

                          // Stock list
                          if (_viewMode != 'confirmFailed') ...[
                            ...(_viewMode == 'viewing' ? _successfulStocks : _stockList)
                                .asMap()
                                .entries
                                .map((entry) => _stockRow(entry.key, entry.value)),
                          ],

                          // Add new stock (edit mode)
                          if (_viewMode == 'editing') ...[
                            const SizedBox(height: 16),
                            _addStockSection(),
                          ],
                        ],
                      ),
          ),

          // Bottom actions
          _bottomActions(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _stockRow(int index, Map<String, dynamic> stock) {
    final symbol = stock['symbol'] ?? stock['tradingsymbol'] ?? '';
    final type = (stock['transactionType'] ?? 'BUY').toString().toUpperCase();
    final qty = stock['quantity'] ?? stock['filledShares'] ?? 0;
    final price = stock['averagePrice'] ?? stock['averageEntryPrice'] ?? 0;
    final exchange = stock['exchange'] ?? 'NSE';
    final isFailed = _isStockFailed(stock);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFailed ? Colors.red.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isFailed ? Colors.red.shade200 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (isFailed) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text("FAILED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                      ),
                    ],
                  ],
                ),
                Text(exchange, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: type == 'BUY' ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(type,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: type == 'BUY' ? Colors.green : Colors.red)),
          ),
          const SizedBox(width: 12),
          if (_viewMode == 'editing') ...[
            SizedBox(
              width: 50,
              child: TextFormField(
                initialValue: '$qty',
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  _stockList[index]['quantity'] = int.tryParse(v) ?? qty;
                  _stockList[index]['filledShares'] = int.tryParse(v) ?? qty;
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: TextFormField(
                initialValue: '$price',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  border: OutlineInputBorder(),
                  prefixText: '\u20B9',
                ),
                onChanged: (v) {
                  final p = double.tryParse(v) ?? price;
                  _stockList[index]['averagePrice'] = p;
                  _stockList[index]['averageEntryPrice'] = p;
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
              onPressed: () => _removeStock(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ] else ...[
            Text("$qty", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Text("\u20B9$price", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ],
      ),
    );
  }

  Widget _confirmFailedRow(Map<String, dynamic> stock) {
    final symbol = stock['symbol'] ?? stock['tradingsymbol'] ?? '';
    final type = (stock['transactionType'] ?? 'BUY').toString().toUpperCase();
    final qty = stock['quantity'] ?? stock['filledShares'] ?? 0;
    final isConfirmed = _confirmedStocks[symbol] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConfirmed ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isConfirmed ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isConfirmed,
            onChanged: (v) => setState(() => _confirmedStocks[symbol] = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text("$type  Qty: $qty", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(
            isConfirmed ? "Confirmed" : "Failed",
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: isConfirmed ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _addStockSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Add Stock", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
          const SizedBox(height: 10),
          TextField(
            controller: _newSymbolController,
            decoration: InputDecoration(
              hintText: "Search symbol...",
              isDense: true,
              suffixIcon: _isSymbolLoading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: _searchSymbol,
          ),
          if (_symbolResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ListView(
                shrinkWrap: true,
                children: _symbolResults.map((r) {
                  final sym = r['symbol'] ?? r['name'] ?? '';
                  final seg = r['segment'] ?? 'NSE';
                  return ListTile(
                    dense: true,
                    title: Text(sym, style: const TextStyle(fontSize: 13)),
                    trailing: Text(seg, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    onTap: () {
                      _newSymbolController.text = sym;
                      _newExchange = seg;
                      setState(() => _symbolResults = []);
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newQuantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: "Qty",
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _newPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: "Price",
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    prefixText: '\u20B9',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_newSymbolController.text.isNotEmpty) {
                    _addStock(_newSymbolController.text, _newExchange);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Add", style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Close"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : _viewMode == 'confirmFailed'
                        ? (_confirmedStocks.values.any((v) => v) ? _confirmFailedOrders : null)
                        : _viewMode == 'editing'
                            ? _saveEdits
                            : () => Navigator.pop(context, _stockList),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _viewMode == 'confirmFailed' ? Colors.orange : const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _viewMode == 'confirmFailed'
                            ? "Confirm Selected"
                            : _viewMode == 'editing'
                                ? "Save Changes"
                                : "Done",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
