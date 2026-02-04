import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../service/ApiService.dart';
import '../../../theme/theme.dart';

class PanCollectDialog extends StatefulWidget {
  const PanCollectDialog({super.key});

  @override
  State<PanCollectDialog> createState() => _PanCollectDialogState();
}

class _PanCollectDialogState extends State<PanCollectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _panController = TextEditingController();
  final _emailController = TextEditingController();

  bool saving = false;
  final storage = const FlutterSecureStorage();

  @override
  void dispose() {
    _panController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final api = ApiService();

      final response = await api.savePanDetails(
        _panController.text.trim(),
        _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      );

      if (response.statusCode == 200) {
        await storage.write(
          key: 'pan',
          value: _panController.text.trim(),
        );

        Navigator.pop(context);
      } else {
        throw Exception("API failed");
      }
    } catch (e) {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to save PAN details")),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Complete Your Profile",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: lightColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),

                /// SEBI COMPLIANCE MESSAGE
                const Text(
                  "As per SEBI regulations, PAN is mandatory to access stock recommendations and investment advice.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 20),

                /// PAN FIELD
                TextFormField(
                  controller: _panController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 10,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    UpperCaseTextFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: "PAN Number *",
                    hintText: "ABCDE1234F",
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "PAN is required";
                    }

                    final panRegex =
                    RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

                    if (!panRegex.hasMatch(value.trim())) {
                      return "Enter a valid PAN (e.g. ABCDE1234F)";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                /// EMAIL (OPTIONAL)
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email (optional)",
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return null; // optional
                    }

                    final emailRegex = RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                    );

                    if (!emailRegex.hasMatch(value.trim())) {
                      return "Enter a valid email address";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text("Save & Continue"),
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

/// 🔠 Forces uppercase input (important for PAN)
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
