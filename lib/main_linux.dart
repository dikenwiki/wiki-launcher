import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'linux_app_service.dart';
import 'services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WikiLauncherApp());
}

class WikiLauncherApp extends StatelessWidget {
  const WikiLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wiki Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.grey,
        colorScheme: const ColorScheme.dark(
          primary: Colors.grey,
          secondary: Colors.grey,
          surface: Colors.black,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.grey,
          selectionColor: Colors.grey.withValues(alpha: 0.3),
          selectionHandleColor: Colors.grey,
        ),
      ),
      home: const LauncherHome(),
    );
  }
}

// Note: FavoritesService and SettingsService are imported from services.dart

// Linux-specific settings extensions
class LinuxSettingsService {
  static const String _fullscreenKey = 'fullscreen_mode';

  static Future<bool> getFullscreen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fullscreenKey) ?? false;
  }

  static Future<void> setFullscreen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fullscreenKey, value);
  }
}

class LauncherHome extends StatefulWidget {
  const LauncherHome({super.key});

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<LinuxAppInfo> _apps = [];
  List<LinuxAppInfo> _displayedApps = [];
  List<LinuxAppInfo> _favoriteApps = [];
  Set<String> _favorites = {};
  Set<String> _hiddenApps = {};
  Map<String, String> _renamedApps = {};
  bool _isLoading = true;
  String? _selectedLetter;
  String? _dragHoverLetter;
  bool _isDragging = false;
  bool _showSearch = false;
  bool _showIcons = true;
  String _searchQuery = '';
  String _userNote = '';
  bool _isEditingNote = false;
  bool _showingHiddenInList = false;
  bool _isFullscreen = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _noteFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final Map<String, Uint8List> _loadedIcons = {};
  List<String> _availableLetters = [];

  static const List<String> _alphabet = [
    '#', '★', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  ];

  static const Map<String, List<String>> _turkishCharMap = {
    'C': ['C', 'Ç'], 'G': ['G', 'Ğ'], 'I': ['I', 'İ', 'ı'],
    'O': ['O', 'Ö'], 'S': ['S', 'Ş'], 'U': ['U', 'Ü'],
  };

  bool _matchesLetter(String appName, String letter) {
    if (appName.isEmpty) return false;
    String firstChar = appName[0].toUpperCase();
    if (letter == '#') {
      bool isStandard = RegExp(r'[A-Z]').hasMatch(firstChar);
      bool isTurkish = ['Ç', 'Ğ', 'İ', 'Ö', 'Ş', 'Ü'].contains(firstChar);
      return !isStandard && !isTurkish;
    }
    if (firstChar == letter) return true;
    if (_turkishCharMap.containsKey(letter)) {
      return _turkishCharMap[letter]!.any((c) => firstChar == c || firstChar == c.toLowerCase());
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApps();
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Pencere odağa geldiğinde uygulama listesini yenile
      _loadApps();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    _noteController.dispose();
    _searchFocusNode.dispose();
    _noteFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final showIcons = await SettingsService.getShowIcons();
    final note = await SettingsService.getNote();
    final fullscreen = await LinuxSettingsService.getFullscreen();
    setState(() {
      _showIcons = showIcons;
      _userNote = note;
      _noteController.text = note;
      _isFullscreen = fullscreen;
    });
  }

  Future<void> _loadApps() async {
    try {
      List<LinuxAppInfo> apps = await LinuxAppService.getInstalledApps();
      Set<String> favorites = await FavoritesService.getFavorites();
      List<String> orderedFavorites = await FavoritesService.getFavoritesOrdered();
      Set<String> hiddenApps = await SettingsService.getHiddenApps();
      Map<String, String> renamedApps = await SettingsService.getRenamedApps();

      for (var app in apps) {
        app.isFavorite = favorites.contains(app.packageName);
        app.isHidden = hiddenApps.contains(app.packageName);
        if (renamedApps.containsKey(app.packageName)) {
          app.customName = renamedApps[app.packageName];
        }
      }

      List<LinuxAppInfo> visibleApps = apps.where((app) => !app.isHidden).toList();

      Map<String, List<LinuxAppInfo>> grouped = {};
      for (var app in visibleApps) {
        String firstChar = app.displayName.isNotEmpty ? app.displayName[0].toUpperCase() : '#';
        if (!RegExp(r'[A-Z]').hasMatch(firstChar)) firstChar = '#';
        grouped.putIfAbsent(firstChar, () => []);
        grouped[firstChar]!.add(app);
      }

      List<String> availableLetters = ['#'];
      if (favorites.isNotEmpty) {
        bool hasVisibleFavorite = visibleApps.any((a) => a.isFavorite);
        if (hasVisibleFavorite) availableLetters.add('★');
      }
      availableLetters.addAll(grouped.keys.where((k) => k != '#').toList()..sort());

      List<LinuxAppInfo> favoriteApps = [];
      for (String pkgName in orderedFavorites) {
        final app = visibleApps.where((a) => a.packageName == pkgName).firstOrNull;
        if (app != null && app.isFavorite) favoriteApps.add(app);
      }
      for (var app in visibleApps) {
        if (app.isFavorite && !favoriteApps.contains(app)) favoriteApps.add(app);
      }

      setState(() {
        _apps = apps;
        _favorites = favorites;
        _hiddenApps = hiddenApps;
        _renamedApps = renamedApps;
        _availableLetters = availableLetters;
        _favoriteApps = favoriteApps;
        if (_selectedLetter == null || _selectedLetter == '★') {
          _displayedApps = List<LinuxAppInfo>.from(favoriteApps);
        } else {
          _displayedApps = visibleApps.where((app) => _matchesLetter(app.displayName, _selectedLetter!)).toList();
          _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        }
        _isLoading = false;
      });

      if (_showIcons) _loadIconsForDisplayedApps();
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading apps: $e');
    }
  }

  Future<void> _loadIconsForDisplayedApps() async {
    for (var app in _displayedApps) {
      if (!_loadedIcons.containsKey(app.packageName)) {
        final icon = await LinuxAppService.getAppIcon(app.iconPath);
        if (icon != null && mounted) {
          setState(() => _loadedIcons[app.packageName] = icon);
        }
      }
    }
  }

  void _selectLetter(String letter) {
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
      _showingHiddenInList = false;
      if (letter == '★') {
        _selectedLetter = null;
        _displayedApps = List<LinuxAppInfo>.from(_favoriteApps);
      } else if (letter == '#') {
        _selectedLetter = '#';
        _displayedApps = _apps.where((a) => !a.isHidden).toList();
        _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      } else {
        _selectedLetter = letter;
        _displayedApps = _apps.where((app) => !app.isHidden && _matchesLetter(app.displayName, letter)).toList();
        _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      }
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
    if (_showIcons) _loadIconsForDisplayedApps();
  }

  void _selectLetterWhileDragging(String letter) {
    if (letter == '★') {
      _selectedLetter = null;
      _displayedApps = List<LinuxAppInfo>.from(_favoriteApps);
    } else if (letter == '#') {
      _selectedLetter = '#';
      _displayedApps = _apps.where((a) => !a.isHidden).toList();
      _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    } else {
      _selectedLetter = letter;
      _displayedApps = _apps.where((app) => !app.isHidden && _matchesLetter(app.displayName, letter)).toList();
      _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    }
    setState(() {});
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_showIcons) _loadIconsForDisplayedApps();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _displayedApps = List<LinuxAppInfo>.from(_favoriteApps);
      } else {
        _displayedApps = _apps.where((app) =>
            !app.isHidden && app.displayName.toLowerCase().contains(query.toLowerCase())).toList();
        _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      }
    });
    if (_showIcons && query.isNotEmpty) _loadIconsForDisplayedApps();
  }

  Future<void> _toggleIcons() async {
    final newValue = !_showIcons;
    await SettingsService.setShowIcons(newValue);
    setState(() => _showIcons = newValue);
    if (newValue) _loadIconsForDisplayedApps();
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
      _displayedApps = _favoriteApps;
    });
    _searchFocusNode.unfocus();
  }

  Future<void> _toggleFavorite(LinuxAppInfo app) async {
    if (app.isFavorite) {
      await FavoritesService.removeFavorite(app.packageName);
      _favorites.remove(app.packageName);
    } else {
      await FavoritesService.addFavorite(app.packageName);
      _favorites.add(app.packageName);
    }
    app.isFavorite = !app.isFavorite;
    _favoriteApps = _favoriteApps.where((a) => a.isFavorite).toList();
    if (app.isFavorite && !_favoriteApps.contains(app)) _favoriteApps.add(app);
    if (_favorites.isNotEmpty && !_availableLetters.contains('★')) {
      _availableLetters.insert(1, '★');
    } else if (_favorites.isEmpty && _availableLetters.contains('★')) {
      _availableLetters.remove('★');
    }
    setState(() {
      if (_selectedLetter == null) _displayedApps = _favoriteApps;
    });
  }

  void _onReorderFavorites(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final app = _favoriteApps.removeAt(oldIndex);
      _favoriteApps.insert(newIndex, app);
      _displayedApps = _favoriteApps;
    });
    final orderedPkgs = _favoriteApps.map((a) => a.packageName).toList();
    FavoritesService.saveFavoritesOrder(orderedPkgs);
  }

  void _launchApp(LinuxAppInfo app) async {
    await LinuxAppService.openApp(app.exec);
  }

  void _toggleHiddenAppsInList() {
    setState(() {
      if (_showingHiddenInList) {
        _showingHiddenInList = false;
        _selectedLetter = null;
        _displayedApps = List<LinuxAppInfo>.from(_favoriteApps);
      } else {
        _showingHiddenInList = true;
        _selectedLetter = '#';
        _displayedApps = _apps.where((app) => app.isHidden).toList();
        _displayedApps.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        if (_displayedApps.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gizli uygulama yok'), duration: Duration(seconds: 1)),
          );
          _showingHiddenInList = false;
          _selectedLetter = null;
          _displayedApps = List<LinuxAppInfo>.from(_favoriteApps);
        }
      }
    });
  }

  void _showAppOptions(LinuxAppInfo app) {
    final isAppImage = LinuxAppService.isAppImage(app);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(app.displayName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (app.appType != 'system') ...[
                  const SizedBox(width: 8),
                  _buildAppTypeBadge(app.appType, small: false),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _optionItem(Icons.edit_outlined, 'Adını Değiştir', () {
              Navigator.pop(context);
              _showRenameDialog(app);
            }),
            _optionItem(Icons.visibility_off_outlined, app.isHidden ? 'Göster' : 'Gizle', () {
              Navigator.pop(context);
              _toggleHideApp(app);
            }),
            _optionItem(Icons.info_outline, 'Uygulama Bilgisi', () {
              Navigator.pop(context);
              LinuxAppService.openAppInfo(app.desktopFile);
            }),
            if (isAppImage) ...[
              const Divider(color: Colors.white24, height: 24),
              _optionItem(Icons.folder_open, 'Dosya Konumunu Aç', () {
                Navigator.pop(context);
                _openAppImageLocation(app);
              }),
              _optionItem(Icons.terminal, 'Terminalde Çalıştır', () {
                Navigator.pop(context);
                _runInTerminal(app);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppTypeBadge(String appType, {bool small = true}) {
    Color bgColor;
    Color textColor;
    String label;
    IconData? icon;

    switch (appType) {
      case 'appimage':
        bgColor = Colors.purple.withValues(alpha: 0.3);
        textColor = Colors.purpleAccent;
        label = 'AppImage';
        icon = Icons.inventory_2_outlined;
        break;
      case 'flatpak':
        bgColor = Colors.blue.withValues(alpha: 0.3);
        textColor = Colors.lightBlueAccent;
        label = 'Flatpak';
        icon = Icons.layers_outlined;
        break;
      case 'snap':
        bgColor = Colors.orange.withValues(alpha: 0.3);
        textColor = Colors.orangeAccent;
        label = 'Snap';
        icon = Icons.camera_outlined;
        break;
      default:
        return const SizedBox.shrink();
    }

    if (small) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label.substring(0, 1),
          style: TextStyle(fontSize: 9, color: textColor, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _openAppImageLocation(LinuxAppInfo app) async {
    try {
      final dir = File(app.exec).parent.path;
      await Process.start('dolphin', [dir], mode: ProcessStartMode.detached);
    } catch (_) {
      try {
        await Process.start('xdg-open', [File(app.exec).parent.path], mode: ProcessStartMode.detached);
      } catch (e) {
        debugPrint('Error opening location: $e');
      }
    }
  }

  Future<void> _runInTerminal(LinuxAppInfo app) async {
    try {
      // Try Konsole first (KDE default)
      await Process.start('konsole', ['-e', app.exec], mode: ProcessStartMode.detached);
    } catch (_) {
      try {
        // Fallback to xterm
        await Process.start('xterm', ['-e', app.exec], mode: ProcessStartMode.detached);
      } catch (e) {
        debugPrint('Error running in terminal: $e');
      }
    }
  }

  Widget _optionItem(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white70}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color.withValues(alpha: 0.9))),
      onTap: onTap,
    );
  }

  void _showRenameDialog(LinuxAppInfo app) {
    final controller = TextEditingController(text: app.displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Uygulamayı Adlandır', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Yeni ad...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              _renameApp(app, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Tamam', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Future<void> _renameApp(LinuxAppInfo app, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) {
      _renamedApps.remove(app.packageName);
    } else {
      _renamedApps[app.packageName] = name;
    }
    await SettingsService.setRenamedApps(_renamedApps);
    _loadApps();
  }

  Future<void> _toggleHideApp(LinuxAppInfo app) async {
    if (app.isHidden) {
      _hiddenApps.remove(app.packageName);
    } else {
      _hiddenApps.add(app.packageName);
    }
    await SettingsService.setHiddenApps(_hiddenApps);
    _loadApps();
  }

  void _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    await LinuxSettingsService.setFullscreen(_isFullscreen);
    // Linux'ta wmctrl ile tam ekran toggle (Wayland uyumlu)
    try {
      if (_isFullscreen) {
        await Process.run('wmctrl', ['-r', ':ACTIVE:', '-b', 'add,fullscreen']);
      } else {
        await Process.run('wmctrl', ['-r', ':ACTIVE:', '-b', 'remove,fullscreen']);
      }
    } catch (e) {
      // wmctrl yoksa KDE için qdbus dene
      try {
        final windowId = await Process.run('xdotool', ['getactivewindow']);
        if (_isFullscreen) {
          await Process.run('qdbus', ['org.kde.KWin', '/KWin', 'fullScreen', windowId.stdout.toString().trim()]);
        }
      } catch (_) {}
    }
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    // Arama veya not düzenleme modundaysa klavye kısayollarını yoksay
    if (_showSearch || _isEditingNote) return KeyEventResult.ignored;

    final key = event.logicalKey;
    
    // F11 - Tam ekran toggle
    if (key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    // Escape - Favorilere dön
    if (key == LogicalKeyboardKey.escape) {
      _selectLetter('★');
      return KeyEventResult.handled;
    }

    // Space - Arama aç
    if (key == LogicalKeyboardKey.space) {
      setState(() => _showSearch = true);
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Harf tuşları - O harfi seç
    final keyLabel = event.character?.toUpperCase();
    if (keyLabel != null && RegExp(r'^[A-Z]$').hasMatch(keyLabel)) {
      if (_availableLetters.contains(keyLabel)) {
        _selectLetter(keyLabel);
      }
      return KeyEventResult.handled;
    }

    // # tuşu (3 ile shift veya doğrudan)
    if (key == LogicalKeyboardKey.digit3 && HardwareKeyboard.instance.isShiftPressed) {
      _selectLetter('#');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => _keyboardFocusNode.requestFocus(),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white54))
              : Row(
                  children: [
                    Expanded(child: _buildAppList()),
                    if (!_showSearch && !_isEditingNote)
                      Padding(padding: const EdgeInsets.only(right: 8), child: _buildAlphabetScroller()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAppList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Row(
            children: [
              if (_selectedLetter != null && _selectedLetter != '★')
                GestureDetector(
                  onTap: () => _selectLetter('★'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _selectedLetter == '#' ? 'Tüm Uygulamalar' : _selectedLetter!,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_showSearch)
                Expanded(
                  child: Row(
                    children: [
                      GestureDetector(onTap: _closeSearch, child: const Icon(Icons.arrow_back, color: Colors.white70, size: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          decoration: InputDecoration(
                            hintText: 'Uygulamalarda ara',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () { _searchController.clear(); _onSearchChanged(''); },
                          child: const Icon(Icons.close, color: Colors.white54, size: 20),
                        ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Text('Favoriler', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: Colors.white.withValues(alpha: 0.6))),
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white38),
                      onPressed: () { setState(() => _showSearch = true); _searchFocusNode.requestFocus(); },
                    ),
                    IconButton(
                      icon: Icon(_showIcons ? Icons.grid_view : Icons.list, color: Colors.white38, size: 20),
                      onPressed: _toggleIcons,
                    ),
                  ],
                ),
              if (!_showSearch) ...[
                const Spacer(),
                Text('${_displayedApps.length}', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.4))),
              ],
            ],
          ),
        ),
        if (_selectedLetter == null && !_showSearch) _buildNoteSection(),
        Expanded(
          child: _displayedApps.isEmpty && !_showSearch
              ? _buildEmptyState()
              : _selectedLetter == null && !_showSearch
                  ? ReorderableListView.builder(
                      scrollController: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: _displayedApps.length,
                      onReorder: _onReorderFavorites,
                      itemBuilder: (context, index) {
                        final app = _displayedApps[index];
                        return _buildAppItem(app, key: ValueKey(app.packageName));
                      },
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 4.5,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: _displayedApps.length,
                      itemBuilder: (context, index) => _buildAppItem(_displayedApps[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildNoteSection() {
    return GestureDetector(
      onTap: () { setState(() => _isEditingNote = true); _noteFocusNode.requestFocus(); },
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 40, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _isEditingNote ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
        ),
        child: _isEditingNote
            ? TextField(
                controller: _noteController,
                focusNode: _noteFocusNode,
                maxLines: null,
                minLines: 1,
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
                decoration: InputDecoration(
                  hintText: 'Not ekle...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  border: InputBorder.none,
                  isDense: true,
                ),
                contextMenuBuilder: (context, editableTextState) {
                  return _buildNoteContextMenu(context, editableTextState);
                },
                onChanged: (value) { _userNote = value; SettingsService.setNote(value); },
                onEditingComplete: () { setState(() => _isEditingNote = false); _noteFocusNode.unfocus(); },
                onTapOutside: (_) { setState(() => _isEditingNote = false); _noteFocusNode.unfocus(); },
              )
            : _userNote.isEmpty
                ? Text('Not eklemek için dokun...', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.3), fontStyle: FontStyle.italic))
                : _buildFormattedNote(),
      ),
    );
  }

  Widget _buildNoteContextMenu(BuildContext context, EditableTextState editableTextState) {
    final selection = editableTextState.textEditingValue.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;

    return AdaptiveTextSelectionToolbar(
      anchors: editableTextState.contextMenuAnchors,
      children: [
        // Sadece Kalın (Bold)
        if (hasSelection)
          _contextMenuButton('Kalın', Icons.format_bold, () {
            _applyFormat('**', '**');
            editableTextState.hideToolbar();
          }),
      ],
    );
  }

  Widget _contextMenuButton(String label, IconData icon, VoidCallback onPressed) {
    return TextSelectionToolbarTextButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _applyFormat(String prefix, String suffix) {
    final selection = _noteController.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final text = _noteController.text;
    final selectedText = text.substring(selection.start, selection.end);
    final newText = text.replaceRange(selection.start, selection.end, '$prefix$selectedText$suffix');

    setState(() {
      _noteController.text = newText;
      _userNote = newText;
    });
    SettingsService.setNote(newText);

    final newPosition = selection.start + prefix.length + selectedText.length + suffix.length;
    _noteController.selection = TextSelection.collapsed(offset: newPosition);
  }

  Widget _buildFormattedNote() {
    return Text.rich(
      _parseFormattedText(_userNote),
      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
    );
  }

  TextSpan _parseFormattedText(String text) {
    return TextSpan(children: _recursiveParse(text, const TextStyle()));
  }

  List<InlineSpan> _recursiveParse(String text, TextStyle baseStyle) {
    if (text.isEmpty) return [];

    final List<InlineSpan> segments = [];
    final RegExp boldRegex = RegExp(r'(\*\*.*?\*\*)');

    int lastEnd = 0;
    for (final match in boldRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        segments.add(TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
      }

      final fullMatch = match.group(0)!;
      TextStyle newStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
      String innerText = fullMatch.substring(2, fullMatch.length - 2);

      segments.addAll(_recursiveParse(innerText, newStyle));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      segments.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }

    return segments;
  }


  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_border, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('Henüz favori yok', style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(height: 8),
          Text('# ile tüm uygulamalara git\nve favorilere ekle', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.25))),
        ],
      ),
    );
  }

  Widget _buildAppItem(LinuxAppInfo app, {Key? key}) {
    final hasIcon = _showIcons && _loadedIcons.containsKey(app.packageName);
    return Dismissible(
      key: key ?? Key(app.packageName),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          await _toggleFavorite(app);
          return false;
        } else if (direction == DismissDirection.startToEnd) {
          _showAppOptions(app);
          return false;
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [Icon(Icons.more_horiz, color: Colors.blue, size: 24), SizedBox(width: 8), Text('Ayarlar', style: TextStyle(color: Colors.blue))]),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: (app.isFavorite ? Colors.red : Colors.amber).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text(app.isFavorite ? 'Çıkar' : 'Favori', style: TextStyle(color: app.isFavorite ? Colors.red : Colors.amber)),
          const SizedBox(width: 8),
          Icon(app.isFavorite ? Icons.star_border : Icons.star, color: app.isFavorite ? Colors.red : Colors.amber, size: 24),
        ]),
      ),
      child: InkWell(
        onTap: () => _launchApp(app),
        onLongPress: () => _showAppOptions(app),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              if (hasIcon)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: (app.iconPath?.toLowerCase().endsWith('.svg') ?? false)
                        ? SvgPicture.memory(
                            _loadedIcons[app.packageName]!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            placeholderBuilder: (BuildContext context) => const SizedBox(width: 32, height: 32),
                          )
                        : Image.memory(
                            _loadedIcons[app.packageName]!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const SizedBox(width: 32, height: 32),
                          ),
                  ),
                )
              else if (_showIcons)
                Container(
                  width: 32, height: 32,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.apps, color: Colors.white38, size: 20),
                ),
              if (app.isFavorite && _selectedLetter == '#' && !_showIcons)
                Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.star, size: 16, color: Colors.amber.withValues(alpha: 0.8))),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(app.displayName,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: Colors.white.withValues(alpha: 0.9), letterSpacing: 0.3),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (app.appType != 'system') ...[
                      const SizedBox(width: 8),
                      _buildAppTypeBadge(app.appType),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlphabetScroller() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // Ekran yüksekliğine göre dinamik boyutlandırma
        final isCompact = availableHeight < 600;
        final verticalPadding = isCompact ? 8.0 : 24.0;
        final fontSize = isCompact ? 10.0 : 12.0;
        final hoverFontSize = isCompact ? 14.0 : 16.0;
        
        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragUpdate: (details) {
            final itemHeight = (availableHeight - verticalPadding * 2) / _alphabet.length;
            int index = ((details.localPosition.dy - verticalPadding) / itemHeight).floor().clamp(0, _alphabet.length - 1);
            String letter = _alphabet[index];
            if (_dragHoverLetter != letter) {
              _selectLetterWhileDragging(letter);
              setState(() => _dragHoverLetter = letter);
            }
          },
          onVerticalDragEnd: (_) {
            if (_dragHoverLetter != null) _selectLetter(_dragHoverLetter!);
            setState(() { _isDragging = false; _dragHoverLetter = null; });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _isDragging ? 44 : 32,
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            decoration: BoxDecoration(color: _isDragging ? Colors.white.withValues(alpha: 0.08) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _alphabet.map((letter) {
                final isAvailable = letter == '#' || _availableLetters.contains(letter);
                final isSelected = _selectedLetter == letter || (letter == '★' && _selectedLetter == null);
                final isHovered = _dragHoverLetter == letter;
                return Expanded(
                  child: GestureDetector(
                    onTap: isAvailable ? () => _selectLetter(letter) : null,
                    onLongPress: letter == '#' ? _toggleHiddenAppsInList : null,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        padding: EdgeInsets.symmetric(horizontal: isHovered ? 6 : 2, vertical: isCompact ? 1 : 2),
                        decoration: BoxDecoration(
                          color: isHovered ? Colors.white.withValues(alpha: 0.3) : isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          letter,
                          style: TextStyle(
                            fontSize: isHovered ? hoverFontSize : fontSize,
                            fontWeight: isSelected || isHovered ? FontWeight.bold : FontWeight.w500,
                            color: isAvailable ? Colors.white : Colors.white38,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
