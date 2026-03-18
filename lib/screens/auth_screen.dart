import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/screens/home_screen.dart';
import 'package:hydra_bin/screens/forgot_password_screen.dart';

const Color _bg      = Color(0xFF0B0E17);
const Color _surface = Color(0xFF131824);
const Color _card    = Color(0xFF1C2030);
const Color _border  = Color(0xFF252B3B);
const Color _accent  = Color(0xFF22C55E);
const Color _textPri = Color(0xFFF8FAFC);
const Color _textSec = Color(0xFF64748B);
const Color _red     = Color(0xFFEF4444);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  Timer? _resendTimer;
  bool _canResend = true;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() { _canResend = false; _cooldownSeconds = 60; });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_cooldownSeconds > 0) { _cooldownSeconds--; } else { _canResend = true; timer.cancel(); }
        });
      }
    });
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: bg == _accent ? Colors.black : Colors.white)),
      backgroundColor: bg, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: _card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1), shape: BoxShape.circle,
                    border: Border.all(color: _accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.mark_email_unread_rounded, color: _accent, size: 30),
                ),
                const SizedBox(height: 16),
                const Text('Verify Your Email', style: TextStyle(color: _textPri, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text(
                  'Check your inbox (and spam folder) for a verification link before signing in.',
                  style: TextStyle(color: _textSec, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _canResend ? () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null && !user.emailVerified && _canResend) {
                      try {
                        await user.sendEmailVerification();
                        if (mounted) _snack('Verification email sent!', _accent);
                        _startCooldown();
                        setDialogState(() {});
                        setState(() {});
                      } catch (e) {
                        if (mounted) _snack(e.toString(), _red);
                      }
                    }
                  } : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _canResend ? _surface : _surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _canResend ? _accent : _border),
                    ),
                    child: Center(child: Text(
                      _canResend ? 'Resend Verification' : 'Resend in ${_cooldownSeconds}s',
                      style: TextStyle(color: _canResend ? _accent : _textSec, fontWeight: FontWeight.w700),
                    )),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(14)),
                    child: const Center(child: Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800))),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final provider = GoogleAuthProvider();
      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      final user = cred.user;
      if (user != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final docSnap = await docRef.get();
        if (!docSnap.exists) {
          await docRef.set({
            'name': user.displayName ?? 'New User',
            'email': user.email ?? '',
            'profileImageUrl': user.photoURL ?? '',
            'profileImageBase64': '',
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'streak': 0,
            'activeFrame': 'none',
            'unlockedFrames': ['none'],
            'isOnline': true,
            'fcmToken': '',
          });
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(e.message ?? 'Google Sign-In failed', _red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (cred.user != null) {
          await cred.user!.reload();
          final user = FirebaseAuth.instance.currentUser!;
          bool isVerified = user.emailVerified;
          final creationTime = user.metadata.creationTime;
          if (creationTime != null && creationTime.isBefore(DateTime(2026, 3, 8))) {
            isVerified = true;
          }
          if (!isVerified) {
            if (!mounted) return;
            _showVerificationDialog();
            return;
          }
        }
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        await cred.user?.sendEmailVerification();
        _startCooldown();
        final uid = cred.user?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'profileImageUrl': '',
            'profileImageBase64': '',
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'streak': 0,
            'activeFrame': 'none',
            'unlockedFrames': ['none'],
            'isOnline': true,
            'fcmToken': '',
          });
        }
        if (!mounted) return;
        _showVerificationDialog();
        setState(() => _isLogin = true);
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(e.message ?? 'Authentication failed', _red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        // Decorative dot grid
        Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),

        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/Caldruki.jpg',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _accent.withValues(alpha: 0.3)),
                            ),
                            child: const Icon(Icons.recycling_rounded, color: _accent, size: 44),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    const Text('Hydra Bin', textAlign: TextAlign.center,
                        style: TextStyle(color: _textPri, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
                    const Text('Smart Recycling Platform', textAlign: TextAlign.center,
                        style: TextStyle(color: _textSec, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 40),

                    // Card
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _border),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 48, offset: const Offset(0, 16))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        // Tabs
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            _authTab('Sign In', _isLogin),
                            _authTab('Create Account', !_isLogin),
                          ]),
                        ),
                        const SizedBox(height: 28),

                        if (!_isLogin) ...[
                          _buildField(controller: _nameController, label: 'Full Name', icon: Icons.person_outline_rounded,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                          const SizedBox(height: 14),
                        ],

                        _buildField(controller: _emailController, label: 'Email Address', icon: Icons.email_outlined,
                            type: TextInputType.emailAddress,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                        const SizedBox(height: 14),

                        _buildField(controller: _passwordController, label: 'Password', icon: Icons.lock_outline_rounded,
                            obscure: true, validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!_isLogin && v.length < 6) return 'Min 6 chars';
                          return null;
                        }),

                        if (_isLogin) ...[
                          const SizedBox(height: 4),
                          Align(alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                              style: TextButton.styleFrom(foregroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), minimumSize: Size.zero),
                              child: const Text('Forgot Password?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Submit
                        GestureDetector(
                          onTap: _isLoading ? null : _submit,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [_accent, const Color(0xFF16A34A)]),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 6))],
                            ),
                            child: Center(child: _isLoading
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                                : Text(_isLogin ? 'Sign In →' : 'Create my Account →',
                                    style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900))),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Row(children: [
                          Expanded(child: Divider(color: _border)),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('OR CONTINUE WITH', style: TextStyle(color: _textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
                          Expanded(child: Divider(color: _border)),
                        ]),
                        const SizedBox(height: 20),

                        // Google
                        GestureDetector(
                          onTap: _isLoading ? null : _loginWithGoogle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Image.network('https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                  height: 20, errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, color: _textPri)),
                              const SizedBox(width: 10),
                              const Text('Continue with Google', style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 28),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_isLogin ? "Don't have an account? " : 'Already have an account? ',
                          style: const TextStyle(color: _textSec, fontSize: 13)),
                      GestureDetector(
                        onTap: _isLoading ? null : () => setState(() {
                          _isLogin = !_isLogin;
                          _formKey.currentState?.reset();
                        }),
                        child: Text(_isLogin ? 'Sign Up' : 'Sign In',
                            style: const TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _authTab(String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _isLogin = label == 'Sign In'; _formKey.currentState?.reset(); }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? _accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? _accent.withValues(alpha: 0.4) : Colors.transparent),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(color: active ? _accent : _textSec, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? type,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: TextFormField(
        controller: controller, obscureText: obscure, keyboardType: type, validator: validator,
        style: const TextStyle(color: _textPri, fontSize: 14),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(color: _textSec, fontSize: 13),
          prefixIcon: Icon(icon, color: _textSec, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF252B3B).withValues(alpha: 0.5)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      for (double y = 0; y < size.height; y += 40) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }
  @override
  bool shouldRepaint(CustomPainter old) => false;
}
