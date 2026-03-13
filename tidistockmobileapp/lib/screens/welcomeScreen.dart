import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  bool isLoading = false;
  bool _isSocialLoading = false;
  bool _isNewUser = false;
  String? phoneError;

  // Firebase state — kept across dialogs for phone linking
  String? _firebaseIdToken;
  String? _firebaseFirstName;
  String? _firebaseLastName;

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
  // Get Firebase ID token from current user
  // -------------------------------------------------------
  Future<String?> _getFirebaseIdToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
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
      debugPrint('[Login] Validating phone: $phone');
      final response = await apiService.validateUser(phone);

      if (response.statusCode == 200) {
        final loginResponse = await apiService.loginUser(phone);

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
        showNamePopup();
      } else {
        setState(() => phoneError = "Server error. Please try again later.");
      }
    } catch (e, stack) {
      debugPrint('[Login] Exception: $e\n$stack');
      setState(() => phoneError = "Network error. Please check your connection.");
    }

    setState(() => isLoading = false);
  }

  // -------------------------------------------------------
  // NAME POPUP FOR NEW USER (phone login)
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
                    Text("New User", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text("Please fill your name to continue.", style: TextStyle(color: Colors.grey[600])),
                    SizedBox(height: 20),
                    TextField(
                      controller: fnameCtrl,
                      decoration: InputDecoration(labelText: "First Name", errorText: fnameError, border: OutlineInputBorder()),
                      inputFormatters: [LengthLimitingTextInputFormatter(20), FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]'))],
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: lnameCtrl,
                      decoration: InputDecoration(labelText: "Last Name", errorText: lnameError, border: OutlineInputBorder()),
                      inputFormatters: [LengthLimitingTextInputFormatter(20), FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]'))],
                    ),
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final f = fnameCtrl.text.trim();
                          final l = lnameCtrl.text.trim();
                          setStatePopup(() {
                            fnameError = f.isEmpty ? "Enter first name" : (f.length > 20 ? "Max 20 characters" : null);
                            lnameError = (l.isNotEmpty && l.length > 20) ? "Max 20 characters" : null;
                          });
                          if (fnameError != null || lnameError != null) return;

                          ApiService apiService = ApiService();
                          final response = await apiService.createUser(f, l, phoneCtrl.text.trim());

                          if (response.statusCode == 202) {
                            var data = jsonDecode(response.body);
                            if (data['data']?['token'] != null) {
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
                            _showErrorSnackBar("Failed to register. Please try again.");
                          }
                        },
                        child: Text("Continue"),
                      ),
                    ),
                    TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text("Cancel")),
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
  // OTP POPUP (for phone login when OTP is enabled)
  // -------------------------------------------------------
  void showOtpPopup(String phone) {
    ApiService apiService = ApiService();
    final List<TextEditingController> otpControllers = List.generate(4, (_) => TextEditingController());
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
        if (secondsLeft == 0) { t.cancel(); setStatePopup(() => canResend = true); }
        else { setStatePopup(() => secondsLeft--); }
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
              WidgetsBinding.instance.addPostFrameCallback((_) => startTimer(setStatePopup));
            }
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Verify OTP", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text("OTP sent to +91 $phone", style: TextStyle(color: Colors.grey[600])),
                    SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(4, (i) => _otpBox(
                        index: i, controller: otpControllers[i],
                        onChanged: (value) {
                          if (value.length == 1 && i < 3) FocusScope.of(dialogCtx).nextFocus();
                          if (value.isEmpty && i > 0) FocusScope.of(dialogCtx).previousFocus();
                        },
                      )),
                    ),
                    if (otpError != null) Padding(padding: EdgeInsets.only(top: 8), child: Text(otpError!, style: TextStyle(color: Colors.red, fontSize: 13))),
                    SizedBox(height: 25),
                    SizedBox(
                      height: 50, width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.center),
                        onPressed: verifying ? null : () async {
                          final otp = otpControllers.map((c) => c.text).join();
                          setStatePopup(() => otpError = null);
                          if (otp.length != 4) { setStatePopup(() => otpError = "Enter valid 4-digit OTP"); return; }
                          setStatePopup(() => verifying = true);
                          try {
                            final response = await apiService.verifyOtp(phone, otp);
                            if (response.statusCode == 202) {
                              var responseData = jsonDecode(response.body);
                              timer?.cancel();
                              Navigator.pop(dialogCtx);
                              await _handleAuthSuccess(responseData['data']['token'], phone, isNewUser: _isNewUser);
                            } else {
                              var responseData = jsonDecode(response.body);
                              setStatePopup(() { verifying = false; otpError = responseData['message']; });
                            }
                          } catch (e) {
                            setStatePopup(() { verifying = false; otpError = "Network error. Please try again."; });
                          }
                        },
                        child: Center(child: verifying
                            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Text("Verify OTP")),
                      ),
                    ),
                    SizedBox(height: 15),
                    canResend
                        ? TextButton(onPressed: () async { await apiService.loginUser(phone); startTimer(setStatePopup); }, child: Text("Resend OTP"))
                        : Text("Resend in ${secondsLeft}s", style: TextStyle(color: Colors.grey)),
                    TextButton(onPressed: () { timer?.cancel(); Navigator.pop(dialogCtx); }, child: Text("Cancel")),
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
  // GOOGLE SIGN-IN via Firebase
  // -------------------------------------------------------
  Future<void> _signInWithGoogle() async {
    setState(() => _isSocialLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? gAccount = await googleSignIn.signIn();
      if (gAccount == null) { setState(() => _isSocialLoading = false); return; }

      final GoogleSignInAuthentication gAuth = await gAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      debugPrint('[SocialLogin] Firebase Google sign-in: ${userCredential.user?.uid}');

      final firebaseToken = await userCredential.user?.getIdToken();
      if (firebaseToken == null) { _showErrorSnackBar("Google sign-in failed."); setState(() => _isSocialLoading = false); return; }

      await _processFirebaseLogin(firebaseToken,
        firstName: gAccount.displayName?.split(' ').first,
        lastName: gAccount.displayName?.split(' ').skip(1).join(' '),
      );
    } catch (e, stack) {
      debugPrint('[SocialLogin] Google error: $e\n$stack');
      _showErrorSnackBar("Google sign-in failed. Please try again.");
    }
    if (mounted) setState(() => _isSocialLoading = false);
  }

  // -------------------------------------------------------
  // APPLE SIGN-IN via Firebase
  // -------------------------------------------------------
  Future<void> _signInWithApple() async {
    setState(() => _isSocialLoading = true);
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );

      final oauthProvider = OAuthProvider('apple.com');
      final credential = oauthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      debugPrint('[SocialLogin] Firebase Apple sign-in: ${userCredential.user?.uid}');

      final firebaseToken = await userCredential.user?.getIdToken();
      if (firebaseToken == null) { _showErrorSnackBar("Apple sign-in failed."); setState(() => _isSocialLoading = false); return; }

      await _processFirebaseLogin(firebaseToken,
        firstName: appleCredential.givenName,
        lastName: appleCredential.familyName,
      );
    } catch (e, stack) {
      debugPrint('[SocialLogin] Apple error: $e\n$stack');
      if (!e.toString().contains('canceled') && !e.toString().contains('cancelled')) {
        _showErrorSnackBar("Apple sign-in failed. Please try again.");
      }
    }
    if (mounted) setState(() => _isSocialLoading = false);
  }

  // -------------------------------------------------------
  // EMAIL/PASSWORD SIGN-IN via Firebase
  // -------------------------------------------------------
  void _showEmailLoginDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? emailError;
    String? passError;
    bool isRegisterMode = false;
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: true,
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
                      Text(isRegisterMode ? "Create Account" : "Sign In",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text(isRegisterMode ? "Register with email and password." : "Sign in with your email and password.",
                          style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                      SizedBox(height: 20),

                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email",
                          errorText: emailError,
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "Password",
                          errorText: passError,
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),

                      SizedBox(height: 22),

                      SizedBox(
                        height: 50, width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.center),
                          onPressed: submitting ? null : () async {
                            final email = emailCtrl.text.trim();
                            final pass = passCtrl.text;

                            setStatePopup(() { emailError = null; passError = null; });

                            if (email.isEmpty || !email.contains('@')) {
                              setStatePopup(() => emailError = "Enter a valid email");
                              return;
                            }
                            if (pass.length < 6) {
                              setStatePopup(() => passError = "Password must be at least 6 characters");
                              return;
                            }

                            setStatePopup(() => submitting = true);

                            try {
                              UserCredential userCredential;
                              if (isRegisterMode) {
                                userCredential = await _firebaseAuth.createUserWithEmailAndPassword(email: email, password: pass);
                              } else {
                                userCredential = await _firebaseAuth.signInWithEmailAndPassword(email: email, password: pass);
                              }

                              final firebaseToken = await userCredential.user?.getIdToken();
                              if (firebaseToken == null) {
                                setStatePopup(() { submitting = false; emailError = "Authentication failed."; });
                                return;
                              }

                              Navigator.pop(dialogCtx);
                              await _processFirebaseLogin(firebaseToken);
                            } on FirebaseAuthException catch (e) {
                              setStatePopup(() => submitting = false);
                              if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
                                setStatePopup(() => emailError = "No account found. Register instead.");
                              } else if (e.code == 'wrong-password') {
                                setStatePopup(() => passError = "Wrong password.");
                              } else if (e.code == 'email-already-in-use') {
                                setStatePopup(() => emailError = "Email already registered. Sign in instead.");
                              } else if (e.code == 'weak-password') {
                                setStatePopup(() => passError = "Password too weak.");
                              } else {
                                setStatePopup(() => emailError = e.message ?? "Auth failed.");
                              }
                            } catch (e) {
                              setStatePopup(() { submitting = false; emailError = "Network error. Please try again."; });
                            }
                          },
                          child: Center(child: submitting
                              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text(isRegisterMode ? "Register" : "Sign In")),
                        ),
                      ),

                      SizedBox(height: 8),

                      if (!isRegisterMode)
                        TextButton(
                          onPressed: () async {
                            final email = emailCtrl.text.trim();
                            if (email.isEmpty || !email.contains('@')) {
                              setStatePopup(() => emailError = "Enter email to reset password");
                              return;
                            }
                            try {
                              await _firebaseAuth.sendPasswordResetEmail(email: email);
                              setStatePopup(() { emailError = null; passError = null; });
                              if (mounted) _showErrorSnackBar("Password reset email sent to $email");
                            } on FirebaseAuthException catch (e) {
                              setStatePopup(() => emailError = e.message ?? "Failed to send reset email.");
                            }
                          },
                          child: Text("Forgot Password?", style: TextStyle(fontSize: 13)),
                        ),

                      TextButton(
                        onPressed: () {
                          setStatePopup(() {
                            isRegisterMode = !isRegisterMode;
                            emailError = null;
                            passError = null;
                          });
                        },
                        child: Text(isRegisterMode ? "Already have an account? Sign In" : "Don't have an account? Register",
                            style: TextStyle(fontSize: 13)),
                      ),

                      TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text("Cancel")),
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
  // PROCESS FIREBASE LOGIN (common for Google, Apple, Email)
  // -------------------------------------------------------
  Future<void> _processFirebaseLogin(String firebaseToken, {String? firstName, String? lastName}) async {
    setState(() => _isSocialLoading = true);
    try {
      ApiService apiService = ApiService();
      final response = await apiService.firebaseLookup(firebaseToken);
      debugPrint('[FirebaseLogin] lookup status: ${response.statusCode}, body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 202 && data['data']?['linked'] == true) {
        // Already linked — log in directly
        await _handleAuthSuccess(data['data']['token'], data['data']['phone_number']);
      } else if (response.statusCode == 200 && data['data']?['linked'] == false) {
        // Not linked — need phone number
        _firebaseIdToken = firebaseToken;
        _firebaseFirstName = firstName ?? data['data']?['social_info']?['first_name'];
        _firebaseLastName = lastName ?? data['data']?['social_info']?['last_name'];
        _showPhoneCollectionDialog();
      } else {
        _showErrorSnackBar(data['message'] ?? "Login failed.");
      }
    } catch (e, stack) {
      debugPrint('[FirebaseLogin] error: $e\n$stack');
      _showErrorSnackBar("Network error. Please try again.");
    }
    if (mounted) setState(() => _isSocialLoading = false);
  }

  // -------------------------------------------------------
  // PHONE COLLECTION DIALOG (after Firebase sign-in)
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
                      Text("Link Phone Number", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text("Enter your phone number to complete sign-in.",
                          style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                      SizedBox(height: 20),
                      TextField(
                        controller: phoneCollectCtrl,
                        maxLength: 10,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          counterText: "", labelText: "Phone Number", prefixText: "+91 ",
                          errorText: phoneCollectError,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      SizedBox(height: 22),
                      SizedBox(
                        height: 50, width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.center),
                          onPressed: submitting ? null : () async {
                            final phone = phoneCollectCtrl.text.trim();
                            if (phone.length != 10) {
                              setStatePopup(() => phoneCollectError = "Enter a valid 10-digit phone number");
                              return;
                            }
                            setStatePopup(() { phoneCollectError = null; submitting = true; });

                            try {
                              ApiService apiService = ApiService();
                              final response = await apiService.firebaseComplete(
                                firebaseIdToken: _firebaseIdToken!,
                                phoneNumber: phone,
                                firstName: _firebaseFirstName,
                                lastName: _firebaseLastName,
                              );

                              final data = jsonDecode(response.body);

                              if (response.statusCode == 202) {
                                Navigator.pop(dialogCtx);
                                await _handleAuthSuccess(data['data']['token'], phone, isNewUser: data['data']['is_new_user'] == true);
                              } else if (response.statusCode == 200 && data['data']?['otp_required'] == true) {
                                Navigator.pop(dialogCtx);
                                _showFirebaseOtpPopup(phone);
                              } else {
                                setStatePopup(() { submitting = false; phoneCollectError = data['message'] ?? "Failed. Try again."; });
                              }
                            } catch (e) {
                              setStatePopup(() { submitting = false; phoneCollectError = "Network error. Try again."; });
                            }
                          },
                          child: Center(child: submitting
                              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text("Continue")),
                        ),
                      ),
                      TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text("Cancel")),
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
  // OTP POPUP FOR FIREBASE LOGIN (when OTP is required)
  // -------------------------------------------------------
  void _showFirebaseOtpPopup(String phone) {
    final List<TextEditingController> otpControllers = List.generate(4, (_) => TextEditingController());
    String? otpError;
    bool verifying = false;
    int secondsLeft = 30;
    bool canResend = false;
    Timer? timer;
    bool timerStarted = false;

    void startTimer(StateSetter setStatePopup) {
      timer?.cancel(); secondsLeft = 30; canResend = false;
      timer = Timer.periodic(Duration(seconds: 1), (t) {
        if (secondsLeft == 0) { t.cancel(); setStatePopup(() => canResend = true); }
        else { setStatePopup(() => secondsLeft--); }
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
              WidgetsBinding.instance.addPostFrameCallback((_) => startTimer(setStatePopup));
            }
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Verify OTP", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text("OTP sent to +91 $phone", style: TextStyle(color: Colors.grey[600])),
                      SizedBox(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, (i) => _otpBox(
                          index: i, controller: otpControllers[i],
                          onChanged: (value) {
                            if (value.length == 1 && i < 3) FocusScope.of(dialogCtx).nextFocus();
                            if (value.isEmpty && i > 0) FocusScope.of(dialogCtx).previousFocus();
                          },
                        )),
                      ),
                      if (otpError != null) Padding(padding: EdgeInsets.only(top: 8), child: Text(otpError!, style: TextStyle(color: Colors.red, fontSize: 13))),
                      SizedBox(height: 25),
                      SizedBox(
                        height: 50, width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.center),
                          onPressed: verifying ? null : () async {
                            final otp = otpControllers.map((c) => c.text).join();
                            setStatePopup(() => otpError = null);
                            if (otp.length != 4) { setStatePopup(() => otpError = "Enter valid 4-digit OTP"); return; }
                            setStatePopup(() => verifying = true);
                            try {
                              ApiService apiService = ApiService();
                              final response = await apiService.firebaseComplete(
                                firebaseIdToken: _firebaseIdToken!, phoneNumber: phone, otp: otp,
                                firstName: _firebaseFirstName, lastName: _firebaseLastName,
                              );
                              final data = jsonDecode(response.body);
                              if (response.statusCode == 202) {
                                timer?.cancel(); Navigator.pop(dialogCtx);
                                await _handleAuthSuccess(data['data']['token'], phone, isNewUser: data['data']['is_new_user'] == true);
                              } else {
                                setStatePopup(() { verifying = false; otpError = data['message'] ?? "Verification failed."; });
                              }
                            } catch (e) {
                              setStatePopup(() { verifying = false; otpError = "Network error. Try again."; });
                            }
                          },
                          child: Center(child: verifying
                              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text("Verify OTP")),
                        ),
                      ),
                      SizedBox(height: 15),
                      canResend
                          ? TextButton(
                              onPressed: () async {
                                ApiService apiService = ApiService();
                                await apiService.firebaseComplete(
                                  firebaseIdToken: _firebaseIdToken!, phoneNumber: phone,
                                  firstName: _firebaseFirstName, lastName: _firebaseLastName,
                                );
                                startTimer(setStatePopup);
                              }, child: Text("Resend OTP"))
                          : Text("Resend in ${secondsLeft}s", style: TextStyle(color: Colors.grey)),
                      TextButton(onPressed: () { timer?.cancel(); Navigator.pop(dialogCtx); }, child: Text("Cancel")),
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
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(
      builder: (context) => DisclaimerScreen(
        onAccept: () { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => SplashScreen()), (route) => false); },
        onDecline: () async { await secureStorage.deleteAll(); Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => WelcomeScreen()), (route) => false); },
      ),
    ), (route) => false);
  }

  void _showWelcomeTrialDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (dialogContext) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.celebration_rounded, size: 48, color: Colors.amber[700]),
          const SizedBox(height: 16),
          const Text("Welcome to TIDI Wealth!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text("You've got 15 days of free access to all stock analysis reports.", style: TextStyle(fontSize: 15, color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () { Navigator.pop(dialogContext); _navigateToDisclaimer(); },
            child: const Text("Start Exploring", style: TextStyle(fontSize: 16)),
          )),
        ])),
      );
    });
  }

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------
  void _showErrorSnackBar(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _otpBox({required int index, required TextEditingController controller, required Function(String) onChanged}) {
    return SizedBox(width: 55, height: 55, child: TextField(
      controller: controller, maxLength: 1, textAlign: TextAlign.center, keyboardType: TextInputType.number,
      decoration: InputDecoration(counterText: "", border: OutlineInputBorder()), onChanged: onChanged,
    ));
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
                  child: AspectRatio(aspectRatio: 1, child: Image.asset('assets/images/tidi_welcome.png', width: double.infinity, fit: BoxFit.cover)),
                ),

                SizedBox(height: 10),
                Text("Enter your phone number to continue.",
                    style: TextStyle(fontSize: 16, color: colors.onSurface.withValues(alpha: 0.7))),
                SizedBox(height: 10),

                TextField(
                  controller: phoneCtrl, maxLength: 10, keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: "", labelText: "Phone Number", prefixText: "+91 ",
                    filled: true, fillColor: colors.surface, errorText: phoneError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),

                SizedBox(height: 20),

                // Continue with phone
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: (isLoading || _isSocialLoading) ? null : onContinue,
                    child: isLoading ? CircularProgressIndicator(color: Colors.white) : Text("Continue", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),

                const SizedBox(height: 20),

                // Divider
                Row(children: [
                  Expanded(child: Divider(color: Colors.grey[300])),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("or", style: TextStyle(color: Colors.grey[500], fontSize: 14))),
                  Expanded(child: Divider(color: Colors.grey[300])),
                ]),

                const SizedBox(height: 20),

                // Google Sign-In
                _socialButton(
                  label: "Sign in with Google",
                  icon: Text("G", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                  onPressed: _signInWithGoogle,
                ),

                // Apple Sign-In (iOS only)
                if (Platform.isIOS) ...[
                  const SizedBox(height: 12),
                  _socialButton(
                    label: "Sign in with Apple",
                    icon: Icon(Icons.apple, size: 24, color: Colors.white),
                    onPressed: _signInWithApple,
                    backgroundColor: Colors.black,
                    textColor: Colors.white,
                  ),
                ],

                // Email/Password Sign-In
                const SizedBox(height: 12),
                _socialButton(
                  label: "Sign in with Email",
                  icon: Icon(Icons.email_outlined, size: 22, color: colors.onSurface),
                  onPressed: _showEmailLoginDialog,
                ),

                const SizedBox(height: 16),

                Center(
                  child: Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                    _policyLink(context, title: "Terms & Conditions", content: termsMarkdown),
                    const Text("|"),
                    _policyLink(context, title: "Privacy Policy", content: privacyMarkdown),
                    const Text("|"),
                    _policyLink(context, title: "Refund Policy", content: refundMarkdown),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? textColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: backgroundColor != null ? backgroundColor : Colors.grey[300]!),
          backgroundColor: backgroundColor,
        ),
        onPressed: (isLoading || _isSocialLoading) ? null : onPressed,
        icon: _isSocialLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : icon,
        label: Text(label, style: TextStyle(fontSize: 16, color: textColor ?? colors.onSurface)),
      ),
    );
  }

  Widget _policyLink(BuildContext context, {required String title, required String content}) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PolicyScreen(title: title, markdownData: content))),
      child: Text(title, style: const TextStyle(color: Colors.black45, decoration: TextDecoration.underline, fontSize: 13)),
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
