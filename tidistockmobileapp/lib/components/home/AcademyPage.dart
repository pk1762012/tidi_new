import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart';
import '../../service/ApiService.dart';
import '../../theme/theme.dart';
import '../../service/RazorPayService.dart';
import 'academy/WorkshopPage.dart';

class AcademyPage extends StatefulWidget {
  const AcademyPage({super.key});

  @override
  State<AcademyPage> createState() => _AcademyPageState();
}

class _AcademyPageState extends State<AcademyPage>
    with SingleTickerProviderStateMixin, RouteAware {
  late AnimationController _controller;
  late Animation<Offset> _pageAnimation;
  late Animation<double> _fadeAnimation;



  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  bool isLoading = false;
  List<dynamic> _courses = [];
  List<dynamic> _branches = [];
  Map<String, String> _branchIdNameMap = {};


  late ScrollController _branchScrollController;
  late RazorpayService razorpayService;

  // Course Transactions
  final ScrollController _transactionScrollController = ScrollController();

  List<dynamic> _transactions = [];
  int _txLimit = 10;
  int _txOffset = 0;
  bool _txLoading = false;
  bool _txHasMore = true;


  @override
  void initState() {
    _loadCourseTransactions();

    _transactionScrollController.addListener(() {
      if (_transactionScrollController.position.pixels >=
          _transactionScrollController.position.maxScrollExtent - 200 &&
          !_txLoading &&
          _txHasMore) {
        _loadCourseTransactions();
      }
    });

    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pageAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo),
    );

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _controller.forward();
    });

    _branchScrollController = ScrollController();

    razorpayService = RazorpayService(onFinish: () {
      if (!mounted) return;
      setState(() {});
    });

    getCourses();
    getBranches();
  }

  Future<void> _loadCourseTransactions() async {
    if (_txLoading || !_txHasMore) return;

    safeSetState(() => _txLoading = true);

    try {
      final res = await ApiService()
          .getCourseTransactions(_txLimit, _txOffset);

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body)['data'];

        if (data.isEmpty) {
          _txHasMore = false;
        } else {
          _transactions.addAll(data);

          // stop loader if returned items are less than limit
          if (data.length < _txLimit) {
            _txHasMore = false;
          } else {
            _txOffset += _txLimit;
          }
        }

      }
    } catch (e) {
      debugPrint("Transaction load error: $e");
    }

    safeSetState(() => _txLoading = false);
  }


  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _controller.dispose();
    _branchScrollController.dispose();
    razorpayService.dispose();
    _transactionScrollController.dispose();
    super.dispose();
  }

  /// Safe setState helper
  void safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> getCourses() async {
    try {
      await ApiService().getCachedCourses(
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          safeSetState(() => _courses = data is List ? data : []);
        },
      );
    } catch (e) {
      debugPrint("Error getCourses: $e");
    }
  }

  Future<void> getBranches() async {
    try {
      safeSetState(() => isLoading = true);
      await ApiService().getCachedBranches(
        onData: (data, {required fromCache}) {
          if (!mounted) return;
          final list = data is List ? data : [];
          safeSetState(() {
            _branches = list;
            _branchIdNameMap = {
              for (var b in list) b['id']: b['name']
            };
          });
        },
      );
    } catch (e) {
      debugPrint("Error getBranches: $e");
    }
    safeSetState(() => isLoading = false);
  }

  String _getBranchName(String? branchId) {
    if (branchId == null) return "Unknown Branch";
    return _branchIdNameMap[branchId] ?? "Unknown Branch";
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();

      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];

      return "${dt.day.toString().padLeft(2, '0')} "
          "${months[dt.month - 1]} "
          "${dt.year}";
    } catch (_) {
      return iso;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _pageAnimation,
            child: isLoading
                ? const SizedBox.shrink() // Empty screen while loading
                : _buildScrollableContent(context),
          ),
        ),
      ),
    );
  }



  Widget _buildScrollableContent(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          _freeWorkshopInfoCard(context),


          if (_courses.isNotEmpty)
              Column(
                children: _courses
                    .map((course) => RepaintBoundary(child: _courseCard(context, course)))
                    .toList(),
              ),

          if (_transactions.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              "Course Transactions",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),

            ListView.builder(
              controller: _transactionScrollController,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions.length + (_txHasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _transactions.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final tx = _transactions[index];
                final branchId = tx['branch']?['id'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Branch Name
                      Text(
                        _getBranchName(branchId),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                      color: statusColor(tx['status'] ?? '').withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                      formatStatus(tx['status'] ?? ''),
                      style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor(tx['status'] ?? ''),
                      ),
                      ),
                ),


                const SizedBox(height: 10),

                      // Order ID
                      Text(
                        "Order ID: ${tx['orderId']}",
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),

                      const SizedBox(height: 4),
                      // Footer Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(tx['dateCreated']),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

          ],


          Text(
              "Our Branches (${_branches.length})",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_branches.isNotEmpty)
              SizedBox(
                height: 400,
                child: ListView.builder(
                  controller: _branchScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _branches.length,
                  padding: const EdgeInsets.only(right: 20),
                  itemBuilder: (ctx, i) {
                    final branch = _branches[i];
                    return Container(
                      width: MediaQuery.of(context).size.width * 0.75,
                      margin: const EdgeInsets.only(right: 10),
                      child: RepaintBoundary(child: _branchCard(context, branch)),
                    );
                  },
                ),
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text("No branches available"),
                ),
              ),
            const SizedBox(height: 30),

        ],
      ),
    );
  }

  String formatStatus(String status) {
    return status.replaceAll('_', '-');
  }

  Color statusColor(String status) {
    switch (status) {
      case 'YET_TO_START':
        return Colors.orange;
      case 'ON_GOING':
        return Colors.blue;
      case 'COMPLETED':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }


  Widget _freeWorkshopInfoCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const WorkshopPage(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 30),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            "assets/images/tidi_workshop.png",
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }




  Widget _courseCard(BuildContext context, dynamic c) {
    final bool isGoldCourse =
        (c['name'] ?? '').toString().toLowerCase() == 'gold';

    final staticData = isGoldCourse ? _goldCourseStaticData : {};

    final List<String> highlights =
    List<String>.from(staticData['highlights'] ?? []);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Title + Level Badge
          Row(
            children: [
              Expanded(
                child: Text(
                  "${c['name']} Course",
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              if (isGoldCourse)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: lightColorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    staticData['level'],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: lightColorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),

          if (isGoldCourse) ...[
            const SizedBox(height: 4),
            Text(
              staticData['duration'],
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],

          const SizedBox(height: 12),

          /// Price
          Row(
            children: [
              Text(
                "₹${c['actualPrice']}",
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "₹${c['price']}",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: lightColorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            "Booking: ₹${c['bookingPrice']}",
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),

          if (isGoldCourse) ...[
            const SizedBox(height: 14),

            /// Highlights
            ...highlights.map(
                  (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle,
                        size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            /// Free Access Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard,
                      size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Free access worth ₹${staticData['freeWorth']}",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          /// CTA
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _onBookCourse(context, c),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: lightColorScheme.primary,
              ),
              child: const Text(
                "Book Now",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _goldCourseStaticData = {
    "level": "Level 1",
    "duration": "2 Days Workshop • 20 Days Practicals",
    "freeWorth": 6000,
    "highlights": [
      "World class hedging secrets revealed",
      "Fundamentals, Technical & Hedging strategies",
      "Karnataka’s highest purchased course",
      "Best value for money",
      "Online & Offline classes available",
    ],
  };


  void _onBookCourse(BuildContext context, dynamic course) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return BranchSelectionBottomSheet(
          branches: _branches,
          course: course,
          onSelected: (branchId) {
            razorpayService.openCourseCheckout(course['id'], branchId);
          },
        );
      },
    );
  }

  Widget _branchCard(BuildContext context, dynamic b) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          )
        ],
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _branchHeader(b),
            const SizedBox(height: 12),
            ..._branchPhones(b),
            const SizedBox(height: 10),
            _branchAddress(b),
            const SizedBox(height: 14),
            _branchImage(b),
          ],
        ),
      ),
    );
  }

  Widget _branchHeader(dynamic b) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Text(
          b['name'],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      InkWell(
        onTap: () => _openMap(b['mapLink']),
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: lightColorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(Icons.location_on, color: Colors.red, size: 22),
        ),
      ),
    ],
  );

  List<Widget> _branchPhones(dynamic b) =>
      (b['phoneNumbers'] as List<dynamic>)
          .map((p) => _phoneNumberTile(p.toString()))
          .toList();

  Widget _branchAddress(dynamic b) => Text(
    b['address'],
    style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
  );

  Widget _branchImage(dynamic b) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: AspectRatio(
      aspectRatio: 1,
      child: Image.asset(
        _branchImagePath(b['name']),
        fit: BoxFit.cover,
      ),
    ),
  );

  String _branchImagePath(String name) {
    return "assets/images/branch/${name}.png";
  }



  Widget _phoneNumberTile(String p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _callNumber(p),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: lightColorScheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_rounded, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p,
                    style: TextStyle(fontWeight: FontWeight.w600, color: lightColorScheme.primary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _callNumber(String number) async {
    final url = "tel:$number";
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      debugPrint("Call error: $e");
    }
  }

  void _openMap(String link) async {
    try {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Map error: $e");
    }
  }
}

// ------------------------- BOTTOM SHEET -------------------------

class BranchSelectionBottomSheet extends StatelessWidget {
  final List<dynamic> branches;
  final dynamic course;
  final void Function(String branchId) onSelected;

  const BranchSelectionBottomSheet({
    super.key,
    required this.branches,
    required this.course,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 55,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              Text(
                "Select Branch for ${course['name']} Course",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: lightColorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              ...branches.map((b) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(b['id']);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: lightColorScheme.primary, width: 1.5),
                      color: Colors.white.withOpacity(0.15),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(b['name'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

}
