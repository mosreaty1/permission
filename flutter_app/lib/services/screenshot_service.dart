import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

class ScreenshotService {
  static const _channel = MethodChannel('com.permissionhub/screen_capture');
  final _firestore = FirebaseFirestore.instance;
  final _storage   = FirebaseStorage.instance;
  final _auth      = FirebaseAuth.instance;

  Stream<DocumentSnapshot> watchScreenshotCommand(String uid) {
    return _firestore
        .collection('users').doc(uid)
        .collection('commands').doc('screenshot')
        .snapshots();
  }

  Future<void> handleScreenshotRequest(String uid) async {
    try {
      // Capture the screen via native MediaProjection
      final bytes = await _channel.invokeMethod<Uint8List>('captureScreen');
      if (bytes == null) return;

      // Upload to Firebase Storage
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref('users/$uid/screenshots/screen_$ts.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      // Write URL + timestamp back to Firestore so dashboard can show it
      await _firestore.collection('users').doc(uid)
          .collection('commands').doc('screenshot')
          .update({
        'status': 'done',
        'url':    url,
        'takenAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      await _firestore.collection('users').doc(uid)
          .collection('commands').doc('screenshot')
          .update({'status': 'error', 'error': e.toString()});
    }
  }
}
