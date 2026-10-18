import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class RegisterPage extends StatefulWidget {
  // final Widget Function() onRegisteredGoTo; // e.g. () => const HomePage()

  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _showPass = false;
  bool _awaitingEmailVerification = false;
  String _verificationEmail = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyAuthError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'This email is already registered. Try signing in.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'weak-password':
          return 'Password is too weak. Use at least 8 characters.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is disabled in Firebase.';
        default:
          return e.message ?? 'Registration failed. Please try again.';
      }
    }
    return 'Registration failed. Please try again.';
  }

  Future<void> _savePendingProfile(User user, String name, String email) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name,
      'email': email,
      'provider': 'password',
      'createdAt': FieldValue.serverTimestamp(),
      'role': 'user',
      'status': 'pending_email_verification',
      'emailVerified': false,
      'emailVerificationRequired': true,
      'emailVerificationSentAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markProfileVerified(User user) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'emailVerified': true,
      'emailVerifiedAt': FieldValue.serverTimestamp(),
      'emailVerificationRequired': false,
      'status': 'active',
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _register() async {
    if (_loading) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_passCtrl.text.trim() != _confirmCtrl.text.trim()) {
      _toast('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      final auth = FirebaseAuth.instance;

      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text.trim();
      final name = _nameCtrl.text.trim();

      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'User is null after registration.',
        );
      }

      // Optional: set display name
      await user.updateDisplayName(name);
      await user.sendEmailVerification();

      // Create user profile doc
      await _savePendingProfile(user, name, email);

      if (!mounted) return;
      setState(() {
        _awaitingEmailVerification = true;
        _verificationEmail = email;
      });
      _toast('Verification email sent. Confirm your email before continuing.');

      // Navigator.of(context).pushAndRemoveUntil(
      //   MaterialPageRoute(builder: (_) => widget.onRegisteredGoTo()),
      //   (_) => false,
      // );
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkEmailVerification() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _toast('Session expired. Please sign in again.');
        setState(() => _awaitingEmailVerification = false);
        return;
      }
      if (!user.emailVerified) {
        _toast('Email is not verified yet. Open the link sent to your inbox.');
        return;
      }
      await _markProfileVerified(user);
      if (!mounted) return;
      _toast('Email verified.');
      Get.offAllNamed('/dashboard');
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _toast('Verification email sent.');
    } catch (e) {
      _toast(_friendlyAuthError(e));
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
    final cs = Theme.of(context).colorScheme;

    if (_awaitingEmailVerification) {
      return Scaffold(
        appBar: AppBar(
          title: const AqsAppBarTitle(
            title: 'Verify email',
            subtitle: 'Confirm your account before continuing',
          ),
        ),
        body: Center(
          child: _RegisterEmailVerificationPanel(
            email: _verificationEmail,
            loading: _loading,
            onCheck: _checkEmailVerification,
            onResend: _resendVerificationEmail,
            onUseAnotherEmail: _useAnotherEmail,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const AqsAppBarTitle(
          title: 'Create account',
          subtitle: 'AQS AUTOboq',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Register',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create your account using email and password.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Name is required';
                      if (s.length < 2) return 'Name is too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _emailCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Email is required';
                      if (!s.contains('@') || !s.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _passCtrl,
                    textInputAction: TextInputAction.next,
                    obscureText: !_showPass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _showPass = !_showPass),
                        icon: Icon(
                          _showPass ? Icons.visibility_off : Icons.visibility,
                        ),
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
                    textInputAction: TextInputAction.done,
                    obscureText: !_showPass,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Confirm your password';
                      return null;
                    },
                    onFieldSubmitted: (_) => _register(),
                  ),
                  const SizedBox(height: 18),

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _register,
                      child:
                          _loading
                              ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('Create account'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: const Text('Already have an account? Sign in'),
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

class _RegisterEmailVerificationPanel extends StatelessWidget {
  const _RegisterEmailVerificationPanel({
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
                'Check your inbox',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a verification link to $displayEmail. Verify the email before opening your AQS workspace.',
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
