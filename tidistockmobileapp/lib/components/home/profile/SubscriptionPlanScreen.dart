import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:tidistockmobileapp/theme/theme.dart';
import '../../../service/RazorPayService.dart';

void showSubscriptionBottomCurtain(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const SubscriptionBottomCurtain(),
  );
}

class SubscriptionBottomCurtain extends StatefulWidget {
  const SubscriptionBottomCurtain({super.key});

  @override
  State<SubscriptionBottomCurtain> createState() =>
      _SubscriptionBottomCurtainState();
}

class _SubscriptionBottomCurtainState extends State<SubscriptionBottomCurtain> {
  String selectedPlan = "";
  bool _loading = false;

  late RazorpayService razorpayService;

  @override
  void initState() {
    super.initState();
    razorpayService = RazorpayService(
      onResult: (success) {
        // Service handles navigation on success and SnackBar on failure
      },
    );
  }

  @override
  void dispose() {
    // Do NOT dispose razorpayService here — listeners must survive
    // after the bottom sheet closes so Razorpay callbacks still fire.
    super.dispose();
  }

  // Convert keys to BACKEND Razorpay parameter
  String mapPlanToBackend(String key) {
    switch (key) {
      case "monthly":
        return "MONTHLY";
      case "half_yearly":
        return "HALF_YEARLY";
      case "yearly":
        return "YEARLY";
      default:
        return "MONTHLY";
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          color: Colors.white,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle Bar
                Container(
                  width: 55,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                // Title
                Text(
                  "Choose Your Membership Plan",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: lightColorScheme.primary,
                  ),
                ),

                const SizedBox(height: 20),

                // Plan Tiles
                _planTile("1 Month", "₹249", "monthly"),
                _planTile("6 Months", "₹1399", "half_yearly", tag: "Save 8%"),
                _planTile("12 Months", "₹2799", "yearly", tag: "Save 15%"),

                const SizedBox(height: 24),

                // Offline Benefits Section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Offline Membership Benefits",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: lightColorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _benefitItem("Access to free Stock Market Workshops"),
                    _benefitItem("Visit any branch and get in-person guidance"),
                    _benefitItem("Mentorship from professional traders"),
                    _benefitItem("Discounts on Trading Floor Charges"),
                    _benefitItem("Exclusive offline learning materials"),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------- PLAN TILE -------------------------------
  Widget _planTile(String title, String price, String key, {String? tag}) {
    bool isSelected = selectedPlan == key;
    bool isLoading = _loading && selectedPlan == key;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _loading
          ? null
          : () async {
              setState(() {
                selectedPlan = key;
                _loading = true;
              });

              String backendKey = mapPlanToBackend(key);
              final opened = await razorpayService.openCheckout(backendKey);

              if (opened) {
                if (mounted) Navigator.pop(context);
              } else {
                if (mounted) setState(() => _loading = false);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 3),
              color: Colors.black.withOpacity(0.07),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? colorScheme.primary : Colors.black87,
                    ),
                  ),

                  if (tag != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Text(
                price,
                style: TextStyle(
                  fontSize: 18,
                  color: isSelected ? colorScheme.primary : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isSelected ? colorScheme.primary : Colors.grey.shade600,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------- BENEFIT ITEM -------------------------------
  Widget _benefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "• ",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
