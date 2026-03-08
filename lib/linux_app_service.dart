import 'dart:io';
import 'package:flutter/foundation.dart';

class LinuxAppInfo {
  String appName;
  String? customName;
  final String desktopFile;
  final String exec;
  final String? iconPath;
  bool isFavorite;
  bool isHidden;
  Uint8List? iconBytes;
  final String appType; // 'system', 'flatpak', 'snap', 'appimage'

  LinuxAppInfo({
    required this.appName,
    required this.desktopFile,
    required this.exec,
    this.iconPath,
    this.isFavorite = false,
    this.isHidden = false,
    this.customName,
    this.iconBytes,
    this.appType = 'system',
  });

  String get displayName => customName ?? appName;
  String get packageName => desktopFile; // Use desktop file as unique ID
}

class LinuxAppService {
  static final String _home = Platform.environment['HOME'] ?? '/home';
  
  // Desktop file locations
  static final List<String> _desktopDirs = [
    // System-wide
    '/usr/share/applications',
    '/usr/local/share/applications',
    // User-specific
    '$_home/.local/share/applications',
    // Flatpak
    '/var/lib/flatpak/exports/share/applications',
    '$_home/.local/share/flatpak/exports/share/applications',
    // Snap
    '/var/lib/snapd/desktop/applications',
    '/snap/current/usr/share/applications',
    // KDE specific
    '/usr/share/kservices5',
    '$_home/.local/share/kservices5',
  ];

  // AppImage locations to scan
  static final List<String> _appImageDirs = [
    '$_home/Applications',
    '$_home/AppImages',
    '$_home/.local/bin',
    '$_home/Downloads',
    '$_home/İndirilenler',
    '$_home/Belgeler',
    '$_home/Documents',
    '$_home/Masaüstü',
    '$_home/Desktop',
    '$_home/Moonlight',
    '$_home/Müzik',
    '$_home/Music',
    '/opt',
    '/usr/local/bin',
    // Common app directories
    '$_home/.local/share/applications',
  ];

  // KDE Plasma optimized icon directories
  static final List<String> _iconDirs = [
    // KDE Breeze theme (most common on KDE Plasma)
    '/usr/share/icons/breeze/apps/48',
    '/usr/share/icons/breeze-dark/apps/48',
    '/usr/share/icons/breeze/apps/64',
    '/usr/share/icons/breeze-dark/apps/64',
    '/usr/share/icons/breeze/apps/scalable',
    '/usr/share/icons/breeze-dark/apps/scalable',
    // Oxygen theme (classic KDE)
    '/usr/share/icons/oxygen/base/48x48/apps',
    '/usr/share/icons/oxygen/base/64x64/apps',
    '/usr/share/icons/oxygen/base/scalable/apps',
    // Hicolor (fallback)
    '/usr/share/icons/hicolor/128x128/apps',
    '/usr/share/icons/hicolor/96x96/apps',
    '/usr/share/icons/hicolor/64x64/apps',
    '/usr/share/icons/hicolor/48x48/apps',
    '/usr/share/icons/hicolor/scalable/apps',
    // Pixmaps
    '/usr/share/pixmaps',
    // User icons
    '$_home/.local/share/icons',
    '$_home/.local/share/icons/hicolor/scalable/apps',
    '$_home/.local/share/icons/hicolor/128x128/apps',
    '$_home/.local/share/icons/hicolor/48x48/apps',
    // Flatpak icons
    '/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps',
    '/var/lib/flatpak/exports/share/icons/hicolor/64x64/apps',
    '$_home/.local/share/flatpak/exports/share/icons/hicolor/128x128/apps',
    // Snap icons
    '/snap/current/usr/share/icons/hicolor/256x256/apps',
  ];

  static Future<List<LinuxAppInfo>> getInstalledApps() async {
    final List<LinuxAppInfo> apps = [];
    final Set<String> seen = {};

    // 1. Scan desktop files from standard locations
    for (final dir in _desktopDirs) {
      final directory = Directory(dir);
      if (!await directory.exists()) continue;

      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.desktop')) {
          try {
            final app = await _parseDesktopFile(entity);
            if (app != null && !seen.contains(app.appName.toLowerCase())) {
              seen.add(app.appName.toLowerCase());
              apps.add(app);
            }
          } catch (e) {
            debugPrint('Error parsing ${entity.path}: $e');
          }
        }
      }
    }

    // 2. Scan for AppImage files
    await _scanAppImages(apps, seen);

    apps.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
    return apps;
  }

  static Future<void> _scanAppImages(List<LinuxAppInfo> apps, Set<String> seen) async {
    for (final dirPath in _appImageDirs) {
      final directory = Directory(dirPath);
      if (!await directory.exists()) continue;

      try {
        await for (final entity in directory.list(recursive: false)) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;
            final lowerName = fileName.toLowerCase();
            
            // Check if it's an AppImage
            bool isAppImage = false;
            if (lowerName.endsWith('.appimage')) {
              isAppImage = true;
            } else {
              // Check if file is executable and has AppImage signature
              try {
                final stat = await entity.stat();
                if (stat.mode & 0x49 != 0) { // Executable by someone
                  final bytes = await entity.openRead(0, 16).toList();
                  if (bytes.isNotEmpty) {
                    final header = bytes.expand((x) => x).toList();
                    // Check for ELF magic + AppImage
                    if (header.length >= 4 && 
                        header[0] == 0x7F && 
                        header[1] == 0x45 && 
                        header[2] == 0x4C && 
                        header[3] == 0x46) {
                      // Could be AppImage, check if name suggests it
                      if (lowerName.contains('appimage') || 
                          lowerName.contains('-x86_64') ||
                          lowerName.contains('-aarch64')) {
                        isAppImage = true;
                      }
                    }
                  }
                }
              } catch (_) {}
            }

            if (isAppImage) {
              final appName = _extractAppNameFromFileName(fileName);
              if (!seen.contains(appName.toLowerCase())) {
                seen.add(appName.toLowerCase());
                
                // Try to find icon for this AppImage
                final iconPath = await _findAppImageIcon(entity.path, appName);
                
                apps.add(LinuxAppInfo(
                  appName: appName,
                  desktopFile: entity.path,
                  exec: entity.path,
                  iconPath: iconPath,
                  appType: 'appimage',
                ));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning AppImages in $dirPath: $e');
      }
    }
  }

  static String _extractAppNameFromFileName(String fileName) {
    // Remove extension
    String name = fileName
        .replaceAll(RegExp(r'\.AppImage$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.appimage$', caseSensitive: false), '');
    
    // Remove version numbers and architecture suffixes
    name = name
        .replaceAll(RegExp(r'-x86_64'), '')
        .replaceAll(RegExp(r'-aarch64'), '')
        .replaceAll(RegExp(r'-linux$'), '')
        .replaceAll(RegExp(r'[-_]v?\d+\.\d+(\.\d+)?.*$'), '')
        .replaceAll(RegExp(r'[-_]\d+$'), '');
    
    // Clean up remaining dashes/underscores at the end
    name = name.replaceAll(RegExp(r'[-_]+$'), '');
    
    // Capitalize first letter of each word
    if (name.isNotEmpty) {
      name = name.split(RegExp(r'[-_]')).map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join(' ');
    }
    
    return name.isEmpty ? fileName : name;
  }

  static Future<String?> _findAppImageIcon(String appImagePath, String appName) async {
    // First check for .DirIcon or icon file next to the AppImage
    final appImageDir = Directory(appImagePath).parent.path;
    final baseName = appImagePath.split('/').last.replaceAll(RegExp(r'\.AppImage$', caseSensitive: false), '');
    
    final possibleLocalIcons = [
      '$appImageDir/$baseName.png',
      '$appImageDir/$baseName.svg',
      '$appImageDir/${appName.toLowerCase()}.png',
      '$appImageDir/${appName.toLowerCase().replaceAll(' ', '-')}.png',
    ];
    
    for (final iconPath in possibleLocalIcons) {
      if (await File(iconPath).exists()) {
        return iconPath;
      }
    }
    
    // Try to find icon by app name in system icon directories
    final iconSearchName = appName.toLowerCase().replaceAll(' ', '-');
    return await _findIcon(iconSearchName);
  }

  static Future<LinuxAppInfo?> _parseDesktopFile(File file) async {
    final content = await file.readAsString();
    final lines = content.split('\n');

    String? name;
    String? nameEn;
    String? exec;
    String? icon;
    bool noDisplay = false;
    bool hidden = false;
    String? type;

    bool inDesktopEntry = false;

    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine == '[Desktop Entry]') {
        inDesktopEntry = true;
        continue;
      }
      if (trimmedLine.startsWith('[') && trimmedLine != '[Desktop Entry]') {
        inDesktopEntry = false;
        continue;
      }
      
      if (!inDesktopEntry) continue;

      if (line.startsWith('Name=')) {
        nameEn ??= line.substring(5).trim();
      } else if (line.startsWith('Name[tr]=')) {
        name = line.substring(9).trim();
      } else if (line.startsWith('GenericName[tr]=') && name == null) {
        // Fallback to generic name in Turkish
        name ??= line.substring(16).trim();
      } else if (line.startsWith('Exec=')) {
        exec = line.substring(5).trim();
        // Remove field codes
        exec = exec.replaceAll(RegExp(r'%[fFuUdDnNickvm]'), '').trim();
      } else if (line.startsWith('Icon=')) {
        icon = line.substring(5).trim();
      } else if (line.startsWith('NoDisplay=')) {
        noDisplay = line.substring(10).trim().toLowerCase() == 'true';
      } else if (line.startsWith('Hidden=')) {
        hidden = line.substring(7).trim().toLowerCase() == 'true';
      } else if (line.startsWith('Type=')) {
        type = line.substring(5).trim();
      } else if (line.startsWith('Categories=')) {
      }
    }

    // Use English name if Turkish not available
    name ??= nameEn;

    if (name == null || exec == null || noDisplay || hidden || type != 'Application') {
      return null;
    }

    final iconPath = await _findIcon(icon);
    
    // Determine app type
    String appType = 'system';
    if (file.path.contains('flatpak')) {
      appType = 'flatpak';
    } else if (file.path.contains('snap')) {
      appType = 'snap';
    }

    return LinuxAppInfo(
      appName: name,
      desktopFile: file.path,
      exec: exec,
      iconPath: iconPath,
      appType: appType,
    );
  }

  static Future<String?> _findIcon(String? iconName) async {
    if (iconName == null) return null;

    // If it's already an absolute path
    if (iconName.startsWith('/')) {
      if (await File(iconName).exists()) return iconName;
      // Try common variations
      for (final ext in ['png', 'svg', 'xpm']) {
        final withExt = '$iconName.$ext';
        if (await File(withExt).exists()) return withExt;
      }
      return null;
    }

    // Search in icon directories - prioritize PNG over SVG for better rendering
    final List<String> preferredExtensions = ['png', 'svg', 'xpm', ''];
    
    for (final dir in _iconDirs) {
      for (final ext in preferredExtensions) {
        final path = ext.isEmpty ? '$dir/$iconName' : '$dir/$iconName.$ext';
        if (await File(path).exists()) return path;
      }
    }

    // Try variations of icon name
    final variations = [
      iconName,
      iconName.toLowerCase(),
      iconName.replaceAll(' ', '-').toLowerCase(),
      iconName.replaceAll(' ', '_').toLowerCase(),
    ];

    for (final variant in variations) {
      for (final dir in _iconDirs) {
        for (final ext in preferredExtensions) {
          final path = ext.isEmpty ? '$dir/$variant' : '$dir/$variant.$ext';
          if (await File(path).exists()) return path;
        }
      }
    }

    return null;
  }

  static Future<Uint8List?> getAppIcon(String? iconPath) async {
    if (iconPath == null) return null;

    try {
      final file = File(iconPath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error loading icon: $e');
    }
    return null;
  }

  static Future<bool> openApp(String exec) async {
    try {
      // Check if it's an AppImage (full path to .AppImage file)
      if (exec.contains('.AppImage') || exec.contains('.appimage') || 
          await File(exec).exists() && (await FileStat.stat(exec)).mode & 0x49 != 0) {
        await Process.start(exec, [], mode: ProcessStartMode.detached);
        return true;
      }

      // Parse and execute the command
      final parts = exec.split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) return false;
      
      final executable = parts.first;
      final args = parts.length > 1 ? parts.sublist(1) : <String>[];
      
      await Process.start(executable, args, mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      debugPrint('Error opening app: $e');
      return false;
    }
  }

  static Future<void> openAppInfo(String desktopFile) async {
    try {
      // For AppImages, show file properties
      if (desktopFile.contains('.AppImage') || desktopFile.contains('.appimage')) {
        // Use Dolphin (KDE file manager) or xdg-open
        try {
          await Process.start('dolphin', ['--select', desktopFile], mode: ProcessStartMode.detached);
          return;
        } catch (_) {
          // Fallback to thunar (XFCE) or nautilus (GNOME)
          try {
            await Process.start('thunar', [desktopFile], mode: ProcessStartMode.detached);
            return;
          } catch (_) {
            await Process.start('nautilus', ['--select', desktopFile], mode: ProcessStartMode.detached);
            return;
          }
        }
      }
      
      // For .desktop files, open with default handler
      await Process.start('xdg-open', [desktopFile], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('Error opening app info: $e');
    }
  }

  // Get list of available AppImage directories for user to browse
  static Future<List<String>> getAppImageDirectories() async {
    final List<String> available = [];
    for (final dir in _appImageDirs) {
      if (await Directory(dir).exists()) {
        available.add(dir);
      }
    }
    return available;
  }

  // Check if an app is an AppImage
  static bool isAppImage(LinuxAppInfo app) {
    return app.appType == 'appimage' || 
           app.exec.toLowerCase().contains('.appimage');
  }
}
