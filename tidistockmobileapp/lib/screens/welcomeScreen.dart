import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'dart:async';
import 'dart:convert';

import '../components/login/PolicyScreen.dart';
import '../components/login/disclaimer.dart';
import '../components/login/splash.dart';

class WelcomeScreen extends StatefulWidget {
  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final TextEditingController phoneCtrl = TextEditingController();

  bool isLoading = false;
  bool _isSocialLoading = false;
  bool _isNewUser = false;
  String? phoneError;

  // Social login state — kept across dialogs
  String? _socialProvider;
  String? _socialIdToken;
  String? _socialFirstName;
  String? _socialLastName;

  // -------------------------------------------------------
  // COMMON: store token & navigate after successful auth
  // -------------------------------------------------------
  Future<void> _handleAuthSuccess(String token, String phone, {bool isNewUser = false}) async {
    await secureStorage.deleteAll();
    await secureStorage.write(key: 'access_token', value: token);
    await secureStorage.write(key: 'phone_number', value: phone);
    ApiService.invalidateTokenCache();
    ApiService().updateDeviceDetails();

    if (isNewUser) {
      _showWelcomeTrialDialog();
    } else {
      _navigateToDisclaimer();
    }
  }

  // -------------------------------------------------------
  // PHONE LOGIN: VALIDATE & HANDLE OTP-OPTIONAL
  // -------------------------------------------------------
  Future<void> onContinue() async {
    final phone = phoneCtrl.text.trim();

    setState(() => phoneError = null);

    if (phone.length != 10) {
      setState(() => phoneError = "Enter a valid 10-digit phone number");
      return;
    }

    setState(() => isLoading = true);

    try {
      ApiService apiService = ApiService();
      debugPrint('[Login] Validating phone: $phone, apiUrl: ${apiService.apiUrl}');
      final response = await apiService.validateUser(phone);
      debugPrint('[Login] validateUser status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        // Existing user — attempt login
        final loginResponse = await apiService.loginUser(phone);
        debugPrint('[Login] loginUser status: ${loginResponse.statusCode}, body: ${loginResponse.body}');

        if (loginResponse.statusCode == 202) {
          // OTP disabled — token returned directly
          var data = jsonDecode(loginResponse.body);
          await _handleAuthSuccess(data['data']['token'], phone);
        } else if (loginResponse.statusCode == 200) {
          // OTP enabled — show OTP popup
          showOtpPopup(phone);
        } else {
          setState(() => phoneError = "Failed to send OTP. Please try again.");
        }
      } else if (response.statusCode == 404) {
        // New user — show registration popup
        showNamePopup();
      } else {
        debugPrint('[Login] Unexpected validate status: ${response.statusCode}');
        setState(() => phoneError = "Server error. Please try again later.");
      }
    } catch (e, stack) {
      debugPrint('[Login] Exception: $e\n$stack');
      setState(() => phoneError = "Network error. Please check your connection.");
    }

    setState(() => isLoading = false);
  }

  // -------------------------------------------------------
  // NAME POPUP FOR NEW USER
  // -------------------------------------------------------
  void showNamePopup() {
    final fnameCtrl = TextEditingController();
    final lnameCtrl = TextEditingController();

    String? fnameError;
    String? lnameError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setStatePopup) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("New User",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

                    SizedBox(height: 10),

                    Text("Please fill your name to continue.",
                        style: TextStyle(color: Colors.grey[600])),

                    SizedBox(height: 20),

                    TextField(
                      controller: fnameCtrl,
                      decoration: InputDecoration(
                        labelText: "First Name",
                        errorText: fnameError,
                        border: OutlineInputBorder(),
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(20),
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      ],
                    ),

                    SizedBox(height: 12),

                    TextField(
                      controller: lnameCtrl,
                      decoration: InputDecoration(
                        labelText: "Last Name",
                        errorText: lnameError,
                        border: OutlineInputBorder(),
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(20),
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      ],
                    ),

                    SizedBox(height: 22),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final f = fnameCtrl.text.trim();
                          final l = lnameCtrl.text.trim();

                          setStatePopup(() {
                            if (f.isEmpty) {
                              fnameError = "Enter first name";
                            } else if (f.length > 20) {
                              fnameError = "Max 20 characters allowed";
                            } else {
                              fnameError = null;
                            }

                            if (l.isNotEmpty && l.length > 20) {
                              lnameError = "Max 20 characters allowed";
                            } else {
                              lnameError = null;
                            }
                          });

                          if (fnameError != null || lnameError != null) return;

                          ApiService apiService = ApiService();
                          final response = await apiService.createUser(fnameCtrl.text.trim(), lnameCtrl.text.trim(), phoneCtrl.text.trim());

                          if (response.statusCode == 202) {
                            // OTP disabled — token returned directly
                            var data = jsonDecode(response.body);
                            if (data['data'] != null && data['data']['token'] != null) {
                              Navigator.pop(dialogCtx);
                              _isNewUser = true;
                              await _handleAuthSuccess(data['data']['token'], phoneCtrl.text.trim(), isNewUser: true);
                              return;
                            }
                          }

                          if (response.statusCode == 201 || response.statusCode == 202 || response.statusCode == 200) {
                            _isNewUser = true;
                            Navigator.pop(dialogCtx);
                            showOtpPopup(phoneCtrl.text.trim());
                          } else {
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Failed to register. Please try again.")),
                            );
                          }
                        },
                        child: Text("Continue"),
                      ),
                    ),

                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text("Cancel"),
                    )
                  ],
                ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------
  // OTP POPUP WITH 4 BOX INPUT & 30 SEC RESEND TIMER
  // -------------------------------------------------------
  void showOtpPopup(String phone) {
    ApiService apiService = ApiService();

    final List<TextEditingController> otpControllers =
    List.generate(4, (_) => TextEditingController());

    String? otpError;
    bool verifying = false;

    int secondsLeft = 30;
    bool canResend = false;

    Timer? timer;
    bool timerStarted = false;

    void startTimer(StateSetter setStatePopup) {
      timer?.cancel();
      secondsLeft = 30;
      canResend = false;

      timer = Timer.periodic(Duration(seconds: 1), (t) {
        if (secondsLeft == 0) {
          t.cancel();
          setStatePopup(() => canResend = true);
        } else {
          setStatePopup(() => secondsLeft--);
        }
      });
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setStatePopup) {
            if (!timerStarted) {
              timerStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                startTimer(setStatePopup);
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Verify OTP",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

                    SizedBox(height: 10),
                    Text("OTP sent to +91 $phone",
                        style: TextStyle(color: Colors.grey[600])),

                    SizedBox(height: 25),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(4, (i) {
                        return _otpBox(
                          index: i,
                          controller: otpControllers[i],
                          onChanged: (value) {
                            if (value.length == 1 && i < 3) {
                              FocusScope.of(dialogCtx).nextFocus();
                            }
                            if (value.isEmpty && i > 0) {
                              FocusScope.of(dialogCtx).previousFocus();
                            }
                          },
                        );
                      }),
                    ),

                    if (otpError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(otpError!,
                            style: TextStyle(color: Colors.red, fontSize: 13)),
                      ),

                    SizedBox(height: 25),

                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.center,
                        ),
                        onPressed: verifying
                            ? null
                            : () async {
                          final otp = otpControllers.map((c) => c.text).join();

                          setStatePopup(() => otpError = null);

                          if (otp.length != 4) {
                            setStatePopup(() => otpError = "Enter valid 4-digit OTP");
                            return;
                          }

                          setStatePopup(() => verifying = true);

                          try {
                            final response = await apiService.verifyOtp(phone, otp);

                            if (response.statusCode == 202) {
                              var responseData = jsonDecode(response.body);
                              String accessToken = responseData['data']['token'];

                              setStatePopup(() => verifying = false);
                              timer?.cancel();
                              Navigator.pop(dialogCtx);

                              await _handleAuthSuccess(accessToken, phone, isNewUser: _isNewUser);
                            } else {
                              var responseData = jsonDecode(response.body);
                              String message = responseData['message'];
                              setStatePopup(() {
                                verifying = false;
                                otpError = message;
                              });
                            }
                          } catch (e) {
                            setStatePopup(() {
                              verifying = false;
                              otpError = "Network error. Please try again.";
                            });
                          }
                        },
                        child: Center(
                          child: verifying
                              ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                              : Text("Verify OTP"),
                        ),
                      ),
                    ),

                    SizedBox(height: 15),

                    canResend
                        ? TextButton(
                      onPressed: () async {
                        await apiService.loginUser(phone);
                        startTimer(setStatePopup);
                      },
                      child: Text("Resend OTP"),
                    )
                        : Text("Resend in ${secondsLeft}s",
                        style: TextStyle(color: Colors.grey)),

                    TextButton(
                      onPressed: () {
                        timer?.cancel();
                        Navigator.pop(dialogCtx);
                      },
                      child: Text("Cancel"),
                    ),
                  ],
                ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------
  // GOOGLE SIGN-IN
  // -------------------------------------------------------
  Future<void> _signInWithGoogle() async {
    setState(() => _isSocialLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: '29712834204-1v7v64ip2sf4mq8usrnsa13smqesdhoe.apps.googleusercontent.com',
      );

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        // User cancelled
        setState(() => _isSocialLoading = false);
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null) {
        debugPrint('[SocialLogin] Google idToken is null');
        _showErrorSnackBar("Google sign-in failed. Please try again.");
        setState(() => _isSocialLoading = false);
        return;
      }

      debugPrint('[SocialLogin] Google idToken obtained, calling lookup...');
      await _processSocialLogin('GOOGLE', idToken,
        firstName: account.displayName?.split(' ').first,
        lastName: account.displayName?.split(' ').skip(1).join(' '),
      );
    } catch (e, stack) {
      debugPrint('[SocialLogin] Google error: $e\n$stack');
      _showErrorSnackBar("Google sign-in failed. Please try again.");
    }

    if (mounted) setState(() => _isSocialLoading = false);
  }

  // -------------------------------------------------------
  // APPLE SIGN-IN
  // -------------------------------------------------------
  Future<void> _signInWithApple() async {
    setState(() => _isSocialLoading = true);

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final String? idToken = credential.identityToken;
      if (idToken == null) {
        debugPrint('[SocialLogin] Apple identityToken is null');
        _showErrorSnackBar("Apple sign-in failed. Please try again.");
        setState(() => _isSocialLoading = false);
        return;
      }

      debugPrint('[SocialLogin] Apple idToken obtained, calling lookup...');
      await _processSocialLogin('APPLE', idToken,
        firstName: credential.givenName,
        lastName: credential.familyName,
      );
    } catch (e, stack) {
      debugPrint('[SocialLogin] Apple error: $e\n$stack');
      if (e.toString().contains('canceled') || e.toString().contains('cancelled')) {
        // User cancelled — do nothing
      } else {
        _showErrorSnackBar("Apple sign-in failed. Please try again.");
      }
    }

    if (mounted) setState(() => _isSocialLoading = false);
  }

  // -------------------------------------------------------
  // PROCESS SOCIAL LOGIN (common for Google & Apple)
  // -------------------------------------------------------
  Future<void> _processSocialLogin(String provider, String idToken, {String? firstName, String? lastName}) async {
    try {
      ApiService apiService = ApiService();
      final response = await apiService.socialLookup(provider, idToken);
      debugPrint('[SocialLogin] lookup status: ${response.statusCode}, body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 202 && data['data']?['linked'] == true) {
        // Already linked — log in directly
        final token = data['data']['token'];
        final phone = data['data']['phone_number'];
        await _handleAuthSuccess(token, phone);
      } else if (response.statusCode == 200 && data['data']?['linked'] == false) {
        // Not linked — need phone number
        _socialProvider = provider;
        _socialIdToken = idToken;
        _socialFirstName = firstName ?? data['data']?['social_info']?['first_name'];
        _socialLastName = lastName ?? data['data']?['social_info']?['last_name'];

        _showPhoneCollectionDialog();
      } else {
        _showErrorSnackBar(data['message'] ?? "Social login failed.");
      }
    } catch (e, stack) {
      debugPrint('[SocialLogin] processSocialLogin error: $e\n$stack');
      _showErrorSnackBar("Network error. Please try again.");
    }
  }

  // -------------------------------------------------------
  // PHONE COLLECTION DIALOG (after social sign-in)
  // -------------------------------------------------------
  void _showPhoneCollectionDialog() {
    final phoneCollectCtrl = TextEditingController();
    String? phoneCollectError;
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setStatePopup) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Link Phone Number",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

                      SizedBox(height: 10),

                      Text("Enter your phone number to complete sign-in.",
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center),

                      SizedBox(height: 20),

                      TextField(
                        controller: phoneCollectCtrl,
                        maxLength: 10,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          counterText: "",
                          labelText: "Phone Number",
                          prefixText: "+91 ",
                          errorText: phoneCollectError,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),

                      SizedBox(height: 22),

                      SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.center,
                          ),
                          onPressed: submitting
                              ? null
                              : () async {
                            final phone = phoneCollectCtrl.text.trim();

                            if (phone.length != 10) {
                              setStatePopup(() => phoneCollectError = "Enter a valid 10-digit phone number");
                              return;
                            }

                            setStatePopup(() {
                              phoneCollectError = null;
                              submitting = true;
                            });

                            try {
                              ApiService apiService = ApiService();
                              final response = await apiService.socialComplete(
                                provider: _socialProvider!,
                                idToken: _socialIdToken!,
                                phoneNumber: phone,
                                firstName: _socialFirstName,
                                lastName: _socialLastName,
                              );

                              debugPrint('[SocialLogin] complete status: ${response.statusCode}, body: ${response.body}');
                              final data = jsonDecode(response.body);

                              if (response.statusCode == 202) {
                                // Success — token received
                                final token = data['data']['token'];
                                final isNew = data['data']['is_new_user'] == true;
                                Navigator.pop(dialogCtx);
                                await _handleAuthSuccess(token, phone, isNewUser: isNew);
                              } else if (response.statusCode == 200 && data['data']?['otp_required'] == true) {
                                // OTP required — show OTP popup
                                Navigator.pop(dialogCtx);
                                _showSocialOtpPopup(phone);
                              } else {
                                setStatePopup(() {
                                  submitting = false;
                                  phoneCollectError = data['message'] ?? "Failed. Please try again.";
                                });
                              }
                            } catch (e) {
                              setStatePopup(() {
                                submitting = false;
                                phoneCollectError = "Network error. Please try again.";
                              });
                            }
                          },
                          child: Center(
                            child: submitting
                                ? SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : Text("Continue"),
                          ),
                        ),
                      ),

                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: Text("Cancel"),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------
  // OTP POPUP FOR SOCIAL LOGIN (when OTP is required)
  // -------------------------------------------------------
  void _showSocialOtpPopup(String phone) {
    final List<TextEditingController> otpControllers =
    List.generate(4, (_) => TextEditingController());

    String? otpError;
    bool verifying = false;
    int secondsLeft = 30;
    bool canResend = false;
    Timer? timer;
    bool timerStarted = false;

    void startTimer(StateSetter setStatePopup) {
      timer?.cancel();
      secondsLeft = 30;
      canResend = false;
      timer = Timer.periodic(Duration(seconds: 1), (t) {
        if (secondsLeft == 0) {
          t.cancel();
          setStatePopup(() => canResend = true);
        } else {
          setStatePopup(() => secondsLeft--);
        }
      });
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setStatePopup) {
            if (!timerStarted) {
              timerStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                startTimer(setStatePopup);
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Verify OTP",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text("OTP sent to +91 $phone",
                          style: TextStyle(color: Colors.grey[600])),
                      SizedBox(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, (i) {
                          return _otpBox(
                            index: i,
                            controller: otpControllers[i],
                            onChanged: (value) {
                              if (value.length == 1 && i < 3) {
                                FocusScope.of(dialogCtx).nextFocus();
                              }
                              if (value.isEmpty && i > 0) {
                                FocusScope.of(dialogCtx).previousFocus();
                              }
                            },
                          );
                        }),
                      ),
                      if (otpError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(otpError!, style: TextStyle(color: Colors.red, fontSize: 13)),
                        ),
                      SizedBox(height: 25),
                      SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.center),
                          onPressed: verifying
                              ? null
                              : () async {
                            final otp = otpControllers.map((c) => c.text).join();
                            setStatePopup(() => otpError = null);
                            if (otp.length != 4) {
                              setStatePopup(() => otpError = "Enter valid 4-digit OTP");
                              return;
                            }
                            setStatePopup(() => verifying = true);

                            try {
                              ApiService apiService = ApiService();
                              final response = await apiService.socialComplete(
                                provider: _socialProvider!,
                                idToken: _socialIdToken!,
                                phoneNumber: phone,
                                otp: otp,
                                firstName: _socialFirstName,
                                lastName: _socialLastName,
                              );

                              final data = jsonDecode(response.body);
                              if (response.statusCode == 202) {
                                final token = data['data']['token'];
                                final isNew = data['data']['is_new_user'] == true;
                                timer?.cancel();
                                Navigator.pop(dialogCtx);
                                await _handleAuthSuccess(token, phone, isNewUser: isNew);
                              } else {
                                setStatePopup(() {
                                  verifying = false;
                                  otpError = data['message'] ?? "Verification failed.";
                                });
                              }
                            } catch (e) {
                              setStatePopup(() {
                                verifying = false;
                                otpError = "Network error. Please try again.";
                              });
                            }
                          },
                          child: Center(
                            child: verifying
                                ? SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : Text("Verify OTP"),
                          ),
                        ),
                      ),
                      SizedBox(height: 15),
                      canResend
                          ? TextButton(
                        onPressed: () async {
                          // Re-trigger social complete without OTP to re-send
                          ApiService apiService = ApiService();
                          await apiService.socialComplete(
                            provider: _socialProvider!,
                            idToken: _socialIdToken!,
                            phoneNumber: phone,
                            firstName: _socialFirstName,
                            lastName: _socialLastName,
                          );
                          startTimer(setStatePopup);
                        },
                        child: Text("Resend OTP"),
                      )
                          : Text("Resend in ${secondsLeft}s",
                          style: TextStyle(color: Colors.grey)),
                      TextButton(
                        onPressed: () {
                          timer?.cancel();
                          Navigator.pop(dialogCtx);
                        },
                        child: Text("Cancel"),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------
  // NAVIGATE TO DISCLAIMER -> SPLASH -> HOME
  // -------------------------------------------------------
  void _navigateToDisclaimer() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => DisclaimerScreen(
          onAccept: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => SplashScreen(),
              ),
              (route) => false,
            );
          },
          onDecline: () async {
            await secureStorage.deleteAll();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => WelcomeScreen()),
              (route) => false,
            );
          },
        ),
      ),
      (route) => false,
    );
  }

  // -------------------------------------------------------
  // WELCOME TRIAL DIALOG FOR NEW USERS
  // -------------------------------------------------------
  void _showWelcomeTrialDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.celebration_rounded, size: 48, color: Colors.amber[700]),
                const SizedBox(height: 16),
                const Text(
                  "Welcome to TIDI Wealth!",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "You've got 15 days of free access to all stock analysis reports.",
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _navigateToDisclaimer();
                    },
                    child: const Text("Start Exploring", style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Widget _otpBox({
    required int index,
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return SizedBox(
      width: 55,
      height: 55,
      child: TextField(
        controller: controller,
        maxLength: 1,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          counterText: "",
          border: OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }


  // -------------------------------------------------------
  // MAIN UI
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.asset(
                      'assets/images/tidi_welcome.png',
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                SizedBox(height: 10),

                Text("Enter your phone number to continue.",
                    style: TextStyle(
                        fontSize: 16,
                        color: colors.onSurface.withValues(alpha: 0.7))),

                SizedBox(height: 10),

                TextField(
                  controller: phoneCtrl,
                  maxLength: 10,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: "",
                    labelText: "Phone Number",
                    prefixText: "+91 ",
                    filled: true,
                    fillColor: colors.surface,
                    errorText: phoneError,
                    border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),

                SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    onPressed: (isLoading || _isSocialLoading) ? null : onContinue,
                    child: isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text("Continue",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),

                const SizedBox(height: 20),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text("or", style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),

                const SizedBox(height: 20),

                // Google Sign-In button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    onPressed: (isLoading || _isSocialLoading) ? null : _signInWithGoogle,
                    icon: _isSocialLoading && _socialProvider == 'GOOGLE'
                        ? SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : Text("G", style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: Colors.blue[700])),
                    label: Text("Sign in with Google",
                        style: TextStyle(fontSize: 16, color: colors.onSurface)),
                  ),
                ),

                // Apple Sign-In button (iOS only)
                if (Platform.isIOS) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: Colors.grey[300]!),
                        backgroundColor: Colors.black,
                      ),
                      onPressed: (isLoading || _isSocialLoading) ? null : _signInWithApple,
                      icon: _isSocialLoading && _socialProvider == 'APPLE'
                          ? SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.apple, size: 24, color: Colors.white),
                      label: Text("Sign in with Apple",
                          style: TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      _policyLink(
                        context,
                        title: "Terms & Conditions",
                        content: termsMarkdown,
                      ),
                      const Text("|"),
                      _policyLink(
                        context,
                        title: "Privacy Policy",
                        content: privacyMarkdown,
                      ),
                      const Text("|"),
                      _policyLink(
                        context,
                        title: "Refund Policy",
                        content: refundMarkdown,
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _policyLink(
      BuildContext context, {
        required String title,
        required String content,
      }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PolicyScreen(
              title: title,
              markdownData: content,
            ),
          ),
        );
      },
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.black45,
          decoration: TextDecoration.underline,
          fontSize: 13,
        ),
      ),
    );
  }

  static const String termsMarkdown = '''
## Terms & Conditions

• This app provides market-related information only
• No execution of trades is done through the app
• Users must comply with SEBI regulations
• Misuse of information is strictly prohibited
''';

  static const String privacyMarkdown = '''
## Privacy Policy

• We collect minimal user data
• No personal data is sold to third parties
• Data is encrypted and securely stored
• PAN & KYC data is never stored in plain text
''';

  static const String refundMarkdown = '''
## Refund Policy

• Membership fees once paid are non-refundable
• Refunds may be issued only in case of duplicate payment
• PMS-related refunds are governed by separate PMS agreements
''';


}
