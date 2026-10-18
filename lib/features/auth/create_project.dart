import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class RegisterAndCreateProjectPage extends StatefulWidget {
  // final Widget Function(String projectId)
  // goToDashboard; // pass created projectId

  const RegisterAndCreateProjectPage({super.key});

  @override
  State<RegisterAndCreateProjectPage> createState() =>
      _RegisterAndCreateProjectPageState();
}

class _RegisterAndCreateProjectPageState
    extends State<RegisterAndCreateProjectPage> {
  final _formKey = GlobalKey<FormState>();

  // Account
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // Project
  final _projectNameCtrl = TextEditingController();
  final _projectDescriptionCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();

  final _phoneCtrl = TextEditingController();

  String? _selectedRegion;
  String _currency = 'TZS';

  static const List<String> currencies = ['TZS', 'USD', 'EUR', 'KES'];

  bool _loading = false;
  bool _showPass = false;
  bool _awaitingEmailVerification = false;
  String _verificationEmail = '';

  User? get _signedInUser => FirebaseAuth.instance.currentUser;

  bool get _hasSignedInUser => _signedInUser != null;

  @override
  void initState() {
    super.initState();
    final user = _signedInUser;
    if (user != null) {
      _nameCtrl.text = user.displayName ?? '';
      _emailCtrl.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();

    _projectNameCtrl.dispose();
    _projectDescriptionCtrl.dispose();
    _regionCtrl.dispose();
    _clientCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _authErr(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'This email is already registered. Please sign in.';
        case 'invalid-email':
          return 'Invalid email address.';
        case 'weak-password':
          return 'Weak password. Use at least 8 characters.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is disabled in Firebase Console.';
        case 'network-request-failed':
          return 'Network error. Check your internet connection.';
        default:
          return e.message ?? 'Registration failed.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  bool _requiresEmailVerification(User user) {
    final usesPassword = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    return usesPassword && !user.emailVerified;
  }

  Future<void> _savePendingEmailProfile({
    required User user,
    required String name,
    required String email,
  }) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final existingProfile = await userRef.get();
    final existingRole = (existingProfile.data()?['role'] ?? '').toString();

    await userRef.set({
      'uid': user.uid,
      'name': name,
      'email': email,
      'photoUrl': user.photoURL,
      'provider': 'password',
      'role': existingRole == 'admin' ? 'admin' : 'owner',
      'status': 'pending_email_verification',
      'emailVerified': false,
      'emailVerificationRequired': true,
      'emailVerificationSentAt': FieldValue.serverTimestamp(),
      if (!existingProfile.exists) 'subscriptionPlan': 'free',
      if (!existingProfile.exists) 'subscriptionStatus': 'free',
      if (!existingProfile.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _createProjectForVerifiedUser(User user) async {
    final fs = FirebaseFirestore.instance;
    final name =
        user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : _nameCtrl.text.trim();
    final email =
        user.email?.trim().isNotEmpty == true
            ? user.email!.trim()
            : _emailCtrl.text.trim();
    final projectName = _projectNameCtrl.text.trim();
    final projectDescription = _projectDescriptionCtrl.text.trim();

    if ((user.displayName ?? '').trim().isEmpty && name.isNotEmpty) {
      try {
        await user.updateDisplayName(name);
      } catch (_) {}
    }

    final userRef = fs.collection('users').doc(user.uid);
    final existingProfile = await userRef.get();
    final existingRole = (existingProfile.data()?['role'] ?? '').toString();
    final provider =
        user.providerData.isEmpty ? 'password' : user.providerData.first.providerId;

    await userRef.set({
      'uid': user.uid,
      'name': name,
      'email': email,
      'photoUrl': user.photoURL,
      'provider': provider,
      if (!existingProfile.exists) 'createdAt': FieldValue.serverTimestamp(),
      'role': existingRole == 'admin' ? 'admin' : 'owner',
      'status': 'active',
      'emailVerified': user.emailVerified,
      if (user.emailVerified) 'emailVerifiedAt': FieldValue.serverTimestamp(),
      'emailVerificationRequired': false,
      if (!existingProfile.exists) 'subscriptionPlan': 'free',
      if (!existingProfile.exists) 'subscriptionStatus': 'free',
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final canCreateProject =
        await SubscriptionService.instance.canCreateProject(user: user);
    if (!canCreateProject) {
      _snack(
        'Free plan allows 1 project only. Please subscribe to add more projects.',
      );
      return;
    }

    final projectRef = fs.collection('projects').doc();
    await projectRef.set({
      'projectId': projectRef.id,
      'name': projectName,
      'description': projectDescription,
      'projectDescription': projectDescription,
      'region': _selectedRegion,
      'client': _clientCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'currency': _currency,
      'ownerId': user.uid,
      'members': [user.uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
    });

    if (!mounted) return;
    _snack(_awaitingEmailVerification ? 'Email verified. Project created.' : 'Project created.');
    Get.offAllNamed('/dashboard');
  }

  Future<void> _submit() async {
    if (_loading) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final pass = _passCtrl.text.trim();
    final conf = _confirmCtrl.text.trim();
    if (!_hasSignedInUser && pass != conf) {
      _snack('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);

    try {
      final auth = FirebaseAuth.instance;
      final existingUser = auth.currentUser;
      final name =
          existingUser?.displayName?.trim().isNotEmpty == true
              ? existingUser!.displayName!.trim()
              : _nameCtrl.text.trim();
      final email =
          existingUser?.email?.trim().isNotEmpty == true
              ? existingUser!.email!.trim()
              : _emailCtrl.text.trim();

      User? user = existingUser;
      if (user == null) {
        final cred = await auth.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );
        user = cred.user;
        if (user == null) {
          throw FirebaseAuthException(
            code: 'no-user',
            message: 'User is null after registration.',
          );
        }
        if (name.isNotEmpty) {
          try {
            await user.updateDisplayName(name);
          } catch (_) {}
        }
        await user.sendEmailVerification();
        await _savePendingEmailProfile(user: user, name: name, email: email);

        if (!mounted) return;
        setState(() {
          _awaitingEmailVerification = true;
          _verificationEmail = email;
        });
        _snack('Verification email sent. Confirm your email before creating the project.');
        return;
      }

      if (_requiresEmailVerification(user)) {
        try {
          await user.sendEmailVerification();
        } catch (_) {}
        await _savePendingEmailProfile(user: user, name: name, email: email);
        if (!mounted) return;
        setState(() {
          _awaitingEmailVerification = true;
          _verificationEmail = email;
        });
        _snack('Please verify your email before creating a project.');
        return;
      }

      await _createProjectForVerifiedUser(user);
    } on FirebaseAuthException catch (e) {
      _snack(_authErr(e));
    } on FirebaseException catch (e) {
      _snack('Project save failed: ${e.code}');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkEmailVerificationAndCreateProject() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _snack('Session expired. Please sign in again.');
        setState(() => _awaitingEmailVerification = false);
        return;
      }
      if (_requiresEmailVerification(user)) {
        _snack('Email is not verified yet. Open the link sent to your inbox.');
        return;
      }
      await _createProjectForVerifiedUser(user);
    } on FirebaseAuthException catch (e) {
      _snack(_authErr(e));
    } on FirebaseException catch (e) {
      _snack('Project save failed: ${e.code}');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'emailVerificationSentAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      _snack('Verification email sent.');
    } on FirebaseAuthException catch (e) {
      _snack(_authErr(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useAnotherEmail() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _awaitingEmailVerification = false;
      _verificationEmail = '';
      _passCtrl.clear();
      _confirmCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedInUser = _signedInUser;
    final hasSignedInUser = signedInUser != null;
    if (_awaitingEmailVerification) {
      return Scaffold(
        appBar: AppBar(
          title: const AqsAppBarTitle(
            title: 'Verify email',
            subtitle: 'Confirm your account before creating the project',
          ),
        ),
        body: Center(
          child: _ProjectEmailVerificationPanel(
            email: _verificationEmail,
            loading: _loading,
            onCheck: _checkEmailVerificationAndCreateProject,
            onResend: _resendVerificationEmail,
            onUseAnotherEmail: _useAnotherEmail,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: AqsAppBarTitle(
          title: hasSignedInUser ? 'Create project' : 'Create account & project',
          subtitle:
              hasSignedInUser
                  ? 'Set up your first AQS project'
                  : 'Set up your AQS workspace',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  if (hasSignedInUser) ...[
                    _SignedInAccountCard(user: signedInUser),
                    const SizedBox(height: 18),
                  ] else ...[
                    const Text(
                      'Account details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Email is required';
                        if (!s.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        hintText: '+2557XXXXXXXX',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Phone number is required';
                        final ok = RegExp(
                          r'^\+?[0-9]{9,15}$',
                        ).hasMatch(s.replaceAll(' ', ''));
                        if (!ok) return 'Enter a valid phone number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: !_showPass,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPass ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed:
                              () => setState(() => _showPass = !_showPass),
                        ),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Password is required';
                        if (s.length < 8) return 'Use at least 8 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: !_showPass,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Confirm password';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 12),
                  ],

                  const Text(
                    'Project details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: _projectNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Project name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _projectDescriptionCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Project description',
                      hintText:
                          'e.g. Construction of classrooms or rehabilitation of health centre',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Project description is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: _selectedRegion,
                    items:
                        tzRegions
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _selectedRegion = v),
                    decoration: const InputDecoration(
                      labelText: 'Region / Location (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _clientCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Client / Employer (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _currency,
                    items:
                        currencies
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _currency = v ?? 'TZS'),
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child:
                          _loading
                              ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Text(
                                hasSignedInUser
                                    ? 'Create project'
                                    : 'Create account & project',
                              ),
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

class _ProjectEmailVerificationPanel extends StatelessWidget {
  const _ProjectEmailVerificationPanel({
    required this.email,
    required this.loading,
    required this.onCheck,
    required this.onResend,
    required this.onUseAnotherEmail,
  });

  final String email;
  final bool loading;
  final VoidCallback onCheck;
  final VoidCallback onResend;
  final VoidCallback onUseAnotherEmail;

  @override
  Widget build(BuildContext context) {
    final displayEmail = email.trim().isEmpty ? 'your email address' : email;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
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
                'Verify your email to continue',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a verification link to $displayEmail. After verification, return here and continue creating the project.',
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
                  onPressed: loading ? null : onCheck,
                  icon:
                      loading
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
                    onPressed: loading ? null : onResend,
                    child: const Text('Resend email'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: loading ? null : onUseAnotherEmail,
                    child: const Text('Use another email'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedInAccountCard extends StatelessWidget {
  const _SignedInAccountCard({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final name = (user.displayName ?? '').trim();
    final email = (user.email ?? '').trim();
    final label =
        name.isNotEmpty
            ? name
            : email.isNotEmpty
            ? email.split('@').first
            : 'Google user';
    final initial = label.isEmpty ? 'U' : label.substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1E0FF)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                user.photoURL == null ? null : NetworkImage(user.photoURL!),
            backgroundColor: const Color(0xFF155EEF),
            child:
                user.photoURL == null
                    ? Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                    : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Signed in with Google',
                  style: TextStyle(
                    color: Color(0xFF155EEF),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: Color(0xFF155EEF)),
        ],
      ),
    );
  }
}
