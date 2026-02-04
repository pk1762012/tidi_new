import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/io.dart';
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

  IOWebSocketChannel? channel; // make nullable
  StreamSubscription? _channelSubscription;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    connectWebSocket();
  }

  void _closeWs() {
    _isConnected = false;
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
      _closeWs(); // app minimized
    }

    if (state == AppLifecycleState.resumed) {
      connectWebSocket(); // app back
    }
  }


  Future<void> connectWebSocket() async {
    if (_isConnected) return;

    try {
      _isConnected = true;

      // Close previous connection if exists
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
      );


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
              });
            }
          } catch (e) {
            print("JSON decode error: $e");
          }
        },
        onDone: () {
          _isConnected = false;
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
        onError: (error) {
          _isConnected = false;
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("Connection error: $e");
      _isConnected = false;
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
    );
  }
}
