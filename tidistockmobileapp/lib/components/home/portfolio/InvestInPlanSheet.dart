import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';

import '../../../service/ApiService.dart';
import '../../../service/AqApiService.dart';
import '../../../service/CacheService.dart';
import '../../../service/RazorPayService.dart';

// ---------------------------------------------------------------------------
// Country code data
// ---------------------------------------------------------------------------
class _CountryCode {
  final String name;
  final String dialCode;
  final String code;
  const _CountryCode(this.name, this.dialCode, this.code);
}

const List<_CountryCode> _countryCodes = [
  _CountryCode('India', '+91', 'IN'),
  _CountryCode('United States', '+1', 'US'),
  _CountryCode('United Kingdom', '+44', 'GB'),
  _CountryCode('Canada', '+1', 'CA'),
  _CountryCode('Australia', '+61', 'AU'),
  _CountryCode('Singapore', '+65', 'SG'),
  _CountryCode('UAE', '+971', 'AE'),
  _CountryCode('Germany', '+49', 'DE'),
  _CountryCode('France', '+33', 'FR'),
  _CountryCode('Japan', '+81', 'JP'),
  _CountryCode('China', '+86', 'CN'),
  _CountryCode('Hong Kong', '+852', 'HK'),
  _CountryCode('South Korea', '+82', 'KR'),
  _CountryCode('Malaysia', '+60', 'MY'),
  _CountryCode('Thailand', '+66', 'TH'),
  _CountryCode('Indonesia', '+62', 'ID'),
  _CountryCode('Philippines', '+63', 'PH'),
  _CountryCode('New Zealand', '+64', 'NZ'),
  _CountryCode('South Africa', '+27', 'ZA'),
  _CountryCode('Brazil', '+55', 'BR'),
  _CountryCode('Mexico', '+52', 'MX'),
  _CountryCode('Netherlands', '+31', 'NL'),
  _CountryCode('Switzerland', '+41', 'CH'),
  _CountryCode('Sweden', '+46', 'SE'),
  _CountryCode('Norway', '+47', 'NO'),
  _CountryCode('Denmark', '+45', 'DK'),
  _CountryCode('Italy', '+39', 'IT'),
  _CountryCode('Spain', '+34', 'ES'),
  _CountryCode('Portugal', '+351', 'PT'),
  _CountryCode('Ireland', '+353', 'IE'),
  _CountryCode('Saudi Arabia', '+966', 'SA'),
  _CountryCode('Qatar', '+974', 'QA'),
  _CountryCode('Kuwait', '+965', 'KW'),
  _CountryCode('Bahrain', '+973', 'BH'),
  _CountryCode('Oman', '+968', 'OM'),
  _CountryCode('Sri Lanka', '+94', 'LK'),
  _CountryCode('Bangladesh', '+880', 'BD'),
  _CountryCode('Nepal', '+977', 'NP'),
  _CountryCode('Pakistan', '+92', 'PK'),
];

const List<String> _nationalities = [
  'American', 'Australian', 'Bangladeshi', 'Brazilian', 'British', 'Canadian',
  'Chinese', 'Danish', 'Dutch', 'Filipino', 'French', 'German', 'Hong Konger',
  'Indian', 'Indonesian', 'Irish', 'Italian', 'Japanese', 'Korean', 'Kuwaiti',
  'Malaysian', 'Mexican', 'Nepalese', 'New Zealander', 'Norwegian', 'Omani',
  'Pakistani', 'Portuguese', 'Qatari', 'Saudi', 'Singaporean', 'South African',
  'Spanish', 'Sri Lankan', 'Swedish', 'Swiss', 'Thai', 'Emirati',
];

// ---------------------------------------------------------------------------
// Step status enum
// ---------------------------------------------------------------------------
enum _StepStatus { pending, current, transitioning, completed }

// ---------------------------------------------------------------------------
// InvestInPlanSheet
// ---------------------------------------------------------------------------
class InvestInPlanSheet extends StatefulWidget {
  final ModelPortfolio portfolio;
  final VoidCallback onSubscribed;

  const InvestInPlanSheet({
    super.key,
    required this.portfolio,
    required this.onSubscribed,
  });

  @override
  State<InvestInPlanSheet> createState() => _InvestInPlanSheetState();
}

class _InvestInPlanSheetState extends State<InvestInPlanSheet>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();

  // Current open step (0-indexed), -1 = none
  int _currentStep = 0;
  final Set<int> _completedSteps = {};

  // Step 1 — Personal Info
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _residencyType = 'indian_resident'; // indian_resident | nri | foreign_national

  // Step 2 — Contact
  final _phoneController = TextEditingController();
  final _telegramController = TextEditingController();
  _CountryCode _selectedCountryCode = _countryCodes.first;
  String? _phoneError;
  bool _phoneValid = false;

  // Step 3 — KYC & Investment
  String _panCategory = 'Individual';
  final _panController = TextEditingController();
  String? _panError;
  bool _panValid = false;
  DateTime? _dob;
  final _gstController = TextEditingController();
  String? _gstError;
  final _investmentController = TextEditingController();
  String? _investmentError;

  // NRI fields
  bool _hasIndianPan = true;
  final _passportController = TextEditingController();
  final _ociPioController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _postalCodeController = TextEditingController();
  bool _form60Acknowledged = false;

  // Foreign national fields
  String? _selectedNationality;

  // Step 4 — Plan Selection & Payment
  String? _selectedTier;
  bool _consentChecked = false;
  bool _loading = false;
  late RazorpayService _razorpayService;

  // Animation
  late AnimationController _progressAnimController;
  late Animation<double> _progressAnim;
  final Map<int, AnimationController> _expandControllers = {};
  final Map<int, Animation<double>> _expandAnimations = {};

  @override
  void initState() {
    super.initState();
    _razorpayService = RazorpayService(
      onResult: (success) {
        if (success) widget.onSubscribed();
      },
    );
    if (widget.portfolio.pricing.isNotEmpty) {
      _selectedTier = widget.portfolio.pricing.keys.first;
    }

    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _progressAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _progressAnimController, curve: Curves.easeOut),
    );

    // Create expand/collapse controllers for each step
    for (int i = 0; i < 4; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      _expandControllers[i] = controller;
      _expandAnimations[i] = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      );
    }
    // Open first step
    _expandControllers[0]!.value = 1.0;

    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _telegramController.dispose();
    _panController.dispose();
    _gstController.dispose();
    _investmentController.dispose();
    _passportController.dispose();
    _ociPioController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    _progressAnimController.dispose();
    for (final c in _expandControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final email = await _storage.read(key: 'user_email');
    final firstName = await _storage.read(key: 'first_name');
    final lastName = await _storage.read(key: 'last_name');
    final phone = await _storage.read(key: 'phone_number');
    final pan = await _storage.read(key: 'pan');

    if (!mounted) return;
    setState(() {
      _emailController.text = email ?? '';
      final name = [firstName ?? '', lastName ?? ''].where((s) => s.isNotEmpty).join(' ');
      _nameController.text = name;
      if (phone != null && phone.isNotEmpty) {
        _phoneController.text = phone;
        _validatePhone(phone);
      }
      if (pan != null && pan.isNotEmpty) {
        _panController.text = pan;
        _validatePan(pan);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  void _validatePhone(String value) {
    if (value.isEmpty) {
      _phoneError = null;
      _phoneValid = false;
    } else if (_selectedCountryCode.dialCode == '+91' && value.length != 10) {
      _phoneError = 'Please enter a valid 10-digit mobile number';
      _phoneValid = false;
    } else if (value.length < 7) {
      _phoneError = 'Please enter a valid mobile number';
      _phoneValid = false;
    } else {
      _phoneError = null;
      _phoneValid = true;
    }
  }

  void _validatePan(String value) {
    if (value.isEmpty) {
      _panError = null;
      _panValid = false;
    } else if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(value.toUpperCase())) {
      _panError = 'Invalid PAN format (e.g. ABCDE1234F)';
      _panValid = false;
    } else {
      _panError = null;
      _panValid = true;
    }
  }

  void _validateGst(String value) {
    if (value.isEmpty) {
      _gstError = null;
    } else if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z][Z][0-9A-Z]$')
        .hasMatch(value.toUpperCase())) {
      _gstError = 'Invalid GST format';
    } else {
      _gstError = null;
    }
  }

  void _validateInvestment(String value) {
    if (value.isEmpty) {
      _investmentError = null;
    } else {
      final amount = int.tryParse(value.replaceAll(',', ''));
      if (amount == null) {
        _investmentError = 'Enter a valid amount';
      } else if (amount < widget.portfolio.minInvestment) {
        _investmentError =
            'Minimum investment is \u20B9${NumberFormat('#,##,###').format(widget.portfolio.minInvestment)}';
      } else {
        _investmentError = null;
      }
    }
  }

  bool _isStepValid(int step) {
    switch (step) {
      case 0:
        return _nameController.text.trim().isNotEmpty &&
            _emailController.text.trim().isNotEmpty;
      case 1:
        return _phoneController.text.trim().isNotEmpty &&
            _phoneValid &&
            _phoneError == null;
      case 2:
        return _isStep3Valid();
      case 3:
        if (!_consentChecked) return false;
        if (_isFree) return true;
        return _selectedTier != null;
      default:
        return false;
    }
  }

  bool _isStep3Valid() {
    final investText = _investmentController.text.replaceAll(',', '');
    final investAmount = int.tryParse(investText);
    if (investAmount == null || investAmount < widget.portfolio.minInvestment) {
      return false;
    }

    switch (_residencyType) {
      case 'indian_resident':
        return _panCategory.isNotEmpty &&
            _panController.text.isNotEmpty &&
            _panValid &&
            _panError == null &&
            _dob != null &&
            (_gstController.text.isEmpty || _gstError == null);
      case 'nri':
        if (_hasIndianPan) {
          return _panCategory.isNotEmpty &&
              _panController.text.isNotEmpty &&
              _panValid &&
              _dob != null &&
              _passportController.text.length >= 6 &&
              _addressLine1Controller.text.isNotEmpty &&
              _cityController.text.isNotEmpty &&
              _countryController.text.isNotEmpty;
        } else {
          return _form60Acknowledged &&
              _passportController.text.length >= 6 &&
              _addressLine1Controller.text.isNotEmpty &&
              _cityController.text.isNotEmpty &&
              _countryController.text.isNotEmpty;
        }
      case 'foreign_national':
        return _form60Acknowledged &&
            _passportController.text.length >= 6 &&
            _selectedNationality != null &&
            _addressLine1Controller.text.isNotEmpty &&
            _cityController.text.isNotEmpty &&
            _countryController.text.isNotEmpty;
      default:
        return false;
    }
  }

  bool get _isFree => widget.portfolio.pricing.isEmpty;

  int get _selectedAmount =>
      _selectedTier != null ? (widget.portfolio.pricing[_selectedTier] ?? 0) : 0;

  /// All portfolios go through the same 4 steps
  List<int> get _activeSteps => [0, 1, 2, 3];
  int get _totalSteps => _activeSteps.length;

  int _nextActiveStep(int currentStepId) {
    final idx = _activeSteps.indexOf(currentStepId);
    if (idx < 0 || idx >= _activeSteps.length - 1) return currentStepId;
    return _activeSteps[idx + 1];
  }

  // ---------------------------------------------------------------------------
  // Step navigation
  // ---------------------------------------------------------------------------

  Future<void> _goToStep(int nextStep) async {
    if (nextStep == _currentStep) return;

    final prevStep = _currentStep;

    // Mark previous step as completed if going forward
    if (_activeSteps.indexOf(nextStep) > _activeSteps.indexOf(prevStep)) {
      _completedSteps.add(prevStep);
    }

    setState(() {});

    // Collapse current step
    await _expandControllers[prevStep]!.reverse();

    // Update progress bar
    _updateProgress();

    // Open next step
    setState(() => _currentStep = nextStep);
    await _expandControllers[nextStep]!.forward();
  }

  void _toggleStep(int step) {
    if (step == _currentStep) return;
    if (!_activeSteps.contains(step)) return;
    // Can only open completed steps or the next incomplete step
    if (_completedSteps.contains(step) || step == _nextIncompleteStep()) {
      _goToStep(step);
    }
  }

  int _nextIncompleteStep() {
    for (final s in _activeSteps) {
      if (!_completedSteps.contains(s)) return s;
    }
    return _activeSteps.last;
  }

  void _updateProgress() {
    final completedActive = _activeSteps.where((s) => _completedSteps.contains(s)).length;
    final target = completedActive / _totalSteps;
    _progressAnim = Tween<double>(
      begin: _progressAnim.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _progressAnimController,
      curve: Curves.easeOut,
    ));
    _progressAnimController.forward(from: 0);
  }

  _StepStatus _stepStatus(int step) {
    if (_completedSteps.contains(step)) return _StepStatus.completed;
    if (step == _currentStep) return _StepStatus.current;
    return _StepStatus.pending;
  }

  // ---------------------------------------------------------------------------
  // API calls
  // ---------------------------------------------------------------------------

  Future<void> _submitLeadUser() async {
    final payload = <String, dynamic>{
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'planName': widget.portfolio.modelName,
      'phone': _phoneController.text.trim(),
      'date': DateTime.now().toUtc().toIso8601String(),
      'residencyStatus': _residencyType,
    };

    if (_telegramController.text.trim().isNotEmpty) {
      payload['telegram'] = _telegramController.text.trim();
    }

    if (_residencyType == 'indian_resident') {
      payload['pan'] = _panController.text.trim().toUpperCase();
      payload['dateOfBirth'] = _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : '';
      if (_gstController.text.trim().isNotEmpty) {
        payload['gstNumber'] = _gstController.text.trim().toUpperCase();
      }
    } else if (_residencyType == 'nri') {
      payload['pan'] = _hasIndianPan ? _panController.text.trim().toUpperCase() : '';
      payload['dateOfBirth'] =
          _hasIndianPan && _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : '';
      payload['passportNumber'] = _passportController.text.trim();
      payload['ociPioCard'] = _ociPioController.text.trim();
      payload['overseasAddress'] = {
        'addressLine1': _addressLine1Controller.text.trim(),
        'addressLine2': _addressLine2Controller.text.trim(),
        'city': _cityController.text.trim(),
        'country': _countryController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
      };
    } else if (_residencyType == 'foreign_national') {
      payload['passportNumber'] = _passportController.text.trim();
      payload['nationality'] = _selectedNationality ?? '';
      payload['foreignAddress'] = {
        'addressLine1': _addressLine1Controller.text.trim(),
        'addressLine2': _addressLine2Controller.text.trim(),
        'city': _cityController.text.trim(),
        'country': _countryController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
      };
    }

    try {
      await AqApiService.instance.submitLeadUser(payload);
    } catch (e) {
      debugPrint('[InvestInPlanSheet] submitLeadUser error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not submit your details. Please try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handlePay() async {
    if (_loading || _selectedTier == null) return;
    setState(() => _loading = true);

    // Save user details to secure storage before payment
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      await _storage.write(key: 'user_email', value: email);
    }
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      final parts = name.split(' ');
      await _storage.write(key: 'first_name', value: parts.first);
      if (parts.length > 1) {
        await _storage.write(key: 'last_name', value: parts.sublist(1).join(' '));
      }
    }
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      await _storage.write(key: 'phone_number', value: phone);
    }
    final pan = _panController.text.trim();
    if (pan.isNotEmpty) {
      await _storage.write(key: 'pan', value: pan);
    }

    final opened = await _razorpayService.openModelPortfolioCheckout(
      planId: widget.portfolio.id,
      planName: widget.portfolio.modelName,
      strategyId: widget.portfolio.strategyId ?? widget.portfolio.id,
      pricingTier: _selectedTier!,
      amount: _selectedAmount,
    );

    if (!opened && mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to start payment. Please try again.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleFreeSubscribe() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final strategyId = widget.portfolio.strategyId ?? widget.portfolio.id;
      final email = _emailController.text.trim();

      debugPrint('[InvestInPlanSheet] _handleFreeSubscribe - portfolioId: ${widget.portfolio.id}, strategyId: $strategyId, email: $email');

      // PRIMARY: Use AQ backend subscribe-strategy API (same as web frontend)
      final response = await AqApiService.instance.subscribeStrategy(
        strategyId: widget.portfolio.id,
        email: email,
        action: 'subscribe',
      ).timeout(const Duration(seconds: 15));

      debugPrint('[InvestInPlanSheet] AQ subscribe response: ${response.statusCode} ${response.body}');

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Save user details to secure storage so portfolio list fetches with correct email
        await _storage.write(key: 'user_email', value: email);
        final name = _nameController.text.trim();
        if (name.isNotEmpty) {
          final parts = name.split(' ');
          await _storage.write(key: 'first_name', value: parts.first);
          if (parts.length > 1) {
            await _storage.write(key: 'last_name', value: parts.sublist(1).join(' '));
          }
        }
        final phone = _phoneController.text.trim();
        if (phone.isNotEmpty) {
          await _storage.write(key: 'phone_number', value: phone);
        }
        final pan = _panController.text.trim();
        if (pan.isNotEmpty) {
          await _storage.write(key: 'pan', value: pan);
        }

        // Fire-and-forget: sync to TIDI backend (non-blocking, 15s timeout)
        ApiService().subscribeFreeModelPortfolio(
          planId: widget.portfolio.id,
          strategyId: strategyId,
        ).timeout(const Duration(seconds: 15)).then((tidiResp) {
          debugPrint('[InvestInPlanSheet] TIDI subscribe sync: ${tidiResp.statusCode}');
        }).catchError((e) {
          debugPrint('[InvestInPlanSheet] TIDI subscribe sync error (non-blocking): $e');
        });

        // Save locally as defensive fallback for instant display on restart
        await _saveLocalSubscription(
          strategyId: strategyId,
          planId: widget.portfolio.id,
          modelName: widget.portfolio.modelName,
          email: email,
        );

        CacheService.instance.invalidateByPrefix('aq/admin/plan/portfolios');
        CacheService.instance.invalidateByPrefix('aq/model-portfolio/subscribed');
        CacheService.instance.invalidateByPrefix('aq/model-portfolio/strategy');
        widget.onSubscribed();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscribed successfully!'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Subscription failed. Please try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[InvestInPlanSheet] _handleFreeSubscribe error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLocalSubscription({
    required String strategyId,
    required String planId,
    required String modelName,
    required String email,
  }) async {
    try {
      final raw = await _storage.read(key: 'local_subscribed_portfolios');
      final List<dynamic> existing = raw != null ? json.decode(raw) : [];
      // Avoid duplicates
      final alreadyExists = existing.any((e) =>
          e is Map &&
          (e['strategyId'] == strategyId || e['planId'] == planId));
      if (!alreadyExists) {
        existing.add({
          'strategyId': strategyId,
          'planId': planId,
          'modelName': modelName,
          'email': email,
          'subscribedAt': DateTime.now().toUtc().toIso8601String(),
        });
        await _storage.write(
          key: 'local_subscribed_portfolios',
          value: json.encode(existing),
        );
        debugPrint('[InvestInPlanSheet] Saved local subscription: $modelName');
      }
    } catch (e) {
      debugPrint('[InvestInPlanSheet] _saveLocalSubscription error: $e');
    }
  }

  String _formatTierLabel(String tier) {
    switch (tier.toLowerCase()) {
      case 'monthly':
        return 'Monthly';
      case 'quarterly':
        return 'Quarterly';
      case 'half_yearly':
      case 'halfyearly':
        return 'Half Yearly';
      case 'yearly':
        return 'Yearly';
      case 'onetime':
      case 'one_time':
        return 'One Time';
      default:
        return tier.replaceAll('_', ' ').split(' ').map((w) =>
            w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w
        ).join(' ');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        color: const Color(0xFFF3F4F6),
        child: Column(
          children: [
            _buildHeader(),
            _buildProgressSection(),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.translucent,
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 30 + keyboardHeight),
                  children: [
                    for (int i = 0; i < _activeSteps.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildStepCard(
                        _activeSteps[i],
                        _stepTitle(_activeSteps[i]),
                        _stepSubtitle(_activeSteps[i]),
                        _stepIcon(_activeSteps[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0: return 'Personal Info';
      case 1: return 'Contact';
      case 2: return 'KYC & Investment';
      case 3: return _isFree ? 'Subscribe' : 'Plan Selection';
      default: return '';
    }
  }

  String _stepSubtitle(int step) {
    switch (step) {
      case 0: return 'Basic details';
      case 1: return 'Phone & messaging';
      case 2: return 'Verification details';
      case 3: return _isFree ? 'Confirm subscription' : 'Choose & pay';
      default: return '';
    }
  }

  IconData _stepIcon(int step) {
    switch (step) {
      case 0: return Icons.person_rounded;
      case 1: return Icons.phone_rounded;
      case 2: return Icons.verified_user_rounded;
      case 3: return Icons.payment_rounded;
      default: return Icons.circle;
    }
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top > 0 ? 16 : 20, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF4338CA)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Invest in ${widget.portfolio.modelName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Progress Section
  // ---------------------------------------------------------------------------

  Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, size: 18, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  '${_activeSteps.where((s) => _completedSteps.contains(s)).length}/$_totalSteps Complete',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: AnimatedBuilder(
                animation: _progressAnim,
                builder: (context, child) {
                  return Stack(
                    children: [
                      Container(color: Colors.grey.shade200),
                      FractionallySizedBox(
                        widthFactor: _progressAnim.value.clamp(0.0, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF4338CA)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step Card
  // ---------------------------------------------------------------------------

  Widget _buildStepCard(int step, String title, String subtitle, IconData icon) {
    final status = _stepStatus(step);
    final isOpen = step == _currentStep;

    Color iconBgStart, iconBgEnd;
    Widget statusBadge;
    IconData displayIcon;

    switch (status) {
      case _StepStatus.completed:
        iconBgStart = const Color(0xFF22C55E);
        iconBgEnd = const Color(0xFF10B981);
        displayIcon = Icons.check_rounded;
        statusBadge = _badge('Done', const Color(0xFFDCFCE7), const Color(0xFF166534));
        break;
      case _StepStatus.current:
        iconBgStart = const Color(0xFF3B82F6);
        iconBgEnd = const Color(0xFF6366F1);
        displayIcon = icon;
        statusBadge = _badge('In Progress', const Color(0xFFDBEAFE), const Color(0xFF1E40AF));
        break;
      case _StepStatus.transitioning:
        iconBgStart = const Color(0xFFF97316);
        iconBgEnd = const Color(0xFFF59E0B);
        displayIcon = icon;
        statusBadge = _badge('...', const Color(0xFFFEF3C7), const Color(0xFF92400E));
        break;
      case _StepStatus.pending:
        iconBgStart = const Color(0xFF9CA3AF);
        iconBgEnd = const Color(0xFF6B7280);
        displayIcon = Icons.access_time_rounded;
        statusBadge = const SizedBox.shrink();
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => _toggleStep(step),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [iconBgStart, iconBgEnd],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(displayIcon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(subtitle, style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  statusBadge,
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(Icons.expand_more, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ),
          // Content
          SizeTransition(
            sizeFactor: _expandAnimations[step]!,
            child: _buildStepContent(step),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _buildStepContent(int step) {
    switch (step) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Personal Info
  // ---------------------------------------------------------------------------

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Full Name'),
          _textField(
            controller: _nameController,
            hint: 'Enter your full name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 16),
          _fieldLabel('Email Address'),
          _textField(
            controller: _emailController,
            hint: 'Enter your email address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),
          _gradientButton(
            label: 'Continue to Contact',
            colors: const [Color(0xFF2563EB), Color(0xFF4F46E5)],
            onTap: _isStepValid(0) ? () => _goToStep(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _residencySelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _residencyOption(
            'indian_resident',
            'Indian Resident',
            Icons.home_rounded,
            const Color(0xFF22C55E),
            'PAN + Aadhaar',
            const Color(0xFFDCFCE7),
            const Color(0xFF166534),
          ),
          const SizedBox(height: 8),
          _residencyOption(
            'nri',
            'NRI',
            Icons.flight_rounded,
            const Color(0xFF3B82F6),
            'PAN + Passport',
            const Color(0xFFDBEAFE),
            const Color(0xFF1E40AF),
          ),
          const SizedBox(height: 8),
          _residencyOption(
            'foreign_national',
            'Foreign National',
            Icons.public_rounded,
            const Color(0xFF8B5CF6),
            'Passport Only',
            const Color(0xFFF3E8FF),
            const Color(0xFF6B21A8),
          ),
          if (_residencyType.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text(
                  'Selected: ',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  _residencyType == 'indian_resident'
                      ? 'Indian Resident'
                      : _residencyType == 'nri'
                          ? 'NRI'
                          : 'Foreign National',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _residencyOption(
    String value, String label, IconData icon, Color iconColor,
    String badgeText, Color badgeBg, Color badgeFg,
  ) {
    final isSelected = _residencyType == value;
    return InkWell(
      onTap: () {
        setState(() {
          _residencyType = value;
          // Reset KYC fields when residency changes
          _panController.clear();
          _panError = null;
          _panValid = false;
          _dob = null;
          _gstController.clear();
          _gstError = null;
          _passportController.clear();
          _ociPioController.clear();
          _addressLine1Controller.clear();
          _addressLine2Controller.clear();
          _cityController.clear();
          _countryController.clear();
          _postalCodeController.clear();
          _form60Acknowledged = false;
          _selectedNationality = null;
          _hasIndianPan = true;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? iconColor.withOpacity(0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              )),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badgeText, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: badgeFg)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? iconColor : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: iconColor,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Contact
  // ---------------------------------------------------------------------------

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Phone Number'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Country code button
              InkWell(
                onTap: _showCountryCodePicker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedCountryCode.dialCode,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more, size: 18, color: Colors.grey.shade600),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => setState(() => _validatePhone(v)),
                  decoration: InputDecoration(
                    hintText: 'Phone number',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.phone_outlined, color: Colors.grey.shade400, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: _phoneController.text.isNotEmpty
                            ? (_phoneValid ? const Color(0xFF22C55E) : Colors.red.shade400)
                            : Colors.grey.shade300,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: _phoneValid ? const Color(0xFF22C55E) : const Color(0xFF3B82F6),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          if (_phoneError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(_phoneError!,
                style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
            ),
          if (_phoneValid && _phoneError == null && _phoneController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text('Valid phone number',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade600)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _fieldLabel('Telegram ID'),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _telegramController,
                  hint: '@username (optional)',
                  icon: Icons.send_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Open Telegram > Settings > Username to find your ID',
                child: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _gradientButton(
            label: 'Continue to Investment',
            colors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
            onTap: _isStepValid(1) ? () => _goToStep(2) : null,
          ),
        ],
      ),
    );
  }

  void _showCountryCodePicker() {
    final searchController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final query = searchController.text.toLowerCase();
            final filtered = _countryCodes.where((c) =>
                c.name.toLowerCase().contains(query) ||
                c.dialCode.contains(query) ||
                c.code.toLowerCase().contains(query)).toList();
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search country...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final cc = filtered[i];
                        return ListTile(
                          leading: Text(cc.dialCode,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          title: Text(cc.name),
                          trailing: Text(cc.code,
                            style: TextStyle(color: Colors.grey.shade500)),
                          onTap: () {
                            setState(() {
                              _selectedCountryCode = cc;
                              _validatePhone(_phoneController.text);
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 — KYC & Investment
  // ---------------------------------------------------------------------------

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_residencyType == 'indian_resident') _buildIndianKyc(),
          if (_residencyType == 'nri') _buildNriKyc(),
          if (_residencyType == 'foreign_national') _buildForeignKyc(),
          const SizedBox(height: 16),
          _buildInvestmentAmountField(),
          const SizedBox(height: 20),
          _gradientButton(
            label: 'Continue to Plan',
            colors: const [Color(0xFF059669), Color(0xFF0D9488)],
            onTap: _isStepValid(2) ? () async {
              // Fire lead_user API (non-blocking)
              _submitLeadUser();
              await _goToStep(3);
            } : null,
          ),
        ],
      ),
    );
  }

  Widget _buildIndianKyc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('PAN Category'),
        const SizedBox(height: 8),
        _dropdown(
          value: _panCategory,
          items: ['Individual', 'Non-individual'],
          onChanged: (v) => setState(() => _panCategory = v!),
        ),
        const SizedBox(height: 16),
        _fieldLabel('PAN Number'),
        _textField(
          controller: _panController,
          hint: 'e.g. ABCDE1234F',
          icon: Icons.badge_outlined,
          maxLength: 10,
          caps: true,
          onChanged: (v) => setState(() => _validatePan(v)),
          errorText: _panError,
          isValid: _panValid,
        ),
        const SizedBox(height: 16),
        _fieldLabel('Date of Birth'),
        const SizedBox(height: 8),
        _datePicker(),
        const SizedBox(height: 16),
        _fieldLabel('GST Number (Optional)'),
        _textField(
          controller: _gstController,
          hint: 'e.g. 22AAAAA0000A1Z5',
          icon: Icons.receipt_long_outlined,
          maxLength: 15,
          caps: true,
          onChanged: (v) => setState(() => _validateGst(v)),
          errorText: _gstError,
        ),
      ],
    );
  }

  Widget _buildNriKyc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('PAN Category'),
        const SizedBox(height: 8),
        _dropdown(
          value: _panCategory,
          items: ['Individual', 'Non-individual'],
          onChanged: (v) => setState(() => _panCategory = v!),
        ),
        const SizedBox(height: 16),
        _fieldLabel('Do you have an Indian PAN Card?'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _radioOption('Yes', _hasIndianPan,
                    () => setState(() => _hasIndianPan = true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _radioOption('No', !_hasIndianPan,
                    () => setState(() => _hasIndianPan = false)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_hasIndianPan) ...[
          _fieldLabel('PAN Number'),
          _textField(
            controller: _panController,
            hint: 'e.g. ABCDE1234F',
            icon: Icons.badge_outlined,
            maxLength: 10,
            caps: true,
            onChanged: (v) => setState(() => _validatePan(v)),
            errorText: _panError,
            isValid: _panValid,
          ),
          const SizedBox(height: 16),
          _fieldLabel('Date of Birth'),
          const SizedBox(height: 8),
          _datePicker(),
          const SizedBox(height: 16),
        ] else ...[
          _infoBanner(
            'Form 60 will be used as an alternative to PAN card for verification.',
            const Color(0xFFFEF3C7),
            const Color(0xFF92400E),
            Icons.info_outline,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _form60Acknowledged,
            onChanged: (v) => setState(() => _form60Acknowledged = v ?? false),
            title: const Text('I acknowledge the Form 60 requirement',
              style: TextStyle(fontSize: 13)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          const SizedBox(height: 16),
        ],
        _fieldLabel('Passport Number'),
        _textField(
          controller: _passportController,
          hint: 'Passport number',
          icon: Icons.menu_book_outlined,
        ),
        const SizedBox(height: 16),
        _fieldLabel('OCI/PIO Card Number (Optional)'),
        _textField(
          controller: _ociPioController,
          hint: 'OCI/PIO card number',
          icon: Icons.credit_card_outlined,
        ),
        const SizedBox(height: 16),
        _fieldLabel('Overseas Address'),
        const SizedBox(height: 8),
        _buildAddressFields(),
        const SizedBox(height: 12),
        _infoBanner(
          'Your documents will be verified within 2-3 business days.',
          const Color(0xFFFEF9C3),
          const Color(0xFF713F12),
          Icons.verified_outlined,
        ),
      ],
    );
  }

  Widget _buildForeignKyc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBanner(
          'Form 60 is used as an alternative identity verification document for foreign nationals.',
          const Color(0xFFF3E8FF),
          const Color(0xFF6B21A8),
          Icons.description_outlined,
        ),
        const SizedBox(height: 16),
        _fieldLabel('Passport Number'),
        _textField(
          controller: _passportController,
          hint: 'Passport number',
          icon: Icons.menu_book_outlined,
        ),
        const SizedBox(height: 16),
        _fieldLabel('Nationality'),
        const SizedBox(height: 8),
        _dropdown(
          value: _selectedNationality,
          items: _nationalities,
          onChanged: (v) => setState(() => _selectedNationality = v),
          hint: 'Select nationality',
        ),
        const SizedBox(height: 16),
        _fieldLabel('Foreign Address'),
        const SizedBox(height: 8),
        _buildAddressFields(),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _form60Acknowledged,
          onChanged: (v) => setState(() => _form60Acknowledged = v ?? false),
          title: const Text('I acknowledge the Form 60 requirement',
            style: TextStyle(fontSize: 13)),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          activeColor: const Color(0xFF8B5CF6),
        ),
        const SizedBox(height: 12),
        _infoBanner(
          'Your documents will be verified within 2-3 business days.',
          const Color(0xFFFEF9C3),
          const Color(0xFF713F12),
          Icons.verified_outlined,
        ),
      ],
    );
  }

  Widget _buildAddressFields() {
    return Column(
      children: [
        _textField(
          controller: _addressLine1Controller,
          hint: 'Address Line 1',
          icon: Icons.location_on_outlined,
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _addressLine2Controller,
          hint: 'Address Line 2 (optional)',
          icon: Icons.location_on_outlined,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: _cityController,
                hint: 'City',
                icon: Icons.location_city_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _textField(
                controller: _countryController,
                hint: 'Country',
                icon: Icons.flag_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _postalCodeController,
          hint: 'Postal Code',
          icon: Icons.markunread_mailbox_outlined,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  Widget _buildInvestmentAmountField() {
    final formatter = NumberFormat('#,##,###');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Investment Amount'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Minimum investment: \u20B9${formatter.format(widget.portfolio.minInvestment)}',
                style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _textField(
          controller: _investmentController,
          hint: 'Enter amount',
          icon: Icons.currency_rupee,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) => setState(() => _validateInvestment(v)),
          errorText: _investmentError,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 — Plan Selection & Payment
  // ---------------------------------------------------------------------------

  Widget _buildStep4() {
    final pricing = widget.portfolio.pricing;
    final formatter = NumberFormat('#,##,###');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isFree) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E7D32), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Color(0xFF2E7D32), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Free Portfolio', style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                        Text('No subscription fee required',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text('Choose Your Plan', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 12),
            ...pricing.entries.map((entry) {
              final tier = entry.key;
              final amount = entry.value;
              final isSelected = _selectedTier == tier;
              return GestureDetector(
                onTap: _loading ? null : () => setState(() => _selectedTier = tier),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF2E7D32).withOpacity(0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Center(child: Container(
                                width: 12, height: 12,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle, color: Color(0xFF2E7D32)),
                              ))
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(_formatTierLabel(tier), style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFF2E7D32) : Colors.black87)),
                      ),
                      Text('\u20B9${formatter.format(amount)}', style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: isSelected ? const Color(0xFF2E7D32) : Colors.black87)),
                    ],
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          // Consent checkbox
          CheckboxListTile(
            value: _consentChecked,
            onChanged: (v) => setState(() => _consentChecked = v ?? false),
            title: const Text(
              'I agree to the disclaimers and terms of service',
              style: TextStyle(fontSize: 13),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: const Color(0xFF2E7D32),
          ),
          const SizedBox(height: 16),
          // Pay / Subscribe button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isStepValid(3)
                  ? (_isFree ? _handleFreeSubscribe : _handlePay)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      _isFree
                          ? 'Subscribe for Free'
                          : _selectedTier != null
                              ? 'Pay \u20B9${formatter.format(_selectedAmount)}'
                              : 'Select a plan',
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
            ),
          ),
          if (!_isFree) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('Secured by Razorpay',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared field widgets
  // ---------------------------------------------------------------------------

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool readOnly = false,
    TextInputType? keyboardType,
    int? maxLength,
    bool caps = false,
    ValueChanged<String>? onChanged,
    String? errorText,
    bool isValid = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final formatters = <TextInputFormatter>[
      if (caps) TextInputFormatter.withFunction(
        (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
      ),
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ...?inputFormatters,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          inputFormatters: formatters.isNotEmpty ? formatters : null,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            suffixIcon: isValid
                ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 20)
                : null,
            filled: readOnly,
            fillColor: readOnly ? Colors.grey.shade100 : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorText != null
                    ? Colors.red.shade400
                    : isValid
                        ? const Color(0xFF22C55E)
                        : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: errorText != null
                    ? Colors.red.shade400
                    : const Color(0xFF3B82F6),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(errorText,
              style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
          ),
      ],
    );
  }

  Widget _dropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? hint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : null,
          isExpanded: true,
          hint: Text(hint ?? 'Select', style: TextStyle(color: Colors.grey.shade400)),
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 14)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _datePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dob ?? DateTime(1990, 1, 1),
          firstDate: DateTime(1920),
          lastDate: DateTime.now(),
        );
        if (picked != null) setState(() => _dob = picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: _dob != null ? const Color(0xFF22C55E) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 20, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Text(
              _dob != null ? DateFormat('dd MMM yyyy').format(_dob!) : 'Select date of birth',
              style: TextStyle(
                fontSize: 14,
                color: _dob != null ? Colors.black87 : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radioOption(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF3B82F6) : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? const Color(0xFF1E40AF) : Colors.grey.shade600,
          )),
        ),
      ),
    );
  }

  Widget _infoBanner(String text, Color bg, Color fg, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required List<Color> colors,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? colors
                : [Colors.grey.shade300, Colors.grey.shade300],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.grey.shade500,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
