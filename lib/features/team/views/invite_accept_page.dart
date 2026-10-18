import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class InviteAcceptPage extends StatefulWidget {
  const InviteAcceptPage({super.key, required this.token});

  final String token;

  @override
  State<InviteAcceptPage> createState() => _InviteAcceptPageState();
}

class _InviteAcceptPageState extends State<InviteAcceptPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _signInExisting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _friendlyAuthError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'This email already has an account. Use “I already have an account” instead.';
        case 'invalid-email':
          return 'Invalid email address.';
        case 'weak-password':
          return 'Password is too weak. Use at least 8 characters.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'user-not-found':
          return 'No account exists for this email. Create the account from this invite.';
        default:
          return e.message ?? 'Invite acceptance failed.';
      }
    }
    return 'Invite acceptance failed.';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _accept(
    QueryDocumentSnapshot<Map<String, dynamic>> inviteDoc,
  ) async {
    if (_loading) return;
    final invite = inviteDoc.data();
    final inviteEmail = (invite['email'] ?? '').toString().trim().toLowerCase();
    final typedEmail = _emailCtrl.text.trim().toLowerCase();
    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (typedEmail != inviteEmail) {
      _snack('Use the invited email address: $inviteEmail');
      return;
    }
    if (password.length < 8) {
      _snack('Password must be at least 8 characters.');
      return;
    }
    if (!_signInExisting && password != confirm) {
      _snack('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      final auth = FirebaseAuth.instance;
      UserCredential cred;
      if (_signInExisting) {
        cred = await auth.signInWithEmailAndPassword(
          email: typedEmail,
          password: password,
        );
      } else {
        cred = await auth.createUserWithEmailAndPassword(
          email: typedEmail,
          password: password,
        );
        if (name.isNotEmpty) {
          await cred.user?.updateDisplayName(name);
        }
      }

      final user = cred.user ?? auth.currentUser;
      if (user == null) throw Exception('No authenticated user.');

      if ((user.email ?? '').trim().toLowerCase() != inviteEmail) {
        await auth.signOut();
        _snack('This invite belongs to $inviteEmail. Please use that account.');
        return;
      }

      final fs = FirebaseFirestore.instance;
      final projectIds =
          ((invite['projectIds'] as List?) ?? const [])
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList();
      final role = (invite['role'] ?? 'quantity_surveyor').toString();
      final displayName =
          name.isNotEmpty
              ? name
              : ((invite['name'] ?? user.displayName ?? typedEmail).toString());

      final batch = fs.batch();
      for (final projectId in projectIds) {
        final ref = fs.collection('projects').doc(projectId);
        batch.set(ref, {
          'members': FieldValue.arrayUnion([user.uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      batch.set(fs.collection('users').doc(user.uid), {
        'uid': user.uid,
        'name': displayName,
        'email': typedEmail,
        'role': 'user',
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        if (!_signInExisting) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(fs.collection('workspaceMembers').doc(user.uid), {
        'uid': user.uid,
        'name': displayName,
        'email': typedEmail,
        'role': role,
        'status': 'active',
        'projectIds': projectIds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(inviteDoc.reference, {
        'status': 'accepted',
        'acceptedBy': user.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();

      if (!mounted) return;
      _snack('Invite accepted.');
      Get.offAllNamed(AppRoutes.dashboard);
    } catch (e) {
      _snack(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.token.trim();
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('teamInvites')
                .where('inviteToken', isEqualTo: token)
                .limit(1)
                .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Invite error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.docs.isEmpty) {
            return const _InviteMessage(
              title: 'Invite not found',
              message: 'Check the invite code or ask the sender to create a new invitation.',
              icon: Icons.link_off_rounded,
            );
          }

          final doc = snap.data!.docs.first;
          final invite = doc.data();
          final status = (invite['status'] ?? 'pending').toString();
          final email = (invite['email'] ?? '').toString();
          final invitedName = (invite['name'] ?? '').toString();
          final projectNames =
              ((invite['projectNames'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toList();

          if (_emailCtrl.text.isEmpty) _emailCtrl.text = email;
          if (_nameCtrl.text.isEmpty && invitedName.isNotEmpty) {
            _nameCtrl.text = invitedName;
          }

          if (status == 'cancelled') {
            return const _InviteMessage(
              title: 'Invite cancelled',
              message: 'This invitation has been cancelled by the sender.',
              icon: Icons.cancel_outlined,
            );
          }
          if (status == 'accepted') {
            return const _InviteMessage(
              title: 'Invite already accepted',
              message: 'This invitation has already been used.',
              icon: Icons.check_circle_outline_rounded,
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 860) ...[
                      Expanded(
                        child: _InviteHero(
                          email: email,
                          projectNames: projectNames,
                        ),
                      ),
                      const SizedBox(width: 22),
                    ],
                    Expanded(
                      child: _InviteFormCard(
                        nameCtrl: _nameCtrl,
                        emailCtrl: _emailCtrl,
                        passwordCtrl: _passwordCtrl,
                        confirmCtrl: _confirmCtrl,
                        loading: _loading,
                        showPassword: _showPassword,
                        signInExisting: _signInExisting,
                        onTogglePassword:
                            () => setState(() => _showPassword = !_showPassword),
                        onModeChanged:
                            (value) =>
                                setState(() => _signInExisting = value),
                        onAccept: () => _accept(doc),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InviteHero extends StatelessWidget {
  const _InviteHero({required this.email, required this.projectNames});

  final String email;
  final List<String> projectNames;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AqsColors.primaryDark, Color(0xFF155EEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24155EEF),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AqsBrand(onDark: true),
          const SizedBox(height: 30),
          const Text(
            'Join the project workspace.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You were invited as $email. Accepting this invite gives you access to the selected projects, drawings, measurements, and BOQs.',
            style: const TextStyle(color: Color(0xFFD6E4FF), height: 1.5),
          ),
          if (projectNames.isNotEmpty) ...[
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  projectNames
                      .map(
                        (project) => Chip(
                          label: Text(project),
                          side: BorderSide.none,
                          backgroundColor: Colors.white.withOpacity(0.14),
                          labelStyle: const TextStyle(color: Colors.white),
                        ),
                      )
                      .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteFormCard extends StatelessWidget {
  const _InviteFormCard({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.loading,
    required this.showPassword,
    required this.signInExisting,
    required this.onTogglePassword,
    required this.onModeChanged,
    required this.onAccept,
  });

  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool loading;
  final bool showPassword;
  final bool signInExisting;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Accept invitation',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create your password or sign in with an existing account.',
            style: TextStyle(color: AqsColors.muted),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            value: signInExisting,
            onChanged: loading ? null : onModeChanged,
            title: const Text('I already have an account'),
            contentPadding: EdgeInsets.zero,
          ),
          if (!signInExisting) ...[
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              enabled: !loading,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Invited email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordCtrl,
            enabled: !loading,
            obscureText: !showPassword,
            decoration: InputDecoration(
              labelText: signInExisting ? 'Password' : 'Create password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                  showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          if (!signInExisting) ...[
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              enabled: !loading,
              obscureText: !showPassword,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : onAccept,
            icon:
                loading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Accept invite'),
          ),
        ],
      ),
    );
  }
}

class _InviteMessage extends StatelessWidget {
  const _InviteMessage({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AqsColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AqsColors.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AqsColors.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Get.offAllNamed(AppRoutes.landing),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
