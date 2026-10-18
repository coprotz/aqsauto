import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/auth/auth_project_gate.dart';
import 'package:aqs/features/auth/create_project.dart';
import 'package:aqs/features/auth/login_page.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/boq/views/boq_templates_page_getx.dart';
import 'package:aqs/features/dashboards/components/top_bar.dart';
import 'package:aqs/features/dashboards/controllers/dashboard_controller.dart';
import 'package:aqs/features/dashboards/views/pages/dashboard.dart';
import 'package:aqs/features/pricing/views/pricing_plans_page.dart';
import 'package:aqs/features/reports/views/reports_page.dart';
import 'package:aqs/features/ipc/ipc_page.dart';
import 'package:aqs/features/support/views/help_support_page.dart';
import 'package:aqs/features/team/views/team_page.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardController controller;

  @override
  void initState() {
    super.initState();

    controller =
        Get.isRegistered<DashboardController>()
            ? Get.find<DashboardController>()
            : Get.put(DashboardController(), permanent: true);
  }

  @override
  Widget build(BuildContext context) {
    return AuthProjectGate(
      goToAuth:
          () => LoginPage(
            onLoggedInGoTo: () {
              Get.offAllNamed(AppRoutes.dashboard);
              return const SizedBox.shrink();
            },
            onGoToRegister: () {
              Get.toNamed(AppRoutes.createProject);
            },
          ),
      goToCreateProject: () => const RegisterAndCreateProjectPage(),
      builder: (user, _) {
        final sections = _dashboardSections(user);

        return Scaffold(
          backgroundColor: AqsColors.canvas,
          body: Obx(() {
            final selectedSection = controller.selectedSection.value;

            final safeSection =
                selectedSection < 0
                    ? 0
                    : selectedSection > sections.length
                    ? sections.length
                    : selectedSection;

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.012, 0),
                  end: Offset.zero,
                ).animate(animation);

                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child:
                  safeSection == 0
                      ? _DashboardHub(
                        key: const ValueKey('dashboard-hub'),
                        user: user,
                        firstName: _firstName(user),
                        email: _email(user),
                        sections: sections,
                        onOpenSection: controller.openSection,
                        onViewPlan: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PricingPlansPage(),
                            ),
                          );
                        },
                      )
                      : _SectionWorkspace(
                        key: ValueKey('dashboard-section-$safeSection'),
                        section: sections[safeSection - 1],
                        onBack: controller.openHome,
                      ),
            );
          }),
        );
      },
    );
  }

  List<_DashboardSection> _dashboardSections(dynamic user) {
    return [
      _DashboardSection(
        title: 'Projects',
        subtitle: 'Open projects, buildings, drawings, BOQs, and measurements.',
        icon: Icons.folder_copy_outlined,
        gradient: const [Color(0xFF0F3B8F), Color(0xFF155EEF)],
        accent: const Color(0xFF155EEF),
        page: () => Dashboard(search: search, user: user, fullRegister: true),
      ),

      _DashboardSection(
        title: 'Build-Up Rates',
        subtitle: 'Build, save, and reuse transparent rates for BOQ items.',
        icon: Icons.calculate_outlined,
        gradient: const [Color(0xFF0E7490), Color(0xFF06B6D4)],
        accent: const Color(0xFF0891B2),
        route: AppRoutes.buildUpRates,
      ),

      _DashboardSection(
        title: 'Labour Rates',
        subtitle: 'Daily wage library and automatic labour-only unit rate build-ups.',
        icon: Icons.engineering_outlined,
        gradient: const [Color(0xFF245C45), Color(0xFF10B981)],
        accent: const Color(0xFF047857),
        route: AppRoutes.labourRates,
      ),

      _DashboardSection(
        title: 'Materials Price List',
        subtitle: 'Compare current construction material prices by supplier.',
        icon: Icons.price_check_outlined,
        gradient: const [Color(0xFF047857), Color(0xFF10B981)],
        accent: const Color(0xFF059669),
        route: AppRoutes.materialPrices,
      ),

      _DashboardSection(
        title: 'BOQ Templates',
        subtitle: 'Create and maintain reusable BOQ structures.',
        icon: Icons.view_list_rounded,
        gradient: const [Color(0xFF5B21B6), Color(0xFF8B5CF6)],
        accent: const Color(0xFF7C3AED),
        page: _boqTemplatesPage,
      ),

      _DashboardSection(
        title: 'Reports',
        subtitle: 'Review cost, valuation, and project progress reports.',
        icon: Icons.bar_chart_rounded,
        gradient: const [Color(0xFF9A3412), Color(0xFFF97316)],
        accent: const Color(0xFFEA580C),
        page: ReportsPage.new,
      ),

      _DashboardSection(
        title: 'Team',
        subtitle: 'Invite members and manage roles and permissions.',
        icon: Icons.groups_2_rounded,
        gradient: const [Color(0xFF047857), Color(0xFF10B981)],
        accent: const Color(0xFF059669),
        page: TeamPage.new,
      ),

      _DashboardSection(
        title: 'Interim Payment Certificates',
        subtitle:
            'Prepare IPC BOQs, choose buildings, and import external BOQs.',
        icon: Icons.request_quote_outlined,
        gradient: const [Color(0xFF075985), Color(0xFF0891B2)],
        accent: const Color(0xFF0891B2),
        page: IpcPage.new,
      ),

      _DashboardSection(
        title: 'Help & Support',
        subtitle: 'Find guidance, tutorials, and contact support.',
        icon: Icons.support_agent_rounded,
        gradient: const [Color(0xFF334155), Color(0xFF64748B)],
        accent: const Color(0xFF475569),
        page: HelpSupportPage.new,
      ),
    ];
  }
}

Widget _boqTemplatesPage() => const BoqTemplatesPageGetX(showAppBar: false);

String _firstName(dynamic user) {
  final raw = '${user.displayName ?? user.email ?? 'there'}'.trim();
  if (raw.isEmpty) return 'there';
  final name = raw.contains('@') ? raw.split('@').first : raw;
  return name.split(RegExp(r'\s+')).first;
}

String _email(dynamic user) => '${user.email ?? ''}'.trim();

class _DashboardSection {
  const _DashboardSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.accent,
    this.page,
    this.route,
  }) : assert(page != null || route != null);

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final Color accent;
  final Widget Function()? page;
  final String? route;
}

class _DashboardHub extends StatelessWidget {
  const _DashboardHub({
    super.key,
    required this.firstName,
    required this.email,
    required this.user,
    required this.sections,
    required this.onOpenSection,
    required this.onViewPlan,
  });

  final User user;
  final String firstName;
  final String email;
  final List<_DashboardSection> sections;
  final ValueChanged<int> onOpenSection;
  final VoidCallback onViewPlan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TopBar(
          search: search,
          title: 'Dashboard',
          subtitle: 'Overview of your quantity surveying work',
          showSearch: false,
          onChanged: () => page = 1,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = _horizontalPadding(constraints.maxWidth);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 36),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WelcomeHero(
                          firstName: firstName,
                          email: email,
                          user: user,
                          onViewPlan: onViewPlan,
                        ),
                        const SizedBox(height: 28),
                        const _SectionIntro(),
                        const SizedBox(height: 16),
                        _SectionGrid(
                          sections: sections,
                          onOpenSection: onOpenSection,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionWorkspace extends StatelessWidget {
  const _SectionWorkspace({
    super.key,
    required this.section,
    required this.onBack,
  });

  final _DashboardSection section;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TopBar(
          search: search,
          title: section.title,
          subtitle: section.subtitle,
          showSearch: false,
          onChanged: () => page = 1,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Dashboard'),
          ),
        ),
        Expanded(child: section.page?.call() ?? const SizedBox.shrink()),
      ],
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({
    required this.firstName,
    required this.email,
    required this.user,
    required this.onViewPlan,
  });

  final String firstName;
  final String email;
  final User user;
  final VoidCallback onViewPlan;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final content = Wrap(
      spacing: 18,
      runSpacing: 18,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Icon(
            Icons.engineering_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, $firstName',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 26 : 32,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                'Continue your take-offs, BOQs, reports, clients, and team management from one clean workspace.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: compact ? 14 : 16,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 14),
              _HeroPill(
                icon: Icons.mail_outline_rounded,
                label: 'Signed in',
                value: email,
              ),
            ],
          ],
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(compact ? 22 : 30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2B67), Color(0xFF155EEF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF155EEF).withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -80,
            child: _GlowOrb(size: 220, opacity: 0.16),
          ),
          Positioned(
            right: 120,
            bottom: -120,
            child: _GlowOrb(size: 260, opacity: 0.10),
          ),
          Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment:
                compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (compact) content else Expanded(child: content),
              SizedBox(width: compact ? 0 : 24, height: compact ? 24 : 0),
              _PlanPanel(user: user, onViewPlan: onViewPlan),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
    const textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Workspace',
          style: TextStyle(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: AqsColors.ink,
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Choose where you want to work. Each card opens a dedicated area.',
          style: TextStyle(
            color: AqsColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [textBlock],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [Expanded(child: textBlock)],
    );
  }
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.user, required this.onViewPlan});

  final User user;
  final VoidCallback onViewPlan;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AqsSubscription>(
      stream: SubscriptionService.instance.watchSubscription(user: user),
      initialData: AqsSubscription.free,
      builder: (context, snapshot) {
        final subscription = snapshot.data ?? AqsSubscription.free;
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final compact = MediaQuery.sizeOf(context).width < 600;
        final plan = _HeroPill(
          icon:
              subscription.isActivePaid
                  ? Icons.workspace_premium_outlined
                  : Icons.verified_user_outlined,
          label: 'Current plan',
          value: loading ? 'Loading...' : _subscriptionPlanLabel(subscription),
        );
        final button = FilledButton(
          onPressed: onViewPlan,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AqsColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
          child: const Text('View plan'),
        );

        return Container(
          width: compact ? double.infinity : null,
          constraints: BoxConstraints(
            minWidth: compact ? 0 : 280,
            maxWidth: 390,
          ),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child:
              compact
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [plan, const SizedBox(height: 12), button],
                  )
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(child: plan),
                      const SizedBox(width: 12),
                      button,
                    ],
                  ),
        );
      },
    );
  }

  String _subscriptionPlanLabel(AqsSubscription subscription) {
    final cycle = subscription.billingCycleLabel;
    if (subscription.isActivePaid && cycle.isNotEmpty) {
      return '${subscription.displayName} · $cycle';
    }

    return subscription.displayName;
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.sections, required this.onOpenSection});

  final List<_DashboardSection> sections;
  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1050
                ? 3
                : constraints.maxWidth >= 680
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sections.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            mainAxisExtent: columns == 1 ? 230 : 260,
          ),
          itemBuilder: (context, index) {
            return _WorkspaceCard(
              section: sections[index],
              onTap: () {
                final route = sections[index].route;
                if (route != null) {
                  Get.toNamed(route);
                  return;
                }
                onOpenSection(index);
              },
            );
          },
        );
      },
    );
  }
}

class _WorkspaceCard extends StatefulWidget {
  const _WorkspaceCard({required this.section, required this.onTap});

  final _DashboardSection section;
  final VoidCallback onTap;

  @override
  State<_WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<_WorkspaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color:
                _hovered
                    ? section.accent.withValues(alpha: 0.35)
                    : AqsColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF101828,
              ).withValues(alpha: _hovered ? 0.12 : 0.06),
              blurRadius: _hovered ? 28 : 18,
              offset: Offset(0, _hovered ? 16 : 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: section.gradient),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: section.accent.withValues(alpha: 0.22),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(section.icon, color: Colors.white),
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              _hovered
                                  ? section.accent
                                  : section.accent.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                          color: _hovered ? Colors.white : section.accent,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.82), size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

double _horizontalPadding(double width) {
  if (width >= 1200) return 48;
  if (width >= 760) return 28;
  return 16;
}
