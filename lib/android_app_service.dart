import 'package:flutter/services.dart';

class AndroidAppInfo {
  final String packageName;
  final String name;
  String? customName;
  bool isFavorite;
  bool isHidden;

  AndroidAppInfo({
    required this.packageName,
    required this.name,
    this.customName,
    this.isFavorite = false,
    this.isHidden = false,
  });

  String get displayName => customName ?? name;
}

class AndroidAppService {
  static const MethodChannel _channel = MethodChannel('wiki.wiki.launcher/apps');

  static Future<List<AndroidAppInfo>> getInstalledApps() async {
    try {
      final List<dynamic> apps = await _channel.invokeMethod('getInstalledApps');
      return apps.map((app) => AndroidAppInfo(
        packageName: app['packageName'] ?? '',
        name: app['name'] ?? '',
      )).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final result = await _channel.invokeMethod('getAppIcon', {'packageName': packageName});
      if (result != null) {
        return Uint8List.fromList(List<int>.from(result));
      }
    } catch (e) {
      // Icon loading failed
    }
    return null;
  }

  static Future<void> openApp(String packageName) async {
    try {
      await _channel.invokeMethod('openApp', {'packageName': packageName});
    } catch (e) {
      // Failed to open app
    }
  }

  static Future<void> openAppInfo(String packageName) async {
    try {
      await _channel.invokeMethod('openAppInfo', {'packageName': packageName});
    } catch (e) {
      // Failed to open app info
    }
  }

  static Future<void> uninstallApp(String packageName) async {
    try {
      await _channel.invokeMethod('uninstallApp', {'packageName': packageName});
    } catch (e) {
      // Failed to uninstall
    }
  }

  static Future<void> expandStatusBar() async {
    try {
      await _channel.invokeMethod('expandStatusBar');
    } catch (e) {
      // Try system command fallback
      try {
        await const MethodChannel('shell').invokeMethod('run', 
          {'command': 'service call statusbar 1'});
      } catch (_) {}
    }
  }
}
