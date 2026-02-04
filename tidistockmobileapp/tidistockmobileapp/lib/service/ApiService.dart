import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class ApiService {

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final String apiUrl = dotenv.env['API_URL'] ?? '';
  final String marketDataUrl = dotenv.env['MARKET_DATA_URL'] ?? '';
  final String marketDataPassword = dotenv.env['MARKET_DATA_PASSWORD'] ?? '';

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
    );
  }

  Future<http.Response> loginUser(String phoneNumber) async {
    return http.get(
        Uri.parse(apiUrl + 'api/user/login/$phoneNumber'),
        headers: {
          'Content-Type': 'application/json',
        }
    );
  }

  Future<http.Response> verifyOtp(String phoneNumber, String otp) async {
    return http.get(
        Uri.parse(apiUrl + 'api/user/verify/$phoneNumber/$otp'),
        headers: {
          'Content-Type': 'application/json',
        }
    );
  }

  Future<http.Response> validateUser(String phoneNumber) async {
    return http.get(
        Uri.parse(apiUrl + 'api/user/validate/$phoneNumber'),
        headers: {
          'Content-Type': 'application/json',
        }
    );
  }

  Future<bool> isAuthenticated() async {
    try {

      String? token = await secureStorage.read(key: 'access_token');
      final response = await http.get(
        Uri.parse(apiUrl + 'api/validate'),
        headers: {
          'Authorization': 'Bearer $token', // Add the Bearer token in the headers
          'Content-Type': 'application/json', // Optional: Specify content type if needed
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await secureStorage.write(key: 'access_token', value: data['access_token']);
        return null != data['username'];
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<http.Response> getUserDetails() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
      Uri.parse(apiUrl + 'api/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<http.Response> getSavedDeviceFcm() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
      Uri.parse(apiUrl + 'api/user/fcm'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }


  Future<http.Response> deleteUserAccount() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.delete(
      Uri.parse(apiUrl + 'api/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<http.Response> getStockRecommendations(int? limit, int? offset, String status, String? type) async {
    String? token = await secureStorage.read(key: 'access_token');
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
    String? token = await secureStorage.read(key: 'access_token');
    return http.post(
        Uri.parse(apiUrl + 'api/user/create_course_order/$courseId/$branchId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }
    );
  }

  Future<http.Response> getCourseTransactions(int? limit, int? offset) async {
    String? token = await secureStorage.read(key: 'access_token');
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
  }

  Future<http.Response> getPortfolio() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
      Uri.parse(apiUrl + 'api/portfolio'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<http.Response> getIPO() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
      Uri.parse(apiUrl + 'api/ipo'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<http.Response> getPortfolioHistory(int? limit, int? offset) async {
    String? token = await secureStorage.read(key: 'access_token');
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
  }

  Future<http.Response> getFiiData(int? limit, int? offset) async {
    String? token = await secureStorage.read(key: 'access_token');
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

  Future<http.Response> registerToWorkshop(String date, String branchId) async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.post(
      Uri.parse(apiUrl + 'api/workshop/register'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "date": date,
        "branchId": branchId,
      }),
    );
  }

  Future<http.Response> getRegisteredWorkshops() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
      Uri.parse(apiUrl + 'api/workshop/register'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }
    );
  }


  Future<http.Response> updateUserDetails(String? firstName, String? lastName) async {
    String? token = await secureStorage.read(key: 'access_token');
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
    String? token = await secureStorage.read(key: 'access_token');
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

  void updateDeviceDetails() async {
    String? token = await secureStorage.read(key: 'access_token');
    String? fcmToken = await FirebaseMessaging.instance.getToken();
    final String topic = dotenv.env['FIREBASE_TOPIC'] ?? 'test_all';
    FirebaseMessaging.instance.subscribeToTopic(topic);

    http.post(
        Uri.parse(apiUrl + 'api/user/update_device_details'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "fcmToken": fcmToken,
          "deviceType": Platform.isIOS ? "IOS" : "ANDROID"
        })
    );
  }

  Future<http.StreamedResponse> uploadProfilePicture(imageFile) async {
    File? compressedImage = await compressImage(File(imageFile.path));
    String? token = await secureStorage.read(key: 'access_token');
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


  Future<http.Response> createSubscriptionOrder(String duration) async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.post(
      Uri.parse(apiUrl + 'api/user/create_subscription_order/$duration'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }
    );
  }

  Future<http.Response> getSubscriptionTransactions(int? limit, int? offset) async {
    String? token = await secureStorage.read(key: 'access_token');
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
  }

  Future<http.Response> searchStock(String query) async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
      Uri.parse(apiUrl + 'api/stock/$query'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }
    );
  }



  Future<http.Response> getMarketHolidayList() async {
    String? token = await secureStorage.read(key: 'access_token');
    return http.get(
        Uri.parse(apiUrl + 'api/market/holiday'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }
    );
  }


  Future<http.Response> getMarketQuote(String symbol) async {
    return http.get(
        Uri.parse(marketDataUrl + 'index/quote/$symbol'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        });
  }

  Future<http.Response> getPreMarketSummary() async {
    return http.get(
        Uri.parse(marketDataUrl + 'pre_market_summary'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        });
  }

  Future<http.Response> getStockAnalysis(String symbol) async {
    return http.get(
        Uri.parse(marketDataUrl + 'stock_analysis/${symbol}.NS'),
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
    return http.get(
        Uri.parse('${marketDataUrl}option-chain/$symbol/pcr'),
        headers: {
          'Authorization': 'Bearer $marketDataPassword',
          'Content-Type': 'application/json',
        });
  }


  Future<http.Response> aiChat(List<String> history, String question) async {
    return http.post(
      Uri.parse(marketDataUrl + 'fini_chat'),
      headers: {
        'Authorization': 'Bearer $marketDataPassword',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'history': history,
        'question': question,
      }),
    );
  }

  Future<http.Response> stockChat(String symbol, List<String> history, String question) async {
    return http.post(
      Uri.parse(marketDataUrl + 'stock_chat'),
      headers: {
        'Authorization': 'Bearer $marketDataPassword',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'symbol': symbol,
        'history': history,
        'question': question,
      }),
    );
  }

  Future<http.Response> multiStockChat(List<String> symbols, List<String> history, String question) async {
    return http.post(
      Uri.parse(marketDataUrl + 'multi_stock_chat'),
      headers: {
        'Authorization': 'Bearer $marketDataPassword',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'symbols': symbols,
        'history': history,
        'question': question,
      }),
    );
  }

}
