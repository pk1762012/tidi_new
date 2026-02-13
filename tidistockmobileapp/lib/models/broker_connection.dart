class BrokerConnection {
  final String? id;
  final String broker;
  final String? clientCode;
  final String? apiKey;
  final String? secretKey;
  final String? jwtToken;
  final String? viewToken;
  final String? sid;
  final String? serverId;
  final String status; // connected, expired, error, disconnected
  final DateTime? tokenExpire;
  final DateTime? connectedAt;
  final DateTime? lastUsed;
  final String? lastError;
  final bool ddpiEnabled;
  final bool tpinEnabled;
  final bool isAuthorizedForSell;

  BrokerConnection({
    this.id,
    required this.broker,
    this.clientCode,
    this.apiKey,
    this.secretKey,
    this.jwtToken,
    this.viewToken,
    this.sid,
    this.serverId,
    this.status = 'disconnected',
    this.tokenExpire,
    this.connectedAt,
    this.lastUsed,
    this.lastError,
    this.ddpiEnabled = false,
    this.tpinEnabled = false,
    this.isAuthorizedForSell = false,
  });

  factory BrokerConnection.fromJson(Map<String, dynamic> json) {
    return BrokerConnection(
      id: json['_id'],
      broker: json['broker'] ?? '',
      clientCode: json['clientCode'],
      apiKey: json['apiKey'],
      secretKey: json['secretKey'],
      jwtToken: json['jwtToken'],
      viewToken: json['viewToken'],
      sid: json['sid'],
      serverId: json['serverId'],
      status: json['status'] ?? 'disconnected',
      tokenExpire: json['token_expire'] != null
          ? DateTime.tryParse(json['token_expire'].toString())
          : null,
      connectedAt: json['connected_at'] != null
          ? DateTime.tryParse(json['connected_at'].toString())
          : null,
      lastUsed: json['last_used'] != null
          ? DateTime.tryParse(json['last_used'].toString())
          : null,
      lastError: json['last_error'],
      ddpiEnabled: json['ddpi_enabled'] ?? false,
      tpinEnabled: json['tpin_enabled'] ?? false,
      isAuthorizedForSell: json['is_authorized_for_sell'] ?? false,
    );
  }

  bool get isConnected => status == 'connected';
  bool get isExpired => status == 'expired';
}
