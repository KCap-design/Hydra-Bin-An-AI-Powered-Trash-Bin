import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/screens/auth_screen.dart';
import 'package:hydra_bin/screens/home_screen.dart';
import 'package:hydra_bin/services/cache_service.dart';

const _bg     = Color(0xFF0D0F1A);
const _accent = Color(0xFF22C55E);
const _textSec = Color(0xFF6B7280);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _bar;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.3, curve: Curves.easeOut));
    _bar  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.05, 0.9, curve: Curves.easeInOut));
    _ctrl.forward();
    _decideRoute();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _decideRoute() async {
    // 4-second splash as requested
    await Future.delayed(const Duration(milliseconds: 4000));
    if (!mounted) return;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      bool isOffline = false;
      try {
        await firebaseUser.reload().timeout(const Duration(seconds: 5));
      } catch (_) {
        isOffline = true;
      }

      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null) {
        bool isVerified = refreshed.emailVerified;
        final created = refreshed.metadata.creationTime;
        if (created != null && created.isBefore(DateTime(2026, 3, 8))) {
          isVerified = true;
        }
        if (refreshed.providerData.any((p) => p.providerId == 'google.com')) {
          isVerified = true;
        }

        // If verified, go home. 
        // If offline and we *can't* verify, but we have cached data, safely assume they were in already.
        final hasCached = await CacheService.hasSession();
        
        if (isVerified || (isOffline && !isVerified && hasCached)) { 
          _goHome(); 
          return; 
        }

        // If we are online and *definitely* unverified, sign out
        if (!isOffline && !isVerified) {
          await FirebaseAuth.instance.signOut();
        }
      }
    }

    final hasCached = await CacheService.hasSession();
    if (hasCached) { _goHome(); return; }
    
    // Total blank state — gotta login, but are we online?
    try {
      // Quick ping to check true online status
      await FirebaseAuth.instance.signInAnonymously().timeout(const Duration(seconds: 3));
      await FirebaseAuth.instance.currentUser?.delete();
      _goAuth();
    } catch (_) {
      // 100% Offline and Logged Out -> show offline page natively
      _goOffline();
    }
  }

  void _goHome() { if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())); }
  void _goAuth() { if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen())); }
  void _goOffline() { 
    if (!mounted) return; 
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const _OfflineScreen())); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        // Dot grid
        Positioned.fill(child: CustomPaint(painter: _DotPainter())),

        // Glow
        Center(child: Container(width: 300, height: 300,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [_accent.withValues(alpha: 0.07), Colors.transparent])))),

        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: FadeTransition(
              opacity: _fade,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Logo image
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/Caldruki.jpg', width: 130, height: 130, fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(width: 130, height: 130,
                      decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(24)),
                      child: const Icon(Icons.recycling_rounded, color: _accent, size: 60)),
                  ),
                ),
                Container(width: 130, height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, _accent.withValues(alpha: 0.4), Colors.transparent]),
                    boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                ),
                const SizedBox(height: 28),
                const Text('HYDRA BIN', style: TextStyle(
                  color: Color(0xFFF0F4FF), fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
                const SizedBox(height: 6),
                const Text('Smart Recycling Platform', style: TextStyle(color: _textSec, fontSize: 13, letterSpacing: 0.5)),

                const SizedBox(height: 48),
                // Animated loading bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AnimatedBuilder(
                    animation: _bar,
                    builder: (_, __) => Stack(children: [
                      Container(width: 160, height: 4, color: const Color(0xFF1A1D2E)),
                      Container(
                        width: 160 * _bar.value,
                        height: 4,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF16A34A)]),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 48),
                const Text('Made by: Kurt Gerfred Caballero', style: TextStyle(color: _textSec, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('CMHS • Creative Tech', style: TextStyle(color: Color(0xFF374151), fontSize: 11)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF2A2F45).withValues(alpha: 0.5);
    for (double x = 0; x < size.width; x += 32) {
      for (double y = 0; y < size.height; y += 32) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }
  @override
  bool shouldRepaint(_) => false;
}

// ─── Native Offline Fallback ──────────────────────────────────────────────
class _OfflineScreen extends StatelessWidget {
  const _OfflineScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _DotPainter())),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D2E),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF2A2F45)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded, color: Color(0xFFEF4444), size: 64),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3))),
                  child: const Text('NO CONNECTION', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
                const SizedBox(height: 24),
                const Text("You're Offline", style: TextStyle(color: Color(0xFFF0F4FF), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                const Text(
                  "Hydra Bin couldn't reach the internet securely. Please check your connection to log in or sync new data.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSec, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashScreen())),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Try Again'),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
