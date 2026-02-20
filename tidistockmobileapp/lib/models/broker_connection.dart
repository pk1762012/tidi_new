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
  final bool isPrimary;

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
    this.isPrimary = false,
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
      isPrimary: json['is_primary'] ?? json['isPrimary'] ?? false,
    );
  }

  bool get isConnected => status == 'connected';
  bool get isExpired => status == 'expired';

  /// True if the token_expire date has passed (or status is explicitly 'expired').
  bool get isTokenExpired {
    if (status == 'expired') return true;
    if (tokenExpire != null && DateTime.now().toUtc().isAfter(tokenExpire!)) {
      return true;
    }
    return false;
  }

  /// True if the broker is connected AND the token hasn't expired.
  /// Use this instead of [isConnected] when you need to verify the session is usable.
  bool get isEffectivelyConnected => isConnected && !isTokenExpired;

  /// Parse the connected brokers API response, setting isPrimary based on
  /// the top-level `primary_broker` field.
  static List<BrokerConnection> parseApiResponse(Map<String, dynamic> data) {
    final rawData = data['data'];
    String? primaryBroker;
    List<dynamic> brokerList;

    if (rawData is Map) {
      primaryBroker = rawData['primary_broker'] as String?;
      brokerList = rawData['connected_brokers'] ?? [];
    } else if (rawData is List) {
      brokerList = rawData;
      primaryBroker = data['primary_broker'] as String?;
    } else {
      primaryBroker = data['primary_broker'] as String?;
      brokerList = data['connected_brokers'] ?? [];
    }

    return brokerList.map((e) {
      final conn = BrokerConnection.fromJson(e);
      if (primaryBroker != null &&
          conn.broker.toLowerCase() == primaryBroker.toLowerCase()) {
        return BrokerConnection(
          id: conn.id,
          broker: conn.broker,
          clientCode: conn.clientCode,
          apiKey: conn.apiKey,
          secretKey: conn.secretKey,
          jwtToken: conn.jwtToken,
          viewToken: conn.viewToken,
          sid: conn.sid,
          serverId: conn.serverId,
          status: conn.status,
          tokenExpire: conn.tokenExpire,
          connectedAt: conn.connectedAt,
          lastUsed: conn.lastUsed,
          lastError: conn.lastError,
          ddpiEnabled: conn.ddpiEnabled,
          tpinEnabled: conn.tpinEnabled,
          isAuthorizedForSell: conn.isAuthorizedForSell,
          isPrimary: true,
        );
      }
      return conn;
    }).toList();
  }
}
