import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

class BrokerSessionService {
  BrokerSessionService._();
  static final BrokerSessionService instance = BrokerSessionService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  String _sessionKey(String broker) =>
      'broker_session_${broker.toLowerCase().replaceAll(' ', '')}';

  /// Store today's IST date as the session timestamp for this broker.
  Future<void> saveSessionTime(String broker) async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    await _storage.write(key: _sessionKey(broker), value: dateStr);
  }

  /// Check if the broker session was established today (IST).
  Future<bool> isSessionFresh(String broker) async {
    final saved = await _storage.read(key: _sessionKey(broker));
    if (saved == null) return false;
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    return saved == todayStr;
  }

  /// Clear session for a specific broker.
  Future<void> clearSession(String broker) async {
    await _storage.delete(key: _sessionKey(broker));
  }
}
