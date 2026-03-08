import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages favorite apps list and ordering.
class FavoritesService {
  static const String _key = 'favorite_apps';
  static const String _orderKey = 'favorite_apps_order';

  static Future<Set<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? favorites = prefs.getStringList(_key);
    return favorites?.toSet() ?? {};
  }

  static Future<List<String>> getFavoritesOrdered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_orderKey) ?? [];
  }

  static Future<void> saveFavoritesOrder(List<String> orderedFavorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, orderedFavorites);
    await prefs.setStringList(_key, orderedFavorites);
  }

  static Future<void> addFavorite(String packageName) async {
    final favorites = await getFavorites();
    final ordered = await getFavoritesOrdered();
    favorites.add(packageName);
    if (!ordered.contains(packageName)) ordered.add(packageName);
    await saveFavoritesOrder(ordered);
  }

  static Future<void> removeFavorite(String packageName) async {
    final ordered = await getFavoritesOrdered();
    ordered.remove(packageName);
    await saveFavoritesOrder(ordered);
  }
}

/// Manages launcher settings (icons, notes, hidden apps, renames).
class SettingsService {
  static const String _showIconsKey = 'show_icons';
  static const String _noteKey = 'user_note';
  static const String _noteStylesKey = 'note_styles';
  static const String _hiddenAppsKey = 'hidden_apps';
  static const String _renamedAppsKey = 'renamed_apps';

  static Future<bool> getShowIcons() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showIconsKey) ?? true;
  }

  static Future<void> setShowIcons(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showIconsKey, value);
  }

  static Future<String> getNote() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_noteKey) ?? '';
  }

  static Future<void> setNote(String note) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteKey, note);
  }

  static Future<String> getNoteStyles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_noteStylesKey) ?? '';
  }

  static Future<void> setNoteStyles(String styles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteStylesKey, styles);
  }

  static Future<Set<String>> getHiddenApps() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? hidden = prefs.getStringList(_hiddenAppsKey);
    return hidden?.toSet() ?? {};
  }

  static Future<void> setHiddenApps(Set<String> hiddenApps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenAppsKey, hiddenApps.toList());
  }

  static Future<Map<String, String>> getRenamedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final String? renamedJson = prefs.getString(_renamedAppsKey);
    if (renamedJson == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(renamedJson);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  static Future<void> setRenamedApps(Map<String, String> renamedApps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_renamedAppsKey, jsonEncode(renamedApps));
  }
}
