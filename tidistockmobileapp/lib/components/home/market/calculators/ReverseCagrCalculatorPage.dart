import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../../../../theme/theme.dart';

class ReverseCagrCalculatorPage extends StatefulWidget {
  @override
  State<ReverseCagrCalculatorPage> createState() =>
      _ReverseCagrCalculatorPageState();
}

class _ReverseCagrCalculatorPageState extends State<ReverseCagrCalculatorPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController initialController = TextEditingController();
  final TextEditingController cagrController = TextEditingController();
  final TextEditingController yearsController = TextEditingController();

  double finalValue = 0;
  bool showResult = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);

    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
  }

  void calculateReverseCAGR() {
    if (!_formKey.currentState!.validate()) return;

    final initial = double.parse(initialController.text);
    final cagr = double.parse(cagrController.text) / 100;
    final years = int.parse(yearsController.text);

    final result = initial * pow(1 + cagr, years);

    setState(() {
      finalValue = result;
      showResult = true;
      _animController.forward(from: 0);
    });
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String error,
    IconData? icon,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType ?? TextInputType.numberWithOptions(decimal: true),
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: lightColorScheme.primary) : null,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? error : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reverse CAGR Calculator"),
        backgroundColor: lightColorScheme.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Initial Investment - up to 2 decimals
                _buildField(
                  controller: initialController,
                  label: "Initial Investment",
                  error: "Enter initial amount",
                  icon: Icons.currency_rupee,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),

                // Expected CAGR (%) - up to 2 decimals
                _buildField(
                  controller: cagrController,
                  label: "Expected CAGR (%)",
                  error: "Enter CAGR",
                  icon: Icons.percent,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),

                // Time Period (Years) - whole numbers only
                _buildField(
                  controller: yearsController,
                  label: "Time Period (Years)",
                  error: "Enter years",
                  icon: Icons.calendar_month,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: lightColorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: calculateReverseCAGR,
                    child: const Text(
                      "Calculate",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                if (showResult)
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "Final Value",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "₹ ${finalValue.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: lightColorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
