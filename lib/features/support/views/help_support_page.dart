import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/contact/widgets/contact_form_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  Future<void> _openWhatsApp(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final message = [
      'Hello AQS Support, I need help.',
      if (user?.email != null) 'Account: ${user!.email}',
      if (user?.uid != null) 'UID: ${user!.uid}',
    ].join('\n');
    final uri = Uri.https('wa.me', '/', {'text': message});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@aqsautoboq.com',
      queryParameters: {
        'subject': 'AQS AUTOboq support request',
        'body': [
          'Describe the issue:',
          '',
          'Account: ${user?.email ?? '-'}',
          'UID: ${user?.uid ?? '-'}',
        ].join('\n'),
      },
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app.')),
      );
    }
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final text = [
      'AQS AUTOboq diagnostics',
      'Email: ${user?.email ?? '-'}',
      'UID: ${user?.uid ?? '-'}',
      'Platform: Web / Flutter app',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics copied.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            compact ? 16 : 22,
            compact ? 16 : 24,
            32,
          ),
          children: [
            _SupportHero(
              onWhatsApp: () => _openWhatsApp(context),
              onEmail: () => _openEmail(context),
              onCopyDiagnostics: () => _copyDiagnostics(context),
            ),
            const SizedBox(height: 18),
            const ContactFormCard(source: 'help-support', compact: true),
            const SizedBox(height: 18),
            const _WorkflowGuide(),
            const SizedBox(height: 18),
            const _HelpTopicsGrid(),
            const SizedBox(height: 18),
            const _TroubleshootingSection(),
            const SizedBox(height: 18),
            const _FaqSection(),
          ],
        );
      },
    );
  }
}

class _SupportHero extends StatelessWidget {
  const _SupportHero({
    required this.onWhatsApp,
    required this.onEmail,
    required this.onCopyDiagnostics,
  });

  final VoidCallback onWhatsApp;
  final VoidCallback onEmail;
  final VoidCallback onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AqsColors.primaryDark, Color(0xFF155EEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22155EEF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              AqsBrand(onDark: true),
              SizedBox(height: 22),
              Text(
                'Help & support',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Get guidance for projects, drawings, measurements, BOQs, reports, team invites, and billing.',
                style: TextStyle(color: Color(0xFFD6E4FF), height: 1.45),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onWhatsApp,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('WhatsApp support'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AqsColors.primary,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onEmail,
                icon: const Icon(Icons.email_outlined),
                label: const Text('Email support'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.45)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCopyDiagnostics,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy diagnostics'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.45)),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, const SizedBox(height: 18), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 24),
              SizedBox(width: 360, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _WorkflowGuide extends StatelessWidget {
  const _WorkflowGuide();

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Create project', 'Set project, client, region, and stage.'),
      ('Add buildings', 'Create working places/buildings for the project.'),
      ('Upload drawings', 'Upload clear PDFs and manage drawings by building.'),
      ('Measure', 'Calibrate drawings, use tools, and link every quantity to BOQ.'),
      ('Review BOQ', 'Check measured quantities, rates, totals, and unmeasured items.'),
      ('Report/export', 'Use Reports for summaries, audit trail, and submissions.'),
    ];
    return _SupportCard(
      title: 'Recommended workflow',
      subtitle: 'Follow this sequence for cleaner quantities and BOQ reporting.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: steps.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: compact ? 1 : 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 104,
            ),
            itemBuilder: (_, i) {
              final step = steps[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AqsColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFEFF4FF),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AqsColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.$1,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.$2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AqsColors.muted,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HelpTopicsGrid extends StatelessWidget {
  const _HelpTopicsGrid();

  @override
  Widget build(BuildContext context) {
    final topics = [
      _Topic(Icons.folder_outlined, 'Projects', 'Create projects and manage access.'),
      _Topic(Icons.description_outlined, 'Drawings', 'Upload, delete, and open drawings.'),
      _Topic(Icons.straighten_rounded, 'Measurements', 'Calibrate drawings and record quantities.'),
      _Topic(Icons.receipt_long_outlined, 'BOQ', 'Import BOQ, add new items, and link measurements.'),
      _Topic(Icons.groups_outlined, 'Team', 'Invite members and choose project access.'),
      _Topic(Icons.analytics_outlined, 'Reports', 'Review BOQ value, unmeasured items, and audit trail.'),
    ];
    return _SupportCard(
      title: 'Help topics',
      subtitle: 'Quick reference for each workspace area.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topics.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: compact ? 1 : 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 118,
            ),
            itemBuilder: (_, i) => _TopicCard(topic: topics[i]),
          );
        },
      ),
    );
  }
}

class _TroubleshootingSection extends StatelessWidget {
  const _TroubleshootingSection();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Drawing is unreadable', 'Delete and re-upload after deploying the high-quality PDF rendering update.'),
      ('Invite link opens localhost', 'Deploy to Firebase Hosting and use the generated web.app invite link.'),
      ('User sees wrong projects', 'Confirm the project members list contains only the intended users.'),
      ('BOQ item missing', 'Use New item in the BOQ picker and place it before/after the right item.'),
    ];
    return _SupportCard(
      title: 'Troubleshooting',
      subtitle: 'Common issues and immediate checks.',
      child: Column(
        children:
            items
                .map(
                  (item) => _SupportListRow(
                    icon: Icons.build_circle_outlined,
                    title: item.$1,
                    body: item.$2,
                  ),
                )
                .toList(),
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  const _FaqSection();

  @override
  Widget build(BuildContext context) {
    return _SupportCard(
      title: 'FAQ',
      subtitle: 'Short answers for repeated questions.',
      child: const Column(
        children: [
          _SupportListRow(
            icon: Icons.lock_outline_rounded,
            title: 'Can invitees see all projects?',
            body: 'No. Invitees should only see projects where their UID is in the members list.',
          ),
          _SupportListRow(
            icon: Icons.calculate_outlined,
            title: 'Where does project cost come from?',
            body: 'Project cost is calculated from BOQ rates and measured or overridden quantities.',
          ),
          _SupportListRow(
            icon: Icons.cloud_upload_outlined,
            title: 'When should I deploy?',
            body: 'Deploy after UI or invite-link changes so remote users receive the latest version.',
          ),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: AqsColors.muted)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});

  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(topic.icon, color: AqsColors.primary),
          const SizedBox(height: 10),
          Text(topic.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            topic.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AqsColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportListRow extends StatelessWidget {
  const _SupportListRow({
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AqsColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(color: AqsColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Topic {
  const _Topic(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}
