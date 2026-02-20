import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:tidistockmobileapp/config/app_config.dart';

class UpdatePromptSheet {
  /// Checks Play Store for an available update and shows a bottom sheet if one exists.
  /// Call this once after HomeScreen has built (via addPostFrameCallback).
  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      if (!context.mounted) return;
      _show(context);
    } catch (_) {
      // Silently ignore — not on Play Store (debug/test builds) or no network
    }
  }

  static void _show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isDismissible: !AppConfig.forceUpdate,
      enableDrag: !AppConfig.forceUpdate,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UpdateSheet(),
    );
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              size: 40,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'New Update Available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),

          // Description
          Text(
            'A newer version of TIDI Stock is available on the Play Store with improvements and new features.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          // Update Now button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                InAppUpdate.performImmediateUpdate();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Update Now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // Maybe Later button (hidden when forceUpdate is true)
          if (!AppConfig.forceUpdate) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Maybe Later',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
