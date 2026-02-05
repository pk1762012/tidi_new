import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

import '../../../../theme/theme.dart';

class EmiBreakdown {
  final int month;
  final double emi;
  final double interest;
  final double principal;
  final double balance;

  EmiBreakdown({
    required this.month,
    required this.emi,
    required this.interest,
    required this.principal,
    required this.balance,
  });
}

class LoanCalculatorPage extends StatefulWidget {
  @override
  State<LoanCalculatorPage> createState() => _LoanCalculatorPageState();
}

class _LoanCalculatorPageState extends State<LoanCalculatorPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController principalController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController yearsController = TextEditingController();
  final TextEditingController monthsController = TextEditingController(text: '0');

  double emi = 0;
  double totalInterest = 0;
  double totalPayment = 0;
  bool showResult = false;

  List<EmiBreakdown> schedule = [];

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

  void calculateLoan() {
    if (!_formKey.currentState!.validate()) return;

    final principal = double.parse(principalController.text);
    final annualRate = double.parse(rateController.text);
    final years = int.parse(yearsController.text.isEmpty ? '0' : yearsController.text);
    final months = int.parse(monthsController.text.isEmpty ? '0' : monthsController.text);

    final totalMonths = years * 12 + months;

    if (totalMonths <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tenure must be greater than 0")),
      );
      return;
    }

    final monthlyRate = annualRate / 12 / 100;

    final emiValue = principal * monthlyRate * pow(1 + monthlyRate, totalMonths) /
        (pow(1 + monthlyRate, totalMonths) - 1);

    double balance = principal;
    List<EmiBreakdown> temp = [];

    for (int i = 1; i <= totalMonths; i++) {
      final interest = balance * monthlyRate;
      final principalPaid = emiValue - interest;
      balance -= principalPaid;

      temp.add(
        EmiBreakdown(
          month: i,
          emi: emiValue,
          interest: interest,
          principal: principalPaid,
          balance: balance < 0 ? 0 : balance,
        ),
      );
    }

    final totalPay = emiValue * totalMonths;
    final interestPay = totalPay - principal;

    setState(() {
      emi = emiValue;
      totalInterest = interestPay;
      totalPayment = totalPay;
      schedule = temp;
      showResult = true;
      _animController.forward(from: 0);
    });
  }

  // Custom field with optional allowZero flag
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String error,
    required IconData icon,
    int decimal = 2,
    bool allowZero = false,
    int? maxValue, // optional max value
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal > 0),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: lightColorScheme.primary),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return error;

        if (decimal > 0) {
          final regex = RegExp(r'^\d+(\.\d{1,' + decimal.toString() + r'})?$');
          if (!regex.hasMatch(v.trim())) return "Enter valid number";
        } else {
          if (!RegExp(r'^\d+$').hasMatch(v.trim())) return "Enter valid number";

          final value = int.parse(v.trim());
          if (!allowZero && value <= 0) return "Must be greater than 0";

          if (maxValue != null && value > maxValue) return "Max value is $maxValue";
        }

        return null;
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Loan EMI Calculator"),
        backgroundColor: lightColorScheme.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildField(
                  controller: principalController,
                  label: "Loan Amount",
                  error: "Enter loan amount",
                  icon: Icons.currency_rupee,
                  decimal: 2,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: rateController,
                  label: "Interest Rate (%)",
                  error: "Enter interest rate",
                  icon: Icons.percent,
                  decimal: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        controller: yearsController,
                        label: "Tenure (Years)",
                        error: "Enter valid number",
                        icon: Icons.calendar_today,
                        decimal: 0,
                        allowZero: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                        controller: monthsController,
                        label: "Tenure (Months)",
                        error: "Enter valid number",
                        icon: Icons.calendar_view_month,
                        decimal: 0,
                        maxValue: 11,
                        allowZero: true,
                      ),
                    ),
                  ],
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
                    onPressed: calculateLoan,
                    child: const Text(
                      "Calculate",
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (showResult)
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Column(
                        children: [
                          Container(
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
                                Text("Monthly EMI: ₹${emi.toStringAsFixed(2)}"),
                                Text(
                                    "Total Interest: ₹${totalInterest.toStringAsFixed(2)}"),
                                Text(
                                  "Total Payment: ₹${totalPayment.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 240,
                                  child: PieChart(
                                    PieChartData(
                                      centerSpaceRadius: 50,
                                      sectionsSpace: 2,
                                      sections: [
                                        PieChartSectionData(
                                          value: totalInterest,
                                          title: "Interest",
                                          color: Colors.redAccent,
                                          radius: 70,
                                        ),
                                        PieChartSectionData(
                                          value: totalPayment - totalInterest,
                                          title: "Principal",
                                          color: Colors.blueAccent,
                                          radius: 70,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          ExpansionTile(
                            title: const Text(
                              "Monthly EMI Breakdown",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            children: [
                              SizedBox(
                                height: 400,
                                child: ListView.builder(
                                  itemCount: schedule.length,
                                  itemBuilder: (context, index) {
                                    final item = schedule[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(12)),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor:
                                          lightColorScheme.secondary,
                                          child: Text(
                                            item.month.toString(),
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                                        title: Text(
                                            "EMI: ₹${item.emi.toStringAsFixed(2)}"),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                "Principal: ₹${item.principal.toStringAsFixed(2)}"),
                                            Text(
                                                "Interest: ₹${item.interest.toStringAsFixed(2)}"),
                                            Text(
                                                "Balance: ₹${item.balance.toStringAsFixed(2)}"),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            ],
                          )
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
