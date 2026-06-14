import 'package:permission_handler/permission_handler.dart';

class AppPermission {
  final String id;
  final String label;
  final String description;
  final String icon;
  final Permission permission;
  bool isEnabled; // controlled by admin
  bool isGranted; // actual device status

  AppPermission({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.permission,
    this.isEnabled = false,
    this.isGranted = false,
  });

  static List<AppPermission> allPermissions() => [
        AppPermission(
          id: 'camera',
          label: 'Camera',
          description: 'Take photos and record video',
          icon: '📷',
          permission: Permission.camera,
        ),
        AppPermission(
          id: 'microphone',
          label: 'Microphone',
          description: 'Record audio',
          icon: '🎙️',
          permission: Permission.microphone,
        ),
        AppPermission(
          id: 'location',
          label: 'Location',
          description: 'Access precise GPS location',
          icon: '📍',
          permission: Permission.locationWhenInUse,
        ),
        AppPermission(
          id: 'location_always',
          label: 'Location (Always)',
          description: 'Access location in background',
          icon: '🗺️',
          permission: Permission.locationAlways,
        ),
        AppPermission(
          id: 'storage',
          label: 'Storage',
          description: 'Read and write files on device',
          icon: '💾',
          permission: Permission.storage,
        ),
        AppPermission(
          id: 'photos',
          label: 'Photos & Media',
          description: 'Access photos and media files',
          icon: '🖼️',
          permission: Permission.photos,
        ),
        AppPermission(
          id: 'contacts',
          label: 'Contacts',
          description: 'Read and write contacts',
          icon: '👥',
          permission: Permission.contacts,
        ),
        AppPermission(
          id: 'phone',
          label: 'Phone',
          description: 'Make and manage phone calls',
          icon: '📞',
          permission: Permission.phone,
        ),
        AppPermission(
          id: 'sms',
          label: 'SMS',
          description: 'Send and receive SMS messages',
          icon: '💬',
          permission: Permission.sms,
        ),
        AppPermission(
          id: 'call_log',
          label: 'Call Log',
          description: 'Access call history',
          icon: '📋',
          permission: Permission.contacts,
        ),
        AppPermission(
          id: 'bluetooth',
          label: 'Bluetooth',
          description: 'Connect to Bluetooth devices',
          icon: '🔵',
          permission: Permission.bluetooth,
        ),
        AppPermission(
          id: 'bluetooth_scan',
          label: 'Bluetooth Scan',
          description: 'Scan for nearby Bluetooth devices',
          icon: '📡',
          permission: Permission.bluetoothScan,
        ),
        AppPermission(
          id: 'notifications',
          label: 'Notifications',
          description: 'Show push notifications',
          icon: '🔔',
          permission: Permission.notification,
        ),
        AppPermission(
          id: 'calendar',
          label: 'Calendar',
          description: 'Read and write calendar events',
          icon: '📅',
          permission: Permission.calendarFullAccess,
        ),
        AppPermission(
          id: 'sensors',
          label: 'Body Sensors',
          description: 'Access health and fitness sensors',
          icon: '❤️',
          permission: Permission.sensors,
        ),
        AppPermission(
          id: 'activity',
          label: 'Activity Recognition',
          description: 'Detect physical activity',
          icon: '🏃',
          permission: Permission.activityRecognition,
        ),
        AppPermission(
          id: 'nearby_wifi',
          label: 'Nearby WiFi',
          description: 'Scan for nearby WiFi networks',
          icon: '📶',
          permission: Permission.nearbyWifiDevices,
        ),
        AppPermission(
          id: 'manage_storage',
          label: 'Manage All Files',
          description: 'Full file system access',
          icon: '🗂️',
          permission: Permission.manageExternalStorage,
        ),
      ];
}
