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
    apiKey:            'AIzaSyDCrOv4QKVoFF5V2CuTsBY6IyBa89q_Q3M',
    appId:             '1:444805548673:android:60d3f51f51874203b89b80',
    messagingSenderId: '444805548673',
    projectId:         'permisionn',
    storageBucket:     'permisionn.firebasestorage.app',
  );
}
