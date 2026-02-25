import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateCheckResult {
  final bool updateAvailable;
  final String? storeUrl;

  const UpdateCheckResult({required this.updateAvailable, this.storeUrl});

  static const noUpdate = UpdateCheckResult(updateAvailable: false);
}

class UpdateCheckService {
  static const String _bundleId = 'com.tidi.tidistockmobileapp';

  /// Returns whether an update is available and the store URL to open.
  /// Never throws — returns [UpdateCheckResult.noUpdate] on any error.
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      if (Platform.isAndroid) {
        return await _checkAndroid();
      } else if (Platform.isIOS) {
        return await _checkIOS();
      }
    } catch (e) {
      debugPrint('[UpdateCheck] Error: $e');
    }
    return UpdateCheckResult.noUpdate;
  }

  static Future<UpdateCheckResult> _checkAndroid() async {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability == UpdateAvailability.updateAvailable) {
      return UpdateCheckResult(
        updateAvailable: true,
        storeUrl: 'https://play.google.com/store/apps/details?id=$_bundleId',
      );
    }
    return UpdateCheckResult.noUpdate;
  }

  static Future<UpdateCheckResult> _checkIOS() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final response = await http
        .get(Uri.parse('https://itunes.apple.com/lookup?bundleId=$_bundleId'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return UpdateCheckResult.noUpdate;

    final data = jsonDecode(response.body);
    final results = data['results'] as List?;
    if (results == null || results.isEmpty) return UpdateCheckResult.noUpdate;

    final storeVersion = results[0]['version'] as String?;
    final storeUrl = results[0]['trackViewUrl'] as String?;

    if (storeVersion == null || storeUrl == null) {
      return UpdateCheckResult.noUpdate;
    }

    if (_isNewerVersion(storeVersion, currentVersion)) {
      return UpdateCheckResult(updateAvailable: true, storeUrl: storeUrl);
    }

    return UpdateCheckResult.noUpdate;
  }

  /// Returns true if [store] is a newer version than [current].
  static bool _isNewerVersion(String store, String current) {
    final storeParts = store.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();

    for (int i = 0; i < storeParts.length; i++) {
      final s = storeParts[i] ?? 0;
      final c = (i < currentParts.length) ? (currentParts[i] ?? 0) : 0;
      if (s > c) return true;
      if (s < c) return false;
    }
    return false;
  }
}
