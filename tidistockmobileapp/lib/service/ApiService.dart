import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'CacheService.dart';

/// Retries an HTTP call on transient network errors (DNS failures, socket
/// resets, timeouts). Uses exponential backoff: 500ms, 1s, 2s.
Future<http.Response> _resilientHttp(
  Future<http.Response> Function() request, {
  int maxRetries = 2,
}) async {
  int attempt = 0;
  while (true) {
    try {
      return await request();
    } on SocketException catch (e) {
      attempt++;
      if (attempt > maxRetries) rethrow;
      debugPrint('[ApiService] SocketException (attempt $attempt/$maxRetries): $e');
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    } on TimeoutException catch (e) {
      attempt++;
      if (attempt > maxRetries) rethrow;
      debugPrint('[ApiService] Timeout (attempt $attempt/$maxRetries): $e');
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    } on HttpException catch (e) {
      attempt++;
      if (attempt > maxRetries) rethrow;
      debugPrint('[ApiService] HttpException (attempt $attempt/$maxRetries): $e');
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
}

class ApiService {

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final String apiUrl = dotenv.env['API_URL'] ?? '';
  final String marketDataUrl = dotenv.env['MARKET_DATA_URL'] ?? '';
  final String marketDataPassword = dotenv.env['MARKET_DATA_PASSWORD'] ?? '';

  // In-memory token cache to avoid repeated platform channel reads.
  // Completer-based lock ensures only one concurrent read from secure storage.
  static String? _cachedToken;
  static Completer<String?>? _tokenCompleter;

  Future<String?> _getToken() async {
    if (_cachedToken != null) return _cachedToken;

    // If another call is already reading the token, wait for it
    if (_tokenCompleter != null) return _tokenCompleter!.future;

    _tokenCompleter = Completer<String?>();
    try {
      _cachedToken = await secureStorage.read(key: 'access_token');
      _tokenCompleter!.complete(_cachedToken);
    } catch (e) {
      _tokenCompleter!.completeError(e);
      _tokenCompleter = null;
      rethrow;
    }
    _tokenCompleter = null;
    return _cachedToken;
  }

  static void invalidateTokenCache() {
    _cachedToken = null;
    _tokenCompleter = null;
  }

  static Future<String?> getFcmTokenSafely() async {
    final messaging = FirebaseMessaging.instance;
    if (Platform.isIOS) {
      for (int i = 0; i < 5; i++) {
        final apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (await messaging.getAPNSToken() == null) return null;
    }
    return await messaging.getToken();
  }

  Future<http.Response> createUser(String fName, String lName, String phoneNumber) async {
    return http.post(
      Uri.parse(apiUrl + 'api/user/create'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
      "firstName": fName,
      "lastName": lName,
      "phone_number": phoneNumber
    })
    ).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> loginUser(String phoneNumber) async {
    return _resilientHttp(() => http.get(
        Uri.parse(apiUrl + 'api/user/login/$phoneNumber'),
        headers: {
          'Content-Type': 'application/json',
        }
    ).timeout(const Duration(seconds: 15)));
  }

  Future<http.Response> verifyOtp(String phoneNumber, String otp) async {
    return _resilientHttp(() => http.get(
        Uri.parse(apiUrl + 'api/user/verify/$phoneNumber/$otp'),
        headers: {
          'Content-Type': 'application/json',
        }
    ).timeout(const Duration(seconds: 15)));
  }

  Future<http.Response> validateUser(String phoneNumber) async {
    return _resilientHttp(() => http.get(
        Uri.parse(apiUrl + 'api/user/validate/$phoneNumber'),
        headers: {
          'Content-Type': 'application/json',
        }
    ).timeout(const Duration(seconds: 15)));
  }

  Future<bool> isAuthenticated() async {
    try {

      String? token = await _getToken();
      final response = await http.get(
        Uri.parse(apiUrl + 'api/validate'),
        headers: {
          'Authorization': 'Bearer $token', // Add the Bearer token in the headers
          'Content-Type': 'application/json', // Optional: Specify content type if needed
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['access_token'];
        await secureStorage.write(key: 'access_token', value: newToken);
        _cachedToken = newToken;
        return null != data['username'];
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<http.Response> getUserDetails() async {
    String? token = await _getToken();
    return http.get(
      Uri.parse(apiUrl + 'api/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> getSavedDeviceFcm() async {
    return CacheService.instance.cachedGet(
      key: 'api/user/fcm',
      fetcher: () async {
        String? token = await _getToken();
        return _resilientHttp(() => http.get(
          Uri.parse(apiUrl + 'api/user/fcm'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 10)));
      },
    );
  }


  Future<http.Response> deleteUserAccount() async {
    String? token = await _getToken();
    return http.delete(
      Uri.parse(apiUrl + 'api/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<http.Response> getStockRecommendations(int? limit, int? offset, String status, String? type) async {
    String? token = await _getToken();
    return http.post(
      Uri.parse(apiUrl + '/api/admin/stock/recommend/get'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
        body: jsonEncode({
          "limit": limit,
          "offset": offset,
          "status": status,
          "type": type
        })
    );
  }

  Future<http.Response> getBranches() async {
    return http.get(
        Uri.parse(apiUrl + '/api/branch'),
        headers: {
          'Content-Type': 'application/json',
        }
    );
  }

  Future<http.Response> getCourses() async {
    return http.get(
        Uri.parse(apiUrl + '/api/course'),
        headers: {
          'Content-Type': 'application/json',
        }
    );
  }

  Future<http.Response> createCourseOrder(String courseId, String branchId) async {
    String? token = await _getToken();
    return http.post(
        Uri.parse(apiUrl + 'api/user/create_course_order/$courseId/$branchId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }
    );
  }

  Future<http.Response> getCourseTransactions(int? limit, int? offset) async {
    return CacheService.instance.cachedGet(
      key: 'api/user/get_course_transactions:$limit:$offset',
      fetcher: () async {
        String? token = await _getToken();
        return http.post(
          Uri.parse(apiUrl + 'api/user/get_course_transactions'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "limit": limit,
            "offset": offset,
          }),
        );
      },
    );
  }

  Future<http.Response> getPortfolio() async {
    String? token = await _getToken();
    return http.get(
      Uri.parse(apiUrl + 'api/portfolio'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  // ── IPO Alerts API (ipoalerts.in) ────────────────────────────

  static const String _ipoAlertsBaseUrl = 'https://api.ipoalerts.in';
  static const String _ipoAlertsApiKey =
      'db3da0321450e5f12bfb1421a433d31a88c0e55f0edae9c8e7736fb300ecedf2';

  /// Fetch all IPOs for a given [status] with pagination from ipoalerts.in.
  /// For closed/listed, limits to recent 60 days to avoid fetching thousands.
  Future<List<dynamic>> _fetchIpoAlertsStatus(String status) async {
    final List<dynamic> allIpos = [];
    int page = 1;
    int totalPages = 1;
    const int pageSize = 3; // API enforces max limit=3
    // Cap pages: open/upcoming are small; closed/listed use date filter
    final int maxPages = (status == 'closed') ? 10 : 5;

    // Build date filter for closed/listed to avoid paginating through years of data
    String dateFilter = '';
    if (status == 'closed' || status == 'listed') {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final fmt = (DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dateFilter = '&startDate=${fmt(from)}&endDate=${fmt(now)}';
    }

    do {
      final uri = Uri.parse(
        '$_ipoAlertsBaseUrl/ipos?status=$status&limit=$pageSize&page=$page$dateFilter',
      );
      debugPrint('[IPO] Fetching: $uri');
      try {
        final response = await http.get(uri, headers: {
          'x-api-key': _ipoAlertsApiKey,
        }).timeout(const Duration(seconds: 20));

        debugPrint('[IPO] $status page $page -> ${response.statusCode} (${response.body.length} bytes)');

        if (response.statusCode != 200) {
          debugPrint('[IPO] $status error: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
          break;
        }

        final decoded = jsonDecode(response.body);
        final List ipos = decoded['ipos'] ?? [];
        allIpos.addAll(ipos);

        totalPages = decoded['meta']?['totalPages'] ?? 1;
        debugPrint('[IPO] $status page $page: got ${ipos.length} ipos, totalPages=$totalPages');
        page++;
      } catch (e) {
        debugPrint('[IPO] $status page $page exception: $e');
        break;
      }
    } while (page <= totalPages && page <= maxPages);

    return allIpos;
  }

  /// Fetch IPOs from ipoalerts.in for all relevant statuses and return a
  /// synthetic [http.Response] containing the combined list.
  Future<http.Response> getIPO() async {
    debugPrint('[IPO] Fetching from ipoalerts.in...');

    final results = await Future.wait([
      _fetchIpoAlertsStatus('open'),
      _fetchIpoAlertsStatus('upcoming'),
      _fetchIpoAlertsStatus('listed'),
      _fetchIpoAlertsStatus('closed'),
    ]);

    final combined = <dynamic>[
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
    ];

    // Normalise type: "EQ" → "Mainboard", "SME" stays as-is
    for (final ipo in combined) {
      if (ipo is Map) {
        final t = (ipo['type'] ?? '').toString().toUpperCase();
        ipo['type'] = (t == 'EQ') ? 'Mainboard' : ipo['type'];
      }
    }

    debugPrint('[IPO] ipoalerts total: open=${results[0].length}, '
        'upcoming=${results[1].length}, listed=${results[2].length}, '
        'closed=${results[3].length} => ${combined.length}');

    final jsonBody = jsonEncode(combined);
    return http.Response.bytes(
      utf8.encode(jsonBody),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<http.Response> getPortfolioHistory(int? limit, int? offset) async {
    return CacheService.instance.cachedGet(
      key: 'api/history/portfolio:$limit:$offset',
      fetcher: () async {
        String? token = await _getToken();
        return http.post(
          Uri.parse(apiUrl + 'api/history/portfolio'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "limit": limit,
            "offset": offset,
          }),
        );
      },
    );
  }

  Future<http.Response> getFiiData(int? limit, int? offset) async {
    String? token = await _getToken();
    return http.post(
      Uri.parse(apiUrl + 'api/fii'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "limit": limit,
        "offset": offset,
      }),
    );
  }

  Future<http.Response> registerToWorkshop(
    String date,
    String branchId, {
    String? participantName,
    String? participantPhone,
    bool? hasStockExperience,
    bool? hasDematAccount,
  }) async {
    String? token = await _getToken();
    final body = <String, dynamic>{
      "date": date,
      "branchId": branchId,
    };
    if (participantName != null) body["participantName"] = participantName;
    if (participantPhone != null) body["participantPhone"] = participantPhone;
    if (hasStockExperience != null) body["hasStockExperience"] = hasStockExperience;
    if (hasDematAccount != null) body["hasDematAccount"] = hasDematAccount;
    return http.post(
      Uri.parse(apiUrl + 'api/workshop/register'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> getRegisteredWorkshops() async {
    return CacheService.instance.cachedGet(
      key: 'api/workshop/register',
      fetcher: () async {
        String? token = await _getToken();
        return http.get(
          Uri.parse(apiUrl + 'api/workshop/register'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      },
    );
  }


  Future<http.Response> updateUserDetails(String? firstName, String? lastName) async {
    String? token = await _getToken();
    return http.patch(
      Uri.parse(apiUrl + 'api/user/update'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "firstName": firstName,
        "lastName": lastName
      })
    );
  }

  Future<http.Response> savePanDetails(String? pan, String? email) async {
    String? token = await _getToken();
    return http.patch(
        Uri.parse(apiUrl + 'api/user/update_pan'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "pan": pan,
          "email": email
        })
    );
  }

  Future<void> updateDeviceDetails() async {
    try {
      String? token = await _getToken();
      String? fcmToken = await getFcmTokenSafely();
      final String topic = dotenv.env['FIREBASE_TOPIC'] ?? 'test_all';
      FirebaseMessaging.instance.subscribeToTopic(topic);

      final response = await _resilientHttp(() => http.post(
        Uri.parse(apiUrl + 'api/user/update_device_details'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "fcmToken": fcmToken,
          "deviceType": Platform.isIOS ? "IOS" : "ANDROID"
        }),
      ).timeout(const Duration(seconds: 10)));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[ApiService] updateDeviceDetails failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ApiService] updateDeviceDetails error: $e');
    }
  }

  Future<http.StreamedResponse> uploadProfilePicture(imageFile) async {
    File? compressedImage = await compressImage(File(imageFile.path));
    String? token = await _getToken();
    var request = http.MultipartRequest('PATCH', Uri.parse(apiUrl + "api/user/update_profile_picture"));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', compressedImage.path));
    return request.send();
  }

  Future<File> compressImage(File imageFile) async {
    final image = img.decodeImage(await imageFile.readAsBytes());

    // Resize the image before compressing
    final resizedImage = img.copyResize(image!, width: 800); // Resize to a width of 800 pixels

    // Compress the resized image
    final compressedImage = img.encodeJpg(resizedImage, quality: 60); // Adjust the quality

    final String fileName = imageFile.uri.pathSegments.last;
    final String directory = imageFile.parent.path;
    final compressedImagePath = '$directory/compressed_$fileName';

    final compressedImageFile = File(compressedImagePath);
    await compressedImageFile.writeAsBytes(compressedImage);

    return compressedImageFile;
  }


  // ---------------------------------------------------------------------------
  // Model Portfolio Payment APIs
  // ---------------------------------------------------------------------------

  Future<http.Response> createModelPortfolioOrder({
    required String planId,
    required String planName,
    required String strategyId,
    required String pricingTier,
    required int amount,
  }) async {
    String? token = await _getToken();
    return http.post(
      Uri.parse(apiUrl + 'api/user/model-portfolio/create-order'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'planId': planId,
        'planName': planName,
        'strategyId': strategyId,
        'pricingTier': pricingTier,
        'amount': amount,
      }),
    ).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> verifyModelPortfolioPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    String? token = await _getToken();
    return http.post(
      Uri.parse(apiUrl + 'api/user/model-portfolio/verify-payment'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      }),
    ).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> subscribeFreeModelPortfolio({
    required String planId,
    required String strategyId,
    String? email,
  }) async {
    String? token = await _getToken();
    final body = <String, dynamic>{
      'planId': planId,
      'strategyId': strategyId,
    };
    if (email != null && email.isNotEmpty) {
      body['email'] = email;
    }
    return http.post(
      Uri.parse(apiUrl + 'api/user/model-portfolio/subscribe-free'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> getModelPortfolioSubscriptionStatus(String planId) async {
    String? token = await _getToken();
    return http.get(
      Uri.parse(apiUrl + 'api/user/model-portfolio/subscription-status/$planId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));
  }

  // ---------------------------------------------------------------------------
  // Model Portfolio - Master Email Gateway (resolves email internally)
  // These endpoints use user_id from JWT to resolve email from tidi_Front_back DB
  // ensuring subscriptions work even if user has different email in AlphaQuark
  // ---------------------------------------------------------------------------

  /// Get all model portfolio subscriptions for the logged-in user
  /// Uses master email from tidi_Front_back database to fetch from AlphaQuark
  Future<http.Response> getUserModelPortfolioSubscriptions() async {
    String? token = await _getToken();
    return http.get(
      Uri.parse(apiUrl + 'api/user/model-portfolio/subscriptions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));
  }

  /// Subscribe to a model portfolio using master email from tidi_Front_back
  /// Email is resolved internally from user_id in JWT - no need to pass email
  Future<http.Response> subscribeToModelPortfolio({
    required String strategyId,
    required String planId,
  }) async {
    String? token = await _getToken();
    debugPrint('[ApiService] subscribeToModelPortfolio - token exists: ${token != null && token.isNotEmpty}');
    debugPrint('[ApiService] subscribeToModelPortfolio - strategyId: $strategyId, planId: $planId');

    final response = await http.post(
      Uri.parse(apiUrl + 'api/user/model-portfolio/subscribe'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'strategyId': strategyId,
        'planId': planId,
      }),
    ).timeout(const Duration(seconds: 30));

    debugPrint('[ApiService] subscribeToModelPortfolio response: ${response.statusCode} ${response.body}');
    return response;
  }

  /// Subscribe or unsubscribe from a strategy using master email
  Future<http.Response> subscribeStrategy({
    required String strategyId,
    required String action, // 'subscribe' or 'unsubscribe'
  }) async {
    String? token = await _getToken();
    return http.put(
      Uri.parse(apiUrl + 'api/user/model-portfolio/subscribe-strategy/$strategyId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': action}),
    ).timeout(const Duration(seconds: 30));
  }

  /// Check subscription status for a specific strategy using master email
  Future<http.Response> getStrategySubscriptionStatus(String strategyId) async {
    String? token = await _getToken();
    return http.get(
      Uri.parse(apiUrl + 'api/user/model-portfolio/strategy-status/$strategyId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));
  }

  // ---------------------------------------------------------------------------
  // Social Auth APIs (Google / Apple Sign-In)
  // ---------------------------------------------------------------------------

  /// Check if a Firebase account is already linked to a user.
  /// Returns 202 + token if linked, 200 + social_info if not linked.
  /// Works for Google, Apple, and Email/Password — all go through Firebase.
  Future<http.Response> firebaseLookup(String firebaseIdToken) async {
    return _resilientHttp(() => http.post(
      Uri.parse(apiUrl + 'api/auth/social/lookup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': firebaseIdToken}),
    ).timeout(const Duration(seconds: 15)));
  }

  /// Complete Firebase login: link Firebase account to existing/new user.
  /// Returns 202 + token on success, 200 + otp_required if OTP needed.
  Future<http.Response> firebaseComplete({
    required String firebaseIdToken,
    required String phoneNumber,
    String? otp,
    String? firstName,
    String? lastName,
  }) async {
    final body = <String, dynamic>{
      'id_token': firebaseIdToken,
      'phone_number': phoneNumber,
    };
    if (otp != null) body['otp'] = otp;
    if (firstName != null) body['first_name'] = firstName;
    if (lastName != null) body['last_name'] = lastName;

    return _resilientHttp(() => http.post(
      Uri.parse(apiUrl + 'api/auth/social/complete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15)));
  }

  Future<http.Response> createSubscriptionOrder(String duration) async {
    String? token = await _getToken();
    return http.post(
      Uri.parse(apiUrl + 'api/user/create_subscription_order/$duration'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }
    );
  }

  Future<http.Response> getSubscriptionTransactions(int? limit, int? offset) async {
    return CacheService.instance.cachedGet(
      key: 'api/user/get_subscription_transactions:$limit:$offset',
      fetcher: () async {
        String? token = await _getToken();
        return http.post(
          Uri.parse(apiUrl + 'api/user/get_subscription_transactions'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "limit": limit,
            "offset": offset,
          }),
        );
      },
    );
  }

  Future<http.Response> searchStock(String query) async {
    return CacheService.instance.cachedGet(
      key: 'api/stock/search:$query',
      fetcher: () async {
        String? token = await _getToken();
        return http.get(
          Uri.parse(apiUrl + 'api/stock/$query'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      },
    );
  }



  Future<http.Response> getMarketHolidayList() async {
    String? token = await _getToken();
    return http.get(
        Uri.parse(apiUrl + 'api/market/holiday'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }
    );
  }


  Future<http.Response> getMarketQuote(String symbol) async {
    return CacheService.instance.cachedGet(
      key: 'index/quote:$symbol',
      fetcher: () => _resilientHttp(() => http.get(
        Uri.parse(marketDataUrl + 'index/quote/$symbol'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 8))),
    );
  }

  Future<http.Response> getPreMarketSummary() async {
    return _resilientHttp(() => http.get(
        Uri.parse(marketDataUrl + 'pre_market_summary'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        }).timeout(const Duration(seconds: 10)));
  }

  Future<http.Response> getStockAnalysis(String symbol) async {
    final cleanSymbol = symbol.replaceAll(RegExp(r'\.(NS|BO)$'), '');
    return http.get(
        Uri.parse(marketDataUrl + 'stock_analysis/$cleanSymbol.NS'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        });
  }

  Future<http.Response> getNifty50StockAnalysis() async {
    return http.get(
        Uri.parse(marketDataUrl + 'nifty_50_stock_analysis'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        });
  }


  Future<http.Response> getOptionPulsePCR(String symbol) async {
    return CacheService.instance.cachedGet(
      key: 'option-chain:$symbol:pcr',
      fetcher: () => _resilientHttp(() => http.get(
        Uri.parse(marketDataUrl + 'option-chain/$symbol/pcr'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 8))),
    );
  }

  /// Cached Option Pulse PCR — stale-while-revalidate wrapper.
  Future<void> getCachedOptionPulsePCR({
    required String symbol,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'option-chain:$symbol:pcr',
      fetcher: () => http.get(
        Uri.parse(marketDataUrl + 'option-chain/$symbol/pcr'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10)),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

  // ---------------------------------------------------------------------------
  // Cached versions — opt-in stale-while-revalidate wrappers
  // ---------------------------------------------------------------------------

  /// Cached market holidays (30-day TTL).
  Future<void> getCachedMarketHolidays({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/market/holiday',
      fetcher: () => getMarketHolidayList(),
      onData: onData,
    );
  }

  /// Cached branches (30-day TTL).
  Future<void> getCachedBranches({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/branch',
      fetcher: () => getBranches(),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

  /// Cached courses (30-day TTL).
  Future<void> getCachedCourses({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/course',
      fetcher: () => getCourses(),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

  /// Cached IPO list (from ipoalerts.in).
  Future<void> getCachedIPO({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/ipo',
      fetcher: () => getIPO(),
      onData: onData,
      parseResponse: (r) {
        final decoded = jsonDecode(r.body);
        if (decoded is List) return decoded;
        if (decoded is Map) {
          if (decoded['ipos'] is List) return decoded['ipos'];
          if (decoded['data'] is List) return decoded['data'];
        }
        return [];
      },
    );
  }

  /// Cached FII/DII data first page (12-hour TTL).
  Future<void> getCachedFiiData({
    required int limit,
    required int offset,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/fii:$limit:$offset',
      fetcher: () => getFiiData(limit, offset),
      onData: onData,
    );
  }

  /// Cached Nifty 50 stock analysis (12-hour TTL).
  Future<void> getCachedNifty50StockAnalysis({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'nifty_50_stock_analysis',
      fetcher: () => getNifty50StockAnalysis(),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

  /// Cached individual stock analysis (12-hour TTL).
  Future<void> getCachedStockAnalysis({
    required String symbol,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'stock_analysis:$symbol',
      fetcher: () => getStockAnalysis(symbol),
      onData: onData,
    );
  }

  /// Cached stock recommendations first page (2-hour TTL).
  Future<void> getCachedStockRecommendations({
    required int limit,
    required int offset,
    required String status,
    required String? type,
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/admin/stock/recommend/get:$status:${type ?? 'ALL'}:$limit:$offset',
      fetcher: () => getStockRecommendations(limit, offset, status, type),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

  /// Cached portfolio (4-hour TTL).
  Future<void> getCachedPortfolio({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/portfolio',
      fetcher: () => getPortfolio(),
      onData: onData,
    );
  }

  /// Cached user details (4-hour TTL).
  Future<void> getCachedUserDetails({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'api/user',
      fetcher: () => getUserDetails(),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

  /// Cached pre-market summary (30-min TTL).
  Future<void> getCachedPreMarketSummary({
    required void Function(dynamic data, {required bool fromCache}) onData,
  }) {
    return CacheService.instance.fetchWithCache(
      key: 'pre_market_summary',
      fetcher: () => getPreMarketSummary(),
      onData: onData,
      parseResponse: (r) => jsonDecode(r.body)['data'],
    );
  }

}
