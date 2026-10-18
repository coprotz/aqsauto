import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/pricing/views/pricing_plans_page.dart';

// Adjust these 2 imports if your actual paths differ.
// import 'package:aqs/features/subscription/services/subscription_service.dart';
import 'package:aqs/features/subscription/pages/pricing_plans_page.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  String _initials(User? user) {
    final name = (user?.displayName ?? '').trim();

    if (name.isNotEmpty) {
      final parts =
          name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();

      if (parts.length == 1) {
        return parts.first.substring(0, 1).toUpperCase();
      }

      return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
          .toUpperCase();
    }

    final email = (user?.email ?? '').trim();

    if (email.isNotEmpty) {
      return email.substring(0, 1).toUpperCase();
    }

    return '?';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _myProjectsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('projects')
        .where('members', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }

    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),

      builder: (context, authSnapshot) {
        final user = authSnapshot.data ?? FirebaseAuth.instance.currentUser;

        if (user == null) {
          return const Scaffold(body: Center(child: Text('Not signed in')));
        }

        return StreamBuilder<AqsSubscription>(
          stream: SubscriptionService.instance.watchSubscription(user: user),

          initialData: AqsSubscription.free,

          builder: (context, subscriptionSnapshot) {
            final subscription =
                subscriptionSnapshot.data ?? AqsSubscription.free;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _myProjectsStream(user.uid),

              builder: (context, projectsSnapshot) {
                final projects = projectsSnapshot.data?.docs ?? const [];

                return _buildPage(
                  context: context,
                  user: user,
                  subscription: subscription,
                  projects: projects,
                  projectsLoading:
                      projectsSnapshot.connectionState ==
                      ConnectionState.waiting,
                  projectsError: projectsSnapshot.error,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPage({
    required BuildContext context,
    required User user,
    required AqsSubscription subscription,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> projects,
    required bool projectsLoading,
    required Object? projectsError,
  }) {
    final cs = Theme.of(context).colorScheme;

    final photo = (user.photoURL ?? '').trim();

    final projectCount = projects.length;

    return Scaffold(
      backgroundColor: AqsColors.canvas,

      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AqsBrand(compact: true, markSize: 32),
            SizedBox(width: 12),
            Text('Account'),
          ],
        ),

        actions: [
          TextButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();

              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),

          const SizedBox(width: 10),
        ],
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),

          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),

            children: [
              /*
               * Header
               */
              const Text(
                'Account & Subscription',
                style: TextStyle(
                  color: AqsColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Manage your profile, subscription and AQS projects.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 24),

              /*
               * Profile + Subscription
               */
              LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth > 780;

                  if (desktop) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: _ProfileCard(
                            user: user,
                            photo: photo,
                            initials: _initials(user),
                          ),
                        ),

                        const SizedBox(width: 18),

                        Expanded(
                          flex: 6,
                          child: _SubscriptionCard(
                            subscription: subscription,
                            projectCount: projectCount,
                            expiryLabel: _formatDate(subscription.expiresAt),
                            onManagePlan: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PricingPlansPage(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      _ProfileCard(
                        user: user,
                        photo: photo,
                        initials: _initials(user),
                      ),

                      const SizedBox(height: 16),

                      _SubscriptionCard(
                        subscription: subscription,
                        projectCount: projectCount,
                        expiryLabel: _formatDate(subscription.expiresAt),
                        onManagePlan: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PricingPlansPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),

              /*
               * Projects Header
               */
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Projects',
                          style: TextStyle(
                            color: AqsColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Projects where you are an owner or team member.',
                          style: TextStyle(
                            color: AqsColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  FilledButton.icon(
                    onPressed: () {
                      /*
                       * Connect to your
                       * new-project flow.
                       */
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New project'),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              if (projectsLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (projectsError != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: cs.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Could not load projects: '
                            '$projectsError',
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (projects.isEmpty)
                _EmptyProjectsCard(
                  onCreate: () {
                    /*
                     * Connect new-project flow.
                     */
                  },
                )
              else
                _ProjectsList(projects: projects, userId: user.uid),
            ],
          ),
        ),
      ),
    );
  }
}

/*
 * =========================================================
 * PROFILE CARD
 * =========================================================
 */

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.photo,
    required this.initials,
  });

  final User user;
  final String photo;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: AqsColors.primary.withOpacity(0.10),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child:
                    photo.isNotEmpty
                        ? null
                        : Text(
                          initials,
                          style: const TextStyle(
                            color: AqsColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (user.displayName ?? 'AQS User').trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      (user.email ?? '').trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          const Divider(height: 1),

          const SizedBox(height: 18),

          const _ProfileInfoRow(
            icon: Icons.verified_user_outlined,
            label: 'Account',
            value: 'Verified user',
          ),

          const SizedBox(height: 14),

          _ProfileInfoRow(
            icon: Icons.fingerprint_rounded,
            label: 'User ID',
            value: user.uid,
          ),

          // const Spacer(),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                /*
                 * Add EditProfilePage
                 * later.
                 */
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AqsColors.muted),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AqsColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/*
 * =========================================================
 * SUBSCRIPTION CARD
 * =========================================================
 */

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.projectCount,
    required this.expiryLabel,
    required this.onManagePlan,
  });

  final AqsSubscription subscription;

  final int projectCount;

  final String expiryLabel;

  final VoidCallback onManagePlan;

  @override
  Widget build(BuildContext context) {
    final isPaid = subscription.isActivePaid;

    final expired = subscription.isExpired;

    final projectLimit = subscription.projectLimit;

    final userLimit = subscription.userLimit;

    final double projectUsage;

    if (projectLimit <= 0) {
      projectUsage = 0.0;
    } else {
      projectUsage = (projectCount / projectLimit).clamp(0.0, 1.0).toDouble();
    }

    final statusLabel =
        expired
            ? 'Expired'
            : isPaid
            ? 'Active'
            : 'Free';

    final statusColor =
        expired
            ? const Color(0xFFD92D20)
            : isPaid
            ? const Color(0xFF039855)
            : const Color(0xFF667085);

    final statusBackground =
        expired
            ? const Color(0xFFFEF3F2)
            : isPaid
            ? const Color(0xFFECFDF3)
            : const Color(0xFFF2F4F7);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SUBSCRIPTION',
                      style: TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 9),

                    Text(
                      '${subscription.displayName} Plan',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),

                    if (!subscription.isFree) ...[
                      const SizedBox(height: 5),

                      Text(
                        subscription.billingCycleLabel,
                        style: const TextStyle(
                          color: Color(0xFFD0D5DD),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),

                    const SizedBox(width: 7),

                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (subscription.isActivePaid)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_available_outlined,
                    color: Color(0xFF86EFAC),
                  ),

                  const SizedBox(width: 11),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Subscription valid until',
                          style: TextStyle(
                            color: Color(0xFF98A2B3),
                            fontSize: 11,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          expiryLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Upgrade to unlock more projects, drawings and advanced AQS tools.',
                style: TextStyle(
                  color: Color(0xFFD0D5DD),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const SizedBox(height: 22),

          /*
           * Project usage
           */
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 20,
                color: Color(0xFFD0D5DD),
              ),

              const SizedBox(width: 10),

              const Expanded(
                child: Text(
                  'Projects',
                  style: TextStyle(
                    color: Color(0xFFD0D5DD),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              Text(
                '$projectCount / $projectLimit',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: projectUsage,
              backgroundColor: Colors.white.withOpacity(0.10),
            ),
          ),

          const SizedBox(height: 18),

          _SubscriptionFeatureRow(
            icon: Icons.people_alt_outlined,
            label:
                userLimit == 1 ? '1 account user' : '$userLimit account users',
          ),

          const SizedBox(height: 11),

          _SubscriptionFeatureRow(
            icon: Icons.workspace_premium_outlined,
            label:
                subscription.isFree
                    ? 'Free tools only'
                    : '${subscription.displayName} features enabled',
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onManagePlan,
              icon: Icon(
                subscription.isFree
                    ? Icons.upgrade_rounded
                    : Icons.settings_outlined,
              ),
              label: Text(
                subscription.isFree ? 'Upgrade plan' : 'Manage subscription',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AqsColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionFeatureRow extends StatelessWidget {
  const _SubscriptionFeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF98A2B3), size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD0D5DD),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/*
 * =========================================================
 * PROJECTS
 * =========================================================
 */

class _ProjectsList extends StatelessWidget {
  const _ProjectsList({required this.projects, required this.userId});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> projects;

  final String userId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = projects[index];

        final data = doc.data();

        final name = (data['name'] ?? 'Project').toString();

        final ownerId = (data['ownerId'] ?? '').toString();

        final members = (data['members'] as List?) ?? const [];

        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        final isOwner = ownerId == userId;

        String createdLabel = '';

        if (createdAt != null) {
          final day = createdAt.day.toString().padLeft(2, '0');

          final month = createdAt.month.toString().padLeft(2, '0');

          createdLabel = '$day/$month/${createdAt.year}';
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7EAF0)),
          ),

          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),

            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AqsColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                isOwner ? Icons.folder_special_outlined : Icons.folder_outlined,
                color: AqsColors.primary,
              ),
            ),

            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AqsColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),

            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${members.length} member(s)'
                '${createdLabel.isEmpty ? '' : ' • $createdLabel'}',
                style: const TextStyle(color: AqsColors.muted),
              ),
            ),

            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOwner)
                  Chip(
                    label: const Text('Owner'),
                    backgroundColor: cs.primaryContainer,
                    side: BorderSide.none,
                  ),

                const SizedBox(width: 8),

                const Icon(Icons.chevron_right_rounded, color: AqsColors.muted),
              ],
            ),

            onTap: () {
              Get.toNamed(AppRoutes.projectBuildingsPath(doc.id, name));
            },
          ),
        );
      },
    );
  }
}

class _EmptyProjectsCard extends StatelessWidget {
  const _EmptyProjectsCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EAF0)),
      ),

      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AqsColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_outlined,
              color: AqsColors.primary,
              size: 28,
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'No projects yet',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Create your first AQS project to start measuring drawings and preparing BOQs.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AqsColors.muted, height: 1.45),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create project'),
          ),
        ],
      ),
    );
  }
}
