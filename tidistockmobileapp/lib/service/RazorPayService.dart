import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../components/login/PaymentSuccess.dart';
import '../main.dart';
import 'ApiService.dart';
import 'CacheService.dart';

class RazorpayService {
  late Razorpay _razorpay;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();

  void Function(bool success)? _onResultCallback;
  bool _isProcessing = false;
  String? _currentCheckoutType;
  Map<String, String> _pendingMetadata = {};

  bool get isProcessing => _isProcessing;

  RazorpayService({void Function(bool success)? onResult}) {
    _onResultCallback = onResult;
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  // --------------- CHECKOUT METHODS ---------------

  Future<bool> openCheckout(String duration) async {
    debugPrint('[RazorpayService] openCheckout called with duration: $duration');
    if (_isProcessing) {
      debugPrint('[RazorpayService] Already processing, returning false');
      return false;
    }
    _isProcessing = true;

    try {
      final apiService = ApiService();
      debugPrint('[RazorpayService] Calling createSubscriptionOrder...');
      final response = await apiService.createSubscriptionOrder(duration);
      debugPrint('[RazorpayService] API response status: ${response.statusCode}');
      debugPrint('[RazorpayService] API response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          String? phone = await secureStorage.read(key: 'phone_number');
          final jsonData = json.decode(response.body);

          final razorpayKey = dotenv.env['RAZORPAY_KEY'] ?? '';
          final orderId = jsonData['data']['orderId'];

          debugPrint('[RazorpayService] openCheckout - key: ${razorpayKey.substring(0, razorpayKey.length.clamp(0, 12))}..., orderId: $orderId');

          var options = {
            'key': razorpayKey,
            'amount': jsonData['data']['amount'],
            'currency': 'INR',
            'name': 'TIDI Wealth',
            'order_id': orderId,
            'description':
                '${duration.replaceAll('_', ' ').toUpperCase()} Membership',
            'timeout': 60,
            'prefill': {'contact': phone ?? ''}
          };

          _razorpay.open(options);
          return true;
        } catch (e) {
          _isProcessing = false;
          debugPrint('[RazorpayService] openCheckout error: $e');
          _showError('Unable to open payment screen. Please try again.');
          return false;
        }
      } else {
        _isProcessing = false;
        _showError(
            'Unable to create order (${response.statusCode}). Please try again later.');
        return false;
      }
    } catch (e) {
      _isProcessing = false;
      _showError('Network error. Please check your connection and try again.');
      return false;
    }
  }

  Future<bool> openCourseCheckout(String courseId, String branchId) async {
    if (_isProcessing) return false;
    _isProcessing = true;

    try {
      final apiService = ApiService();
      final response = await apiService.createCourseOrder(courseId, branchId);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          String? phone = await secureStorage.read(key: 'phone_number');
          final jsonData = json.decode(response.body);

          final razorpayKey = dotenv.env['RAZORPAY_KEY'] ?? '';
          final orderId = jsonData['data']['orderId'];

          debugPrint('[RazorpayService] openCourseCheckout - key: ${razorpayKey.substring(0, razorpayKey.length.clamp(0, 12))}..., orderId: $orderId');

          var options = {
            'key': razorpayKey,
            'amount': jsonData['data']['amount'],
            'currency': 'INR',
            'name': 'TIDI Wealth',
            'order_id': orderId,
            'description': 'Course Booking',
            'timeout': 60,
            'prefill': {'contact': phone ?? ''}
          };

          _razorpay.open(options);
          return true;
        } catch (e) {
          _isProcessing = false;
          debugPrint('[RazorpayService] openCourseCheckout error: $e');
          _showError('Unable to open payment screen. Please try again.');
          return false;
        }
      } else {
        _isProcessing = false;
        _showError(
            'Unable to create order (${response.statusCode}). Please try again later.');
        return false;
      }
    } catch (e) {
      _isProcessing = false;
      _showError('Network error. Please check your connection and try again.');
      return false;
    }
  }

  Future<bool> openWorkshopCheckout(String date, String branchId) async {
    if (_isProcessing) return false;
    _isProcessing = true;

    try {
      final response = await ApiService().registerToWorkshop(date, branchId);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = json.decode(response.body);

          final razorpayKey = dotenv.env['RAZORPAY_KEY'] ?? '';
          final orderId = jsonData['data']['orderId'];

          debugPrint('[RazorpayService] openWorkshopCheckout - key: ${razorpayKey.substring(0, razorpayKey.length.clamp(0, 12))}..., orderId: $orderId');

          var options = {
            'key': razorpayKey,
            'amount': jsonData['data']['amount'],
            'currency': 'INR',
            'name': 'TIDI Wealth',
            'order_id': orderId,
            'description': 'Workshop Registration',
            'timeout': 60,
          };

          _razorpay.open(options);
          return true;
        } catch (e) {
          _isProcessing = false;
          debugPrint('[RazorpayService] openWorkshopCheckout error: $e');
          _showError('Unable to open payment screen. Please try again.');
          return false;
        }
      } else {
        _isProcessing = false;
        _showError(
            'Unable to create order (${response.statusCode}). Please try again later.');
        return false;
      }
    } catch (e) {
      _isProcessing = false;
      _showError('Network error. Please check your connection and try again.');
      return false;
    }
  }

  Future<bool> openModelPortfolioCheckout({
    required String planId,
    required String planName,
    required String strategyId,
    required String pricingTier,
    required int amount,
  }) async {
    debugPrint('[RazorpayService] openModelPortfolioCheckout called - planId: $planId, strategyId: $strategyId, tier: $pricingTier, amount: $amount');

    if (_isProcessing) {
      debugPrint('[RazorpayService] openModelPortfolioCheckout - already processing, returning false');
      return false;
    }
    _isProcessing = true;

    try {
      String? phone = await secureStorage.read(key: 'phone_number');
      String? email = await secureStorage.read(key: 'user_email');

      debugPrint('[RazorpayService] openModelPortfolioCheckout - calling TIDI createModelPortfolioOrder API...');
      final response = await ApiService().createModelPortfolioOrder(
        planId: planId,
        planName: planName,
        strategyId: strategyId,
        pricingTier: pricingTier,
        amount: amount,
      );

      debugPrint('[RazorpayService] openModelPortfolioCheckout - API response status: ${response.statusCode}');
      debugPrint('[RazorpayService] openModelPortfolioCheckout - API response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = json.decode(response.body);

          final razorpayKey = dotenv.env['RAZORPAY_KEY'] ?? '';
          final orderId = jsonData['data']['orderId'];
          final amountInPaise = jsonData['data']['amount'] ?? amount;

          debugPrint('[RazorpayService] openModelPortfolioCheckout - key: ${razorpayKey.substring(0, razorpayKey.length.clamp(0, 12))}..., orderId: $orderId');

          _currentCheckoutType = 'model_portfolio';
          _pendingMetadata = {
            'planId': planId,
            'strategyId': strategyId,
            'pricingTier': pricingTier,
            'amount': amount.toString(),
            'userEmail': email ?? '',
          };

          var options = {
            'key': razorpayKey,
            'amount': amountInPaise,
            'currency': 'INR',
            'name': 'TIDI Wealth',
            'order_id': orderId,
            'description': '$planName - ${pricingTier.replaceAll('_', ' ').toUpperCase()}',
            'timeout': 120,
            'prefill': {'contact': phone ?? ''}
          };

          debugPrint('[RazorpayService] openModelPortfolioCheckout - opening Razorpay with options: $options');
          _razorpay.open(options);
          return true;
        } catch (e) {
          _isProcessing = false;
          _currentCheckoutType = null;
          debugPrint('[RazorpayService] openModelPortfolioCheckout parse/open error: $e');
          _showError('Unable to open payment screen. Please try again.');
          return false;
        }
      } else {
        _isProcessing = false;
        debugPrint('[RazorpayService] create-order failed: ${response.statusCode} - ${response.body}');
        _showError('Unable to create order (${response.statusCode}). Please try again later.');
        return false;
      }
    } catch (e) {
      _isProcessing = false;
      _currentCheckoutType = null;
      debugPrint('[RazorpayService] openModelPortfolioCheckout network error: $e');
      _showError('Network error. Please check your connection and try again.');
      return false;
    }
  }

  // --------------- HANDLERS ---------------

  void _handleSuccess(PaymentSuccessResponse response) async {
    _isProcessing = false;

    if (_currentCheckoutType == 'model_portfolio') {
      try {
        final verifyResp = await ApiService().verifyModelPortfolioPayment(
          razorpayOrderId: response.orderId ?? '',
          razorpayPaymentId: response.paymentId ?? '',
          razorpaySignature: response.signature ?? '',
        );
        if (verifyResp.statusCode >= 200 && verifyResp.statusCode < 300) {
          CacheService.instance.invalidateByPrefix('aq/admin/plan/portfolios');
          CacheService.instance.invalidateByPrefix('aq/model-portfolio/subscribed');
          _navigateToSuccess();
          _onResultCallback?.call(true);
        } else {
          _showError('Payment received but activation failed. Contact support.');
          _onResultCallback?.call(false);
        }
      } catch (e) {
        debugPrint('[RazorpayService] model_portfolio verify error: $e');
        _showError('Payment received. Subscription will activate shortly.');
        _onResultCallback?.call(false);
      }
      _currentCheckoutType = null;
      _pendingMetadata = {};
      return;
    }

    // Existing flow for membership/course/workshop
    CacheService.instance.invalidate('api/user');
    CacheService.instance.invalidateByPrefix('api/admin/stock/recommend/get');
    CacheService.instance
        .invalidateByPrefix('api/user/get_subscription_transactions');
    CacheService.instance
        .invalidateByPrefix('api/user/get_course_transactions');
    CacheService.instance.invalidateByPrefix('api/workshop/register');
    _navigateToSuccess();
    _onResultCallback?.call(true);
  }

  void _handleError(PaymentFailureResponse response) {
    _isProcessing = false;
    if (response.code == 2) {
      _showError('Payment cancelled.');
    } else {
      _showError('Payment failed. Please try again.');
    }
    _onResultCallback?.call(false);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _onResultCallback?.call(false);
  }

  // --------------- HELPERS ---------------

  void _showError(String message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _navigateToSuccess() {
    final navState = navigatorKey.currentState;
    if (navState == null) return;
    navState.pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SuccessSplashScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  void dispose() {
    if (!_isProcessing) {
      _razorpay.clear();
    }
  }
}
