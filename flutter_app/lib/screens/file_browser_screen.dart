import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mime/mime.dart';
import 'image_viewer_screen.dart';

class FileBrowserScreen extends StatefulWidget {
  final String? initialPath;
  const FileBrowserScreen({super.key, this.initialPath});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  String _currentPath = '/storage/emulated/0';
  List<FileSystemEntity> _entities = [];
  bool _loading = true;
  bool _hasPermission = false;
  final List<String> _history = [];

  static const _imageExts = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'
  };
  static const _videoExts = {'.mp4', '.mkv', '.avi', '.mov', '.3gp'};
  static const _audioExts = {'.mp3', '.m4a', '.wav', '.aac', '.ogg', '.flac'};
  static const _docExts = {'.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt'};

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) _currentPath = widget.initialPath!;
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    setState(() => _hasPermission = status.isGranted);
    if (_hasPermission) _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() => _loading = true);
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        _currentPath = '/storage/emulated/0';
        await _loadDirectory(_currentPath);
        return;
      }
      final entities = dir.listSync(followLinks: false)
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      setState(() {
        _currentPath = path;
        _entities = entities;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot access: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _navigate(String path) {
    _history.add(_currentPath);
    _loadDirectory(path);
  }

  bool _canGoBack() => _history.isNotEmpty;

  void _goBack() {
    if (_history.isNotEmpty) {
      _loadDirectory(_history.removeLast());
    }
  }

  String _fileName(FileSystemEntity e) => e.path.split('/').last;

  String _ext(String name) {
    final idx = name.lastIndexOf('.');
    return idx == -1 ? '' : name.substring(idx).toLowerCase();
  }

  IconData _fileIcon(FileSystemEntity e) {
    if (e is Directory) return Icons.folder;
    final ext = _ext(_fileName(e));
    if (_imageExts.contains(ext)) return Icons.image;
    if (_videoExts.contains(ext)) return Icons.video_file;
    if (_audioExts.contains(ext)) return Icons.audio_file;
    if (_docExts.contains(ext)) return Icons.description;
    if (ext == '.apk') return Icons.android;
    if (ext == '.zip' || ext == '.rar' || ext == '.7z') return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _fileColor(FileSystemEntity e) {
    if (e is Directory) return const Color(0xFFF59E0B);
    final ext = _ext(_fileName(e));
    if (_imageExts.contains(ext)) return const Color(0xFF10B981);
    if (_videoExts.contains(ext)) return const Color(0xFFEF4444);
    if (_audioExts.contains(ext)) return const Color(0xFF8B5CF6);
    if (_docExts.contains(ext)) return const Color(0xFF3B82F6);
    return Colors.white54;
  }

  String _fileSize(FileSystemEntity e) {
    if (e is Directory) return 'Folder';
    try {
      final bytes = (e as File).lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (_) {
      return '';
    }
  }

  Future<void> _openFile(FileSystemEntity e) async {
    if (e is Directory) {
      _navigate(e.path);
      return;
    }
    final name = _fileName(e);
    final ext = _ext(name);

    if (_imageExts.contains(ext)) {
      // Collect all images in current dir for gallery
      final images = _entities
          .whereType<File>()
          .where((f) => _imageExts.contains(_ext(_fileName(f))))
          .map((f) => f.path)
          .toList();
      final idx = images.indexOf(e.path);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(
              imagePaths: images,
              initialIndex: idx < 0 ? 0 : idx,
            ),
          ),
        );
      }
    } else {
      final result = await OpenFile.open(e.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot open file: ${result.message}'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<_QuickAccess> get _quickAccess => [
        _QuickAccess('📷 Camera', '/storage/emulated/0/DCIM/Camera'),
        _QuickAccess('🖼️ Pictures', '/storage/emulated/0/Pictures'),
        _QuickAccess('⬇️ Downloads', '/storage/emulated/0/Download'),
        _QuickAccess('📹 Videos', '/storage/emulated/0/Movies'),
        _QuickAccess('🎵 Music', '/storage/emulated/0/Music'),
        _QuickAccess('📄 Documents', '/storage/emulated/0/Documents'),
      ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_canGoBack()) {
          _goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            color: Colors.white,
            onPressed: () {
              if (_canGoBack()) {
                _goBack();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File Browser',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                _currentPath.replaceAll('/storage/emulated/0', '~/'),
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.white70),
              onPressed: () =>
                  _loadDirectory('/storage/emulated/0'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: () => _loadDirectory(_currentPath),
            ),
          ],
        ),
        body: !_hasPermission
            ? _buildNoPermission()
            : Column(
                children: [
                  // Quick access row
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      children: _quickAccess
                          .map((qa) => _buildQuickChip(qa))
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF6366F1)))
                        : _entities.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.folder_open,
                                        color: Colors.white24, size: 64),
                                    const SizedBox(height: 12),
                                    Text('Empty folder',
                                        style: GoogleFonts.inter(
                                            color: Colors.white38,
                                            fontSize: 16)),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _entities.length,
                                itemBuilder: (ctx, i) =>
                                    _buildFileTile(_entities[i]),
                              ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildQuickChip(_QuickAccess qa) {
    return GestureDetector(
      onTap: () => _navigate(qa.path),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: Text(qa.label,
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _buildFileTile(FileSystemEntity e) {
    final name = _fileName(e);
    final color = _fileColor(e);
    return InkWell(
      onTap: () => _openFile(e),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_fileIcon(e), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _fileSize(e),
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (e is Directory)
              const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPermission() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, color: Colors.white24, size: 80),
            const SizedBox(height: 20),
            Text('Storage Permission Required',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              'Ask your admin to enable Storage permission, then tap below.',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _checkAndLoad,
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccess {
  final String label;
  final String path;
  _QuickAccess(this.label, this.path);
}
