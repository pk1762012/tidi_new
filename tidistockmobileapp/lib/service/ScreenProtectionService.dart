import 'package:flutter/services.dart';

class ScreenProtectionService {
  ScreenProtectionService._();
  static final ScreenProtectionService instance = ScreenProtectionService._();

  static const _channel =
      MethodChannel('com.tidi.tidistockmobileapp/screen_protection');

  int _refCount = 0;

  Future<void> enableProtection() async {
    _refCount++;
    if (_refCount == 1) {
      await _channel.invokeMethod('enableProtection');
    }
  }

  Future<void> disableProtection() async {
    if (_refCount > 0) _refCount--;
    if (_refCount == 0) {
      await _channel.invokeMethod('disableProtection');
    }
  }
}
