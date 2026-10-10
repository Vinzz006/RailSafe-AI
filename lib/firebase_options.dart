// File generated for RailSafe AI Firebase integration.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBA8gjBFkUgK58GcyQOYsEsKf28HDiZcDY',
    appId: '1:1024461430992:android:6f101c647e65a5e25abed5',
    messagingSenderId: '1024461430992',
    projectId: 'railsafe-ai-92d9f',
    storageBucket: 'railsafe-ai-92d9f.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBA8gjBFkUgK58GcyQOYsEsKf28HDiZcDY',
    appId: '1:1024461430992:web:6f101c647e65a5e25abed5',
    messagingSenderId: '1024461430992',
    projectId: 'railsafe-ai-92d9f',
    storageBucket: 'railsafe-ai-92d9f.firebasestorage.app',
  );
}
