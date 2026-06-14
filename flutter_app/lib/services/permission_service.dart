import 'package:permission_handler/permission_handler.dart';
import '../models/permission_model.dart';

class PermissionService {
  // Request a single permission and return if granted
  Future<bool> requestPermission(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  // Request multiple permissions at once
  Future<Map<Permission, PermissionStatus>> requestMultiple(
      List<Permission> permissions) async {
    return await permissions.request();
  }

  // Check status without requesting
  Future<bool> checkPermission(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  // Sync device permission status for all app permissions
  Future<void> syncGrantedStatus(List<AppPermission> perms) async {
    for (final p in perms) {
      p.isGranted = await checkPermission(p.permission);
    }
  }

  // Request ALL admin-enabled permissions
  Future<void> requestEnabledPermissions(List<AppPermission> perms) async {
    for (final p in perms) {
      if (p.isEnabled && !p.isGranted) {
        p.isGranted = await requestPermission(p.permission);
      }
    }
  }

  // Open app settings so user can manually grant
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
