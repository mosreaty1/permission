import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mime/mime.dart';
import '../services/file_sync_service.dart';

// ─── Category definition ───────────────────────────────────────────────────
class FileCategory {
  final String id;
  final String label;
  final String icon;
  final Color color;
  final List<String> scanDirs;
  final Set<String> extensions;
  bool selected;
  int fileCount;
  List<_ScannedFile> files;

  FileCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.scanDirs,
    required this.extensions,
    this.selected = false,
    this.fileCount = 0,
    List<_ScannedFile>? files,
  }) : files = files ?? [];
}

class _ScannedFile {
  final File file;
  final String name;
  final int size;
  bool selected;
  _ScannedFile(this.file, this.name, this.size, {this.selected = true});
}

// ─── Screen ────────────────────────────────────────────────────────────────
class FileSelectorScreen extends StatefulWidget {
  const FileSelectorScreen({super.key});
  @override
  State<FileSelectorScreen> createState() => _FileSelectorScreenState();
}

class _FileSelectorScreenState extends State<FileSelectorScreen> {
  final _syncService = FileSyncService();

  bool _scanning    = false;
  bool _uploading   = false;
  bool _scanned     = false;
  int  _uploadDone  = 0;
  int  _uploadTotal = 0;
  String _uploadCurrent = '';
  String? _error;

  // Which category's files are shown in the detail panel
  FileCategory? _openCategory;

  final List<FileCategory> _categories = [
    FileCategory(
      id: 'images',
      label: 'Images',
      icon: '🖼️',
      color: const Color(0xFF10B981),
      scanDirs: [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Screenshots',
        '/storage/emulated/0/Download',
      ],
      extensions: {'.jpg','.jpeg','.png','.gif','.webp','.bmp','.heic','.tiff'},
    ),
    FileCategory(
      id: 'videos',
      label: 'Videos',
      icon: '🎬',
      color: const Color(0xFFEF4444),
      scanDirs: [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Videos',
        '/storage/emulated/0/Download',
      ],
      extensions: {'.mp4','.mkv','.avi','.mov','.3gp','.wmv','.flv','.webm'},
    ),
    FileCategory(
      id: 'audio',
      label: 'Audio',
      icon: '🎵',
      color: const Color(0xFF8B5CF6),
      scanDirs: [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Ringtones',
        '/storage/emulated/0/Recordings',
        '/storage/emulated/0/Voice Recorder',
      ],
      extensions: {'.mp3','.m4a','.wav','.aac','.ogg','.flac','.wma','.opus'},
    ),
    FileCategory(
      id: 'documents',
      label: 'Documents',
      icon: '📄',
      color: const Color(0xFF3B82F6),
      scanDirs: [
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
      ],
      extensions: {'.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.csv','.rtf'},
    ),
    FileCategory(
      id: 'whatsapp',
      label: 'WhatsApp',
      icon: '💚',
      color: const Color(0xFF25D366),
      scanDirs: [
        '/storage/emulated/0/WhatsApp/Media',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media',
      ],
      extensions: {'.jpg','.jpeg','.png','.mp4','.mp3','.ogg','.opus','.gif','.webp','.pdf','.doc','.docx'},
    ),
    FileCategory(
      id: 'whatsapp_chat',
      label: 'WhatsApp Chats',
      icon: '💬',
      color: const Color(0xFF128C7E),
      scanDirs: [
        '/storage/emulated/0/WhatsApp/Databases',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Databases',
      ],
      extensions: {'.db','.db.crypt15','.db.crypt14','.db.crypt13','.txt'},
    ),
    FileCategory(
      id: 'telegram',
      label: 'Telegram',
      icon: '✈️',
      color: const Color(0xFF2AABEE),
      scanDirs: [
        '/storage/emulated/0/Telegram',
        '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram',
      ],
      extensions: {'.jpg','.jpeg','.png','.mp4','.mp3','.ogg','.gif','.webp','.pdf','.doc','.docx','.zip'},
    ),
    FileCategory(
      id: 'downloads',
      label: 'Downloads',
      icon: '⬇️',
      color: const Color(0xFFF59E0B),
      scanDirs: [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
      ],
      extensions: {}, // all files
    ),
    FileCategory(
      id: 'apks',
      label: 'APK Files',
      icon: '📦',
      color: const Color(0xFFEC4899),
      scanDirs: [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/APKs',
      ],
      extensions: {'.apk'},
    ),
    FileCategory(
      id: 'contacts_backup',
      label: 'Contacts Backup',
      icon: '👥',
      color: const Color(0xFF06B6D4),
      scanDirs: [
        '/storage/emulated/0/',
        '/storage/emulated/0/Download',
      ],
      extensions: {'.vcf'},
    ),
  ];

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i == -1 ? '' : name.substring(i).toLowerCase();
  }

  Future<void> _scanAll() async {
    var status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) {
      setState(() => _error = 'Storage permission is required.');
      return;
    }

    setState(() { _scanning = true; _error = null; });

    for (final cat in _categories) {
      cat.files.clear();
      cat.fileCount = 0;
    }

    for (final cat in _categories) {
      for (final dirPath in cat.scanDirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        try {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final name = entity.path.split('/').last;
              final ext  = _ext(name);
              if (cat.extensions.isEmpty || cat.extensions.contains(ext)) {
                try {
                  final stat = await entity.stat();
                  if (stat.size > 0 && stat.size <= 100 * 1024 * 1024) {
                    cat.files.add(_ScannedFile(entity, name, stat.size));
                  }
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
      // Deduplicate by path
      final seen = <String>{};
      cat.files.retainWhere((f) => seen.add(f.file.path));
      cat.fileCount = cat.files.length;
    }

    setState(() { _scanning = false; _scanned = true; });
  }

  Future<void> _uploadSelected() async {
    final toUpload = <_ScannedFile>[];
    for (final cat in _categories) {
      if (cat.selected) {
        toUpload.addAll(cat.files.where((f) => f.selected));
      }
    }
    if (toUpload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files selected'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() {
      _uploading    = true;
      _uploadDone   = 0;
      _uploadTotal  = toUpload.length;
      _uploadCurrent = '';
      _error = null;
    });

    int succeeded = 0, failed = 0;
    await _syncService.syncSelectedFiles(
      files: toUpload.map((f) => f.file).toList(),
      onProgress: (done, total, current) {
        if (mounted) setState(() {
          _uploadDone    = done;
          _uploadTotal   = total;
          _uploadCurrent = current;
        });
      },
    );

    setState(() => _uploading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload complete! ${toUpload.length} files sent to admin.'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  int get _totalSelected {
    int n = 0;
    for (final cat in _categories) {
      if (cat.selected) n += cat.files.where((f) => f.selected).length;
    }
    return n;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
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
        title: Text('Select Files to Upload',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (_scanned && !_uploading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _scanAll,
                icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF6366F1)),
                label: Text('Rescan', style: GoogleFonts.inter(color: const Color(0xFF6366F1), fontSize: 13)),
              ),
            ),
        ],
      ),
      body: _uploading ? _buildUploadProgress() : _buildContent(),
      bottomNavigationBar: _scanned && !_uploading ? _buildBottomBar() : null,
    );
  }

  // ── Main content ──────────────────────────────────────────────────────────
  Widget _buildContent() {
    if (!_scanned && !_scanning) return _buildStartScan();
    if (_scanning) return _buildScanning();
    return _openCategory != null ? _buildFileList(_openCategory!) : _buildCategoryGrid();
  }

  Widget _buildStartScan() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.12),
              ),
              child: const Icon(Icons.folder_open, color: Color(0xFF6366F1), size: 48),
            ),
            const SizedBox(height: 24),
            Text('Select Files to Upload',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('Scan your device to see files by category,\nthen choose exactly what to send to admin.',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _scanAll,
                icon: const Icon(Icons.search, size: 20),
                label: Text('Scan Device', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanning() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 56, height: 56,
            child: CircularProgressIndicator(color: Color(0xFF6366F1), strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text('Scanning device…', style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Finding all your files by category', style: GoogleFonts.inter(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Select all row
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Text('Choose Categories', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() { for (final c in _categories) { if (c.fileCount > 0) c.selected = true; } }),
                child: Text('All', style: GoogleFonts.inter(color: const Color(0xFF6366F1), fontSize: 13)),
              ),
              Text('·', style: GoogleFonts.inter(color: Colors.white38)),
              TextButton(
                onPressed: () => setState(() { for (final c in _categories) c.selected = false; }),
                child: Text('None', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
              ),
            ],
          ),
        ),
        ...(_categories.map((cat) => _buildCategoryCard(cat))),
      ],
    );
  }

  Widget _buildCategoryCard(FileCategory cat) {
    final hasFiles = cat.fileCount > 0;
    return GestureDetector(
      onTap: hasFiles ? () => setState(() => _openCategory = cat) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cat.selected && hasFiles
                ? cat.color.withOpacity(0.5)
                : Colors.white.withOpacity(0.06),
            width: cat.selected && hasFiles ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: hasFiles
                  ? () => setState(() => cat.selected = !cat.selected)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: cat.selected && hasFiles ? cat.color : Colors.transparent,
                  border: Border.all(
                    color: cat.selected && hasFiles ? cat.color : Colors.white24,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: cat.selected && hasFiles
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            // Icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: hasFiles ? cat.color.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(cat.icon, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.label,
                      style: GoogleFonts.inter(
                          color: hasFiles ? Colors.white : Colors.white38,
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    hasFiles ? '${cat.fileCount} files found' : 'No files found',
                    style: GoogleFonts.inter(
                        color: hasFiles ? Colors.white54 : Colors.white24,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            if (hasFiles) ...[
              // Selected count chip
              if (cat.selected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cat.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${cat.files.where((f) => f.selected).length}',
                    style: GoogleFonts.inter(color: cat.color, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.white24, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  // ── File list for a category ──────────────────────────────────────────────
  Widget _buildFileList(FileCategory cat) {
    return Column(
      children: [
        // Sub-header
        Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _openCategory = null),
                child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white70),
              ),
              const SizedBox(width: 10),
              Text(cat.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(cat.label, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() { for (final f in cat.files) f.selected = true; }),
                child: Text('All', style: GoogleFonts.inter(color: cat.color, fontSize: 13)),
              ),
              TextButton(
                onPressed: () => setState(() { for (final f in cat.files) f.selected = false; }),
                child: Text('None', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
              ),
            ],
          ),
        ),
        // File list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: cat.files.length,
            itemBuilder: (_, i) {
              final f = cat.files[i];
              return GestureDetector(
                onTap: () => setState(() => f.selected = !f.selected),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: f.selected ? cat.color.withOpacity(0.4) : Colors.white.withOpacity(0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: f.selected ? cat.color : Colors.transparent,
                          border: Border.all(color: f.selected ? cat.color : Colors.white24, width: 2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: f.selected ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.name,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis),
                            Text(_fmtSize(f.size),
                                style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Upload progress ───────────────────────────────────────────────────────
  Widget _buildUploadProgress() {
    final pct = _uploadTotal == 0 ? 0.0 : _uploadDone / _uploadTotal;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120, height: 120,
                child: CircularProgressIndicator(
                  value: pct > 0 ? pct : null,
                  color: const Color(0xFF6366F1),
                  backgroundColor: Colors.white10,
                  strokeWidth: 6,
                ),
              ),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Uploading to Admin…',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('$_uploadDone / $_uploadTotal files',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 15)),
          const SizedBox(height: 12),
          Text(_uploadCurrent,
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final total = _totalSelected;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$total files selected',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              Text('${_categories.where((c) => c.selected).length} categories',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: total > 0 ? _uploadSelected : null,
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: Text('Upload', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
