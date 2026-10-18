import 'package:aqs/app_routes.dart';
import 'package:aqs/core/controlers/aqs_data_controller.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/projects/pages/projects_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  /// Where to go after successful login
  final Widget Function() onLoggedInGoTo;

  /// Optional: open register page
  final VoidCallback? onGoToRegister;

  const LoginPage({
    super.key,
    required this.onLoggedInGoTo,
    this.onGoToRegister,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _emailLoading = false;
  bool _googleLoading = false;
  bool _showPass = false;
  bool _googleInitialized = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyAuthError(Object e) {
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return 'Google sign-in was cancelled.';
      }
      return e.description ?? 'Google sign-in failed.';
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'user-disabled':
          return 'This account is disabled.';
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
          return 'Incorrect password.';
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'network-request-failed':
          return 'Network error. Check your connection.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with this email. Sign in using the original method first.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled in Firebase.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return 'Google sign-in was cancelled.';
        case 'popup-blocked':
          return 'The Google sign-in popup was blocked by the browser.';
        default:
          return e.message ?? 'Login failed.';
      }
    }
    return 'Login failed. Please try again.';
  }

  bool _requiresEmailVerification(User user) {
    final usesPassword = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    return usesPassword && !user.emailVerified;
  }

  Future<void> _login() async {
    if (_emailLoading || _googleLoading) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _emailLoading = true);
    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text.trim();

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final user = cred.user ?? FirebaseAuth.instance.currentUser;
      if (user != null && _requiresEmailVerification(user)) {
        try {
          await user.sendEmailVerification();
        } catch (_) {}
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _toast(
          'Please verify your email before signing in. We sent a verification link to $email.',
        );
        return;
      }

      if (!mounted) return;
      _toast('Signed in.');
      final dataController = Get.find<AqsDataController>();

      await dataController.loadInitialData();
      final role =
          (dataController.currentUser['role'] ?? '').toString().toLowerCase();

      if (role == 'admin') {
        Get.offAllNamed(AppRoutes.admin);
      } else {
        Get.offAllNamed(AppRoutes.dashboard);
      }

      // ✅ await navigation
      // await Navigator.of(context).pushAndRemoveUntil(
      //   MaterialPageRoute(builder: (_) => widget.onLoggedInGoTo()),
      //   (_) => false,
      // );
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _ensureUserProfile(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final existing = await ref.get();
    await ref.set({
      'uid': user.uid,
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoURL,
      'provider': 'google',
      'role': 'user',
      'status': 'active',
      'lastLoginAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<UserCredential> _signInWithGoogleCredential() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      return FirebaseAuth.instance.signInWithPopup(provider);
    }

    final signIn = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await signIn.initialize();
      _googleInitialized = true;
    }
    if (!signIn.supportsAuthenticate()) {
      throw FirebaseAuthException(
        code: 'operation-not-supported',
        message: 'Google sign-in is not supported on this platform.',
      );
    }

    final GoogleSignInAccount? googleUser = await signIn.authenticate();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'cancelled-popup-request',
        message: 'Google sign-in was cancelled.',
      );
    }
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> _loginWithGoogle() async {
    if (_emailLoading || _googleLoading) return;

    setState(() => _googleLoading = true);
    try {
      final cred = await _signInWithGoogleCredential();
      final user = cred.user ?? FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _ensureUserProfile(user);
      }

      if (!mounted) return;
      _toast('Signed in with Google.');

      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => widget.onLoggedInGoTo()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _toast('Enter your email first, then tap "Forgot password".');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast('Password reset email sent.');
    } catch (e) {
      _toast(_friendlyAuthError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showBrandPanel = constraints.maxWidth >= 900;

          return Row(
            children: [
              if (showBrandPanel)
                const Expanded(flex: 11, child: _LoginBrandPanel()),
              Expanded(
                flex: showBrandPanel ? 10 : 1,
                child: SafeArea(
                  child: Stack(
                    children: [
                      if (Navigator.of(context).canPop())
                        Positioned(
                          right: 20,
                          top: 12,
                          child: IconButton.filledTonal(
                            tooltip: 'Go back',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: constraints.maxWidth < 480 ? 24 : 48,
                            vertical: 40,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Form(
                              key: _formKey,
                              child: _LoginForm(
                                emailController: _emailCtrl,
                                passwordController: _passCtrl,
                                emailLoading: _emailLoading,
                                googleLoading: _googleLoading,
                                showPassword: _showPass,
                                onTogglePassword:
                                    () =>
                                        setState(() => _showPass = !_showPass),
                                onLogin: _login,
                                onGoogleSignIn: _loginWithGoogle,
                                onResetPassword: _resetPassword,
                                onGoToRegister: widget.onGoToRegister,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.emailController,
    required this.passwordController,
    required this.emailLoading,
    required this.googleLoading,
    required this.showPassword,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onGoogleSignIn,
    required this.onResetPassword,
    required this.onGoToRegister,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool emailLoading;
  final bool googleLoading;
  final bool showPassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onResetPassword;
  final VoidCallback? onGoToRegister;

  static const _blue = Color(0xFF155EEF);
  static const _ink = Color(0xFF101828);
  static const _muted = Color(0xFF667085);

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      floatingLabelStyle: const TextStyle(
        color: _blue,
        fontWeight: FontWeight.w600,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _blue, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD92D20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = emailLoading || googleLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AqsBrand(),
        const SizedBox(height: 42),
        Text(
          'Welcome back',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Sign in to continue to your estimating workspace.',
          style: TextStyle(color: _muted, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: loading ? null : onGoogleSignIn,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _ink,
              side: const BorderSide(color: Color(0xFFD0D5DD)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child:
                googleLoading
                    ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                    : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GoogleMark(),
                        SizedBox(width: 12),
                        Text('Continue with Google'),
                      ],
                    ),
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(child: Divider(color: Color(0xFFE4E7EC))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or sign in with email',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: Divider(color: Color(0xFFE4E7EC))),
          ],
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: emailController,
          enabled: !loading,
          autofillHints: const [AutofillHints.email],
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: 'Email address',
            hint: 'name@company.com',
            icon: Icons.mail_outline_rounded,
          ),
          validator: (value) {
            final email = (value ?? '').trim();
            if (email.isEmpty) return 'Email is required';
            if (!email.contains('@') || !email.contains('.')) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: passwordController,
          enabled: !loading,
          autofillHints: const [AutofillHints.password],
          obscureText: !showPassword,
          textInputAction: TextInputAction.done,
          decoration: _fieldDecoration(
            label: 'Password',
            hint: 'Enter your password',
            icon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              tooltip: showPassword ? 'Hide password' : 'Show password',
              onPressed: onTogglePassword,
              icon: Icon(
                showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 21,
              ),
            ),
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) return 'Password is required';
            return null;
          },
          onFieldSubmitted: (_) => onLogin(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: loading ? null : onResetPassword,
            style: TextButton.styleFrom(
              foregroundColor: _blue,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: loading ? null : onLogin,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _blue.withOpacity(0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child:
                emailLoading
                    ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                    : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Sign in'),
                        SizedBox(width: 9),
                        Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
          ),
        ),
        if (onGoToRegister != null) ...[
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'New to AQS? ',
                style: TextStyle(color: _muted, fontSize: 14),
              ),
              TextButton(
                onPressed: loading ? null : onGoToRegister,
                style: TextButton.styleFrom(
                  foregroundColor: _blue,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 32),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: _muted),
            SizedBox(width: 7),
            Text(
              'Your account is securely protected',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
        ),
      ),
    );
  }
}

class _LoginBrandPanel extends StatelessWidget {
  const _LoginBrandPanel();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColoredBox(
        color: const Color(0xFF0B2B67),
        child: CustomPaint(
          painter: _BlueprintPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(64, 54, 64, 58),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    AqsLogoMark(inverted: true),
                    SizedBox(width: 12),
                    Text(
                      'AQS AUTOboq',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 550),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Eyebrow(),
                      SizedBox(height: 24),
                      Text(
                        'Build estimates with\nclarity and confidence.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 45,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.3,
                        ),
                      ),
                      SizedBox(height: 22),
                      Text(
                        'One workspace for measurements, quantities, and '
                        'bills of quantities—from drawing to final estimate.',
                        style: TextStyle(
                          color: Color(0xFFCBD9F5),
                          fontSize: 17,
                          height: 1.6,
                        ),
                      ),
                      SizedBox(height: 38),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _FeatureChip(
                            icon: Icons.straighten_rounded,
                            label: 'Digital takeoff',
                          ),
                          _FeatureChip(
                            icon: Icons.calculate_outlined,
                            label: 'Live quantities',
                          ),
                          _FeatureChip(
                            icon: Icons.description_outlined,
                            label: 'Smart BOQs',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  'Built for quantity surveyors and construction teams.',
                  style: TextStyle(color: Color(0xFF9FB6E1), fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: const Text(
        'YOUR ESTIMATING WORKSPACE',
        style: TextStyle(
          color: Color(0xFFDBE7FF),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF173F7D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF315890)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFBFD2FA), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.045)
          ..strokeWidth = 1;
    const gap = 42.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final glowPaint =
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x553C78E8), Color(0x003C78E8)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.82, size.height * 0.22),
              radius: size.width * 0.55,
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final linePaint =
        Paint()
          ..color = const Color(0xFF7CA4EF).withOpacity(0.13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.79),
      size.width * 0.26,
      linePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.79),
      size.width * 0.18,
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
