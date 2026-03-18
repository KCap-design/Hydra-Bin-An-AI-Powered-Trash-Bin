import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/firebase_options.dart';
import 'package:hydra_bin/screens/splash_screen.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const HydraBinApp());
}

class HydraBinApp extends StatefulWidget {
  const HydraBinApp({super.key});

  @override
  State<HydraBinApp> createState() => _HydraBinAppState();
}

class _HydraBinAppState extends State<HydraBinApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToAuth();
  }

  @override
  void dispose() {
    _updateOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateOnlineStatus(state == AppLifecycleState.resumed);
  }

  void _updateOnlineStatus(bool online) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }
  }

  void _listenToAuth() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _updateOnlineStatus(true);
    });
  }

  ThemeData _theme() {
    const bg      = Color(0xFF0D0F1A);
    const surface = Color(0xFF141622);
    const accent  = Color(0xFF22C55E);
    const textPri = Color(0xFFF0F4FF);
    const textSec = Color(0xFF6B7280);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        surface: surface, primary: accent, onSurface: textPri, onPrimary: Colors.black,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: textPri, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: textSec),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: surface, foregroundColor: textPri, elevation: 0),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1D2E), elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2A2F45))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hydra Bin',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: const SplashScreen(),
    );
  }
}
