// ⚠️  REPLACE ALL VALUES BELOW WITH YOUR OWN FIREBASE PROJECT CONFIG
// Steps:
//   1. Go to https://console.firebase.google.com
//   2. Create project → Add Android app (package: com.example.permission_app)
//   3. Download google-services.json → place in flutter_app/android/app/
//   4. Run: flutterfire configure
//   This file will be auto-generated. Until then, fill in manually:

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError('Only Android is supported');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );
}
