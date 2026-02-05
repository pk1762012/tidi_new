import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

import '../../../../theme/theme.dart';

class LumpsumCalculatorPage extends StatefulWidget {
  @override
  State<LumpsumCalculatorPage> createState() => _LumpsumCalculatorPageState();
}

class _LumpsumCalculatorPageState extends State<LumpsumCalculatorPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController amountController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController yearsController = TextEditingController();

  double investedAmount = 0;
  double returns = 0;
  bool showChart = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
  }

  void calculate() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(amountController.text);
    final rate = double.parse(rateController.text) / 100;
    final years = int.parse(yearsController.text);

    final futureValue = amount * pow((1 + rate), years);

    setState(() {
      investedAmount = amount;
      returns = futureValue - amount;
      showChart = true;
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
        title: Text("Lumpsum Calculator"),
        backgroundColor: lightColorScheme.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Investment Amount - up to 2 decimals
                _buildField(
                  controller: amountController,
                  label: "Investment Amount (₹)",
                  error: "Enter amount",
                  icon: Icons.savings,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                SizedBox(height: 16),

                // Expected Annual Return - up to 2 decimals
                _buildField(
                  controller: rateController,
                  label: "Expected Annual Return (%)",
                  error: "Enter return %",
                  icon: Icons.percent,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                SizedBox(height: 16),

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
                SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: lightColorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: calculate,
                    child: Text(
                      "Calculate",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                SizedBox(height: 24),

                if (showChart)
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Column(
                        children: [
                          Text(
                            "Total Invested: ₹${investedAmount.toStringAsFixed(2)}",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Estimated Returns: ₹${returns.toStringAsFixed(2)}",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Maturity Amount: ₹${(investedAmount + returns).toStringAsFixed(2)}",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 20),

                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                )
                              ],
                            ),
                            child: SizedBox(
                              height: 260,
                              child: PieChart(
                                PieChartData(
                                  centerSpaceRadius: 55,
                                  sectionsSpace: 2,
                                  sections: [
                                    PieChartSectionData(
                                      value: investedAmount,
                                      color: lightColorScheme.primary,
                                      radius: 70,
                                      title: "Invested",
                                      titleStyle: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                    PieChartSectionData(
                                      value: returns,
                                      color: lightColorScheme.secondary,
                                      radius: 70,
                                      title: "Returns",
                                      titleStyle: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
