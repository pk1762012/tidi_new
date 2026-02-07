import 'dart:convert';
import 'dart:ui';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'ApiService.dart';
import 'CacheService.dart';

class RazorpayService {
  late Razorpay _razorpay;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();

  VoidCallback? _onFinishCallback; // 🔄 Callback to trigger UI reload

  RazorpayService({VoidCallback? onFinish}) {
    _onFinishCallback = onFinish;
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void openCheckout(String duration) async {
    final apiService = ApiService();
    final response = await apiService.createSubscriptionOrder(duration);

    if (response.statusCode == 201) {
      try {
        String? phone = await secureStorage.read(key: 'phone_number');
        final jsonData = json.decode(response.body);

        var options = {
          'key': dotenv.env['RAZORPAY_KEY'],
          'amount': jsonData['data']['amount'],
          'currency': 'INR',
          'name': 'TIDI Wealth',
          'order_id': jsonData['data']['orderId'],
          'description': '${duration.replaceAll('_', ' ').toUpperCase()} Membership',
          'timeout': 60,
          'prefill': {'contact': phone}
        };

        _razorpay.open(options);
      } catch (e) {
        print('Error opening Razorpay checkout: $e');
        _onFinishCallback?.call(); // 🔄 still trigger in case of failure to open
      }
    } else {
      print("Failed to create Razorpay order");
      _onFinishCallback?.call();
    }
  }

  void openCourseCheckout(String courseId, String branchId) async {
    final apiService = ApiService();
    final response = await apiService.createCourseOrder(courseId, branchId);

    if (response.statusCode == 201) {
      try {
        String? phone = await secureStorage.read(key: 'phone_number');
        final jsonData = json.decode(response.body);

        var options = {
          'key': dotenv.env['RAZORPAY_KEY'],
          'amount': jsonData['data']['amount'],
          'currency': 'INR',
          'name': 'TIDI Wealth',
          'order_id': jsonData['data']['orderId'],
          'description': 'Course Booking',
          'timeout': 60,
          'prefill': {'contact': phone}
        };

        _razorpay.open(options);
      } catch (e) {
        print('Error opening Razorpay checkout: $e');
        _onFinishCallback?.call(); // 🔄 still trigger in case of failure to open
      }
    } else {
      print("Failed to create Razorpay order");
      _onFinishCallback?.call();
    }
  }

  void openWorkshopCheckout(String date, String branchId) async {
    final response = await ApiService().registerToWorkshop(date, branchId);

    if (response.statusCode == 201) {
      try {
        final jsonData = json.decode(response.body);

        var options = {
          'key': dotenv.env['RAZORPAY_KEY'],
          'amount': jsonData['data']['amount'],
          'currency': 'INR',
          'name': 'TIDI Wealth',
          'order_id': jsonData['data']['orderId'],
          'description': 'Workshop Registration',
          'timeout': 60,
        };

        _razorpay.open(options);
      } catch (e) {
        print('Error opening Razorpay checkout: $e');
        _onFinishCallback?.call(); // 🔄 still trigger in case of failure to open
      }
    } else {
      print("Failed to create Razorpay order");
      _onFinishCallback?.call();
    }
  }


  void _handleSuccess(PaymentSuccessResponse response) {
    print("Payment successful: ${response.paymentId}");
    CacheService.instance.invalidate('api/user');
    CacheService.instance.invalidateByPrefix('api/admin/stock/recommend/get');
    CacheService.instance.invalidateByPrefix('api/user/get_subscription_transactions');
    CacheService.instance.invalidateByPrefix('api/user/get_course_transactions');
    CacheService.instance.invalidateByPrefix('api/workshop/register');
    _onFinishCallback?.call(); // 🔄 refresh UI
  }

  void _handleError(PaymentFailureResponse response) {
    print("Payment failed: ${response.code} - ${response.message}");
    _onFinishCallback?.call(); // 🔄 refresh UI
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print("External wallet selected: ${response.walletName}");
    _onFinishCallback?.call(); // 🔄 refresh UI
  }

  void dispose() {
    _razorpay.clear();
  }
}
