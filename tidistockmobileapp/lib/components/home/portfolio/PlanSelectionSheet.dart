import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tidistockmobileapp/models/model_portfolio.dart';

import '../../../service/RazorPayService.dart';

class PlanSelectionSheet extends StatefulWidget {
  final ModelPortfolio portfolio;
  final VoidCallback onSubscribed;

  const PlanSelectionSheet({
    super.key,
    required this.portfolio,
    required this.onSubscribed,
  });

  @override
  State<PlanSelectionSheet> createState() => _PlanSelectionSheetState();
}

class _PlanSelectionSheetState extends State<PlanSelectionSheet> {
  String? _selectedTier;
  bool _loading = false;
  late RazorpayService _razorpayService;

  @override
  void initState() {
    super.initState();
    _razorpayService = RazorpayService(
      onResult: (success) {
        if (success) {
          widget.onSubscribed();
        }
      },
    );
    // Auto-select first tier
    if (widget.portfolio.pricing.isNotEmpty) {
      _selectedTier = widget.portfolio.pricing.keys.first;
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

  int get _selectedAmount =>
      _selectedTier != null ? (widget.portfolio.pricing[_selectedTier] ?? 0) : 0;

  Future<void> _handlePay() async {
    if (_loading || _selectedTier == null) return;
    setState(() => _loading = true);

    debugPrint('[PlanSelectionSheet] _handlePay - tier: $_selectedTier, amount: $_selectedAmount');
    debugPrint('[PlanSelectionSheet] planId: ${widget.portfolio.id}, strategyId: ${widget.portfolio.strategyId}');

    final opened = await _razorpayService.openModelPortfolioCheckout(
      planId: widget.portfolio.id,
      planName: widget.portfolio.modelName,
      strategyId: widget.portfolio.strategyId ?? widget.portfolio.id,
      pricingTier: _selectedTier!,
      amount: _selectedAmount,
    );

    debugPrint('[PlanSelectionSheet] checkout opened: $opened');

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

  @override
  Widget build(BuildContext context) {
    final pricing = widget.portfolio.pricing;
    final formatter = NumberFormat('#,##,###');

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
                // Handle bar
                Container(
                  width: 55,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                // Portfolio info
                Row(
                  children: [
                    if (widget.portfolio.image != null &&
                        widget.portfolio.image!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          widget.portfolio.image!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderIcon(),
                        ),
                      )
                    else
                      _placeholderIcon(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.portfolio.modelName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Title
                const Text(
                  "Choose Your Plan",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 16),

                // Pricing tier cards
                ...pricing.entries.map((entry) {
                  final tier = entry.key;
                  final amount = entry.value;
                  final isSelected = _selectedTier == tier;

                  return GestureDetector(
                    onTap: _loading
                        ? null
                        : () => setState(() => _selectedTier = tier),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2E7D32).withOpacity(0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 6,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                            color: Colors.black.withOpacity(0.05),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Radio indicator
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? Center(
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF2E7D32),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _formatTierLabel(tier),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? const Color(0xFF2E7D32)
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            "\u20B9${formatter.format(amount)}",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? const Color(0xFF2E7D32)
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // Pay button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        (_loading || _selectedTier == null) ? null : _handlePay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _selectedTier != null
                                ? "Pay \u20B9${formatter.format(_selectedAmount)}"
                                : "Select a plan",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Secured by Razorpay
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      "Secured by Razorpay",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.account_balance,
          size: 24, color: Color(0xFF3F51B5)),
    );
  }
}
