import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Generates a JWT `aq-encrypted-key` header value matching the
/// `encryptApiKey()` function from prod-alphaquark's cryptoUtils.js.
///
/// The JWT contains:
///   - apiKey: the AQ API key
///   - exp: expiration time (60 seconds from now, IST)
///   - iat: issued-at time (IST)
///
/// Signed with HMAC-SHA256 using the AQ secret.
class AqCryptoService {
  AqCryptoService._();
  static final AqCryptoService instance = AqCryptoService._();

  static const int _tokenExpirySeconds = 60;

  /// Generate the `aq-encrypted-key` JWT token.
  String encryptApiKey(String apiKey, String secretKey) {
    final now = _nowIST();
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    final exp = iat + _tokenExpirySeconds;
    final utcNow = DateTime.now().toUtc();
    debugPrint('[AqCrypto] JWT iat=$iat exp=$exp utcNow=${utcNow.toIso8601String()} istNow=${now.toIso8601String()} diff=${iat - (utcNow.millisecondsSinceEpoch ~/ 1000)}s');

    final header = {'alg': 'HS256', 'typ': 'JWT'};
    final payload = {
      'apiKey': apiKey,
      'exp': exp,
      'iat': iat,
    };

    final headerB64 = _base64UrlEncode(jsonEncode(header));
    final payloadB64 = _base64UrlEncode(jsonEncode(payload));
    final signingInput = '$headerB64.$payloadB64';

    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final signature = hmac.convert(utf8.encode(signingInput));
    final signatureB64 = _base64UrlEncodeBytes(signature.bytes);

    return '$signingInput.$signatureB64';
  }

  /// Current time offset to IST (UTC+5:30), matching the JS implementation.
  DateTime _nowIST() {
    final now = DateTime.now().toUtc();
    return now.add(const Duration(hours: 5, minutes: 30));
  }

  String _base64UrlEncode(String input) {
    return _base64UrlEncodeBytes(utf8.encode(input));
  }

  String _base64UrlEncodeBytes(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
