import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

import 'package:tidistockmobileapp/theme/theme.dart';

class SipCalculatorPage extends StatefulWidget {
  @override
  State<SipCalculatorPage> createState() => _SipCalculatorPageState();
}

class _SipCalculatorPageState extends State<SipCalculatorPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController sipController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController yearsController = TextEditingController();

  double invested = 0;
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

    final sip = double.parse(sipController.text);
    final rate = double.parse(rateController.text) / 100 / 12;
    final months = int.parse(yearsController.text) * 12;

    double futureValue =
        sip * ((pow(1 + rate, months) - 1) / rate) * (1 + rate);
    double totalInvested = sip * months;

    setState(() {
      invested = totalInvested;
      returns = futureValue - totalInvested;
      showChart = true;
      _animController.forward(from: 0);
    });
  }

  Widget _buildTextField({
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
        title: Text("SIP Calculator"),
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
                // SIP Amount - allow up to 2 decimals
                _buildTextField(
                  controller: sipController,
                  label: "Monthly SIP Amount",
                  error: "Enter SIP amount",
                  icon: Icons.savings,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                SizedBox(height: 16),

                // Expected Annual Return - allow up to 2 decimals
                _buildTextField(
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

                // Years - whole numbers only
                _buildTextField(
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
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                            "Total Invested: ₹${invested.toStringAsFixed(2)}",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Estimated Returns: ₹${returns.toStringAsFixed(2)}",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Maturity Amount: ₹${(invested + returns).toStringAsFixed(2)}",
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
                                  centerSpaceRadius: 60,
                                  sectionsSpace: 2,
                                  sections: [
                                    PieChartSectionData(
                                      value: invested,
                                      color: lightColorScheme.primary,
                                      radius: 70,
                                      title: "Invested",
                                      titleStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    PieChartSectionData(
                                      value: returns,
                                      color: lightColorScheme.secondary,
                                      radius: 70,
                                      title: "Returns",
                                      titleStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
