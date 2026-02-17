import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/DataRepository.dart';
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

  // Throttle: buffer WS updates & flush to UI at ~3fps
  Timer? _uiUpdateTimer;
  bool _hasPendingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startUiUpdateTimer();
    _fetchInitialData();
    connectWebSocket();
  }

  void _startUiUpdateTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_hasPendingUpdate && mounted) {
        _hasPendingUpdate = false;
        setState(() {});
      }
    });
  }

  void _closeWs() {
    _isConnected = false;
    _isConnecting = false;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
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
      _startUiUpdateTimer();
      // Skip HTTP fetch on resume if we already have valid data (4.3)
      if (nifty == 0.0) {
        _fetchInitialData();
      }
      connectWebSocket();
    }
  }

  Future<void> _fetchInitialData() async {
    try {
      final apiService = ApiService();

      double tempNifty = nifty;
      double tempNiftyChange = niftyChange;
      double tempBankNifty = bankNifty;
      double tempBankNiftyChange = bankNiftyChange;

      bool gotData = false;

      // Try primary index/quote endpoint first
      try {
        final results = await Future.wait([
          apiService.getMarketQuote('NIFTY 50'),
          apiService.getMarketQuote('NIFTY BANK'),
        ]).timeout(const Duration(seconds: 8));

        final niftyResponse = results[0];
        final bankNiftyResponse = results[1];

        if (niftyResponse.statusCode == 200) {
          final body = await DataRepository.parseJsonMap(niftyResponse.body);
          final data = body['data'] ?? body;
          final cmp = (data['cmp'] ?? data['last'] ?? data['ltp'] ?? 0).toDouble();
          final prevClose = (data['prev_close'] ?? data['previousClose'] ?? cmp).toDouble();
          if (cmp > 0) {
            tempNifty = double.parse(cmp.toStringAsFixed(2));
            tempNiftyChange = double.parse((cmp - prevClose).toStringAsFixed(2));
            gotData = true;
          }
        }

        if (bankNiftyResponse.statusCode == 200) {
          final body = await DataRepository.parseJsonMap(bankNiftyResponse.body);
          final data = body['data'] ?? body;
          final cmp = (data['cmp'] ?? data['last'] ?? data['ltp'] ?? 0).toDouble();
          final prevClose = (data['prev_close'] ?? data['previousClose'] ?? cmp).toDouble();
          if (cmp > 0) {
            tempBankNifty = double.parse(cmp.toStringAsFixed(2));
            tempBankNiftyChange = double.parse((cmp - prevClose).toStringAsFixed(2));
            gotData = true;
          }
        }
      } catch (e) {
        print("Primary index/quote failed: $e");
      }

      // Fallback: use pre_market_summary + option-chain PCR in parallel
      if (!gotData) {
        final fallbackResults = await Future.wait([
          apiService.getPreMarketSummary().catchError((_) => http.Response('{}', 0)),
          apiService.getOptionPulsePCR('NIFTY').catchError((_) => http.Response('{}', 0)),
          apiService.getOptionPulsePCR('BANKNIFTY').catchError((_) => http.Response('{}', 0)),
        ]).timeout(const Duration(seconds: 10), onTimeout: () => [
          http.Response('{}', 0),
          http.Response('{}', 0),
          http.Response('{}', 0),
        ]);

        // Pre-market summary for Nifty
        try {
          final summaryResponse = fallbackResults[0];
          if (summaryResponse.statusCode == 200) {
            final body = await DataRepository.parseJsonMap(summaryResponse.body);
            final data = body['data'];
            if (data != null) {
              final niftySpot = data['nifty_spot'] ?? data['gift_nifty']?['data'];
              if (niftySpot != null) {
                final last = (niftySpot['last'] ?? 0).toDouble();
                if (last > 0) {
                  final pctStr = (niftySpot['pct_change'] ?? '+0%').toString().replaceAll('%', '');
                  final pct = double.tryParse(pctStr) ?? 0;
                  final prevClose = pct != 0 ? last / (1 + pct / 100) : last;
                  tempNifty = double.parse(last.toStringAsFixed(2));
                  tempNiftyChange = double.parse((last - prevClose).toStringAsFixed(2));
                  gotData = true;
                }
              }
            }
          }
        } catch (e) {
          print("Pre-market summary fallback failed: $e");
        }

        // Nifty PCR for more accurate underlying value
        try {
          final niftyPcrResponse = fallbackResults[1];
          if (niftyPcrResponse.statusCode == 200) {
            final body = await DataRepository.parseJsonMap(niftyPcrResponse.body);
            final pcrData = body['data'];
            if (pcrData != null) {
              final uv = (pcrData['underlyingValue'] ?? 0).toDouble();
              if (uv > 0) {
                tempNifty = double.parse(uv.toStringAsFixed(2));
                gotData = true;
              }
            }
          }
        } catch (e) {
          print("Nifty PCR fallback failed: $e");
        }

        // BankNifty PCR
        try {
          final bankNiftyPcrResponse = fallbackResults[2];
          if (bankNiftyPcrResponse.statusCode == 200) {
            final body = await DataRepository.parseJsonMap(bankNiftyPcrResponse.body);
            final pcrData = body['data'];
            if (pcrData != null) {
              final uv = (pcrData['underlyingValue'] ?? 0).toDouble();
              if (uv > 0) {
                tempBankNifty = double.parse(uv.toStringAsFixed(2));
                gotData = true;
              }
            }
          }
        } catch (e) {
          print("BankNifty PCR fallback failed: $e");
        }
      }

      if (!mounted) return;
      setState(() {
        nifty = tempNifty;
        niftyChange = tempNiftyChange;
        bankNifty = tempBankNifty;
        bankNiftyChange = tempBankNiftyChange;
        _isLoading = false;
        _hasError = !gotData && tempNifty == 0.0 && tempBankNifty == 0.0;
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
              // Update fields without setState; the periodic timer will flush to UI
              nifty = tempNifty;
              niftyChange = tempNiftyChange;
              bankNifty = tempBankNifty;
              bankNiftyChange = tempBankNiftyChange;
              otherIndices = tempOther;
              _isLoading = false;
              _hasError = false;
              _hasPendingUpdate = true;
            }
          } catch (e) {
            print("JSON decode error: $e");
          }
        },
        onDone: () {
          _isConnected = false;
          _isConnecting = false;
          if (!mounted) return;
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) connectWebSocket();
          });
        },
        onError: (error) {
          _isConnected = false;
          _isConnecting = false;
          if (!mounted) return;
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) connectWebSocket();
          });
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
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) connectWebSocket();
      });
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
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) connectWebSocket();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiUpdateTimer?.cancel();
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
