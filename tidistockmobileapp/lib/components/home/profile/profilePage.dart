import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tidistockmobileapp/screens/welcomeScreen.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:tidistockmobileapp/service/CacheService.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../../../main.dart';
import '../../../theme/theme.dart';
import '../../../widgets/customScaffold.dart';
import '../../login/splash.dart';
import 'SubscriptionPlanScreen.dart';
import 'SubscriptionTransactionsScreen.dart';


class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final ImagePicker picker = ImagePicker();

  String? imageUrl;
  String? firstName;
  String? phoneNumber;
  String? lastName;
  bool? isSubscribed;
  String? subscriptionEndDate;
  bool isLoading = true;

  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    updateUserDetails();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> updateUserDetails() async {
    setState(() => isLoading = true);

    try {
      // Check if test user (skip backend call)
      final accessToken = await secureStorage.read(key: 'access_token');
      final enableTestLogin = dotenv.env['ENABLE_TEST_LOGIN'] == 'true';
      final isTestUser = accessToken == 'test_review_token_9999999999';

      if (enableTestLogin && isTestUser) {
        // Use stored test user data (skip backend call)
        imageUrl = null;
        firstName = await secureStorage.read(key: 'first_name') ?? 'Test';
        phoneNumber = await secureStorage.read(key: 'phone_number') ?? '9999999999';
        lastName = await secureStorage.read(key: 'last_name') ?? 'User';
        isSubscribed = true;
        subscriptionEndDate = '';

        setState(() {
          isLoading = false;
        });
        _controller.forward();
        return;
      }

      await ApiService().getCachedUserDetails(
        onData: (data, {required fromCache}) async {
          if (!mounted) return;

          if (data == null) {
            showErrorSnackBar("No user data found");
            setState(() => isLoading = false);
            return;
          }

          imageUrl = data['profilePicture'];
          firstName = data['firstName'] ?? '';
          phoneNumber = data['username'] ?? '';
          lastName = data['lastName'] ?? '';
          isSubscribed = data['isSubscribed'] ?? false;
          subscriptionEndDate = data['subscriptionEndDate']?.toString() ?? '';

          await secureStorage.write(key: 'user_id', value: data['id']?.toString());
          await secureStorage.write(key: 'profile_picture', value: imageUrl ?? '');
          await secureStorage.write(key: 'phone_number', value: data['username']);
          await secureStorage.write(key: 'first_name', value: firstName ?? '');
          await secureStorage.write(key: 'last_name', value: lastName ?? '');
          await secureStorage.write(key: 'is_subscribed', value: data['isSubscribed'].toString());
          await secureStorage.write(key: 'is_paid', value: data['isPaid'].toString());
          await secureStorage.write(key: 'subscription_end_date', value: data['subscriptionEndDate']?.toString());
          await secureStorage.write(key: 'pan', value: data['pan']?.toString());
          await secureStorage.write(key: 'is_stock_analysis_trial_active', value: data['isStockAnalysisTrialActive'].toString());

          final List configs = data['config'] ?? [];

          for (final item in configs) {
            await secureStorage.write(
              key: item['name'],
              value: item['value'].toString(),
            );
          }

          if (mounted) {
            setState(() => isLoading = false);
            _controller.forward();
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      showErrorSnackBar("Something went wrong");
      setState(() => isLoading = false);
    }
  }

  Future<void> saveProfileChanges(String newFirstName, String newLastName) async {
    try {
      ApiService apiService = ApiService();
      final response = await apiService.updateUserDetails(newFirstName, newLastName);

      if (response.statusCode == 200) {
        CacheService.instance.invalidate('api/user');

        // Reset animation & state to reload profile page UI
        setState(() {
          isLoading = true;
          // Reset animation controller to start
          _controller.reset();
        });

        // Fetch latest user details and then start animation
        await updateUserDetails();
      } else {
        showErrorSnackBar("Failed to update profile");
      }
    } catch (e) {
      showErrorSnackBar("Something went wrong");
    }
  }

  void showEditProfileSheet() {
    final firstNameController = TextEditingController(text: firstName ?? '');
    final lastNameController = TextEditingController(text: lastName ?? '');

    final _formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.95),
                      Colors.white.withOpacity(0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  //backdropFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    top: 12,
                  ),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Drag handle
                        Center(
                          child: Container(
                            height: 5,
                            width: 60,
                            margin: const EdgeInsets.only(top: 8, bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),

                        // Title
                        const Text(
                          "Edit Name",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            letterSpacing: 0.4,
                          ),
                        ),

                        const SizedBox(height: 26),

                        // FIRST NAME FIELD (Redesigned)
                        _modernTextField(
                          controller: firstNameController,
                          label: "First Name",
                          icon: Icons.person_outline_rounded,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter first name';
                            }
                            if (value.length > 20) {
                              return 'Max 20 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // LAST NAME FIELD
                        _modernTextField(
                          controller: lastNameController,
                          label: "Last Name",
                          icon: Icons.person_rounded,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter last name';
                            }
                            if (value.length > 20) {
                              return 'Max 20 characters';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 30),

                        // Save Button
                        SizedBox(
                          height: 55,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                saveProfileChanges(
                                  firstNameController.text.trim(),
                                  lastNameController.text.trim(),
                                );
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                            ),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [
                                    lightColorScheme.primary.withOpacity(0.95),
                                    lightColorScheme.secondary.withOpacity(0.85),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  "Save Changes",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Modern styled textfield
  Widget _modernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            validator: validator,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.grey.shade700),
              border: InputBorder.none,
              hintText: label,
              hintStyle: const TextStyle(color: Colors.black38),
              contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Do you really want to logout?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context, false)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: lightColorScheme.error,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
    if (confirmed == true) logout();
  }

  Future<void> logout() async {
    ApiService.invalidateTokenCache();
    await CacheService.instance.clearAll();
    await secureStorage.deleteAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => WelcomeScreen()),
          (Route<dynamic> route) => false,
    );
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile == null) return;

      final response = await ApiService().uploadProfilePicture(pickedFile);
      if (response.statusCode == 200) {
        CacheService.instance.invalidate('api/user');
        updateUserDetails();
        showErrorSnackBar("Profile picture updated.");
        Navigator.of(navigatorKey.currentContext!, rootNavigator: true)
            .pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SplashScreen(),
            transitionDuration: Duration.zero, // No animation
            reverseTransitionDuration: Duration.zero,
          ),
              (route) => false,
        );
      } else {
        showErrorSnackBar("Upload failed.");
      }
    } catch (e) {
      showErrorSnackBar("Image selection failed.");
    }
  }

  void showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context);
                  pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
            position: _slideAnimation,
            child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [

          // 📄 Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [

                  // ⭐ Floating Profile Card (Magic Glow)
                  AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutQuint,
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.12),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTapDown: (_) => HapticFeedback.selectionClick(),
                              onTap: showImageSourceSheet,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [

                                  // Avatar Wrapper
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          scheme.primary.withOpacity(0.1),
                                          scheme.secondary.withOpacity(0.1),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withOpacity(0.25),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                      child: CircleAvatar(
                                        radius: 48,
                                        backgroundColor: Colors.grey.shade200,
                                        backgroundImage:
                                        imageUrl != null ? CachedNetworkImageProvider(imageUrl!) : null,
                                        child: imageUrl == null
                                            ? Icon(Icons.person, size: 65, color: scheme.primary)
                                            : null,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  // Tap to upload label
                                  Text(
                                    imageUrl != null ? "Tap to update"  :"Tap to upload",
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),
                            buildName(firstName, lastName),
                            Text(
                              "${phoneNumber ?? ''}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w400,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildMagicAction(Icons.edit, "Edit", showEditProfileSheet),
                                _buildMagicAction(Icons.info_outline, "About", showAboutUsDialog),
                                _buildMagicAction(Icons.contacts, "Contact Us", showContactUsDialog),
                                _buildMagicAction(Icons.share_rounded, "Share", shareApp),
                              ],
                            ),
                            const SizedBox(height: 18),
                            buildSubscriptionStatus(scheme),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () {
                                showSubscriptionBottomCurtain(context);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                                decoration: BoxDecoration(
                                  gradient:  LinearGradient(
                                    colors: [lightColorScheme.primary, lightColorScheme.secondary], // New blue gradient
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: lightColorScheme.primary.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_card, color: Colors.blue, size: 20), // New icon
                                    const SizedBox(width: 8),
                                    Text(
                                      isSubscribed == true
                                          ? 'Renew TIDI Wealth Membership'
                                          : 'Join TIDI Wealth Membership',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CustomScaffold(
                                      allowBackNavigation: true,
                                      displayActions: false,
                                      imageUrl: null,
                                      menu: "Membership History",
                                      child: const SubscriptionTransactionsScreen(),
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                                decoration: BoxDecoration(
                                  gradient:  LinearGradient(
                                    colors: [lightColorScheme.primary, lightColorScheme.secondary], // New blue gradient
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.teal.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.receipt_long, color: Colors.blue, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      "View Transactions",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                  const SizedBox(height: 10),
                  InkWell(
                    onTap: confirmLogout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFFF5252)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.logout, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "Logout",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  InkWell(
                    onTap: confirmDeleteAccount,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.redAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.delete_forever, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            "Delete",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    )
        ));
  }

  int? getDaysLeft() {
    if (subscriptionEndDate == null) return null;

    try {
      final end = DateTime.parse(subscriptionEndDate!);
      final now = DateTime.now();
      return end.difference(now).inDays;
    } catch (_) {
      return null;
    }
  }

  Widget buildSubscriptionStatus(ColorScheme scheme) {
    if (isSubscribed != true) return SizedBox();

    final daysLeft = getDaysLeft();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface,
        border: Border.all(color: scheme.primary.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
            Icon(Icons.verified, color: Colors.greenAccent.shade700, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TIDI Wealth Membership Active",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              if (daysLeft != null)
                Text(
                  "$daysLeft days left",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          )
        ],
      ),
    );
  }


  Widget buildName(String? first, String? last) {
    final fullName = "${first ?? ''} ${last ?? ''}".trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: fullName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w400,
              color: Colors.black87,
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        // If text fits in one line → show full name in one line
        if (!textPainter.didExceedMaxLines) {
          return Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          );
        }

        // If it overflows → show first + last in two centered lines
        return Column(
          children: [
            Text(
              first ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            Text(
              last ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ],
        );
      },
    );
  }


// Mini Action Button Widget
  Widget _buildMagicAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, size: 26, color: Colors.blueAccent),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

// Share Function Wrapper
  void shareApp() {
    Share.share(
      'Check out TIDI Wealth — a smart stock-market companion app:\n'
          'Android: https://play.google.com/store/apps/details?id=com.tidi.tidistockmobileapp\n'
          'iOS: https://apps.apple.com/us/app/tidi-wealth/id6755061061',
    );
  }



  Future<void> showContactUsDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Contact Us"),
        backgroundColor: Colors.white,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const Text(
                "If you have any questions, feedback, or issues, feel free to reach out to us:\n",
                style: TextStyle(height: 1.5),
              ),

              // EMAIL
              GestureDetector(
                onTap: () async {
                  final Uri emailUri = Uri(
                    scheme: 'mailto',
                    path: 'support@tidiwealth.in',
                  );
                  await launchUrl(emailUri);
                },
                child: Row(
                  children: const [
                    Icon(Icons.email, color: Colors.blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "support@tidiwealth.in",
                        style: TextStyle(color: Colors.blue),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // WEBSITE
              GestureDetector(
                onTap: () async {
                  final Uri webUri = Uri.parse('https://www.tidiwealth.in');
                  await launchUrl(webUri, mode: LaunchMode.externalApplication);
                },
                child: Row(
                  children: const [
                    Icon(Icons.public, color: Colors.blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "www.tidiwealth.in",
                        style: TextStyle(color: Colors.blue),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // INSTAGRAM
              GestureDetector(
                onTap: () async {
                  final Uri instaUri = Uri.parse('https://www.instagram.com/tidi.academy');
                  await launchUrl(instaUri, mode: LaunchMode.externalApplication);
                },
                child: Row(
                  children: const [
                    Icon(Icons.camera_alt, color: Colors.pink),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "@tidi.academy",
                        style: TextStyle(color: Colors.pink),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // WHATSAPP
              GestureDetector(
                onTap: () async {
                  final Uri waUri = Uri.parse("https://wa.me/919900072521");
                  await launchUrl(waUri, mode: LaunchMode.externalApplication);
                },
                child: Row(
                  children: const [
                    Icon(Icons.message, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Chat on WhatsApp",
                        style: TextStyle(color: Colors.green),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // YOUTUBE
              GestureDetector(
                onTap: () async {
                  final Uri ytUri = Uri.parse("https://www.youtube.com/@tidiacademy");
                  await launchUrl(ytUri, mode: LaunchMode.externalApplication);
                },
                child: Row(
                  children: const [
                    Icon(Icons.play_circle_fill, color: Colors.red),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "YouTube Channel",
                        style: TextStyle(color: Colors.red),
                      ),
                    )
                  ],
                ),
              ),

            ],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }




  Future<void> showAboutUsDialog() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appName = packageInfo.appName;
    final version = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "About $appName",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // -------- Research Analyst Header ----------
              Row(
                children: const [
                  Icon(Icons.person_pin_rounded, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    "Research Analyst Details",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  )
                ],
              ),
              const SizedBox(height: 10),

              const Text(
                "Name: MANOJ KUMAR A\n"
                    "Type: Individual\n\n"
                    "Registered Office:\n"
                    "GROUND FLOOR NO 776 LIG N NO 966/7762, 2ND STAGE B SECTOR,\n"
                    "YELAHANKA NEW TOWN, BENGALURU, KARNATAKA - 560064\n\n"
                    "Registration No: INH000020068\n"
                    "BSE Enlistment No: 6544\n"
                    "Registration Date: 12/03/2025\n"
                    "Registration Validity: 12/03/2030\n\n"
                    "Principal / Grievance / Compliance Officer:\n"
                    "DHANANJAYA K R (Phone: 9900072509)\n",
                style: TextStyle(height: 1.4),
              ),

              const SizedBox(height: 20),

              // -------- SEBI Header ----------
              Row(
                children: const [
                  Icon(Icons.verified_rounded, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    "SEBI Details",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  )
                ],
              ),
              const SizedBox(height: 10),

              const Text(
                "SEBI Office:\n"
                    "SEBI Bhavan BKC, Bandra-Kurla Complex,\n"
                    "Mumbai - 400051, Maharashtra, India\n",
                style: TextStyle(height: 1.4),
              ),

              // -------- Clickable SEBI Links ----------
              GestureDetector(
                onTap: () async {
                  await launchUrl(
                      Uri.parse("https://scores.sebi.gov.in/"),
                      mode: LaunchMode.externalApplication
                  );
                },
                child: Row(
                  children: const [
                    Icon(Icons.open_in_new, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "SEBI SCORES Portal",
                        style: TextStyle(color: Colors.blue),
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 8),

              GestureDetector(
                onTap: () async {
                  await launchUrl(
                      Uri.parse("https://smartodr.in/"),
                      mode: LaunchMode.externalApplication
                  );
                },
                child: Row(
                  children: const [
                    Icon(Icons.open_in_new, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Smart ODR Platform",
                        style: TextStyle(color: Colors.blue),
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // -------- App Version ----------
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    "App Version: $version+$buildNumber",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Future<void> confirmDeleteAccount() async {
    final TextEditingController _controller = TextEditingController();
    bool isDeleteEnabled = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text("Delete Account"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black, height: 1.5),
                      children: [
                        const TextSpan(
                            text:
                            "Warning: Deleting your account will permanently remove "),
                        TextSpan(
                            text: "all your data",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(
                            text:
                            ", including profile information, wallet balance, coins, addresses, and contest history. "),
                        const TextSpan(text: "This action "),
                        TextSpan(
                            text: "cannot be undone",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(
                            text:
                            ". If you change your mind, the only way to recover your account is by contacting our support team at "),
                        TextSpan(
                            text: "support@tidiwealth.in",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                        const TextSpan(text: "."),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Type "DELETE" below to confirm:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Type DELETE',
                    ),
                    onChanged: (value) {
                      setState(() {
                        isDeleteEnabled = value.trim() == "DELETE";
                      });
                    },
                  ),
                ],
              ),
            ),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            actions: [
              TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.pop(context, false)),
              ElevatedButton(
                onPressed: isDeleteEnabled
                    ? () => Navigator.pop(context, true)
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: const Text("Delete Account"),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) logout();
  }


}

class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const radius = 40.0;
    final path = Path();
    path.moveTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);
    path.lineTo(size.width, size.height - 60);
    path.quadraticBezierTo(
        size.width / 2, size.height, 0, size.height - 60);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
