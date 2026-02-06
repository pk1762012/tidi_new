import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CustomScaffold extends StatelessWidget {
  CustomScaffold({
    super.key,
    this.child,
    required this.allowBackNavigation,
    required this.displayActions,
    required this.imageUrl,
    required this.menu,
    this.onProfileTap,
  });

  final Widget? child;
  final bool allowBackNavigation;
  final bool displayActions;
  final String? imageUrl;
  final String? menu;

  final VoidCallback? onProfileTap;
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // keep transparent
        statusBarIconBrightness: Brightness.dark, // ANDROID: dark icons
        statusBarBrightness: Brightness.light, // IOS: dark icons
      ),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: lightColorScheme.secondary.withValues(alpha: .05), // FIXED COLOR
          elevation: 0,

          // 👇 THIS IS THE IMPORTANT PART
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: Brightness.light, // iOS → DARK text/icons
            statusBarIconBrightness: Brightness.dark, // Android
          ),
          // Show back button if allowed
          automaticallyImplyLeading: allowBackNavigation,

          // Profile on left if back button is not shown
          leading: !allowBackNavigation && displayActions
              ? Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Tooltip(
              message: "Profile",
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (onProfileTap != null) onProfileTap!();
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: lightColorScheme.primary,
                      width: 1,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: lightColorScheme.secondary,
                    backgroundImage:
                    imageUrl != null ? CachedNetworkImageProvider(imageUrl!) : null,
                    child: imageUrl == null
                        ? Icon(
                      FeatherIcons.user,
                      size: 22,
                      color: lightColorScheme.surface,
                    )
                        : null,
                  ),
                ),
              ),
            ),
          )
              : null,

          // Right-side menu text if available
          actions: menu != null
              ? [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  menu!,
                  style: TextStyle(
                    color: lightColorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ]
              : null,
        ),


        extendBodyBehindAppBar: false, // <--- important to fix background color
        body: Container(
          color: lightColorScheme.secondary.withValues(alpha: .05),
          child: SafeArea(
            bottom: true,
            child: child!,
          ),
        ),

      ),
    );
  }
}
