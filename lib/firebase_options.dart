import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyChHhZAI0w6xGUWAdS4N5tikVj4zkxBy3s',
    appId: '1:756530453252:web:2e6335c3a18941c3614e51',
    messagingSenderId: '756530453252',
    projectId: 'hydra-bin',
    authDomain: 'hydra-bin.firebaseapp.com',
    storageBucket: 'hydra-bin.firebasestorage.app',
    measurementId: 'G-VDKM4V0QDS',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCn756TUdxyRR7Gfo7bjqT-gtrU7hfyO9E',
    appId: '1:756530453252:android:4d48150ce03e4e6e614e51',
    messagingSenderId: '756530453252',
    projectId: 'hydra-bin',
    storageBucket: 'hydra-bin.firebasestorage.app',
  );
}
