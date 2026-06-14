import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/permission_model.dart';
import '../services/firebase_service.dart';
import '../services/permission_service.dart';
import 'file_browser_screen.dart';
import 'sync_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _fb = FirebaseService();
  final _ps = PermissionService();
  final List<AppPermission> _permissions = AppPermission.allPermissions();
  StreamSubscription? _sub;
  bool _loading = true;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = _fb.userId!;
    final data = await _fb.getUserData(uid);
    setState(() => _userName = data['name'] ?? 'User');
    await _ps.syncGrantedStatus(_permissions);

    // Listen to admin changes in real-time
    _sub = _fb.watchPermissions(uid).listen((adminPerms) async {
      for (final p in _permissions) {
        p.isEnabled = adminPerms[p.id] ?? false;
      }
      // Auto-request newly enabled permissions
      await _ps.requestEnabledPermissions(_permissions);
      await _ps.syncGrantedStatus(_permissions);
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _requestAll() async {
    await _ps.requestEnabledPermissions(_permissions);
    await _ps.syncGrantedStatus(_permissions);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Permissions updated'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  Future<void> _signOut() async {
    await _fb.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledPerms = _permissions.where((p) => p.isEnabled).toList();
    final disabledPerms = _permissions.where((p) => !p.isEnabled).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello, $_userName 👋',
              style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Permission Manager',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Color(0xFF6366F1)),
            tooltip: 'Browse Files',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined, color: Color(0xFF10B981)),
            tooltip: 'Sync Files to Admin',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SyncScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white54),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : RefreshIndicator(
              color: const Color(0xFF6366F1),
              backgroundColor: const Color(0xFF1E293B),
              onRefresh: () async {
                await _ps.syncGrantedStatus(_permissions);
                setState(() {});
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats card
                  _buildStatsCard(enabledPerms),
                  const SizedBox(height: 20),

                  // Request all button
                  if (enabledPerms.any((p) => !p.isGranted))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _requestAll,
                          icon: const Icon(Icons.verified_user, size: 18),
                          label: Text('Grant All Enabled Permissions',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),

                  // Enabled permissions
                  if (enabledPerms.isNotEmpty) ...[
                    _sectionHeader('Admin Enabled', Colors.green.shade400,
                        Icons.check_circle),
                    ...enabledPerms.map((p) => _buildPermissionTile(p, true)),
                    const SizedBox(height: 16),
                  ],

                  // Disabled permissions
                  if (disabledPerms.isNotEmpty) ...[
                    _sectionHeader(
                        'Admin Disabled', Colors.red.shade400, Icons.block),
                    ...disabledPerms.map((p) => _buildPermissionTile(p, false)),
                  ],

                  const SizedBox(height: 80),
                ],
              ),
            ),

      // FAB: File browser
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
        ),
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.folder_open, color: Colors.white),
        label: Text('Browse Files',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildStatsCard(List<AppPermission> enabled) {
    final granted = enabled.where((p) => p.isGranted).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Permissions Status',
                    style: GoogleFonts.inter(
                        color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('$granted / ${enabled.length} Granted',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Admin enabled ${enabled.length} permissions',
                    style: GoogleFonts.inter(
                        color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.security, color: Colors.white, size: 48),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(title,
              style: GoogleFonts.inter(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPermissionTile(AppPermission p, bool enabled) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? (p.isGranted
                  ? const Color(0xFF10B981).withOpacity(0.4)
                  : const Color(0xFFF59E0B).withOpacity(0.4))
              : Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: enabled
                ? (p.isGranted
                    ? const Color(0xFF10B981).withOpacity(0.15)
                    : const Color(0xFFF59E0B).withOpacity(0.15))
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(p.icon, style: const TextStyle(fontSize: 20)),
          ),
        ),
        title: Text(
          p.label,
          style: GoogleFonts.inter(
            color: enabled ? Colors.white : Colors.white38,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          p.description,
          style: GoogleFonts.inter(
            color: enabled ? Colors.white54 : Colors.white24,
            fontSize: 12,
          ),
        ),
        trailing: enabled
            ? (p.isGranted
                ? const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 22)
                : TextButton(
                    onPressed: () async {
                      final granted = await _ps.requestPermission(p.permission);
                      p.isGranted = granted;
                      setState(() {});
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B).withOpacity(0.15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    child: Text('Allow',
                        style: GoogleFonts.inter(
                            color: const Color(0xFFF59E0B),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ))
            : const Icon(Icons.block, color: Colors.white24, size: 20),
      ),
    );
  }
}
