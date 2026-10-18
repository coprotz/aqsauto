import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';

class AuthProjectGate extends StatefulWidget {
  final Widget Function(User user, String defaultProjectId) builder;

  /// Where to go if not logged in
  final Widget Function() goToAuth;

  /// Where to go if logged in but no project
  final Widget Function() goToCreateProject;

  const AuthProjectGate({
    super.key,
    required this.builder,
    required this.goToAuth,
    required this.goToCreateProject,
  });

  @override
  State<AuthProjectGate> createState() => _AuthProjectGateState();
}

class _AuthProjectGateState extends State<AuthProjectGate> {
  bool _sentAdminToAdminTab = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;
        if (user == null) {
          // ✅ Not authenticated
          _sentAdminToAdminTab = false;
          if (selectedNav.value == 7 || selectedNav.value == 8) {
            selectedNav.value = 0;
          }
          return widget.goToAuth();
        }

        if (_requiresEmailVerification(user)) {
          return _EmailVerificationRequiredPage(
            user: user,
            onVerified: () => setState(() {}),
          );
        }

        return FutureBuilder<_AccountAccessState>(
          future: _loadAccountAccess(user),
          builder: (context, accessSnap) {
            if (accessSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final access = accessSnap.data ?? const _AccountAccessState();
            if (access.isBlocked) {
              return _AccountBlockedPage(status: access.status);
            }

            final isAdmin = access.isAdmin;
            if (isAdmin && !_sentAdminToAdminTab) {
              _sentAdminToAdminTab = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (selectedNav.value == 0) selectedNav.value = 7;
              });
            } else if (!isAdmin &&
                (selectedNav.value == 7 || selectedNav.value == 8)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (selectedNav.value == 7 || selectedNav.value == 8) {
                  selectedNav.value = 0;
                }
              });
            }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('projects').snapshots(),
          builder: (context, projSnap) {
            if (projSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (projSnap.hasError) {
              return Scaffold(
                body: Center(child: Text('Projects error: ${projSnap.error}')),
              );
            }

            final allDocs = projSnap.data?.docs ?? const [];
            final userDocs =
                allDocs.where((doc) {
                  final data = doc.data();
                  final ownerId = (data['ownerId'] ?? '').toString();
                  final members = (data['members'] as List?) ?? const [];
                  return ownerId == user.uid ||
                      members.map((e) => e.toString()).contains(user.uid);
                }).toList();
            final docs = isAdmin ? allDocs : userDocs;
            if (docs.isEmpty) {
              if (!isAdmin) {
                // ✅ No project
                return widget.goToCreateProject();
              }
              return widget.builder(user, '');
            }

            final projectId = docs.first.id;
            return widget.builder(user, projectId);
          },
        );
          },
        );
      },
    );
  }

  Future<_AccountAccessState> _loadAccountAccess(User user) async {
    var isAdmin = false;
    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? {};
      isAdmin = claims['admin'] == true;
    } catch (_) {
      isAdmin = false;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? const <String, dynamic>{};
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final disabled = data['disabled'] == true || data['accessBlocked'] == true;
      final blockedStatuses = {'suspended', 'deleted', 'disabled', 'blocked'};
      return _AccountAccessState(
        isAdmin: isAdmin,
        status: status,
        isBlocked: disabled || blockedStatuses.contains(status),
      );
    } catch (_) {
      return _AccountAccessState(isAdmin: isAdmin);
    }
  }

  bool _requiresEmailVerification(User user) {
    final usesPassword = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    return usesPassword && !user.emailVerified;
  }
}

class _AccountAccessState {
  const _AccountAccessState({
    this.isAdmin = false,
    this.status = '',
    this.isBlocked = false,
  });

  final bool isAdmin;
  final String status;
  final bool isBlocked;
}

class _AccountBlockedPage extends StatelessWidget {
  const _AccountBlockedPage({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().isEmpty ? 'blocked' : status.trim();
    final isDeleted = normalized.toLowerCase() == 'deleted';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isDeleted
                        ? Icons.delete_outline_rounded
                        : Icons.block_rounded,
                    color: const Color(0xFFD92D20),
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isDeleted ? 'Account deleted' : 'Account suspended',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDeleted
                        ? 'This user account has been removed from active access. Contact your workspace administrator if this is unexpected.'
                        : 'This user account is suspended. Contact your workspace administrator to restore access.',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Sign out'),
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

class _EmailVerificationRequiredPage extends StatefulWidget {
  const _EmailVerificationRequiredPage({
    required this.user,
    required this.onVerified,
  });

  final User user;
  final VoidCallback onVerified;

  @override
  State<_EmailVerificationRequiredPage> createState() =>
      _EmailVerificationRequiredPageState();
}

class _EmailVerificationRequiredPageState
    extends State<_EmailVerificationRequiredPage> {
  bool _checking = false;
  bool _resending = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkVerification() async {
    if (_checking || _resending) return;
    setState(() => _checking = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user?.emailVerified == true) {
        await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
          'emailVerified': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'emailVerificationRequired': false,
          'status': 'active',
        }, SetOptions(merge: true));
        widget.onVerified();
      } else {
        _snack('Email is not verified yet. Open the link we sent to your inbox.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_checking || _resending) return;
    setState(() => _resending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _snack('Verification email sent.');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Could not send verification email.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email ?? 'your email address';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    color: Color(0xFF155EEF),
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Verify your email',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a verification link to $email. Verify the email before using AQS.',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _checkVerification,
                      icon:
                          _checking
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.verified_outlined),
                      label: const Text('I have verified my email'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _resending ? null : _resendVerification,
                        child: Text(
                          _resending ? 'Sending...' : 'Resend email',
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _signOut,
                        child: const Text('Use another email'),
                      ),
                    ],
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
