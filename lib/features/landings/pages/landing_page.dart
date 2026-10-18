import 'dart:async';

import 'package:aqs/app_routes.dart';
// import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/contact/widgets/contact_form_card.dart';
import 'package:aqs/features/pricing/data/pricing_plans.dart';
import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:aqs/features/pricing/views/pricing_plans_page.dart';
import 'package:aqs/features/tutorials/models/tutorial_video.dart';
import 'package:aqs/features/tutorials/views/tutorial_videos_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

// Add the published AQS walkthrough URL here when the video is ready.
// YouTube, Vimeo, or a directly hosted video page can be used.
const _aqsWalkthroughVideoUrl = '';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key, this.openContact = false});

  final bool openContact;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _productKey = GlobalKey();
  final _ratesKey = GlobalKey();
  final _materialsKey = GlobalKey();
  final _pricingKey = GlobalKey();
  final _workflowKey = GlobalKey();
  final _capabilitiesKey = GlobalKey();

  final _tutorialsKey = GlobalKey();
  final _contactKey = GlobalKey();
  late final StreamSubscription<User?> _authSubscription;
  bool _isAuthenticated = FirebaseAuth.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final authenticated = user != null;
      if (mounted && authenticated != _isAuthenticated) {
        setState(() => _isAuthenticated = authenticated);
      }
    });
    if (widget.openContact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollTo(_contactKey);
        });
      });
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
  }

  Future<void> _openAuthenticatedDestination() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      Get.toNamed(AppRoutes.createProject);
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final role = (doc.data()?['role'] ?? '').toString().trim().toLowerCase();

      if (role == 'admin') {
        Get.toNamed(AppRoutes.admin);
      } else {
        Get.toNamed(AppRoutes.dashboard);
      }
    } catch (e) {
      debugPrint('Could not determine user role: $e');

      // Safe fallback for authenticated users
      Get.toNamed(AppRoutes.dashboard);
    }
  }

  void _openWorkspace() {
    if (!_isAuthenticated) {
      Get.toNamed(AppRoutes.createProject);
      return;
    }

    _openAuthenticatedDestination();
  }

  void _openAccountDestination() {
    _openAuthenticatedDestination();
  }

  // void _openWorkspace() {
  //   Get.toNamed(
  //     _isAuthenticated ? AppRoutes.dashboard : AppRoutes.createProject,
  //   );
  // }

  // void _openAccountDestination() => Get.toNamed(AppRoutes.dashboard);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      floatingActionButton: const _LandingChatButton(),
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _NavDelegate(
                onProduct: () => _scrollTo(_productKey),

                onRates: () => _scrollTo(_ratesKey),
                onMaterials: () => _scrollTo(_materialsKey),
                onPricing: () => _scrollTo(_pricingKey),

                onWorkflow: () => _scrollTo(_workflowKey),

                onCapabilities: () => _scrollTo(_capabilitiesKey),

                onTutorials: () => _scrollTo(_tutorialsKey),

                onContact: () => _scrollTo(_contactKey),

                onStart: _openWorkspace,

                onAccount: _openAccountDestination,

                isAuthenticated: _isAuthenticated,
              ),
            ),
            SliverToBoxAdapter(child: _Hero(onStart: _openWorkspace)),
            SliverToBoxAdapter(child: _ProductSection(key: _productKey)),

            SliverToBoxAdapter(child: _BuildUpRatesSection(key: _ratesKey)),
            SliverToBoxAdapter(
              child: _MaterialPricesSection(key: _materialsKey),
            ),

            SliverToBoxAdapter(child: _WorkflowSection(key: _workflowKey)),
            SliverToBoxAdapter(child: _PricingSection(key: _pricingKey)),
            SliverToBoxAdapter(
              child: _CapabilitiesSection(key: _capabilitiesKey),
            ),
            SliverToBoxAdapter(child: _TutorialsSection(key: _tutorialsKey)),
            SliverToBoxAdapter(child: _ProofSection()),
            SliverToBoxAdapter(child: _ContactSection(key: _contactKey)),
            SliverToBoxAdapter(child: _ClosingCta(onStart: _openWorkspace)),
            const SliverToBoxAdapter(child: _Footer()),
          ],
        ),
      ),
    );
  }
}

class _LandingChatButton extends StatelessWidget {
  const _LandingChatButton();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'landing-help-chat',
      backgroundColor: const Color(0xFF155EEF),
      foregroundColor: Colors.white,
      elevation: 8,
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _LandingChatSheet(),
        );
      },
      icon: const Icon(Icons.chat_bubble_outline_rounded),
      label: const Text(
        'Ask AQS',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LandingChatSheet extends StatefulWidget {
  const _LandingChatSheet();

  @override
  State<_LandingChatSheet> createState() => _LandingChatSheetState();
}

class _LandingChatSheetState extends State<_LandingChatSheet> {
  final _questionController = TextEditingController();
  final _scrollController = ScrollController();
  final List<({bool fromUser, String text})> _messages = [
    (
      fromUser: false,
      text:
          'Hi! I’m the AQS website assistant. Ask me a simple question about take-off, BOQs, pricing, files, or getting started.',
    ),
  ];

  static const _suggestions = [
    'What is AQS?',
    'How do I get started?',
    'Which files can I upload?',
    'Is there a free plan?',
  ];

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _answer(String question) {
    final q = question.toLowerCase().trim();

    bool hasAny(List<String> words) => words.any(q.contains);

    if (hasAny(['hello', 'hi ', 'hey', 'good morning', 'good afternoon'])) {
      return 'Hello! I can help you understand AQS, drawing take-off, BOQs, subscriptions, and how to begin.';
    }
    if (hasAny(['what is aqs', 'what does aqs', 'about aqs'])) {
      return 'AQS AUTOboq helps quantity surveyors measure drawings, build structured BOQs, and keep quantities traceable through the project workflow.';
    }
    if (hasAny([
      'get started',
      'start measuring',
      'first takeoff',
      'sign up',
    ])) {
      return 'Choose “Start measuring” or “Start your first takeoff”, create your account and project, add a building, upload a drawing, calibrate its scale, then select a measuring tool.';
    }
    if (hasAny(['file', 'upload', 'pdf', 'drawing format', 'image'])) {
      return 'You can upload project drawings and use the processed drawing image for take-off. PDF drawings and common image formats are supported by the drawing workflow.';
    }
    if (hasAny(['free', 'price', 'pricing', 'cost', 'subscription', 'plan'])) {
      return 'AQS offers a free starting option and paid plans with broader capabilities. Open the Pricing section above for the current plan features and prices.';
    }
    if (hasAny(['boq', 'bill of quantities', 'template'])) {
      return 'AQS connects measured quantities to BOQ items. You can add or import a BOQ template, link each measurement to the relevant item, and keep the resulting quantities traceable.';
    }
    if (hasAny(['calibrate', 'calibration', 'scale'])) {
      return 'Calibration converts drawing pixels into real dimensions. Select two known points, enter their actual distance, and confirm the scale before measuring.';
    }
    if (hasAny(['takeoff', 'take-off', 'measure', 'quantity'])) {
      return 'Drawing take-off lets you measure lengths, areas, counts, and composite building elements. AQS then calculates quantities using the dimensions and settings you provide.';
    }
    if (hasAny(['excel', 'export', 'download', 'pdf output'])) {
      return 'AQS supports structured outputs for reviewing and sharing project quantities, including Excel and PDF workflows.';
    }
    if (hasAny(['contact', 'support', 'human', 'help'])) {
      return 'For account-specific or detailed help, use the Contact section on this page and the AQS team can assist you.';
    }
    if (hasAny(['thank', 'thanks'])) {
      return 'You’re welcome! Ask another question whenever you like.';
    }

    return 'I’m currently best at simple questions about AQS, take-off, BOQs, pricing, uploads, calibration, and getting started. For a detailed or account-specific question, please use the Contact section.';
  }

  void _send([String? suggestedQuestion]) {
    final question = (suggestedQuestion ?? _questionController.text).trim();
    if (question.isEmpty) return;

    setState(() {
      _messages.add((fromUser: true, text: question));
      _messages.add((fromUser: false, text: _answer(question)));
      _questionController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width < 620 ? screenSize.width : 440.0;
    final height = screenSize.height * (screenSize.width < 620 ? 0.88 : 0.72);

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.only(
          right: screenSize.width < 620 ? 0 : 24,
          bottom: bottomInset,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 10, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF102A56), Color(0xFF155EEF)],
                    ),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.auto_awesome_rounded, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ask AQS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Quick answers about AQS',
                              style: TextStyle(color: Color(0xFFD6E4FF)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final message in _messages)
                        _LandingChatBubble(message: message),
                      if (_messages.length == 1) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final suggestion in _suggestions)
                              ActionChip(
                                label: Text(suggestion),
                                onPressed: () => _send(suggestion),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _questionController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Ask a question…',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
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

class _LandingChatBubble extends StatelessWidget {
  const _LandingChatBubble({required this.message});

  final ({bool fromUser, String text}) message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
          message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color:
              message.fromUser
                  ? const Color(0xFF155EEF)
                  : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.fromUser ? Colors.white : const Color(0xFF344054),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _PricingSection extends StatefulWidget {
  const _PricingSection({super.key});

  @override
  State<_PricingSection> createState() => _PricingSectionState();
}

class _PricingSectionState extends State<_PricingSection> {
  bool yearly = false;

  String _money(num value) {
    if (value == 0) return 'Free';

    final raw = value.round().toString();

    final buffer = StringBuffer();

    for (var i = 0; i < raw.length; i++) {
      final position = raw.length - i;

      buffer.write(raw[i]);

      if (position > 1 && position % 3 == 1) {
        buffer.write(',');
      }
    }

    return 'TZS ${buffer.toString()}';
  }

  void _openPlan(PricingPlan plan) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      Get.toNamed(AppRoutes.createProject);

      return;
    }

    if (plan.id == 'free') {
      Get.toNamed(AppRoutes.dashboard);
      return;
    }

    Get.to(
      () => PricingPlansPage(
        initialPlanId: plan.id,
        initialYearly: yearly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: _PageWidth(
        padding: const EdgeInsets.fromLTRB(22, 88, 22, 88),
        child: Column(
          children: [
            const _SectionHeading(
              eyebrow: 'SIMPLE PRICING',
              title: 'Choose the AQS plan that matches your workload.',
              subtitle:
                  'Start free, then move to a plan that gives you the project capacity, drawing volume and professional tools you need.',
            ),

            const SizedBox(height: 28),

            // ============================================
            // MONTHLY / YEARLY
            // ============================================
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEAECF0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PricingPeriodButton(
                    label: 'Monthly',
                    selected: !yearly,
                    onTap: () {
                      setState(() {
                        yearly = false;
                      });
                    },
                  ),

                  _PricingPeriodButton(
                    label: 'Yearly',
                    selected: yearly,
                    badge: 'Save 2 months',
                    onTap: () {
                      setState(() {
                        yearly = true;
                      });
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 38),

            // ============================================
            // PLAN CARDS
            // ============================================
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth < 700
                        ? 1
                        : constraints.maxWidth < 1100
                        ? 2
                        : 4;

                final width =
                    (constraints.maxWidth - ((columns - 1) * 16)) / columns;

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final plan in pricingPlans)
                      SizedBox(
                        width: width,
                        child: _LandingPricingCard(
                          plan: plan,
                          yearly: yearly,
                          priceText: _money(
                            yearly ? plan.yearlyPrice : plan.monthlyPrice,
                          ),
                          onTap: () {
                            _openPlan(plan);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            const Text(
              'Prices are shown in Tanzanian Shillings (TZS).',
              style: TextStyle(color: Color(0xFF667085), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingPeriodButton extends StatelessWidget {
  const _PricingPeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF155EEF) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      selected
                          ? Colors.white.withOpacity(.17)
                          : const Color(0xFFECFDF3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF027A48),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LandingPricingCard extends StatelessWidget {
  const _LandingPricingCard({
    required this.plan,
    required this.yearly,
    required this.priceText,
    required this.onTap,
  });

  final PricingPlan plan;
  final bool yearly;
  final String priceText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.highlight;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              highlighted ? const Color(0xFF155EEF) : const Color(0xFFEAECF0),
          width: highlighted ? 2 : 1,
        ),
        boxShadow:
            highlighted
                ? const [
                  BoxShadow(
                    color: Color(0x18155EEF),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              if (plan.badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        highlighted
                            ? const Color(0xFFEFF4FF)
                            : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    plan.badge,
                    style: TextStyle(
                      color:
                          highlighted
                              ? const Color(0xFF155EEF)
                              : const Color(0xFF475467),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            priceText,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),

          if (plan.id != 'free')
            Text(
              yearly ? '/ year' : '/ month',
              style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
            ),

          const SizedBox(height: 16),

          Text(
            plan.description,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.5,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 20),

          _PricingMeta(icon: Icons.folder_outlined, text: plan.projects),

          _PricingMeta(icon: Icons.image_outlined, text: plan.drawings),

          _PricingMeta(icon: Icons.person_outline, text: plan.users),

          const SizedBox(height: 18),

          const Divider(),

          const SizedBox(height: 14),

          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: Color(0xFF12B76A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child:
                highlighted
                    ? FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF155EEF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Get started'),
                    )
                    : OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        plan.id == 'free'
                            ? 'Start free'
                            : 'Choose ${plan.name}',
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _PricingMeta extends StatelessWidget {
  const _PricingMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF155EEF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF344054),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// class PricingPlansView extends StatelessWidget {
//   const PricingPlansView({
//     super.key,
//     this.showCurrentPlan = false,
//     this.onSelectPlan,
//   });

//   final bool showCurrentPlan;
//   final ValueChanged<String>? onSelectPlan;

//   @override
//   Widget build(BuildContext context) {
//     // existing pricing cards here
//   }
// }

class _NavDelegate extends SliverPersistentHeaderDelegate {
  _NavDelegate({
    required this.onProduct,
    required this.onRates,
    required this.onMaterials,
    required this.onPricing,
    required this.onWorkflow,
    required this.onCapabilities,
    required this.onTutorials,
    required this.onContact,
    required this.onStart,
    required this.onAccount,
    required this.isAuthenticated,
  });

  final VoidCallback onProduct;
  final VoidCallback onRates;
  final VoidCallback onMaterials;
  final VoidCallback onPricing;
  final VoidCallback onWorkflow;
  final VoidCallback onCapabilities;
  final VoidCallback onTutorials;
  final VoidCallback onContact;
  final VoidCallback onStart;
  final VoidCallback onAccount;
  final bool isAuthenticated;

  @override
  double get minExtent => 72;

  @override
  double get maxExtent => 72;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.white.withOpacity(0.96),
      elevation: overlapsContent || shrinkOffset > 0 ? 2 : 0,
      shadowColor: Colors.black12,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1180;
                return Row(
                  children: [
                    const AqsBrand(),
                    const Spacer(),
                    if (compact) ...[
                      IconButton(
                        tooltip: 'Menu',
                        onPressed:
                            () => _openMobileMenu(
                              context,
                              onProduct: onProduct,
                              onRates: onRates,
                              onMaterials: onMaterials,

                              onWorkflow: onWorkflow,
                              onCapabilities: onCapabilities,
                              onTutorials: onTutorials,
                              onContact: onContact,
                              onAccount: onAccount,
                              onStart: onStart,
                              isAuthenticated: isAuthenticated,
                            ),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      _NavButton(label: 'Product', onTap: onProduct),
                      _NavButton(label: 'Build-Up Rates', onTap: onRates),
                      _NavButton(label: 'Material Prices', onTap: onMaterials),
                      _NavButton(label: 'Pricing', onTap: onPricing),
                      _NavButton(label: 'Workflow', onTap: onWorkflow),
                      _NavButton(label: 'Capabilities', onTap: onCapabilities),
                      _NavButton(label: 'Tutorials', onTap: onTutorials),
                      _NavButton(
                        label: 'About',
                        onTap: () => Get.toNamed(AppRoutes.about),
                      ),
                      _NavButton(label: 'Contact', onTap: onContact),
                      const SizedBox(width: 12),
                      if (!isAuthenticated) ...[
                        TextButton(
                          onPressed: () => Get.toNamed(AppRoutes.login),
                          child: const Text('Sign in'),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                    FilledButton(
                      onPressed: onStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF155EEF),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 14 : 20,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        isAuthenticated
                            ? (compact ? 'Dashboard' : 'Open dashboard')
                            : (compact ? 'Start' : 'Start measuring'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _NavDelegate oldDelegate) =>
      oldDelegate.isAuthenticated != isAuthenticated;

  void _openMobileMenu(
    BuildContext context, {
    required VoidCallback onProduct,
    required VoidCallback onRates,
    required VoidCallback onMaterials,
    required VoidCallback onWorkflow,
    required VoidCallback onCapabilities,
    required VoidCallback onTutorials,
    required VoidCallback onContact,
    required VoidCallback onAccount,
    required VoidCallback onStart,
    required bool isAuthenticated,
  }) {
    void go(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD0D5DD),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const AqsBrand(),
                    const SizedBox(height: 10),
                    _MobileNavTile(
                      icon: Icons.layers_outlined,
                      label: 'Product',
                      onTap: () => go(onProduct),
                    ),
                    _MobileNavTile(
                      icon: Icons.calculate_outlined,
                      label: 'Build-Up Rates',
                      onTap: () => go(onRates),
                    ),
                    _MobileNavTile(
                      icon: Icons.price_check_outlined,
                      label: 'Material Prices',
                      onTap: () => go(onMaterials),
                    ),
                    _MobileNavTile(
                      icon: Icons.payments_outlined,
                      label: 'Pricing',
                      onTap: () => go(onPricing),
                    ),
                    _MobileNavTile(
                      icon: Icons.route_outlined,
                      label: 'Workflow',
                      onTap: () => go(onWorkflow),
                    ),
                    _MobileNavTile(
                      icon: Icons.widgets_outlined,
                      label: 'Capabilities',
                      onTap: () => go(onCapabilities),
                    ),
                    _MobileNavTile(
                      icon: Icons.video_library_outlined,
                      label: 'Tutorials',
                      onTap: () => go(onTutorials),
                    ),
                    _MobileNavTile(
                      icon: Icons.info_outline_rounded,
                      label: 'About',
                      onTap: () => go(() => Get.toNamed(AppRoutes.about)),
                    ),
                    _MobileNavTile(
                      icon: Icons.contact_mail_outlined,
                      label: 'Contact',
                      onTap: () => go(onContact),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Get.toNamed(AppRoutes.login),
                            child: Text('Sign in'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => go(onStart),
                            child: Text(isAuthenticated ? 'Open' : 'Start'),
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
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: const Color(0xFF344054)),
      child: Text(label),
    );
  }
}

class _MobileNavTile extends StatelessWidget {
  const _MobileNavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minVerticalPadding: 6,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(icon, color: const Color(0xFF155EEF)),
      title: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF101828),
          fontWeight: FontWeight.w800,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final compactScreen = MediaQuery.sizeOf(context).width < 700;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FAFF), Color(0xFFEEF4FF)],
        ),
      ),
      child: _PageWidth(
        padding: EdgeInsets.fromLTRB(
          22,
          compactScreen ? 30 : 72,
          22,
          compactScreen ? 58 : 78,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;
            final copy = _HeroCopy(onStart: onStart, compact: stacked);
            const preview = _ProductPreview();
            return stacked
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [copy, const SizedBox(height: 44), preview],
                )
                : Row(
                  children: [
                    Expanded(flex: 10, child: copy),
                    const SizedBox(width: 54),
                    const Expanded(flex: 11, child: preview),
                  ],
                );
          },
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onStart, required this.compact});

  final VoidCallback onStart;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(
          icon: Icons.auto_awesome_outlined,
          text: 'BUILT FOR QUANTITY SURVEYORS',
        ),
        const SizedBox(height: 22),
        Text(
          'Turn drawings into\ncredible quantities.',
          style: TextStyle(
            color: const Color(0xFF101828),
            fontSize: compact ? 44 : 62,
            height: 1.02,
            letterSpacing: -2.3,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: const Text(
            'Measure complex building elements directly from drawings, build structured BOQs, and keep every quantity traceable from tender through valuation.',
            style: TextStyle(
              color: Color(0xFF475467),
              fontSize: 18,
              height: 1.6,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Start your first takeoff'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF155EEF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 17,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showAqsWalkthrough(context),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Watch how it works'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF344054),
                side: const BorderSide(color: Color(0xFFD0D5DD)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Check(text: 'No spreadsheet setup'),
            _Check(text: 'Audit-ready quantities'),
            _Check(text: 'Excel & PDF outputs'),
          ],
        ),
      ],
    );
  }
}

Future<void> _showAqsWalkthrough(BuildContext context) async {
  final videoUri = Uri.tryParse(_aqsWalkthroughVideoUrl);
  if (videoUri != null && videoUri.hasScheme) {
    final opened = await launchUrl(videoUri, mode: LaunchMode.platformDefault);
    if (opened || !context.mounted) return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => const _WalkthroughComingSoonDialog(),
  );
}

class _WalkthroughComingSoonDialog extends StatelessWidget {
  const _WalkthroughComingSoonDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: const Color(0xFF101828),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_fill_rounded,
                          color: Color(0xFF84ADFF),
                          size: 72,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'AQS walkthrough coming soon',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'The complete product demonstration is being prepared.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFD0D5DD)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'See the complete AQS workflow',
                            style: TextStyle(
                              color: Color(0xFF101828),
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'The video will demonstrate account creation, project setup, drawing upload and calibration, measurement, BOQ linking, and the final BOQ output.',
                            style: TextStyle(
                              color: Color(0xFF667085),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildUpRatesSection extends StatelessWidget {
  const _BuildUpRatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: _PageWidth(
        padding: const EdgeInsets.fromLTRB(22, 88, 22, 88),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;

            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow(
                  icon: Icons.calculate_outlined,
                  text: 'BUILD-UP RATES',
                ),

                const SizedBox(height: 20),

                Text(
                  'Build rates from the '
                  'resources that make up '
                  'the work.',
                  style: TextStyle(
                    color: const Color(0xFF101828),
                    fontSize: stacked ? 38 : 48,
                    height: 1.08,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'Prepare transparent rate build-ups for BOQ items '
                  'using materials, labour, plant, waste, transport, '
                  'overheads and profit. Build reusable rates for '
                  'walling, plastering, painting, tiling, concrete, '
                  'formwork and other construction activities.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 28),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _RateFeatureChip(
                      icon: Icons.inventory_2_outlined,
                      label: 'Materials',
                    ),
                    _RateFeatureChip(
                      icon: Icons.engineering_outlined,
                      label: 'Labour',
                    ),
                    _RateFeatureChip(
                      icon: Icons.precision_manufacturing_outlined,
                      label: 'Plant',
                    ),
                    _RateFeatureChip(
                      icon: Icons.local_shipping_outlined,
                      label: 'Transport',
                    ),
                    _RateFeatureChip(
                      icon: Icons.percent_rounded,
                      label: 'OH&P',
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                FilledButton.icon(
                  onPressed: () {
                    Get.toNamed(AppRoutes.buildUpRates);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Build your rate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF155EEF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 17,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            );

            const preview = _RateBuildUpPreview();

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [content, const SizedBox(height: 40), preview],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: content),
                const SizedBox(width: 56),
                const Expanded(flex: 5, child: preview),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MaterialPricesSection extends StatelessWidget {
  const _MaterialPricesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: _PageWidth(
        padding: const EdgeInsets.fromLTRB(22, 88, 22, 88),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 860;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow(
                  icon: Icons.price_check_outlined,
                  text: 'MATERIALS PRICE LIST',
                ),
                const SizedBox(height: 20),
                Text(
                  'Compare construction material prices with confidence.',
                  style: TextStyle(
                    color: const Color(0xFF101828),
                    fontSize: stacked ? 36 : 46,
                    height: 1.08,
                    letterSpacing: -1.3,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Review current prices from different suppliers, locations, '
                  'and effective dates. Search by material or category and use '
                  'the latest market information when preparing your estimates.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.materialPrices),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('View material prices'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF039855),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 17,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            );

            const preview = _MaterialPricePreview();
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 40), preview],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: heading),
                const SizedBox(width: 56),
                const Expanded(flex: 5, child: preview),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MaterialPricePreview extends StatelessWidget {
  const _MaterialPricePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFABEFC6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF039855),
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supplier price comparison',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Updated by the AQS administrator',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _MaterialPriceBenefit(
            icon: Icons.storefront_outlined,
            title: 'Multiple suppliers',
            text: 'Compare like-for-like offers before selecting a source.',
          ),
          const SizedBox(height: 12),
          const _MaterialPriceBenefit(
            icon: Icons.location_on_outlined,
            title: 'Location-aware pricing',
            text: 'See where each quoted material price applies.',
          ),
          const SizedBox(height: 12),
          const _MaterialPriceBenefit(
            icon: Icons.event_available_outlined,
            title: 'Clear effective dates',
            text: 'Know how current every supplier price is.',
          ),
        ],
      ),
    );
  }
}

class _MaterialPriceBenefit extends StatelessWidget {
  const _MaterialPriceBenefit({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1FADF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: const Color(0xFF039855)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RateFeatureChip extends StatelessWidget {
  const _RateFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF155EEF)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateBuildUpPreview extends StatelessWidget {
  const _RateBuildUpPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAECF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12101828),
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.calculate_outlined,
                  color: Color(0xFF155EEF),
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rate Build-Up',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '230 mm block wall',
                      style: TextStyle(color: Color(0xFF667085), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          const _RatePreviewRow(
            label: 'Concrete blocks',
            quantity: '12.5 No.',
            amount: '18,750',
          ),

          const _RatePreviewRow(
            label: 'Cement mortar',
            quantity: '0.03 m³',
            amount: '4,800',
          ),

          const _RatePreviewRow(
            label: 'Mason',
            quantity: '0.45 hr',
            amount: '3,600',
          ),

          const _RatePreviewRow(
            label: 'Labourer',
            quantity: '0.60 hr',
            amount: '2,100',
          ),

          const Divider(height: 28),

          const Row(
            children: [
              Expanded(
                child: Text(
                  'Built-up rate',
                  style: TextStyle(
                    color: Color(0xFF344054),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'TZS / m²',
                style: TextStyle(
                  color: Color(0xFF155EEF),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatePreviewRow extends StatelessWidget {
  const _RatePreviewRow({
    required this.label,
    required this.quantity,
    required this.amount,
  });

  final String label;
  final String quantity;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              quantity,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// class _RatePreviewRow extends StatelessWidget {
//   const _RatePreviewRow({
//     required this.label,
//     required this.quantity,
//     required this.amount,
//   });

//   final String label;
//   final String quantity;
//   final String amount;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 9),
//       child: Row(
//         children: [
//           Expanded(
//             flex: 5,
//             child: Text(
//               label,
//               style: const TextStyle(
//                 color: Color(0xFF475467),
//                 fontSize: 13,
//                 fontWeight: FontWeight.w700,
//               ),
//             ),
//           ),
//           Expanded(
//             flex: 2,
//             child: Text(
//               quantity,
//               textAlign: TextAlign.right,
//               style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
//             ),
//           ),
//           Expanded(
//             flex: 2,
//             child: Text(
//               amount,
//               textAlign: TextAlign.right,
//               style: const TextStyle(
//                 color: Color(0xFF101828),
//                 fontSize: 12,
//                 fontWeight: FontWeight.w800,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class _ProductPreview extends StatefulWidget {
  const _ProductPreview();

  @override
  State<_ProductPreview> createState() => _ProductPreviewState();
}

class _ProductPreviewState extends State<_ProductPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332054C7),
            blurRadius: 48,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: const Color(0xFF1D2939),
              child: const Row(
                children: [
                  _WindowDot(color: Color(0xFFF97066)),
                  SizedBox(width: 7),
                  _WindowDot(color: Color(0xFFFDB022)),
                  SizedBox(width: 7),
                  _WindowDot(color: Color(0xFF32D583)),
                  Spacer(),
                  Text(
                    'Terminal Building · Ground Floor',
                    style: TextStyle(
                      color: Color(0xFFD0D5DD),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 1.38,
              child: AnimatedBuilder(
                animation: _controller,
                builder:
                    (context, _) => Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BlueprintPainter(
                              progress: _controller.value,
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 16,
                          top: 16,
                          child: _FloatingTools(),
                        ),
                        Positioned(
                          right: 16,
                          top: 18,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF3),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Color(0xFF039855),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Scale calibrated',
                                  style: TextStyle(
                                    color: Color(0xFF027A48),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _SurveyorCursorPainter(
                                progress: _controller.value,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 18,
                          bottom: 18,
                          child: _QuantityCard(progress: _controller.value),
                        ),
                      ],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _FloatingTools extends StatelessWidget {
  const _FloatingTools();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        children: [
          _PreviewTool(icon: Icons.straighten, label: 'Length'),
          _PreviewTool(
            icon: Icons.view_week_outlined,
            label: 'Wall 230',
            active: true,
          ),
          _PreviewTool(icon: Icons.grid_on_outlined, label: 'Slab'),
          _PreviewTool(icon: Icons.roofing_outlined, label: 'Roof'),
        ],
      ),
    );
  }
}

class _PreviewTool extends StatelessWidget {
  const _PreviewTool({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEFF4FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: active ? const Color(0xFF155EEF) : const Color(0xFF667085),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF155EEF) : const Color(0xFF475467),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityCard extends StatelessWidget {
  const _QuantityCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const totals = [0.0, 13.4, 29.8, 42.68];
    final scaled = progress * 3;
    final segment = scaled.floor().clamp(0, 2);
    final localProgress = scaled - segment;
    final quantity =
        totals[segment] +
        (totals[segment + 1] - totals[segment]) * localProgress;

    return Container(
      width: 184,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE QUANTITY',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 9,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${quantity.toStringAsFixed(3)} m',
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'External wall · 230 mm',
            style: TextStyle(color: Color(0xFF475467), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  const _BlueprintPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF9FAFB),
    );

    final grid =
        Paint()
          ..color = const Color(0xFFE4E7EC)
          ..strokeWidth = 0.7;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final wall =
        Paint()
          ..color = const Color(0xFF344054)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    final thin =
        Paint()
          ..color = const Color(0xFF98A2B3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;

    final plan =
        Path()
          ..moveTo(size.width * .25, size.height * .18)
          ..lineTo(size.width * .83, size.height * .18)
          ..lineTo(size.width * .83, size.height * .78)
          ..lineTo(size.width * .29, size.height * .78)
          ..lineTo(size.width * .29, size.height * .55)
          ..lineTo(size.width * .19, size.height * .55)
          ..lineTo(size.width * .19, size.height * .30)
          ..lineTo(size.width * .25, size.height * .30)
          ..close();
    canvas.drawPath(plan, wall);

    canvas.drawLine(
      Offset(size.width * .53, size.height * .18),
      Offset(size.width * .53, size.height * .78),
      thin,
    );
    canvas.drawLine(
      Offset(size.width * .29, size.height * .48),
      Offset(size.width * .83, size.height * .48),
      thin,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .57,
        size.height * .53,
        size.width * .19,
        size.height * .16,
      ),
      thin,
    );

    final measure =
        Paint()
          ..color = const Color(0xFF155EEF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
    final points = [
      Offset(size.width * .29, size.height * .78),
      Offset(size.width * .53, size.height * .78),
      Offset(size.width * .83, size.height * .78),
      Offset(size.width * .83, size.height * .48),
    ];
    final scaled = progress * (points.length - 1);
    final completed = scaled.floor().clamp(0, points.length - 1);
    final partial = scaled - completed;

    for (var i = 0; i < completed; i++) {
      canvas.drawLine(points[i], points[i + 1], measure);
    }
    if (completed < points.length - 1) {
      canvas.drawLine(
        points[completed],
        Offset.lerp(points[completed], points[completed + 1], partial)!,
        measure,
      );
    }
    for (var i = 0; i <= completed && i < points.length; i++) {
      final point = points[i];
      canvas.drawCircle(point, 5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3.5, Paint()..color = const Color(0xFF155EEF));
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SurveyorCursorPainter extends CustomPainter {
  const _SurveyorCursorPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      Offset(size.width * .29, size.height * .78),
      Offset(size.width * .53, size.height * .78),
      Offset(size.width * .83, size.height * .78),
      Offset(size.width * .83, size.height * .48),
    ];
    final scaled = progress * (points.length - 1);
    final segment = scaled.floor().clamp(0, points.length - 2);
    final localProgress = scaled - segment;
    final position =
        Offset.lerp(points[segment], points[segment + 1], localProgress)!;

    final pulse = 7 + 2 * (1 - (localProgress * 2 - 1).abs());
    canvas.drawCircle(
      position,
      pulse + 5,
      Paint()..color = const Color(0x33155EEF),
    );
    canvas.drawCircle(position, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(position, 3.8, Paint()..color = const Color(0xFF155EEF));

    final bubbleLeft = (position.dx - 44).clamp(8, size.width - 104).toDouble();
    final bubbleTop = (position.dy - 47).clamp(8, size.height - 40).toDouble();
    final bubbleRect = Rect.fromLTWH(bubbleLeft, bubbleTop, 96, 27);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF101828),
    );

    final text = TextPainter(
      text: const TextSpan(
        text: 'QS measuring…',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset(
        bubbleRect.left + (bubbleRect.width - text.width) / 2,
        bubbleRect.top + (bubbleRect.height - text.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _SurveyorCursorPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _PageWidth(
      padding: const EdgeInsets.fromLTRB(22, 88, 22, 60),
      child: Column(
        children: [
          const _SectionHeading(
            eyebrow: 'ONE CONNECTED WORKSPACE',
            title: 'Measure once. Use the quantity everywhere.',
            subtitle:
                'AQS connects drawing takeoff to BOQ production and project-stage reporting, so quantities remain visible, structured, and defensible.',
          ),
          const SizedBox(height: 42),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 850;
              const items = [
                _Feature(
                  number: '01',
                  icon: Icons.architecture_outlined,
                  title: 'Drawing takeoff',
                  body:
                      'Calibrate PDF drawings and measure walls, beams, slabs, stairs, roofs, finishes, civil works, areas, and volumes.',
                ),
                _Feature(
                  number: '02',
                  icon: Icons.table_chart_outlined,
                  title: 'Structured BOQs',
                  body:
                      'Map quantities to BOQ items, maintain consistent descriptions, and export clean schedules for review or pricing.',
                ),
                _Feature(
                  number: '03',
                  icon: Icons.fact_check_outlined,
                  title: 'Project controls',
                  body:
                      'Carry quantities into tender, progress, valuation, and verification workflows without rebuilding the measurement record.',
                ),
              ];
              if (stacked) {
                return Column(
                  children: [
                    _FeatureCard(feature: items[0]),
                    const SizedBox(height: 14),
                    _FeatureCard(feature: items[1]),
                    const SizedBox(height: 14),
                    _FeatureCard(feature: items[2]),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _FeatureCard(feature: items[0])),
                  const SizedBox(width: 18),
                  Expanded(child: _FeatureCard(feature: items[1])),
                  const SizedBox(width: 18),
                  Expanded(child: _FeatureCard(feature: items[2])),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Feature {
  const _Feature({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });
  final String number;
  final IconData icon;
  final String title;
  final String body;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(feature.icon, color: const Color(0xFF155EEF)),
              ),
              const Spacer(),
              Text(
                feature.number,
                style: const TextStyle(
                  color: Color(0xFFD0D5DD),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            feature.title,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            feature.body,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.55,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection({super.key});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        icon: Icons.folder_copy_outlined,
        title: 'Create project',
        body:
            'Start with the project, client, currency, stage, and key job details.',
      ),
      (
        icon: Icons.apartment_rounded,
        title: 'Add buildings',
        body:
            'Create each building or facility so work is organized by real site areas.',
      ),
      (
        icon: Icons.image_outlined,
        title: 'Add drawings',
        body:
            'Upload drawings to the correct facility before starting take-off.',
      ),
      (
        icon: Icons.receipt_long_outlined,
        title: 'Upload BOQ template',
        body:
            'Import or select the BOQ structure that measured quantities map into.',
      ),
      (
        icon: Icons.square_foot_outlined,
        title: 'Set calibration',
        body: 'Set the drawing scale from a known dimension before measuring.',
      ),
      (
        icon: Icons.polyline_outlined,
        title: 'Take-off',
        body:
            'Measure lengths, walls, slabs, roofs, areas, volumes, and finishes.',
      ),
      (
        icon: Icons.file_download_outlined,
        title: 'Deliver BOQ',
        body:
            'Issue the BOQ, take-off records, summaries, and project reports.',
      ),
    ];

    return Container(
      color: const Color(0xFF101828),
      child: _PageWidth(
        padding: const EdgeInsets.fromLTRB(22, 82, 22, 88),
        child: Column(
          children: [
            const _SectionHeading(
              dark: true,
              eyebrow: 'A PRACTICAL WORKFLOW',
              title: 'From project setup to delivered BOQ.',
              subtitle:
                  'AQS follows the full quantity surveying flow: organize the project, attach drawings and BOQs, calibrate, take off, and deliver clean quantities.',
            ),
            const SizedBox(height: 46),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth < 620
                        ? 1
                        : constraints.maxWidth < 980
                        ? 2
                        : constraints.maxWidth < 1240
                        ? 3
                        : 4;
                final width =
                    (constraints.maxWidth - (columns - 1) * 16) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      SizedBox(
                        width: width,
                        child: _WorkflowStep(
                          index: i + 1,
                          icon: steps[i].icon,
                          title: steps[i].title,
                          body: steps[i].body,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2939),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF344054)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF84ADFF), size: 27),
              const Spacer(),
              Text(
                '0$index',
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilitiesSection extends StatelessWidget {
  const _CapabilitiesSection({super.key});

  @override
  Widget build(BuildContext context) {
    const capabilities = [
      (Icons.view_week_outlined, 'Walls & finishes'),
      (Icons.horizontal_rule, 'Beams & lintels'),
      (Icons.grid_on_outlined, 'Slabs & floors'),
      (Icons.foundation_outlined, 'Foundations'),
      (Icons.stairs_outlined, 'Stairs & ramps'),
      (Icons.roofing_outlined, 'Roof coverings'),
      (Icons.carpenter_outlined, 'Timber & steel roof'),
      (Icons.add_road_outlined, 'Roads & kerbs'),
      (Icons.crop_square_outlined, 'Areas & volumes'),
      (Icons.door_front_door_outlined, 'Doors & windows'),
      (Icons.linear_scale_outlined, 'Services & pipework'),
      (Icons.verified_outlined, 'BOQ verification'),
    ];

    return _PageWidth(
      padding: const EdgeInsets.fromLTRB(22, 88, 22, 88),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 800;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow(
                icon: Icons.widgets_outlined,
                text: 'PURPOSE-BUILT TOOLS',
              ),
              const SizedBox(height: 18),
              Text(
                'Measure the object,\nnot just the line.',
                style: TextStyle(
                  color: const Color(0xFF101828),
                  fontSize: stacked ? 38 : 46,
                  height: 1.08,
                  letterSpacing: -1.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Each tool understands the information needed for that element, giving you faster capture and more useful quantities than a generic markup application.',
                style: TextStyle(
                  color: Color(0xFF667085),
                  height: 1.6,
                  fontSize: 16,
                ),
              ),
            ],
          );

          final grid = GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: capabilities.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth < 520 ? 2 : 3,
              mainAxisExtent: 92,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final item = capabilities[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEAECF0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$1, size: 22, color: const Color(0xFF155EEF)),
                    const SizedBox(height: 9),
                    Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          );

          if (stacked) {
            return Column(children: [intro, const SizedBox(height: 38), grid]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 4, child: intro),
              const SizedBox(width: 58),
              Expanded(flex: 6, child: grid),
            ],
          );
        },
      ),
    );
  }
}

class _TutorialsSection extends StatelessWidget {
  const _TutorialsSection({super.key});

  Stream<List<TutorialVideo>> _latestVideosStream() {
    return FirebaseFirestore.instance
        .collection('tutorial_videos')
        .orderBy('createdAt', descending: true)
        .limit(8)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map(TutorialVideo.fromDoc)
                  .where((video) => video.isPublished)
                  .take(3)
                  .toList(),
        );
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: _PageWidth(
        padding: const EdgeInsets.fromLTRB(22, 86, 22, 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final heading = const _SectionHeading(
                  alignLeft: true,
                  eyebrow: 'WATCH AND LEARN',
                  title: 'Tutorial videos for faster takeoff work.',
                  subtitle:
                      'View practical short videos on measuring, calibration, BOQ setup, and project workflow.',
                );
                final button = FilledButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.tutorialVideos),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('View all tutorials'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF155EEF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [heading, const SizedBox(height: 18), button],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 20),
                    button,
                  ],
                );
              },
            ),
            const SizedBox(height: 34),
            StreamBuilder<List<TutorialVideo>>(
              stream: _latestVideosStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final videos = snapshot.data ?? const <TutorialVideo>[];
                if (videos.isEmpty) {
                  return const _LandingTutorialEmpty();
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth < 680
                            ? 1
                            : constraints.maxWidth < 980
                            ? 2
                            : 3;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 18) / columns;
                    return Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        for (final video in videos)
                          SizedBox(
                            width: width,
                            child: TutorialVideoCard(
                              video: video,
                              onPlay: () => _openVideo(video.youtubeUrl),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingTutorialEmpty extends StatelessWidget {
  const _LandingTutorialEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.video_library_outlined, color: Color(0xFF155EEF)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tutorial videos will show here when the admin uploads them.',
              style: TextStyle(
                color: Color(0xFF475467),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: _PageWidth(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 54),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const stats = [
              _Stat(value: '1', label: 'source of truth for quantities'),
              _Stat(value: '22+', label: 'purpose-built takeoff tools'),
              _Stat(value: '7', label: 'step workflow from setup to BOQ'),
              _Stat(value: '100%', label: 'traceable measurement geometry'),
            ];
            if (constraints.maxWidth < 700) {
              return Wrap(
                spacing: 20,
                runSpacing: 28,
                children:
                    stats
                        .map((stat) => SizedBox(width: 145, child: stat))
                        .toList(),
              );
            }
            return Row(
              children: [
                Expanded(child: stats[0]),
                const _Divider(),
                Expanded(child: stats[1]),
                const _Divider(),
                Expanded(child: stats[2]),
                const _Divider(),
                Expanded(child: stats[3]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF155EEF),
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 54, color: const Color(0xFFEAECF0));
  }
}

class _ClosingCta extends StatelessWidget {
  const _ClosingCta({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _PageWidth(
      padding: const EdgeInsets.fromLTRB(22, 88, 22, 88),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 46),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF155EEF), Color(0xFF004EEB)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your next takeoff can be clearer.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: stacked ? 29 : 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Create a project, upload a drawing, and keep the complete quantity trail in one workspace.',
                  style: TextStyle(
                    color: Color(0xFFD1E0FF),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ],
            );
            final button = FilledButton.icon(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF155EEF),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 17,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text(
                'Start measuring',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 26), button],
              );
            }
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 30),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({super.key});

  Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F9FC),
      child: _PageWidth(
        padding: const EdgeInsets.fromLTRB(22, 82, 22, 40),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;
            final intro = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow(
                  icon: Icons.support_agent_rounded,
                  text: 'CONTACT',
                ),
                const SizedBox(height: 18),
                Text(
                  'Need help, pricing, or implementation support?',
                  style: TextStyle(
                    color: const Color(0xFF101828),
                    fontSize: stacked ? 34 : 44,
                    height: 1.08,
                    letterSpacing: -1.4,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Send a message and it will appear inside the Admin dashboard. This keeps sales, support, and product feedback in one controlled place.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    height: 1.6,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                const Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _ContactPoint(
                      icon: Icons.lock_outline_rounded,
                      label: 'Stored securely in Firestore',
                    ),
                    _ContactPoint(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Visible to admin users',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ContactActionChip(
                      icon: Icons.call_outlined,
                      label: '+255 746 575 399',
                      onTap:
                          () =>
                              _open(Uri(scheme: 'tel', path: '+255746575399')),
                    ),
                    _ContactActionChip(
                      icon: Icons.chat_outlined,
                      label: 'WhatsApp +255 789 097 907',
                      onTap:
                          () => _open(
                            Uri.https('wa.me', '/255789097907', {
                              'text':
                                  'Hello AQS AutoBOQ, I need help with pricing or implementation.',
                            }),
                          ),
                    ),
                    _SocialActionChip(
                      label: 'Instagram',
                      badge: 'IG',
                      onTap:
                          () =>
                              _open(Uri.https('instagram.com', '/aqsautoboq')),
                    ),
                    _SocialActionChip(
                      label: 'Facebook',
                      badge: 'f',
                      onTap:
                          () => _open(Uri.https('facebook.com', '/aqsautoboq')),
                    ),
                    _SocialActionChip(
                      label: 'LinkedIn',
                      badge: 'in',
                      onTap:
                          () => _open(
                            Uri.https(
                              'www.linkedin.com',
                              '/company/aqsautoboq',
                            ),
                          ),
                    ),
                  ],
                ),
              ],
            );
            const form = ContactFormCard(source: 'landing');
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [intro, const SizedBox(height: 28), form],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: intro),
                const SizedBox(width: 42),
                const Expanded(flex: 6, child: form),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ContactPoint extends StatelessWidget {
  const _ContactPoint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF155EEF)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactActionChip extends StatelessWidget {
  const _ContactActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF155EEF),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x22155EEF),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

class _SocialActionChip extends StatelessWidget {
  const _SocialActionChip({
    required this.label,
    required this.badge,
    required this.onTap,
  });

  final String label;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label · @aqsautoboq',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              color: Color(0xFF155EEF),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101828),
      child: _PageWidth(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: LayoutBuilder(
          builder:
              (context, constraints) => Row(
                children: [
                  const Text(
                    'AQS AutoBOQ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (constraints.maxWidth > 620)
                    const Text(
                      'AQS AutoBOQ · Quantity intelligence for the built environment',
                      style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
                    ),
                ],
              ),
        ),
      ),
    );
  }
}

class _PageWidth extends StatelessWidget {
  const _PageWidth({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.dark = false,
    this.alignLeft = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final bool dark;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          eyebrow,
          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: dark ? const Color(0xFF84ADFF) : const Color(0xFF155EEF),
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Text(
            title,
            textAlign: alignLeft ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF101828),
              fontSize: 38,
              height: 1.12,
              letterSpacing: -1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 15),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 730),
          child: Text(
            subtitle,
            textAlign: alignLeft ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              color: dark ? const Color(0xFF98A2B3) : const Color(0xFF667085),
              fontSize: 16,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD1E0FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF155EEF)),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF1849A9),
              fontSize: 10,
              letterSpacing: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF12B76A), size: 18),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF475467),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
