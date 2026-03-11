import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/screens/home_screen.dart';
import 'package:hydra_bin/screens/forgot_password_screen.dart';

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
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _cooldownSeconds = 60;
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_cooldownSeconds > 0) {
            _cooldownSeconds--;
          } else {
            _canResend = true;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified && _canResend) {
      try {
        await user.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _startCooldown();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send email: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          // Re-use timer state from underlying AuthScreen state
          return AlertDialog(
            title: const Text('Verify Your Email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please verify your email before logging in.\n\n'
                  'IMPORTANT: Please check your Spam or Junk folder if you do not see it in your inbox.',
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: _canResend
                        ? () async {
                            await _resendVerificationEmail();
                            setState(() {}); // trigger rebuild to show timer
                            this.setState(() {}); // trigger underlying map too
                          }
                        : null,
                    icon: const Icon(Icons.email),
                    label: Text(_canResend
                        ? 'Resend Verification Email'
                        : 'Resend Email in $_cooldownSeconds s'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        });
      },
    );
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
          await cred.user!.reload(); // Force refresh status just in case
          final user = FirebaseAuth.instance.currentUser!;
          
          bool isVerified = user.emailVerified;
          
          // Legacy bypass: Accounts created before March 8, 2026
          final creationTime = user.metadata.creationTime;
          if (creationTime != null && creationTime.isBefore(DateTime(2026, 3, 8))) {
            isVerified = true;
          }

          if (!isVerified) {
            // Unverified user logic
            if (!mounted) return;
            _showVerificationDialog();
            return; // Stop execution, don't navigate to HomeScreen
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
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(), // For tie-breaker
            'streak': 0,
            'lastConnectionDate': null,
            'activeTheme': 'Dark Mode',
            'activeFrame': 'Default',
            'unlockedThemes': ['Dark Mode'],
            'unlockedFrames': ['Default'],
            'fcmToken': '',
          });
        }
        
        if (!mounted) return;
        _showVerificationDialog();
        setState(() => _isLogin = true); // Switch to login view
        return; // Don't navigate to HomeScreen yet
      }
      
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Authentication failed')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.recycling, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Hydra Bin: Trash Sorter',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Login' : 'Sign up',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                if (!_isLogin) ...[
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter password';
                    if (!_isLogin && v.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isLogin ? 'Login' : 'Create account'),
                ),
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                      child: const Text('Forgot Password?'),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign up"
                        : 'Already have an account? Login',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
