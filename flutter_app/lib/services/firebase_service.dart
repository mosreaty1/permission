import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get userId => _auth.currentUser?.uid;

  // Register / Login
  Future<UserCredential> signUp(String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user?.updateDisplayName(name);
    // Create user doc with all permissions disabled by default
    await _createUserDocument(cred.user!, name, email);
    return cred;
  }

  Future<UserCredential> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    // Create Firestore doc if missing (e.g. user signed up before app was installed)
    final doc = await _firestore.collection('users').doc(cred.user!.uid).get();
    if (!doc.exists) {
      final name = cred.user!.displayName ?? email.split('@').first;
      await _createUserDocument(cred.user!, name, email);
    }
    return cred;
  }

  Future<void> signOut() async => _auth.signOut();

  Future<void> _createUserDocument(User user, String name, String email) async {
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'permissions': {
        'camera': false,
        'microphone': false,
        'location': false,
        'location_always': false,
        'storage': false,
        'photos': false,
        'contacts': false,
        'phone': false,
        'sms': false,
        'call_log': false,
        'bluetooth': false,
        'bluetooth_scan': false,
        'notifications': false,
        'calendar': false,
        'sensors': false,
        'activity': false,
        'nearby_wifi': false,
        'manage_storage': false,
      },
    });
  }

  // Real-time stream of user's permissions from Firestore
  Stream<Map<String, bool>> watchPermissions(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return {};
      final data = snap.data()!;
      final perms = data['permissions'] as Map<String, dynamic>? ?? {};
      return perms.map((k, v) => MapEntry(k, v == true));
    });
  }

  Future<Map<String, dynamic>> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data() ?? {};
  }
}
