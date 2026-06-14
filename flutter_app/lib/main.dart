import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PermissionApp());
}

class PermissionApp extends StatelessWidget {
  const PermissionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PermissionHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: FirebaseService().currentUser != null
          ? const HomeScreen()
          : const LoginScreen(),
    );
  }
}
