import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class DeviceFile {
  final String name;
  final String localPath;
  final int size;
  final String mimeType;
  final String fileType; // image | video | audio | document | apk | archive | other
  final String storageUrl;
  final String storagePath;
  final DateTime lastModified;
  final DateTime syncedAt;
  final String folder;

  DeviceFile({
    required this.name,
    required this.localPath,
    required this.size,
    required this.mimeType,
    required this.fileType,
    required this.storageUrl,
    required this.storagePath,
    required this.lastModified,
    required this.syncedAt,
    required this.folder,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'localPath': localPath,
        'size': size,
        'mimeType': mimeType,
        'fileType': fileType,
        'storageUrl': storageUrl,
        'storagePath': storagePath,
        'lastModified': Timestamp.fromDate(lastModified),
        'syncedAt': Timestamp.fromDate(syncedAt),
        'folder': folder,
      };
}

class FileSyncService {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage   = FirebaseStorage.instance;

  // 100 MB max per file upload
  static const int _maxFileBytes = 100 * 1024 * 1024;

  static const _imageExts  = {'.jpg','.jpeg','.png','.gif','.webp','.bmp','.heic','.tiff'};
  static const _videoExts  = {'.mp4','.mkv','.avi','.mov','.3gp','.wmv','.flv'};
  static const _audioExts  = {'.mp3','.m4a','.wav','.aac','.ogg','.flac','.wma'};
  static const _docExts    = {'.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.csv'};
  static const _archiveExts= {'.zip','.rar','.7z','.tar','.gz'};

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i == -1 ? '' : name.substring(i).toLowerCase();
  }

  String _fileType(String name) {
    final ext = _ext(name);
    if (_imageExts.contains(ext))   return 'image';
    if (_videoExts.contains(ext))   return 'video';
    if (_audioExts.contains(ext))   return 'audio';
    if (_docExts.contains(ext))     return 'document';
    if (ext == '.apk')              return 'apk';
    if (_archiveExts.contains(ext)) return 'archive';
    return 'other';
  }

  // Scan all files in a directory recursively
  Future<List<File>> _scanDirectory(String path) async {
    final results = <File>[];
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return results;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.size > 0 && stat.size <= _maxFileBytes) {
              results.add(entity);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return results;
  }

  // Main sync: scans device, uploads to Storage, saves metadata to Firestore
  Future<SyncResult> syncAllFiles({
    void Function(int done, int total, String currentFile)? onProgress,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return SyncResult(0, 0, 'Not logged in');

    // Scan all accessible folders
    final scanDirs = [
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/WhatsApp',
      '/storage/emulated/0/Telegram',
      '/storage/emulated/0/Screenshots',
      '/storage/emulated/0/Camera',
    ];

    final allFiles = <File>[];
    for (final dir in scanDirs) {
      final files = await _scanDirectory(dir);
      allFiles.addAll(files);
    }

    // Remove duplicates by path
    final seen = <String>{};
    final unique = allFiles.where((f) => seen.add(f.path)).toList();

    int done = 0;
    int succeeded = 0;
    int failed = 0;

    // Get already-synced files to skip re-upload
    final existingSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('device_files')
        .get();
    final existingPaths = {
      for (final d in existingSnap.docs)
        (d.data()['localPath'] as String? ?? ''): d.id
    };

    for (final file in unique) {
      done++;
      final name = p.basename(file.path);
      onProgress?.call(done, unique.length, name);

      try {
        final stat = await file.stat();

        // Skip if already synced and file hasn't changed
        if (existingPaths.containsKey(file.path)) {
          final existingDoc = await _firestore
              .collection('users')
              .doc(uid)
              .collection('device_files')
              .doc(existingPaths[file.path])
              .get();
          final existing = existingDoc.data();
          if (existing != null) {
            final existingModified = (existing['lastModified'] as Timestamp?)?.toDate();
            if (existingModified != null &&
                !stat.modified.isAfter(existingModified.add(const Duration(seconds: 5)))) {
              succeeded++;
              continue; // already synced, skip
            }
          }
        }

        // Upload to Firebase Storage
        final storagePath = 'users/$uid/files/${file.path.replaceAll('/', '_')}';
        final ref = _storage.ref(storagePath);
        final mime = lookupMimeType(file.path) ?? 'application/octet-stream';

        await ref.putFile(file, SettableMetadata(contentType: mime));
        final downloadUrl = await ref.getDownloadURL();

        final folder = p.dirname(file.path)
            .replaceAll('/storage/emulated/0/', '')
            .split('/')
            .first;

        final deviceFile = DeviceFile(
          name: name,
          localPath: file.path,
          size: stat.size,
          mimeType: mime,
          fileType: _fileType(name),
          storageUrl: downloadUrl,
          storagePath: storagePath,
          lastModified: stat.modified,
          syncedAt: DateTime.now(),
          folder: folder,
        );

        // Save metadata to Firestore
        final docId = existingPaths[file.path] ??
            _firestore
                .collection('users')
                .doc(uid)
                .collection('device_files')
                .doc()
                .id;

        await _firestore
            .collection('users')
            .doc(uid)
            .collection('device_files')
            .doc(docId)
            .set(deviceFile.toMap());

        succeeded++;
      } catch (_) {
        failed++;
      }
    }

    // Update summary in user doc
    await _firestore.collection('users').doc(uid).update({
      'fileStats': {
        'total': succeeded,
        'lastSync': FieldValue.serverTimestamp(),
      },
    });

    return SyncResult(succeeded, failed, null);
  }
}

class SyncResult {
  final int succeeded;
  final int failed;
  final String? error;
  SyncResult(this.succeeded, this.failed, this.error);
}
