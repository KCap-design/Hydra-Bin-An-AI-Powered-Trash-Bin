import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/screens/auth_screen.dart';
import 'package:hydra_bin/screens/home_screen.dart';
import 'package:hydra_bin/services/cache_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    // Small delay to show the splash screen animation
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    // ── Priority 1: Firebase has an active session ───────────────────────
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      // Try to reload for the latest verification status (may fail if offline)
      try {
        await firebaseUser.reload().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Offline or slow — use whatever state we have
      }

      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null) {
        bool isVerified = refreshed.emailVerified;

        // Legacy bypass: accounts created before March 8, 2026
        final created = refreshed.metadata.creationTime;
        if (created != null && created.isBefore(DateTime(2026, 3, 8))) {
          isVerified = true;
        }

        if (isVerified) {
          _goHome();
          return;
        }

        // Unverified — sign out and show auth
        await FirebaseAuth.instance.signOut();
        _goAuth();
        return;
      }
    }

    // ── Priority 2: No Firebase session but we have cached data ──────────
    // Happens when: device is offline and Firebase couldn't restore auth,
    // OR user was previously logged in and the token was cleared offline.
    final hasCached = await CacheService.hasSession();
    if (hasCached) {
      _goHome();
      return;
    }

    // ── Priority 3: No session at all — must log in ───────────────────────
    _goAuth();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _goAuth() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.recycling,
              size: 100,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Hydra Bin: Trash Sorter',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
            const SizedBox(height: 48),
            Text(
              'Made by: Kurt Gerfred Caballero - For Creative Tech',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade400,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'CMHS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
