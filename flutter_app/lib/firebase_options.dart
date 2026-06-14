import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError('Only Android is supported');
  }

  // ⚠️  Replace appId and messagingSenderId below with values from
  //     your google-services.json (download from Firebase Console →
  //     Project Settings → Android app)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAwVeCSzwO50MPqp9SkjDKk3AZ91xml0Uk',
    appId:             '1:444805548673:android:REPLACE_WITH_ANDROID_APP_ID',
    messagingSenderId: '444805548673',
    projectId:         'permisionn',
    storageBucket:     'permisionn.firebasestorage.app',
  );
}
