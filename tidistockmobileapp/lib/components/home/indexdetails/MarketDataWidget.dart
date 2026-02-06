import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/io.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'MarketIndexBar.dart';

class MarketDataWidget extends StatefulWidget {
  const MarketDataWidget({super.key});

  @override
  State<MarketDataWidget> createState() => MarketDataWidgetState();
}

class MarketDataWidgetState extends State<MarketDataWidget>
    with WidgetsBindingObserver {

  double nifty = 0.0;
  double bankNifty = 0.0;
  double niftyChange = 0.0;
  double bankNiftyChange = 0.0;

  Map<String, Map<String, double>> otherIndices = {};
  final String token = dotenv.env['MARKET_DATA_PASSWORD'] ?? '';
  final String url = dotenv.env['MARKET_WS_URL'] ?? '';

  IOWebSocketChannel? channel;
  StreamSubscription? _channelSubscription;
  bool _isConnected = false;
  bool _isConnecting = false;

  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchInitialData();
    connectWebSocket();
  }

  void _closeWs() {
    _isConnected = false;
    _isConnecting = false;
    _channelSubscription?.cancel();
    _channelSubscription = null;

    channel?.sink.close();
    channel = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _closeWs();
    }

    if (state == AppLifecycleState.resumed) {
      _fetchInitialData();
      connectWebSocket();
    }
  }

  Future<void> _fetchInitialData() async {
    try {
      final apiService = ApiService();
      final results = await Future.wait([
        apiService.getMarketQuote('NIFTY 50'),
        apiService.getMarketQuote('NIFTY BANK'),
      ]).timeout(const Duration(seconds: 10));

      final niftyResponse = results[0];
      final bankNiftyResponse = results[1];

      double tempNifty = nifty;
      double tempNiftyChange = niftyChange;
      double tempBankNifty = bankNifty;
      double tempBankNiftyChange = bankNiftyChange;

      if (niftyResponse.statusCode == 200) {
        final body = json.decode(niftyResponse.body);
        final data = body['data'] ?? body;
        final cmp = (data['cmp'] ?? data['last'] ?? data['ltp'] ?? 0).toDouble();
        final prevClose = (data['prev_close'] ?? data['previousClose'] ?? cmp).toDouble();
        if (cmp > 0) {
          tempNifty = double.parse(cmp.toStringAsFixed(2));
          tempNiftyChange = double.parse((cmp - prevClose).toStringAsFixed(2));
        }
      }

      if (bankNiftyResponse.statusCode == 200) {
        final body = json.decode(bankNiftyResponse.body);
        final data = body['data'] ?? body;
        final cmp = (data['cmp'] ?? data['last'] ?? data['ltp'] ?? 0).toDouble();
        final prevClose = (data['prev_close'] ?? data['previousClose'] ?? cmp).toDouble();
        if (cmp > 0) {
          tempBankNifty = double.parse(cmp.toStringAsFixed(2));
          tempBankNiftyChange = double.parse((cmp - prevClose).toStringAsFixed(2));
        }
      }

      if (!mounted) return;
      setState(() {
        nifty = tempNifty;
        niftyChange = tempNiftyChange;
        bankNifty = tempBankNifty;
        bankNiftyChange = tempBankNiftyChange;
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      print("HTTP fetch error: $e");
      if (!mounted) return;
      setState(() {
        if (_isLoading) {
          _hasError = true;
          _isLoading = false;
        }
      });
    }
  }

  void retryConnection() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _fetchInitialData();
    connectWebSocket();
  }

  Future<void> connectWebSocket() async {
    if (_isConnecting || _isConnected) return;

    try {
      _isConnecting = true;

      await _channelSubscription?.cancel();
      await channel?.sink.close();

      final uri = Uri(
        scheme: 'wss',
        host: Uri.parse(url).host,
        path: '/ws/indices',
      );

      final ws = await WebSocket.connect(
        uri.toString(),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      _isConnected = true;
      _isConnecting = false;

      channel = IOWebSocketChannel(ws);

      _channelSubscription = channel!.stream.listen(
            (message) {
          try {
            final decoded = json.decode(message);
            if (decoded['type'] == "indices_snapshot") {
              final data = decoded['data'] as List<dynamic>;

              double tempNifty = nifty;
              double tempNiftyChange = niftyChange;
              double tempBankNifty = bankNifty;
              double tempBankNiftyChange = bankNiftyChange;

              Map<String, Map<String, double>> tempOther = {};

              for (var item in data) {
                final instrument = item['instrument'] ?? '';
                final cmp = (item['cmp'] != null)
                    ? double.parse((item['cmp'] as num).toStringAsFixed(2))
                    : 0.0;
                final prevClose = (item['prev_close'] != null)
                    ? double.parse((item['prev_close'] as num).toStringAsFixed(2))
                    : cmp;
                final change = cmp - prevClose;

                if (instrument.toUpperCase() == "NIFTY_50") {
                  tempNifty = cmp;
                  tempNiftyChange = change;
                } else if (instrument.toUpperCase() == "NIFTY_BANK") {
                  tempBankNifty = cmp;
                  tempBankNiftyChange = change;
                } else {
                  tempOther[instrument] = {
                    "cmp": cmp,
                    "change": change,
                  };
                }
              }

              if (!mounted) return;
              setState(() {
                nifty = tempNifty;
                niftyChange = tempNiftyChange;
                bankNifty = tempBankNifty;
                bankNiftyChange = tempBankNiftyChange;
                otherIndices = tempOther;
                _isLoading = false;
                _hasError = false;
              });
            }
          } catch (e) {
            print("JSON decode error: $e");
          }
        },
        onDone: () {
          _isConnected = false;
          _isConnecting = false;
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
        onError: (error) {
          _isConnected = false;
          _isConnecting = false;
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
        cancelOnError: true,
      );
    } on TimeoutException {
      print("WebSocket connection timed out");
      _isConnecting = false;
      _isConnected = false;
      if (!mounted) return;
      if (_isLoading) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
      Future.delayed(const Duration(seconds: 5), connectWebSocket);
    } catch (e) {
      print("Connection error: $e");
      _isConnecting = false;
      _isConnected = false;
      if (!mounted) return;
      if (_isLoading) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
      Future.delayed(const Duration(seconds: 5), connectWebSocket);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeWs();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return MarketIndexBar(
      nifty: nifty,
      niftyChange: niftyChange,
      bankNifty: bankNifty,
      bankNiftyChange: bankNiftyChange,
      otherIndices: otherIndices,
      isLoading: _isLoading,
      hasError: _hasError,
      onRetry: retryConnection,
    );
  }
}
