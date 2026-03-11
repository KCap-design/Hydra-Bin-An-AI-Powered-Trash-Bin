import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/firebase_options.dart';
import 'package:hydra_bin/screens/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const HydraBinApp());
}

class HydraBinApp extends StatefulWidget {
  const HydraBinApp({super.key});

  @override
  State<HydraBinApp> createState() => _HydraBinAppState();
}

class _HydraBinAppState extends State<HydraBinApp> {
  String _activeTheme = 'Dark Mode';

  @override
  void initState() {
    super.initState();
    _listenToTheme();
  }

  void _listenToTheme() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((snap) {
          if (snap.exists && mounted) {
            final theme = snap.data()?['activeTheme'] as String? ?? 'Dark Mode';
            if (_activeTheme != theme) {
              setState(() {
                _activeTheme = theme;
              });
            }
          }
        });
      }
    });
  }

  ThemeData _getThemeData() {
    switch (_activeTheme) {
      case 'Forest Green':
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.dark,
            surface: const Color(0xFF1B241B),
            primary: Colors.green.shade400,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF101A10),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1B241B),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
        );
      case 'Ocean Blue':
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
            surface: const Color(0xFF1B2430),
            primary: Colors.blue.shade400,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF101620),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1B2430),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
        );
      case 'Dark Mode':
      default:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.dark,
            surface: const Color(0xFF1E1E1E),
            primary: Colors.blueGrey.shade300,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E1E1E),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hydra Bin',
      debugShowCheckedModeBanner: false,
      theme: _getThemeData(),
      home: const SplashScreen(),
    );
  }
}
