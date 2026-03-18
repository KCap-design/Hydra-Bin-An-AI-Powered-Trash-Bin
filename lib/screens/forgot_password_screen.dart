import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Design tokens
const Color _bg      = Color(0xFF0B0E17);
const Color _surface = Color(0xFF131824);
const Color _card    = Color(0xFF1C2030);
const Color _border  = Color(0xFF252B3B);
const Color _accent  = Color(0xFF22C55E);
const Color _textPri = Color(0xFFF8FAFC);
const Color _textSec = Color(0xFF64748B);
const Color _red     = Color(0xFFEF4444);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _snack(String msg, Color col) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: col,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _snack('Please enter your registered email', _red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _accent.withValues(alpha: 0.3))),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1), shape: BoxShape.circle,
                    border: Border.all(color: _accent.withValues(alpha: 0.4))),
                child: const Icon(Icons.mark_email_read_rounded, color: _accent, size: 30),
              ),
              const SizedBox(height: 16),
              const Text('Reset Email Sent', style: TextStyle(
                  color: _textPri, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'We have sent a password reset link to $email.\n\nCheck your email and follow the instructions to reset your password.',
                style: const TextStyle(color: _textSec, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to login
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _accent, borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(child: Text('OK',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800))),
                ),
              ),
            ]),
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(e.message ?? 'An error occurred. Please try again.', _red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(62),
        child: Container(
          decoration: const BoxDecoration(
              color: _surface, border: Border(bottom: BorderSide(color: _border))),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPri, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Text('Forgot Password',
                      style: TextStyle(color: _textPri, fontSize: 17,
                          fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                ),
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: _accent, size: 20),
                ),
              ]),
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _border),
                  ),
                  child: Column(children: [
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                        color: _surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: _border, width: 2),
                      ),
                      child: const Icon(Icons.password_rounded, color: _textPri, size: 32),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Reset your password',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textPri, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your registered email below to receive password reset instructions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textSec, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    
                    // Email Field
                    Container(
                      decoration: BoxDecoration(
                        color: _surface, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                      ),
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: _textPri, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: const TextStyle(color: _textSec, fontSize: 14),
                          prefixIcon: Icon(Icons.email_rounded, color: _accent.withValues(alpha: 0.7), size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Submit Button
                    GestureDetector(
                      onTap: _isLoading ? null : _resetPassword,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: _isLoading ? _accent.withValues(alpha: 0.5) : _accent,
                        ),
                        child: Center(child: _isLoading
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                            : const Text('Send Reset Link',
                                style: TextStyle(
                                    color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800))),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
