import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../service/ApiService.dart';
import '../../../service/RazorPayService.dart';
import '../../../theme/theme.dart';
import '../../../widgets/customScaffold.dart';
import 'QrImageWidget.dart';

class WorkshopPage extends StatefulWidget {
  const WorkshopPage({super.key});

  @override
  State<WorkshopPage> createState() => _WorkshopPageState();
}

class _WorkshopPageState extends State<WorkshopPage>
    with SingleTickerProviderStateMixin {
  DateTime? selectedDate;

  List<dynamic> branches = [];

  late RazorpayService razorpayService;


  /// full registration records
  List<Map<String, dynamic>> registrations = [];

  /// fast lookup (date_branch)
  Set<String> registeredKeys = {};

  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));

    _initData();

    razorpayService = RazorpayService(onResult: (success) {
      if (!mounted) return;
      setState(() {});
      if (success) _loadRegistrations();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
  }

  Future<void> _initData() async {
    await _loadBranches();        // ✅ first
    await _loadRegistrations();   // ✅ then
  }


  @override
  void dispose() {
    _controller.dispose();
    if (!razorpayService.isProcessing) razorpayService.dispose();
    super.dispose();
  }

  // ---------------- DATA ----------------

  Future<void> _loadBranches() async {
    final res = await ApiService().getBranches();
    if (res.statusCode == 200) {
      branches = json.decode(res.body)['data'];
      setState(() {});
    }
  }

  Future<void> _loadRegistrations() async {
    final res = await ApiService().getRegisteredWorkshops();
    if (res.statusCode != 200) return;

    final List data = json.decode(res.body);

    registrations.clear();
    registeredKeys.clear();

    for (final w in data) {
      final date = w['date'];
      final branchId = w['branch']?['id'];
      final id = w['id'];

      if (date != null && branchId != null) {
        registrations.add({
          'id': id,
          'date': date,
          'branchId': branchId,
          'branchName': _branchName(branchId),
        });

        registeredKeys.add("${date}_$branchId");
      }
    }

    setState(() {});
  }

  String _branchName(String branchId) {
    final b = branches.firstWhere(
          (e) => e['id'] == branchId,
      orElse: () => null,
    );
    return b?['name']?.toString() ?? 'Branch';
  }

  String formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  // ---------------- DATE ----------------

  DateTime _getNextSunday() {
    DateTime d = DateTime.now();
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }

  bool _alreadyRegisteredForDate(String date) {
    return registrations.any((r) => r['date'] == date);
  }

  // ---------------- REGISTER ----------------

  Future<bool> _register(String branchId) async {
    final date = selectedDate!.toIso8601String().substring(0, 10);

    /// already registered for same day
    if (_alreadyRegisteredForDate(date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.black,
          content: Text(
            "You have already registered for the Workshop.",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );

      return false;
    }

    return razorpayService.openWorkshopCheckout(date, branchId);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      menu: null,
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _aboutCard(),
                const SizedBox(height: 24),
                _registerCTA(),
                const SizedBox(height: 24),

                if (_upcoming.isNotEmpty) _ticketSection(),
                if (_completed.isNotEmpty) _completedSection(),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- SECTIONS ----------------

  List<Map<String, dynamic>> get _upcoming {
    final today = DateTime.now();
    return registrations.where((r) {
      final d = DateTime.parse(r['date']);
      return d.isAfter(today);
    }).toList();
  }

  List<Map<String, dynamic>> get _completed {
    final today = DateTime.now();
    return registrations.where((r) {
      final d = DateTime.parse(r['date']);
      return d.isBefore(today);
    }).toList();
  }

  Widget _ticketSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Workshop Ticket",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._upcoming.map(_ticketCard),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _completedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Workshops Attended",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._completed.map(_completedCard),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _ticketCard(Map<String, dynamic> r) {
    return GestureDetector(
      onTap: () => _showTicketPopup(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: lightColorScheme.primary.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number,
                color: Colors.black, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Workshop Confirmed",
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r['branchName'],
                    style: const TextStyle(color: Colors.black87),
                  ),
                  Text(
                      "${formatDate(r['date'])}",
                      style: const TextStyle(color: Colors.black87),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.black87, size: 16),
          ],
        ),
      ),
    );
  }


  Widget _completedCard(Map<String, dynamic> r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Workshop Completed",
                style: TextStyle(fontWeight: FontWeight.w600)),
            Text("${r['branchName']} • ${formatDate(r['date'])}"),
          ])
        ],
      ),
    );
  }



  // ---------------- CTA ----------------

  Widget _registerCTA() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _openRegisterSheet,
        style: ElevatedButton.styleFrom(
          backgroundColor: lightColorScheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: const Text("Register for Workshop",
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }


// Make sure this is imported


  void _showTicketPopup(Map<String, dynamic> r) {
    // Prepare QR data
    final qrData = jsonEncode({
      "id": r['id'],
      "branch": r['branchName'],
      "date": r['date'],
      "time": "10:00 AM – 1:00 PM",
      "mode": "Offline",
    });

    // Generate QR code object
    final qrCode = QrCode.fromData(
      data: qrData,
      errorCorrectLevel: 1, // L=1, adjust as needed
    );
    final qrImage = QrImage.withMaskPattern(qrCode, 0); // mask pattern 0

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      lightColorScheme.primary.withOpacity(0.3),
                      lightColorScheme.secondary.withOpacity(0.3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        size: 48, color: Colors.white),
                    const SizedBox(height: 12),
                    const Text(
                      "Workshop Entry Pass",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),

                    _ticketRow("Branch", r['branchName']),
                    _ticketRow("Date", "${formatDate(r['date'])}"),
                    _ticketRow("Time", "10:00 AM – 1:00 PM"),
                    _ticketRow("Mode", "Offline"),
                    const SizedBox(height: 20),

                    // QR Code
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: QrImageWidget(
                        qrImage: qrImage,
                        size: 140,
                        darkColor: lightColorScheme.primary,
                        lightColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 18),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withOpacity(0.2),
                      ),
                      child: const Text(
                        "Show this ticket at branch reception",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          "Done",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: lightColorScheme.primary,
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
      },
    );
  }


// Helper method for ticket rows
  Widget _ticketRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          )
        ],
      ),
    );
  }






  // ---------------- BOTTOM SHEET ----------------

  void _openRegisterSheet() {
    DateTime tempDate = _getNextSunday();
    String? selectedBranchId;
    bool isRegistering = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /// TITLE
                    const Text(
                      "Register",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// DATE PICKER
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        "Date: ${tempDate.toString().substring(0, 10)}",
                      ),
                      onPressed: isRegistering
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: tempDate,
                                firstDate: tempDate,
                                lastDate: tempDate.add(const Duration(days: 90)),
                                selectableDayPredicate: (d) =>
                                d.weekday == DateTime.sunday,
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        surface: Colors.white,
                                        primary: Colors.black,
                                        onPrimary: Colors.white,
                                        onSurface: Colors.black,
                                      ),
                                      dialogBackgroundColor: Colors.white,
                                    ),
                                    child: child!,
                                  );
                                },
                              );

                              if (picked != null) {
                                setDialog(() => tempDate = picked);
                              }
                            },
                    ),

                    const SizedBox(height: 16),

                    /// BRANCH DROPDOWN
                    DropdownButtonFormField<String>(
                      hint: const Text("Select Branch"),
                      value: selectedBranchId,
                      dropdownColor: Colors.white,
                      items: branches.map<DropdownMenuItem<String>>((b) {
                        return DropdownMenuItem<String>(
                          value: b['id'].toString(),
                          child: Text(
                            b['name'].toString(),
                            style: const TextStyle(color: Colors.black),
                          ),
                        );
                      }).toList(),
                      onChanged: isRegistering
                          ? null
                          : (String? v) {
                              setDialog(() => selectedBranchId = v);
                            },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                          const BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                          const BorderSide(color: Colors.black),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    /// CONFIRM BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (selectedBranchId == null || isRegistering)
                            ? null
                            : () async {
                          setDialog(() => isRegistering = true);
                          selectedDate = tempDate;

                          final opened = await _register(selectedBranchId!);

                          if (opened) {
                            if (ctx.mounted) Navigator.pop(ctx);
                          } else {
                            setDialog(() => isRegistering = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isRegistering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text("Confirm Registration"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }



  // ---------------- ABOUT ----------------

  Widget _aboutCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// 🎓 HEADER
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: lightColorScheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.school,
                      color: lightColorScheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Free Stock Market Workshop",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
        SizedBox(
          width: double.infinity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: lightColorScheme.primary.withOpacity(0.08),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule,
                    size: 18, color: lightColorScheme.primary),
                const SizedBox(width: 6),
                const Text("Sunday | 10 AM – 1 PM"),
              ],
            ),
          ),
        ),

        const SizedBox(height: 5),

              /// 📚 CONTENT
              _aboutPoint(Icons.trending_up, "Stock Market Basics"),
              _aboutPoint(Icons.bar_chart, "Live Market Examples"),
              _aboutPoint(Icons.psychology, "Trading Psychology"),
              _aboutPoint(Icons.question_answer, "Q&A with Mentors"),
            ],
          ),
        ),
      ),
    );
  }
  Widget _aboutPoint(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: lightColorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

}
