import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidistockmobileapp/service/ApiService.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  String? phoneError;

  // -------------------------------------------------------
  // VALIDATE & SHOW OTP POPUP
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
      // Test number bypass for app review
      final enableTestLogin = dotenv.env['ENABLE_TEST_LOGIN'] == 'true';
      if (enableTestLogin && phone == "9999999999") {
        showOtpPopup(phone);
        return;
      }

      ApiService apiService = ApiService();
      final response = await apiService.validateUser(phone);

      if (response.statusCode == 200) {
        final loginResponse = await apiService.loginUser(phone);
        if (loginResponse.statusCode == 200) {
          showOtpPopup(phone);
        } else {
          setState(() => phoneError = "Something went wrong. Try again.");
        }
      } else {
        showNamePopup();
      }
    } catch (e) {
      setState(() => phoneError = "Something went wrong. Try again.");
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
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStatePopup) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
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
                            // fname required + max 20
                            if (f.isEmpty) {
                              fnameError = "Enter first name";
                            } else if (f.length > 20) {
                              fnameError = "Max 20 characters allowed";
                            } else {
                              fnameError = null;
                            }

                            // lname optional but max 20
                            if (l.isNotEmpty && l.length > 20) {
                              lnameError = "Max 20 characters allowed";
                            } else {
                              lnameError = null;
                            }
                          });

                          // Stop if fname has any error OR lname has an error
                          if (fnameError != null || lnameError != null) return;

                          Navigator.pop(context);
                          ApiService apiService = ApiService();
                          final response = await apiService.createUser(fnameCtrl.text.trim(), lnameCtrl.text.trim(), phoneCtrl.text.trim());
                          if (response.statusCode == 201 || response.statusCode == 202) {
                            showOtpPopup(phoneCtrl.text.trim());
                          } else {
                            Navigator.pop(context);   // <-- Close name popup and go back
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Failed to register. Please try again.")),
                            );
                          }

                        },
                        child: Text("Continue"),
                      ),
                    ),

                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Cancel"),
                    )
                  ],
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

    // 4 controllers for 4 digits
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
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStatePopup) {
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
                              FocusScope.of(context).nextFocus();
                            }
                            if (value.isEmpty && i > 0) {
                              FocusScope.of(context).previousFocus();
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
                          padding: EdgeInsets.zero,                // remove default padding
                          alignment: Alignment.center,             // center content
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

                          // Hardcoded test credentials for app review
                          final enableTestLogin = dotenv.env['ENABLE_TEST_LOGIN'] == 'true';
                          if (enableTestLogin && phone == "9999999999" && otp == "1234") {
                            // Skip backend call, create dummy token for test account
                            const String testToken = "test_review_token_9999999999";

                            secureStorage.deleteAll();
                            await secureStorage.write(key: 'access_token', value: testToken);

                            setStatePopup(() => verifying = false);
                            timer?.cancel();
                            Navigator.pop(context);

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
                            return;
                          }

                          final response = await apiService.verifyOtp(phone, otp);

                          if (response.statusCode == 202) {
                            var responseData = jsonDecode(response.body);
                            String accessToken = responseData['data']['token'];

                            secureStorage.deleteAll();
                            await secureStorage.write(key: 'access_token', value: accessToken);
                            apiService.updateDeviceDetails();

                            setStatePopup(() => verifying = false);
                            timer?.cancel();
                            Navigator.pop(context);

                            /*ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("OTP Verified Successfully!")),
                            );*/

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
                                          (route) => false, // Remove all previous routes
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
                          } else {
                            var responseData = jsonDecode(response.body);
                            String message = responseData['message'];
                            setStatePopup(() {
                              verifying = false;
                              otpError = message;
                            });
                          }
                        },
                        child: Center(                               // <-- FIX: centers loader/text
                          child: verifying
                              ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(  // <-- smaller loader fits perfectly
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
                        // Skip backend call for test number
                        final enableTestLogin = dotenv.env['ENABLE_TEST_LOGIN'] == 'true';
                        if (!enableTestLogin || phone != "9999999999") {
                          await apiService.loginUser(phone);
                        }
                        startTimer(setStatePopup);
                      },
                      child: Text("Resend OTP"),
                    )
                        : Text("Resend in ${secondsLeft}s",
                        style: TextStyle(color: Colors.grey)),

                    TextButton(
                      onPressed: () {
                        timer?.cancel();
                        Navigator.pop(context);
                      },
                      child: Text("Cancel"),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }



  // -------------------------------------------------------
  // CUSTOM 4 DIGIT BOX ANIMATED INPUT
  // -------------------------------------------------------
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
                    aspectRatio: 1, // 1:1 ratio
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

                SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    onPressed: isLoading ? null : onContinue,
                    child: isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text("Continue",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
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
