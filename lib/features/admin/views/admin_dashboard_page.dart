import 'package:aqs/core/controlers/admin_dashboard_controller.dart';
import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/admin/models/admin_dashboard_data.dart';
import 'package:aqs/features/admin/models/admin_models.dart';
import 'package:aqs/features/admin/models/admin_user_row.dart';
import 'package:aqs/features/admin/models/payment_attemp_line.dart';
import 'package:aqs/features/admin/models/payment_row.dart';
import 'package:aqs/features/admin/models/project_admin_data.dart';
import 'package:aqs/features/admin/models/project_client_row.dart';
import 'package:aqs/features/tutorials/views/admin_tutorial_videos_page.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final AdminDashboardController controller;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    controller =
        Get.isRegistered<AdminDashboardController>()
            ? Get.find<AdminDashboardController>()
            : Get.put(AdminDashboardController(), permanent: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();

    // IMPORTANT:
    // Do NOT delete the GetX controller here.
    //
    // We want state to survive navigation.

    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmUserAction({
    required String title,
    required String message,
    required String actionLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style:
                  destructive
                      ? FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD92D20),
                      )
                      : null,
              onPressed: () {
                Navigator.pop(ctx, true);
              },
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );

    return ok == true;
  }

  Future<void> _changeUserStatus(
    dynamic row,
    String status, {
    bool deleted = false,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (row.uid == currentUid) {
      _snack('You cannot change your own admin account status.');
      return;
    }

    final normalized = status.trim().toLowerCase();

    final confirmed = await _confirmUserAction(
      title:
          normalized == 'suspended'
              ? 'Suspend user?'
              : normalized == 'deleted'
              ? 'Delete user?'
              : 'Activate user?',
      message:
          normalized == 'deleted'
              ? 'This will mark ${row.displayName} as deleted and block access to AQS.'
              : normalized == 'suspended'
              ? 'This will block ${row.displayName} from using AQS until you activate the account again.'
              : 'This will restore access for ${row.displayName}.',
      actionLabel:
          normalized == 'deleted'
              ? 'Delete'
              : normalized == 'suspended'
              ? 'Suspend'
              : 'Activate',
      destructive: normalized == 'deleted',
    );

    if (!confirmed) return;

    try {
      await controller.setUserStatus(row, normalized, deleted: deleted);

      _snack(
        normalized == 'deleted'
            ? 'User deleted from active access.'
            : normalized == 'suspended'
            ? 'User suspended.'
            : 'User activated.',
      );
    } on FirebaseException catch (e) {
      _snack('Could not update user: ${e.code}');
    } catch (_) {
      _snack('Could not update user.');
    }
  }

  Future<void> _suspendUser(dynamic row) {
    return _changeUserStatus(row, 'suspended');
  }

  Future<void> _activateUser(dynamic row) {
    return _changeUserStatus(row, 'active');
  }

  Future<void> _deleteUser(dynamic row) {
    return _changeUserStatus(row, 'deleted', deleted: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      body: SafeArea(
        child: Obx(() {
          if (controller.checkingAccess.value) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.errorMessage.value.isNotEmpty) {
            return _ErrorState(onRetry: controller.initialize);
          }

          return Column(
            children: [
              _AdminTopBar(onRefresh: controller.refreshCurrentSection),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AdminWelcomeHero(
                              onOpenUsers: () {
                                controller.openSection(0);
                              },
                              onOpenProjects: () {
                                controller.openSection(3);
                              },
                            ),

                            const SizedBox(height: 24),

                            _AdminSectionCards(
                              selectedIndex: controller.selectedSection.value,
                              onSelected: controller.openSection,
                            ),

                            const SizedBox(height: 24),

                            _SelectedAdminSectionHeader(
                              selectedIndex: controller.selectedSection.value,
                            ),

                            const SizedBox(height: 14),

                            _buildSelectedSection(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSelectedSection() {
    switch (controller.selectedSection.value) {
      // =====================================================
      // USERS
      // =====================================================

      case 0:
        if (controller.loadingUsers.value && controller.users.isEmpty) {
          return const _AdminSectionLoading();
        }

        return _UsersPanel(
          title: 'Users',
          subtitle: '${controller.filteredUsers.length} users shown',
          includeUsageColumns: false,
          controller: _searchCtrl,
          rows: List<AdminUserRow>.from(controller.filteredUsers),
          onChanged: controller.setSearchQuery,
          currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
          onSuspend: _suspendUser,
          onActivate: _activateUser,
          onDelete: _deleteUser,
        );

      // =====================================================
      // SUBSCRIBERS
      // =====================================================

      case 1:
        if (controller.loadingUsers.value && controller.users.isEmpty) {
          return const _AdminSectionLoading();
        }

        return _UsersPanel(
          title: 'Subscribers',
          subtitle:
              '${controller.filteredSubscribers.length} subscribed users shown',
          includeUsageColumns: false,
          controller: _searchCtrl,
          rows: List<AdminUserRow>.from(controller.filteredSubscribers),
          onChanged: controller.setSearchQuery,
          currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
          onSuspend: _suspendUser,
          onActivate: _activateUser,
          onDelete: _deleteUser,
        );

      // =====================================================
      // BILLING / WEBHOOKS
      // =====================================================

      case 2:
        if (controller.loadingBilling.value &&
            controller.billingData.value == null) {
          return const _AdminSectionLoading();
        }

        final AdminDashboardData? data =
            controller.billingData.value as AdminDashboardData?;

        if (data == null) {
          return _AdminEmptySummary(text: 'No billing information loaded.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoStrip(
              icon: Icons.info_outline_rounded,
              text:
                  'Billing delay is measured from payment creation to callback, or current waiting time while pending. A payment is marked delayed when it is still pending after 10 minutes or its callback took more than 10 minutes.',
            ),

            const SizedBox(height: 18),

            _SubscriptionPaymentsPanel(data: data),
          ],
        );

      // =====================================================
      // PROJECTS
      // =====================================================

      case 3:
        if (controller.loadingProjects.value &&
            controller.projectsData.value == null) {
          return const _AdminSectionLoading();
        }

        final ProjectsAdminData? data =
            controller.projectsData.value as ProjectsAdminData?;

        if (data == null) {
          return const _AdminEmptySummary(
            text: 'No project information loaded.',
          );
        }

        return _ProjectsAdminPanel(data: data);

      // =====================================================
      // SPACE USAGE
      // =====================================================

      case 4:
        if (controller.loadingSpaceUsage.value &&
            controller.spaceUsageUsers.isEmpty) {
          return const _AdminSectionLoading();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoStrip(
              icon: Icons.cloud_outlined,
              text:
                  'Space usage is loaded separately because it counts project buildings, drawings, measurements, and BOQ items. This is the heaviest admin check.',
            ),

            const SizedBox(height: 18),

            _UsersPanel(
              title: 'Space usage',
              subtitle:
                  '${controller.filteredSpaceUsageUsers.length} users with project usage shown',
              includeUsageColumns: true,
              controller: _searchCtrl,
              rows: List<AdminUserRow>.from(
                controller.filteredSpaceUsageUsers as Iterable<AdminUserRow>,
              ),
              onChanged: controller.setSearchQuery,
              currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
              onSuspend: _suspendUser,
              onActivate: _activateUser,
              onDelete: _deleteUser,
            ),
          ],
        );

      // =====================================================
      // TUTORIALS
      // =====================================================

      case 5:
        return const AdminTutorialVideosPage();

      default:
        return const SizedBox.shrink();
    }
  }
}

class _AdminSectionLoading extends StatelessWidget {
  const _AdminSectionLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AqsColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text(
            'Loading admin data...',
            style: TextStyle(
              color: AqsColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final displayName =
        user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'Administrator';

    final email =
        user?.email?.trim().isNotEmpty == true
            ? user!.email!.trim()
            : 'Admin account';

    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        children: [
          // ------------------------------------------------
          // AQS LOGO
          // ------------------------------------------------
          // Container(
          //   width: 54,
          //   height: 54,
          //   padding: const EdgeInsets.all(7),
          //   decoration: BoxDecoration(
          //     color: Colors.white,
          //     borderRadius: BorderRadius.circular(15),
          //     border: Border.all(color: AqsColors.border),
          //   ),
          //   child: Image.asset(
          //     'assets/images/aqs_logo.png',
          //     fit: BoxFit.contain,
          //     errorBuilder: (context, error, stackTrace) {
          //       return Container(
          //         decoration: BoxDecoration(
          //           color: AqsColors.primary,
          //           borderRadius: BorderRadius.circular(11),
          //         ),
          //         child: const Icon(
          //           Icons.architecture_rounded,
          //           color: Colors.white,
          //         ),
          //       );
          //     },
          //   ),
          // ),
          const AqsBrand(),
          Spacer(),

          // const SizedBox(width: 14),

          // ------------------------------------------------
          // TITLE
          // ------------------------------------------------
          // const Expanded(
          //   child: Column(
          //     mainAxisAlignment: MainAxisAlignment.center,
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       Text(
          //         'AQS Admin',
          //         maxLines: 1,
          //         overflow: TextOverflow.ellipsis,
          //         style: TextStyle(
          //           color: AqsColors.ink,
          //           fontSize: 20,
          //           fontWeight: FontWeight.w900,
          //           letterSpacing: -0.3,
          //         ),
          //       ),
          //       SizedBox(height: 3),
          //       Text(
          //         'Administration Console',
          //         maxLines: 1,
          //         overflow: TextOverflow.ellipsis,
          //         style: TextStyle(
          //           color: AqsColors.muted,
          //           fontSize: 12,
          //           fontWeight: FontWeight.w600,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),

          // ------------------------------------------------
          // REFRESH
          // ------------------------------------------------
          _TopBarAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh admin data',
            onTap: onRefresh,
          ),

          const SizedBox(width: 12),

          // ------------------------------------------------
          // ADMIN PROFILE
          // ------------------------------------------------
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _showAdminProfileDialog(context);
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 205, maxWidth: 280),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AqsColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AqsColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: AqsColors.primary,
                        size: 20,
                      ),
                    ),

                    const SizedBox(width: 10),

                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AqsColors.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AqsColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AqsColors.muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdminProfileDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _AdminProfileDialog(user: user);
      },
    );
  }
}

class _AdminProfileDialog extends StatelessWidget {
  const _AdminProfileDialog({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final displayName =
        user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Administrator';

    final email =
        user.email?.trim().isNotEmpty == true ? user.email!.trim() : 'No email';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ========================================
              // HEADER
              // ========================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 22, 16, 22),
                decoration: const BoxDecoration(
                  color: Color(0xFF111827),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Image.asset(
                        'assets/images/aqs_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: AqsColors.primary,
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ADMIN PROFILE',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // ========================================
              // BODY
              // ========================================
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AdminProfileDetail(
                      icon: Icons.person_outline_rounded,
                      label: 'Name',
                      value: displayName,
                    ),

                    const SizedBox(height: 10),

                    _AdminProfileDetail(
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                      value: email,
                    ),

                    const SizedBox(height: 10),

                    const _AdminProfileDetail(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Role',
                      value: 'Administrator',
                    ),

                    const SizedBox(height: 10),

                    _AdminProfileDetail(
                      icon: Icons.fingerprint_rounded,
                      label: 'User ID',
                      value: user.uid,
                    ),

                    const SizedBox(height: 24),

                    const Divider(),

                    const SizedBox(height: 16),

                    // =================================
                    // LOG OUT
                    // =================================
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final shouldLogout = await _confirmAdminLogout(
                            context,
                          );

                          if (!shouldLogout) {
                            return;
                          }

                          Navigator.of(context).pop();

                          await FirebaseAuth.instance.signOut();

                          // Replace '/login' if your
                          // login route is different.
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login',
                              (route) => false,
                            );
                          }
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Log out'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD92D20),
                          side: const BorderSide(color: Color(0xFFFDA29B)),
                        ),
                      ),
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

  Future<bool> _confirmAdminLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text(
            'Are you sure you want to log out of the AQS Administration Console?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),

            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD92D20),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }
}

class _AdminProfileDetail extends StatelessWidget {
  const _AdminProfileDetail({
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AqsColors.primary, size: 18),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                SelectableText(
                  value,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _TopBarAction extends StatelessWidget {
  const _TopBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AqsColors.border),
          ),
          child: Icon(icon, color: AqsColors.ink, size: 20),
        ),
      ),
    );
  }
}

class _AdminWelcomeHero extends StatelessWidget {
  const _AdminWelcomeHero({
    required this.onOpenUsers,
    required this.onOpenProjects,
  });

  final VoidCallback onOpenUsers;
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.14)),
                ),
                child: const Text(
                  'ADMIN WORKSPACE',
                  style: TextStyle(
                    color: Color(0xFFD0D5DD),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Welcome to your\nAQS control centre.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 13),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 660),
                child: Text(
                  'Manage users, subscriptions, billing activity, projects, storage usage and tutorial content from one place.',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 15,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onOpenUsers,
                    icon: const Icon(Icons.people_alt_outlined),
                    label: const Text('Manage users'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF111827),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenProjects,
                    icon: const Icon(Icons.folder_copy_outlined),
                    label: const Text('View projects'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.25)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          final visual = Container(
            width: compact ? double.infinity : 280,
            height: 190,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.dashboard_customize_rounded,
                  color: Colors.white,
                  size: 56,
                ),
                SizedBox(height: 16),
                Text(
                  'Central administration',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'One console for the operational side of AQS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [content, const SizedBox(height: 24), visual],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 28),
              visual,
            ],
          );
        },
      ),
    );
  }
}

class _AdminSectionCards extends StatelessWidget {
  const _AdminSectionCards({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const sections = <_AdminSectionDefinition>[
    _AdminSectionDefinition(
      icon: Icons.people_alt_outlined,
      title: 'Users',
      description: 'Manage accounts, roles and access status.',
    ),
    _AdminSectionDefinition(
      icon: Icons.workspace_premium_outlined,
      title: 'Subscribers',
      description: 'Review active paid plans and subscribers.',
    ),
    _AdminSectionDefinition(
      icon: Icons.webhook_outlined,
      title: 'Billing & Webhooks',
      description: 'Inspect payments, attempts and callback delays.',
    ),
    _AdminSectionDefinition(
      icon: Icons.folder_copy_outlined,
      title: 'Projects',
      description: 'Monitor projects, clients, invites and teams.',
    ),
    _AdminSectionDefinition(
      icon: Icons.cloud_outlined,
      title: 'Space Usage',
      description: 'Review project data and user storage activity.',
    ),
    _AdminSectionDefinition(
      icon: Icons.video_library_outlined,
      title: 'Tutorial Videos',
      description: 'Manage help and training video content.',
    ),
    _AdminSectionDefinition(
      icon: Icons.price_change_outlined,
      title: 'Material Prices',
      description: 'Upload and maintain supplier material prices.',
      route: AppRoutes.adminMaterialPrices,
    ),
    _AdminSectionDefinition(
      icon: Icons.description_outlined,
      title: 'BOQ Templates',
      description: 'View, add, edit and delete BOQ templates and their items.',
      route: AppRoutes.boqTemplatesManage,
    ),
    _AdminSectionDefinition(
      icon: Icons.mark_email_unread_outlined,
      title: 'User Messages',
      description: 'Read messages submitted through the AQS contact form.',
      route: AppRoutes.adminMessages,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1180
                ? 3
                : constraints.maxWidth >= 720
                ? 2
                : 1;

        const gap = 16.0;
        final cardWidth =
            (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < sections.length; i++)
              SizedBox(
                width: cardWidth,
                child: _AdminModuleCard(
                  section: sections[i],
                  selected: selectedIndex == i,
                  onTap: () {
                    final route = sections[i].route;
                    if (route != null) {
                      Get.toNamed(route);
                      return;
                    }
                    onSelected(i);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AdminModuleCard extends StatelessWidget {
  const _AdminModuleCard({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _AdminSectionDefinition section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 145),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected ? AqsColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color:
                  selected
                      ? AqsColors.primary.withOpacity(0.55)
                      : AqsColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF101828,
                ).withOpacity(selected ? 0.08 : 0.035),
                blurRadius: selected ? 24 : 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: selected ? AqsColors.primary : AqsColors.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  section.icon,
                  color: selected ? Colors.white : AqsColors.primary,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            section.title,
                            style: const TextStyle(
                              color: AqsColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.arrow_forward_rounded,
                          color:
                              selected ? AqsColors.primary : AqsColors.subtle,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      section.description,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      selected ? 'Currently open' : 'Open module',
                      style: TextStyle(
                        color: selected ? AqsColors.primary : AqsColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
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

class _SelectedAdminSectionHeader extends StatelessWidget {
  const _SelectedAdminSectionHeader({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final section = _AdminSectionCards.sections[selectedIndex];

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ADMIN MODULE',
                style: TextStyle(
                  color: AqsColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                section.title,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AqsColors.primarySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(section.icon, color: AqsColors.primary),
        ),
      ],
    );
  }
}

class _AdminSectionDefinition {
  const _AdminSectionDefinition({
    required this.icon,
    required this.title,
    required this.description,
    this.route,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? route;
}

class _ProjectsAdminPanel extends StatefulWidget {
  const _ProjectsAdminPanel({required this.data});

  final ProjectsAdminData data;

  @override
  State<_ProjectsAdminPanel> createState() => _ProjectsAdminPanelState();
}

class _ProjectsAdminPanelState extends State<_ProjectsAdminPanel> {
  int _selected = 0;

  ProjectsAdminData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _Metric(
        icon: Icons.folder_copy_outlined,
        label: 'Projects',
        value: data.projectCount.toString(),
        note: 'Created project records',
      ),

      _Metric(
        icon: Icons.business_center_outlined,
        label: 'Clients',
        value: data.clientCount.toString(),
        note: 'Registered clients',
      ),

      _Metric(
        icon: Icons.mark_email_unread_outlined,
        label: 'Open invites',
        value: data.inviteCount.toString(),
        note: 'Team invitations',
      ),

      _Metric(
        icon: Icons.groups_2_outlined,
        label: 'Workspace members',
        value: data.workspaceMemberCount.toString(),
        note: 'Accepted team members',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AqsColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Projects & Workspace',
                style: TextStyle(
                  color: AqsColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Select a category below to inspect projects, clients, invitations and workspace members.',
                style: TextStyle(color: AqsColors.muted, height: 1.45),
              ),

              const SizedBox(height: 18),

              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth < 620
                          ? 1
                          : constraints.maxWidth < 980
                          ? 2
                          : 4;

                  const spacing = 14.0;

                  final width =
                      (constraints.maxWidth - (columns - 1) * spacing) /
                      columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (var i = 0; i < metrics.length; i++)
                        SizedBox(
                          width: width,
                          child: _MetricCard(
                            metric: metrics[i],

                            selected: _selected == i,

                            onTap: () {
                              setState(() {
                                _selected = i;
                              });
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        _buildSelectedContent(),
      ],
    );
  }

  Widget _buildSelectedContent() {
    switch (_selected) {
      case 0:
        return _ProjectsSummaryList(projects: data.projects);

      case 1:
        return _ClientsSummaryList(clients: data.clients);

      case 2:
        return _InvitesSummaryList(invites: data.invites);

      case 3:
        return _WorkspaceMembersSummaryList(members: data.workspaceMembers);

      default:
        return const SizedBox.shrink();
    }
  }
}

class _ProjectsSummaryList extends StatelessWidget {
  const _ProjectsSummaryList({required this.projects});

  final List<AdminProjectRow> projects;

  @override
  Widget build(BuildContext context) {
    return _AdminSummarySection(
      title: 'Projects',
      subtitle: '${projects.length} projects found',
      icon: Icons.folder_copy_outlined,
      child:
          projects.isEmpty
              ? const _AdminEmptySummary(
                text: 'No projects have been created yet.',
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 2 : 1;

                  const gap = 14.0;

                  final width =
                      (constraints.maxWidth - ((columns - 1) * gap)) / columns;

                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final project in projects)
                        SizedBox(
                          width: width,
                          child: _AdminProjectCard(project: project),
                        ),
                    ],
                  );
                },
              ),
    );
  }
}

class _AdminProjectCard extends StatelessWidget {
  const _AdminProjectCard({required this.project});

  final AdminProjectRow project;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showProjectDetailsDialog(context, project),
        child: Container(
          padding: const EdgeInsets.all(18),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AqsColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.folder_copy_outlined,
                      color: AqsColors.primary,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AqsColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          'Owner: ${project.ownerLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AqsColors.subtle,
                    size: 16,
                  ),
                ],
              ),

              const SizedBox(height: 18),

              const Divider(height: 1, color: AqsColors.border),

              const SizedBox(height: 14),

              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 15,
                    color: AqsColors.muted,
                  ),

                  const SizedBox(width: 7),

                  Expanded(
                    child: Text(
                      'Created ${formatDate(project.createdAt)}',
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const Text(
                    'View details',
                    style: TextStyle(
                      color: AqsColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(width: 4),

                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: AqsColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProjectDetailsDialog(
    BuildContext context,
    AdminProjectRow project,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProjectDialogHeader(
                    project: project,
                    onClose: () {
                      Navigator.of(dialogContext).pop();
                    },
                  ),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
                      child: _ProjectDialogBody(project: project),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProjectDialogHeader extends StatelessWidget {
  const _ProjectDialogHeader({required this.project, required this.onClose});

  final AdminProjectRow project;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 18, 22),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Icon(Icons.folder_copy_outlined, color: Colors.white),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROJECT DETAILS',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  project.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Created ${formatDate(project.createdAt)}',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            onPressed: onClose,
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ProjectDialogBody extends StatelessWidget {
  const _ProjectDialogBody({required this.project});

  final AdminProjectRow project;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Project information',
          style: TextStyle(
            color: AqsColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 14),

        _ProjectDetailRow(
          icon: Icons.folder_outlined,
          label: 'Project name',
          value: project.displayName,
        ),

        _ProjectDetailRow(
          icon: Icons.person_outline_rounded,
          label: 'Owner',
          value: project.ownerLabel,
        ),

        _ProjectDetailRow(
          icon: Icons.business_outlined,
          label: 'Client',
          value:
              project.clientName.isEmpty ? 'Not specified' : project.clientName,
        ),

        _ProjectDetailRow(
          icon: Icons.calendar_today_outlined,
          label: 'Date created',
          value: formatDate(project.createdAt),
        ),

        _ProjectDetailRow(
          icon: Icons.fingerprint_rounded,
          label: 'Project ID',
          value: project.id,
        ),

        const SizedBox(height: 24),

        const Text(
          'Project usage',
          style: TextStyle(
            color: AqsColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 14),

        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 560 ? 4 : 2;

            const gap = 10.0;

            final width =
                (constraints.maxWidth - ((columns - 1) * gap)) / columns;

            final items = [
              _ProjectDialogMetric(
                icon: Icons.apartment_outlined,
                label: 'Facilities',
                value: project.facilities.toString(),
              ),
              _ProjectDialogMetric(
                icon: Icons.description_outlined,
                label: 'Drawings',
                value: project.drawings.toString(),
              ),
              _ProjectDialogMetric(
                icon: Icons.straighten_outlined,
                label: 'Measurements',
                value: project.measurements.toString(),
              ),
              _ProjectDialogMetric(
                icon: Icons.receipt_long_outlined,
                label: 'BOQ Items',
                value: project.boqItems.toString(),
              ),
            ];

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items) SizedBox(width: width, child: item),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        const Text(
          'Project information is available for administrative oversight only.',
          style: TextStyle(
            color: AqsColors.muted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ProjectDetailRow extends StatelessWidget {
  const _ProjectDetailRow({
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AqsColors.primary, size: 18),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                SelectableText(
                  value,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

class _ProjectDialogMetric extends StatelessWidget {
  const _ProjectDialogMetric({
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
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AqsColors.primary, size: 19),

          // const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AqsColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSummarySection extends StatelessWidget {
  const _AdminSummarySection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AqsColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AqsColors.primary),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          child,
        ],
      ),
    );
  }
}

class _AdminEmptySummary extends StatelessWidget {
  const _AdminEmptySummary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AqsColors.muted),
      ),
    );
  }
}

class _ClientsSummaryList extends StatelessWidget {
  const _ClientsSummaryList({required this.clients});

  final List<AdminClientRow> clients;

  @override
  Widget build(BuildContext context) {
    return _AdminSummarySection(
      title: 'Clients',
      subtitle: '${clients.length} clients found',
      icon: Icons.business_outlined,
      child: Column(
        children: [
          for (final client in clients)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AqsColors.primarySoft,
                child: Icon(Icons.business_outlined, color: AqsColors.primary),
              ),
              title: Text(client.displayName),
              subtitle: Text(
                [
                  client.company,
                  client.email,
                  client.phone,
                ].where((e) => e.trim().isNotEmpty).join(' • '),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
              onTap: () {
                // Client details later.
              },
            ),
        ],
      ),
    );
  }
}

class _InvitesSummaryList extends StatelessWidget {
  const _InvitesSummaryList({required this.invites});

  final List<AdminInviteRow> invites;

  @override
  Widget build(BuildContext context) {
    return _AdminSummarySection(
      title: 'Invited users',
      subtitle: '${invites.length} invitations',
      icon: Icons.mark_email_unread_outlined,
      child: Column(
        children: [
          for (final invite in invites)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AqsColors.primarySoft,
                child: Icon(Icons.mail_outline, color: AqsColors.primary),
              ),
              title: Text(invite.displayName),
              subtitle: Text(
                [
                  invite.role,
                  invite.status,
                  invite.projectName,
                ].where((e) => e.trim().isNotEmpty).join(' • '),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
              onTap: () {},
            ),
        ],
      ),
    );
  }
}

class _WorkspaceMembersSummaryList extends StatelessWidget {
  const _WorkspaceMembersSummaryList({required this.members});

  final List<AdminWorkspaceMemberRow> members;

  @override
  Widget build(BuildContext context) {
    return _AdminSummarySection(
      title: 'Workspace members',
      subtitle: '${members.length} members found',
      icon: Icons.groups_2_outlined,
      child: Column(
        children: [
          for (final member in members)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AqsColors.primarySoft,
                child: Icon(Icons.person_outline, color: AqsColors.primary),
              ),
              title: Text(member.displayName),
              subtitle: Text(
                [
                  member.email,
                  member.role,
                  member.status,
                ].where((e) => e.trim().isNotEmpty).join(' • '),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
              onTap: () {},
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.onTap,
    this.selected = false,
  });

  final _Metric metric;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 155),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? AqsColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AqsColors.primary : AqsColors.border,
              width: selected ? 1.5 : 1,
            ),
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
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color:
                          selected ? AqsColors.primary : AqsColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      metric.icon,
                      color: selected ? Colors.white : AqsColors.primary,
                    ),
                  ),

                  const Spacer(),

                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_rounded,
                    color: selected ? AqsColors.primary : AqsColors.subtle,
                    size: 20,
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                metric.note,
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
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFEDF89)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFB54708)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF93370D),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionPaymentsPanel extends StatelessWidget {
  const _SubscriptionPaymentsPanel({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final payments = data.subscriptionPayments;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AqsColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    color: AqsColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Subscription billing',
                        style: TextStyle(
                          color: AqsColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payments.isEmpty
                            ? 'No subscription payments recorded yet'
                            : '${payments.length} payment records • ${data.successfulSubscriptionPayments} successful • ${data.failedSubscriptionPayments} failed',
                        style: const TextStyle(color: AqsColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final cardWidth =
                    width >= 980
                        ? (width - 50) / 6
                        : width >= 680
                        ? (width - 20) / 3
                        : width;
                final cards = [
                  _BillingSummaryCard(
                    label: 'Successful',
                    value: data.successfulSubscriptionPayments.toString(),
                    note: formatMoney(data.subscriptionRevenue, 'TZS'),
                    tone: PillTone.green,
                  ),
                  _BillingSummaryCard(
                    label: 'Failed',
                    value: data.failedSubscriptionPayments.toString(),
                    note: '${formatPercent(data.subscriptionFailureRate)} rate',
                    tone: PillTone.red,
                  ),
                  _BillingSummaryCard(
                    label: 'Pending',
                    value: data.pendingSubscriptionPayments.toString(),
                    note: '${data.delayedSubscriptionPayments} delayed',
                    tone: PillTone.amber,
                  ),
                  _BillingSummaryCard(
                    label: 'Attempts',
                    value: data.subscriptionAttempts.toString(),
                    note:
                        '${data.successfulSubscriptionAttempts} ok / ${data.failedSubscriptionAttempts} failed',
                    tone: PillTone.blue,
                  ),
                  _BillingSummaryCard(
                    label: 'Success rate',
                    value: formatPercent(data.subscriptionSuccessRate),
                    note: 'Paid out of all payment records',
                    tone: PillTone.green,
                  ),
                  _BillingSummaryCard(
                    label: 'Avg delay',
                    value: formatDuration(data.averagePaymentDelay),
                    note:
                        '${formatPercent(data.subscriptionDelayRate)} delayed',
                    tone: PillTone.grey,
                  ),
                ];
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final card in cards)
                      SizedBox(width: cardWidth, child: card),
                  ],
                );
              },
            ),
          ),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 10, 28, 30),
              child: Text(
                'Subscription purchases will appear here after users start payment.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AqsColors.muted),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  for (final payment in payments) ...[
                    _SubscriptionPaymentTile(payment: payment),
                    if (payment != payments.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BillingSummaryCard extends StatelessWidget {
  const _BillingSummaryCard({
    required this.label,
    required this.value,
    required this.note,
    required this.tone,
  });

  final String label;
  final String value;
  final String note;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = pillColors(tone);
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.fg,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
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
    );
  }
}

class _SubscriptionPaymentTile extends StatelessWidget {
  const _SubscriptionPaymentTile({required this.payment});

  final SubscriptionPaymentRow payment;

  @override
  Widget build(BuildContext context) {
    final tone =
        payment.isSuccessful
            ? PillTone.green
            : payment.isFailed
            ? PillTone.red
            : payment.isDelayed
            ? PillTone.amber
            : PillTone.blue;
    final colors = pillColors(tone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final body = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colors.bg,
                    child: Icon(payment.statusIcon, color: colors.fg, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payment.userLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AqsColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          payment.contactLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Pill(text: payment.statusLabel, tone: tone),
                            _Pill(text: payment.planLabel, tone: PillTone.blue),
                            _Pill(
                              text: payment.amountLabel,
                              tone: PillTone.grey,
                            ),
                            _Pill(
                              text: payment.delayLabel,
                              tone:
                                  payment.isDelayed
                                      ? PillTone.amber
                                      : PillTone.grey,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final meta = Column(
                crossAxisAlignment:
                    compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDateTime(payment.createdAt),
                    style: const TextStyle(
                      color: AqsColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    payment.providerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Pill(
                    text: payment.attemptSummary,
                    tone:
                        payment.failedAttempts > 0
                            ? PillTone.red
                            : PillTone.grey,
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [body, const SizedBox(height: 12), meta],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: body),
                  const SizedBox(width: 18),
                  SizedBox(width: 220, child: meta),
                ],
              );
            },
          ),
          if (payment.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PaymentNotice(text: payment.errorMessage),
          ],
          const SizedBox(height: 12),
          if (payment.attempts.isEmpty)
            const Text(
              'No attempt rows recorded for this payment.',
              style: TextStyle(color: AqsColors.muted, fontSize: 12),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Attempts',
                  style: TextStyle(
                    color: AqsColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                for (final attempt in payment.attempts) ...[
                  PaymentAttemptLine(attempt: attempt),
                  if (attempt != payment.attempts.last)
                    const SizedBox(height: 6),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECDD6)),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFC01048),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      ),
    );
  }
}

class _UsersPanel extends StatelessWidget {
  const _UsersPanel({
    required this.title,
    required this.subtitle,
    required this.includeUsageColumns,
    required this.controller,
    required this.rows,
    required this.onChanged,
    required this.currentUserId,
    required this.onSuspend,
    required this.onActivate,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final bool includeUsageColumns;
  final TextEditingController controller;
  final List<AdminUserRow> rows;
  final ValueChanged<String> onChanged;
  final String currentUserId;
  final ValueChanged<AdminUserRow> onSuspend;
  final ValueChanged<AdminUserRow> onActivate;
  final ValueChanged<AdminUserRow> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AqsColors.muted),
                    ),
                  ],
                );
                final search = SizedBox(
                  width: compact ? double.infinity : 360,
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search user, email, role, plan',
                    ),
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [titleBlock, const SizedBox(height: 12), search],
                  );
                }
                return Row(children: [Expanded(child: titleBlock), search]);
              },
            ),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No matching users found.',
                  style: TextStyle(color: AqsColors.muted),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: AqsColors.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
                dataTextStyle: const TextStyle(
                  color: AqsColors.text,
                  fontWeight: FontWeight.w600,
                ),
                columnSpacing: 26,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 78,
                columns: [
                  const DataColumn(label: Text('USER')),
                  const DataColumn(label: Text('ROLE')),
                  const DataColumn(label: Text('STATUS')),
                  if (includeUsageColumns) ...const [
                    DataColumn(label: Text('PROJECTS')),
                    DataColumn(label: Text('FACILITIES')),
                    DataColumn(label: Text('DRAWINGS')),
                    DataColumn(label: Text('MEASURES')),
                    DataColumn(label: Text('BOQ ITEMS')),
                  ],
                  const DataColumn(label: Text('PLAN')),
                  const DataColumn(label: Text('SPACE')),
                  const DataColumn(label: Text('LAST LOGIN')),
                  const DataColumn(label: Text('ACTIONS')),
                ],
                rows: rows.map(_buildRow).toList(),
              ),
            ),
        ],
      ),
    );
  }

  DataRow _buildRow(AdminUserRow row) {
    final isCurrentUser = row.uid == currentUserId;
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 260,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AqsColors.primarySoft,
                  child: Text(
                    row.initials,
                    style: const TextStyle(
                      color: AqsColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AqsColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        row.email.isEmpty ? row.uid : row.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AqsColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(_Pill(text: row.role, tone: PillTone.blue)),
        DataCell(_Pill(text: row.status, tone: _statusTone(row))),
        if (includeUsageColumns) ...[
          DataCell(
            _UserUsageCell(
              value: row.totalProjects,
              note: '${row.ownedProjects} owned · ${row.sharedProjects} shared',
              width: 120,
            ),
          ),
          DataCell(_UserUsageCell(value: row.buildings, width: 76)),
          DataCell(_UserUsageCell(value: row.drawings, width: 76)),
          DataCell(_UserUsageCell(value: row.measurements, width: 76)),
          DataCell(_UserUsageCell(value: row.boqItems, width: 82)),
        ],
        DataCell(
          _Pill(
            text: row.plan,
            tone: row.isSubscribed ? PillTone.green : PillTone.grey,
          ),
        ),
        DataCell(Text(row.storageLabel)),
        DataCell(Text(row.lastLoginLabel)),
        DataCell(
          _UserActions(
            row: row,
            disabled: isCurrentUser,
            onSuspend: () => onSuspend(row),
            onActivate: () => onActivate(row),
            onDelete: () => onDelete(row),
          ),
        ),
      ],
    );
  }

  PillTone _statusTone(AdminUserRow row) {
    if (row.isActive) return PillTone.green;
    if (row.isSuspended) return PillTone.amber;
    if (row.isDeleted) return PillTone.red;
    return PillTone.grey;
  }
}

class _UserUsageCell extends StatelessWidget {
  const _UserUsageCell({required this.value, this.note, this.width = 72});

  final int value;
  final String? note;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(
              color: AqsColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AqsColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserActions extends StatelessWidget {
  const _UserActions({
    required this.row,
    required this.disabled,
    required this.onSuspend,
    required this.onActivate,
    required this.onDelete,
  });

  final AdminUserRow row;
  final bool disabled;
  final VoidCallback onSuspend;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canActivate = row.isSuspended || row.isDeleted;
    final canSuspend = row.isActive;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message:
              disabled
                  ? 'You cannot change your own account'
                  : canActivate
                  ? 'Activate user'
                  : 'Suspend user',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed:
                disabled
                    ? null
                    : canActivate
                    ? onActivate
                    : canSuspend
                    ? onSuspend
                    : null,
            icon: Icon(
              canActivate
                  ? Icons.check_circle_outline_rounded
                  : Icons.block_rounded,
              color: canActivate ? AqsColors.success : const Color(0xFFB54708),
            ),
          ),
        ),
        Tooltip(
          message:
              disabled
                  ? 'You cannot delete your own account'
                  : row.isDeleted
                  ? 'Already deleted'
                  : 'Delete user access',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: disabled || row.isDeleted ? null : onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFD92D20),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.tone});

  final String text;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = pillColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.fg,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AqsColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.admin_panel_settings_outlined,
              size: 42,
              color: AqsColors.primary,
            ),
            const SizedBox(height: 14),
            const Text(
              'Admin data could not be loaded',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AqsColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check Firestore access rules for users, projects, clients, invitations, and workspace members.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AqsColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String note;
}
