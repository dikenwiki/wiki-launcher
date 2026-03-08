import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight localization system for Wiki Launcher.
/// Supports Turkish (tr) and English (en).
class AppLocalizations {
  static const String _languageKey = 'app_language';
  static String _currentLanguage = 'en';

  static String get currentLanguage => _currentLanguage;

  static Future<void> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString(_languageKey) ?? 'en';
  }

  static Future<void> setLanguage(String languageCode) async {
    _currentLanguage = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }

  /// Get a translated string by key.
  static String get(String key) {
    final map = _currentLanguage == 'tr' ? _tr : _en;
    return map[key] ?? _en[key] ?? key;
  }

  static const Map<String, String> _tr = {
    // Main UI
    'favorites': 'Favoriler',
    'allApps': 'Tüm Uygulamalar',
    'searchApps': 'Uygulamalarda ara',
    'noFavorites': 'Henüz favori yok',
    'noFavoritesHint': '# ile tüm uygulamalara git\nve favorilere ekle',
    'noHiddenApps': 'Gizli uygulama yok',

    // App options
    'addToFavorites': 'Favorilere Ekle',
    'removeFromFavorites': 'Favorilerden Çıkar',
    'reorder': 'Yerini Değiştir',
    'rename': 'Adını Değiştir',
    'hide': 'Gizle',
    'show': 'Göster',
    'appInfo': 'Uygulama Bilgisi',
    'uninstall': 'Kaldır',

    // Dialogs
    'cancel': 'İptal',
    'ok': 'Tamam',
    'newName': 'Yeni ad...',
    'renameApp': 'Uygulamayı Adlandır',
    'changeOrder': 'Sırasını Değiştir',
    'newOrder': 'Yeni sıra',

    // Notes
    'hideNotes': 'Notları Gizle',
    'showNotes': 'Notları Göster',
    'addNote': 'Not eklemek için dokun...',
    'writeNote': 'Not yazın...',
    'bold': 'Kalın',

    // Settings
    'settings': 'Ayarlar',
    'language': 'Dil',
    'turkish': 'Türkçe',
    'english': 'English',
    'showIcons': 'İkonları Göster',
    'hiddenApps': 'Gizli Uygulamalar',
    'version': 'Sürüm',
  };

  static const Map<String, String> _en = {
    // Main UI
    'favorites': 'Favorites',
    'allApps': 'All Apps',
    'searchApps': 'Search apps',
    'noFavorites': 'No favorites yet',
    'noFavoritesHint': 'Go to all apps with #\nand add to favorites',
    'noHiddenApps': 'No hidden apps',

    // App options
    'addToFavorites': 'Add to Favorites',
    'removeFromFavorites': 'Remove from Favorites',
    'reorder': 'Reorder',
    'rename': 'Rename',
    'hide': 'Hide',
    'show': 'Show',
    'appInfo': 'App Info',
    'uninstall': 'Uninstall',

    // Dialogs
    'cancel': 'Cancel',
    'ok': 'OK',
    'newName': 'New name...',
    'renameApp': 'Rename App',
    'changeOrder': 'Change Order',
    'newOrder': 'New position',

    // Notes
    'hideNotes': 'Hide Notes',
    'showNotes': 'Show Notes',
    'addNote': 'Tap to add a note...',
    'writeNote': 'Write a note...',
    'bold': 'Bold',

    // Settings
    'settings': 'Settings',
    'language': 'Language',
    'turkish': 'Türkçe',
    'english': 'English',
    'showIcons': 'Show Icons',
    'hiddenApps': 'Hidden Apps',
    'version': 'Version',
  };
}
