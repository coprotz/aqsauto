import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _AboutNav()),
            const SliverToBoxAdapter(child: _AboutHero()),
            const SliverToBoxAdapter(child: _VisionMissionSection()),
            const SliverToBoxAdapter(child: _CeoSection()),
            const SliverToBoxAdapter(child: _WhatWeBelieveSection()),
            SliverToBoxAdapter(child: _AboutCta()),
          ],
        ),
      ),
    );
  }
}

class _AboutNav extends StatelessWidget {
  const _AboutNav();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.96),
      child: _AboutWidth(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            return Row(
              children: [
                const AqsBrand(),
                const Spacer(),
                if (compact)
                  IconButton(
                    tooltip: 'Menu',
                    onPressed: () => _openAboutMenu(context),
                    icon: const Icon(Icons.menu_rounded),
                  )
                else ...[
                  TextButton(
                    onPressed: () => Get.offAllNamed(AppRoutes.landing),
                    child: const Text('Home'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Get.toNamed(AppRoutes.dashboard),
                    child: const Text('Open dashboard'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _openAboutMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
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
                  const SizedBox(height: 14),
                  const AqsBrand(),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(
                      Icons.home_outlined,
                      color: AqsColors.primary,
                    ),
                    title: const Text('Home'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.offAllNamed(AppRoutes.landing);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.dashboard_outlined,
                      color: AqsColors.primary,
                    ),
                    title: const Text('Open dashboard'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.toNamed(AppRoutes.dashboard);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8FAFF), Color(0xFFEFF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: _AboutWidth(
        padding: const EdgeInsets.fromLTRB(22, 74, 22, 78),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 880;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AboutPill(
                  icon: Icons.architecture_outlined,
                  label: 'ABOUT AQS AUTOBOQ',
                ),
                const SizedBox(height: 22),
                Text(
                  'Built by a Quantity Surveyor, for Quantity Surveyors.',
                  style: TextStyle(
                    color: AqsColors.ink,
                    fontSize: stacked ? 42 : 58,
                    height: 1.02,
                    letterSpacing: -2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'AQS AutoBOQ exists to reduce the repetitive pressure of taking off quantities and preparing BOQs. It connects drawings, measurements, BOQ items, reports, and teams in one workspace so Quantity Surveyors can work faster with better traceability.',
                  style: TextStyle(
                    color: AqsColors.muted,
                    fontSize: 17,
                    height: 1.65,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => Get.toNamed(AppRoutes.dashboard),
                      icon: const Icon(Icons.dashboard_outlined),
                      label: const Text('Open workspace'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Get.offAllNamed(AppRoutes.landing),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back to landing'),
                    ),
                  ],
                ),
              ],
            );
            const portrait = _FounderPortrait();
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 34), portrait],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 50),
                const Expanded(flex: 5, child: portrait),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FounderPortrait extends StatelessWidget {
  const _FounderPortrait();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22155EEF),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/aurea_salvatory.png',
              height: 360,
              width: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Aurea Salvatory',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'CEO · AQS AUTOBOQ',
            style: TextStyle(
              color: AqsColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisionMissionSection extends StatelessWidget {
  const _VisionMissionSection();

  @override
  Widget build(BuildContext context) {
    return _AboutWidth(
      padding: const EdgeInsets.fromLTRB(22, 72, 22, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final cards = [
            const _AboutCard(
              icon: Icons.visibility_outlined,
              title: 'Our vision',
              body:
                  'To become the trusted digital quantity surveying workspace for construction teams across Africa and beyond, where every quantity is clear, traceable, and easier to verify.',
            ),
            const _AboutCard(
              icon: Icons.flag_outlined,
              title: 'Our mission',
              body:
                  'To simplify QS work by turning drawings into structured measurements, BOQs, and reports while reducing repetitive manual work, errors, and disconnected spreadsheets.',
            ),
          ];
          if (stacked) {
            return Column(
              children: [cards[0], const SizedBox(height: 16), cards[1]],
            );
          }
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 18),
              Expanded(child: cards[1]),
            ],
          );
        },
      ),
    );
  }
}

class _CeoSection extends StatelessWidget {
  const _CeoSection();

  @override
  Widget build(BuildContext context) {
    return _AboutWidth(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 42),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AqsColors.primaryDark,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x220B2B67),
              blurRadius: 28,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 820;
            final quote = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(
                  Icons.format_quote_rounded,
                  color: Color(0xFF84ADFF),
                  size: 42,
                ),
                SizedBox(height: 10),
                Text(
                  'Words from the CEO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'As a Quantity Surveyor, I have seen how much time fellow QS professionals spend taking off quantities, checking drawings, linking measurements to BOQ items, and rebuilding schedules under pressure. AQS AutoBOQ was created from that real experience: to make QS work simpler, faster, and more reliable without losing professional control.',
                  style: TextStyle(
                    color: Color(0xFFDDE7FF),
                    fontSize: 17,
                    height: 1.65,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Our goal is not to replace the Quantity Surveyor. Our goal is to remove unnecessary struggle, so the QS can focus on judgment, accuracy, cost control, and advising the project team.',
                  style: TextStyle(
                    color: Color(0xFFDDE7FF),
                    fontSize: 17,
                    height: 1.65,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  '— Aurea Salvatory, CEO & Founder',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            );
            const values = _CeoValueList();
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [quote, const SizedBox(height: 24), values],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: quote),
                const SizedBox(width: 30),
                const Expanded(flex: 4, child: values),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CeoValueList extends StatelessWidget {
  const _CeoValueList();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Practical', 'Built around the daily workflow of real QS teams.'),
      ('Traceable', 'Every measurement can remain connected to its BOQ item.'),
      ('Collaborative', 'Projects, clients, teams, and reports stay together.'),
    ];
    return Column(
      children: [
        for (final item in items) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF84ADFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          color: Color(0xFFDDE7FF),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (item != items.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _WhatWeBelieveSection extends StatelessWidget {
  const _WhatWeBelieveSection();

  @override
  Widget build(BuildContext context) {
    const beliefs = [
      _AboutCard(
        icon: Icons.fact_check_outlined,
        title: 'Better measurement records',
        body:
            'AQS AutoBOQ keeps measurements linked to BOQ items, making review and verification easier.',
      ),
      _AboutCard(
        icon: Icons.speed_outlined,
        title: 'Less repetitive work',
        body:
            'The platform is designed to reduce repeated copying between drawings, spreadsheets, and BOQ schedules.',
      ),
      _AboutCard(
        icon: Icons.groups_outlined,
        title: 'A stronger QS profession',
        body:
            'By reducing manual pressure, QS professionals can spend more time on analysis, judgment, and project advice.',
      ),
    ];
    return _AboutWidth(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 72),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 720 ? 1 : 3;
          return GridView.count(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 1 ? 2.4 : 0.98,
            children: beliefs,
          );
        },
      ),
    );
  }
}

class _AboutCta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _AboutWidth(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 72),
      child: Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AqsColors.primary, Color(0xFF004EEB)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Ready to simplify QS work?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Start from one project, one drawing, and one BOQ item. Build the measurement trail from there.',
                  style: TextStyle(color: Color(0xFFDDE7FF), height: 1.5),
                ),
              ],
            );
            final action = FilledButton.icon(
              onPressed: () => Get.toNamed(AppRoutes.dashboard),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AqsColors.primary,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Open AQS AutoBOQ'),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 20), action],
              );
            }
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 20),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AqsColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(color: AqsColors.muted, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _AboutPill extends StatelessWidget {
  const _AboutPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD1E0FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AqsColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1849A9),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutWidth extends StatelessWidget {
  const _AboutWidth({required this.child, required this.padding});

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
