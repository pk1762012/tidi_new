import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tidistockmobileapp/theme/theme.dart';

class DisclaimerScreen extends StatelessWidget {
  final VoidCallback onAccept;
  final Future<void> Function() onDecline;

  const DisclaimerScreen({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("Disclaimer"),
        backgroundColor: lightColorScheme.onSecondary,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          color: lightColorScheme.onSecondary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [


                // Disclaimer text
                Expanded(
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: '''
**Important Notice**

By using the TIDI Wealth application (“App”), you acknowledge and agree to the following:

1. **SEBI Registration**
TIDI Wealth provides research analysis, stock recommendations, and PMS-related services through a 
**SEBI-Registered Research Analyst (RA)** and/or **SEBI-Registered Portfolio Manager (PMS)**.
Registration details are available on the SEBI website.

2. **Nature of Services**
The app may provide:
• Research-based stock recommendations  
• Model portfolios  
• General investment insights  
• PMS-related information  

However, the recommendations provided are **general in nature** and **not personalised investment advice**.

3. **Risk Disclosure**
Investments in securities markets are subject to market risks.  
Past performance does not guarantee future results.  
Stock markets may be volatile, and you may lose part or all of your capital.

4. **No Guarantee of Returns**
We DO NOT guarantee:
• Accuracy of information  
• Future performance  
• Minimum or fixed returns (including 0.1%–0.2% daily/weekly/monthly returns or any assured return)  

Any such guarantee is strictly prohibited by SEBI.

5. **Conflicts of Interest Disclosure**
As per SEBI RA Regulations:
• The Research Analyst may hold positions in the securities recommended.  
• Such holdings, if any, will be disclosed as required under SEBI rules.  
• No unfair or misleading recommendations are made.

6. **Data Source & Delays**
Market data shown in the app may be:
• Sourced from third-party data providers  
• Delayed up to 15 minutes  
• Not guaranteed for completeness or accuracy  

This data must not be relied upon for actual trading.

7. **User Responsibility**
You are solely responsible for:
• Your investment decisions  
• Verification of information  
• Assessing your risk tolerance  

TIDI Wealth and its creators shall not be liable for any loss or damage arising from use of the app.

8. **PMS Disclosure**
If you opt for PMS:
• The Portfolio Manager will provide a separate PMS agreement  
• PMS carries significant market risks  
• Fees, charges, and performance-based fees (if any) will be disclosed separately  

9. **Age & Compliance**
You confirm that you are **18 years or older** for investment-related features.  
Users must comply with all applicable laws and SEBI guidelines.

---

By tapping **“I Accept”**, you agree to these terms.  
If you tap **“Decline”**, you will be logged out and returned to the login screen.

''',


                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                        h2: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Accept / Decline buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("I Accept"),
                        onPressed: onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        label: const Text("Decline"),
                        onPressed: () async {
                          await onDecline();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
