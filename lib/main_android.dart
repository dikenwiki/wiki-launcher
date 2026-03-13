import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'app_localizations.dart';
import 'services.dart';
import 'android_app_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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

// WYSIWYG note controller with bold text support
class RichNoteController extends TextEditingController {
  final List<Map<String, dynamic>> Function() getStyles;

  RichNoteController({required this.getStyles});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<Map<String, dynamic>> styles = getStyles();
    if (styles.isEmpty || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    List<TextSpan> children = [];
    final String currentText = text;

    for (int i = 0; i < currentText.length; i++) {
      bool isBold = false;
      for (var s in styles) {
        if (i >= (s['start'] ?? 0) && i < (s['end'] ?? 0)) {
          if (s['bold'] == true) isBold = true;
        }
      }
      children.add(TextSpan(
        text: currentText[i],
        style: style?.copyWith(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ));
    }

    return TextSpan(style: style, children: children);
  }
}

class LauncherHome extends StatefulWidget {
  const LauncherHome({super.key});

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome>
    with WidgetsBindingObserver {
  List<AndroidAppInfo> _apps = [];
  List<AndroidAppInfo> _displayedApps = [];
  List<AndroidAppInfo> _favoriteApps = [];
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
  List<Map<String, dynamic>> _noteStyles = [];
  bool _isEditingNote = false;
  bool _showNotes = true;
  bool _showingHiddenInList = false;

  final ScrollController _scrollController = ScrollController();
  double _totalOverscroll = 0;
  final TextEditingController _searchController = TextEditingController();
  late final RichNoteController _noteController =
      RichNoteController(getStyles: () => _noteStyles);
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _noteFocusNode = FocusNode();
  final Map<String, Uint8List> _loadedIcons = {};
  List<String> _availableLetters = [];

  static const String _appName = 'Wiki Launcher';
  static const String _appVersion = '0.3.1';
  static const String _repoUrl = 'https://github.com/dikenwiki/wiki-launcher';

  static const List<String> _alphabet = [
    '#', '★', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  static const Map<String, List<String>> _turkishCharMap = {
    'C': ['C', 'Ç'],
    'G': ['G', 'Ğ'],
    'I': ['I', 'İ', 'ı'],
    'O': ['O', 'Ö'],
    'S': ['S', 'Ş'],
    'U': ['U', 'Ü'],
  };

  /// Returns true if the first letter of [appName] matches the given [letter].
  bool _matchesLetter(String appName, String letter) {
    if (appName.isEmpty) return false;
    final firstChar = appName[0].toUpperCase();
    if (letter == '#') {
      final isStandard = RegExp(r'[A-Z]').hasMatch(firstChar);
      final isTurkish = ['Ç', 'Ğ', 'İ', 'Ö', 'Ş', 'Ü'].contains(firstChar);
      return !isStandard && !isTurkish;
    }
    if (firstChar == letter) return true;
    if (_turkishCharMap.containsKey(letter)) {
      return _turkishCharMap[letter]!
          .any((c) => firstChar == c || firstChar == c.toLowerCase());
    }
    return false;
  }

  // ─── Lifecycle ───

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _setupMethodChannel();
  }

  Future<void> _initialize() async {
    await AppLocalizations.loadLanguage();
    await _loadSettings();
    await _loadApps();
  }

  void _setupMethodChannel() {
    const channel = MethodChannel('wiki.wiki.launcher/apps');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAppListChanged') {
        _loadApps();
      } else if (call.method == 'onHomePressed') {
        _goToFavorites();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _goToFavorites();
      _loadApps();
    }
  }

  void _goToFavorites() {
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
      _selectedLetter = null;
      _showingHiddenInList = false;
      _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
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
    super.dispose();
  }

  // ─── Data Loading ───

  Future<void> _loadSettings() async {
    final showIcons = await SettingsService.getShowIcons();
    final note = await SettingsService.getNote();
    final stylesStr = await SettingsService.getNoteStyles();

    // Parse note styles
    List<Map<String, dynamic>> loadedStyles = [];
    if (stylesStr.isNotEmpty) {
      for (var s in stylesStr.split(';')) {
        final parts = s.split(',');
        if (parts.length >= 3) {
          loadedStyles.add({
            'start': int.tryParse(parts[0]) ?? 0,
            'end': int.tryParse(parts[1]) ?? 0,
            'bold': parts[2] == 'true',
          });
        }
      }
    }

    setState(() {
      _showIcons = showIcons;
      _userNote = note;
      _noteController.text = note;
      _noteStyles = loadedStyles;
    });
  }

  Future<void> _loadApps() async {
    try {
      final apps = await AndroidAppService.getInstalledApps();
      final favorites = await FavoritesService.getFavorites();
      final orderedFavorites = await FavoritesService.getFavoritesOrdered();
      final hiddenApps = await SettingsService.getHiddenApps();
      final renamedApps = await SettingsService.getRenamedApps();

      for (var app in apps) {
        app.isFavorite = favorites.contains(app.packageName);
        app.isHidden = hiddenApps.contains(app.packageName);
        if (renamedApps.containsKey(app.packageName)) {
          app.customName = renamedApps[app.packageName];
        }
      }

      final visibleApps = apps.where((app) => !app.isHidden).toList();

      // Group apps by first letter
      final Map<String, List<AndroidAppInfo>> grouped = {};
      for (var app in visibleApps) {
        String firstChar = app.displayName.isNotEmpty
            ? app.displayName[0].toUpperCase()
            : '#';
        if (!RegExp(r'[A-Z]').hasMatch(firstChar)) firstChar = '#';
        grouped.putIfAbsent(firstChar, () => []);
        grouped[firstChar]!.add(app);
      }

      // Build available letters for the alphabet scroller
      final List<String> availableLetters = ['#'];
      if (favorites.isNotEmpty) {
        final hasVisibleFavorite = visibleApps.any((a) => a.isFavorite);
        if (hasVisibleFavorite) availableLetters.add('★');
      }
      availableLetters
          .addAll(grouped.keys.where((k) => k != '#').toList()..sort());

      // Build ordered favorites list
      final List<AndroidAppInfo> favoriteApps = [];
      for (final pkgName in orderedFavorites) {
        final app =
            visibleApps.where((a) => a.packageName == pkgName).firstOrNull;
        if (app != null && app.isFavorite) favoriteApps.add(app);
      }
      for (var app in visibleApps) {
        if (app.isFavorite && !favoriteApps.contains(app)) {
          favoriteApps.add(app);
        }
      }

      setState(() {
        _apps = apps;
        _favorites = favorites;
        _hiddenApps = hiddenApps;
        _renamedApps = renamedApps;
        _availableLetters = availableLetters;
        _favoriteApps = favoriteApps;
        if (_selectedLetter == null || _selectedLetter == '★') {
          _displayedApps = List<AndroidAppInfo>.from(favoriteApps);
        } else {
          _displayedApps = visibleApps
              .where(
                  (app) => _matchesLetter(app.displayName, _selectedLetter!))
              .toList();
          _displayedApps.sort((a, b) =>
              a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
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
        final icon = await AndroidAppService.getAppIcon(app.packageName);
        if (icon != null && mounted) {
          setState(() => _loadedIcons[app.packageName] = icon);
        }
      }
    }
  }

  // ─── Letter Navigation ───

  void _selectLetter(String letter) {
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
      _showingHiddenInList = false;
      if (letter == '★') {
        _selectedLetter = null;
        _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
      } else if (letter == '#') {
        _selectedLetter = '#';
        _displayedApps = _apps.where((a) => !a.isHidden).toList();
        _displayedApps.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      } else {
        _selectedLetter = letter;
        _displayedApps = _apps
            .where((app) =>
                !app.isHidden && _matchesLetter(app.displayName, letter))
            .toList();
        _displayedApps.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      }
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
    if (_showIcons) _loadIconsForDisplayedApps();
  }

  void _selectLetterWhileDragging(String letter) {
    setState(() {
      if (letter == '★') {
        _selectedLetter = null;
        _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
      } else {
        _selectedLetter = letter;
        _displayedApps = _apps
            .where((app) =>
                !app.isHidden && _matchesLetter(app.displayName, letter))
            .toList();
        _displayedApps.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      }
    });
    if (_showIcons) _loadIconsForDisplayedApps();
  }

  // ─── Search ───

  void _onSearchChanged(String query) {
    // Settings command: typing "/set" opens settings
    if (query.toLowerCase().trim() == '/set') {
      _searchController.clear();
      _searchFocusNode.unfocus();
      setState(() {
        _showSearch = false;
        _searchQuery = '';
      });
      _showSettingsDialog();
      return;
    }

    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
      } else {
        _displayedApps = _apps
            .where((app) =>
                !app.isHidden &&
                app.displayName.toLowerCase().contains(query.toLowerCase()))
            .toList();
        _displayedApps.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      }
    });
    if (_showIcons && query.isNotEmpty) _loadIconsForDisplayedApps();
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

  void _openSearch() {
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  // ─── Settings Dialog ───

  void _showSettingsDialog() {
    final t = AppLocalizations.get;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  t('settings'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Language selection
              ListTile(
                leading:
                    const Icon(Icons.language, color: Colors.white70),
                title: Text(t('language'),
                    style: const TextStyle(color: Colors.white)),
                trailing: DropdownButton<String>(
                  value: AppLocalizations.currentLanguage,
                  dropdownColor: const Color(0xFF1E1E1E),
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(
                      value: 'tr',
                      child: Text(t('turkish'),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    DropdownMenuItem(
                      value: 'en',
                      child: Text(t('english'),
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value != null) {
                      await AppLocalizations.setLanguage(value);
                      setSheetState(() {});
                      setState(() {}); // Refresh main UI
                    }
                  },
                ),
              ),

              // Show icons toggle
              SwitchListTile(
                secondary:
                    const Icon(Icons.apps, color: Colors.white70),
                title: Text(t('showIcons'),
                    style: const TextStyle(color: Colors.white)),
                value: _showIcons,
                activeThumbColor: Colors.white,
                onChanged: (value) async {
                  await SettingsService.setShowIcons(value);
                  setSheetState(() => _showIcons = value);
                  setState(() => _showIcons = value);
                  if (value) _loadIconsForDisplayedApps();
                },
              ),

              // Hidden apps
              ListTile(
                leading: const Icon(Icons.visibility_off,
                    color: Colors.white70),
                title: Text(t('hiddenApps'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _toggleHiddenAppsInList();
                },
              ),

              // About
              ListTile(
                leading: const Icon(Icons.info_outline,
                    color: Colors.white70),
                title: Text(t('about'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showAboutDialog();
                },
              ),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${t('version')}: $_appVersion',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── About Dialog ───

  void _showAboutDialog() {
    final t = AppLocalizations.get;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t('about'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _appName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${t('version')}: $_appVersion',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              '${t('license')}: ${t('openSource')}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              '${t('sourceCode')}:',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(const ClipboardData(text: _repoUrl));
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(t('sourceCode')),
                    backgroundColor: const Color(0xFF1E1E1E),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                _repoUrl.replaceFirst('https://', ''),
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.blue,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('ok'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Favorites ───

  Future<void> _toggleFavorite(AndroidAppInfo app) async {
    if (app.isFavorite) {
      await FavoritesService.removeFavorite(app.packageName);
      _favorites.remove(app.packageName);
    } else {
      await FavoritesService.addFavorite(app.packageName);
      _favorites.add(app.packageName);
    }
    app.isFavorite = !app.isFavorite;
    _favoriteApps = _favoriteApps.where((a) => a.isFavorite).toList();
    if (app.isFavorite && !_favoriteApps.contains(app)) {
      _favoriteApps.add(app);
    }
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
    if (oldIndex < 0 || oldIndex >= _favoriteApps.length) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      newIndex = newIndex.clamp(0, _favoriteApps.length - 1);
      final app = _favoriteApps.removeAt(oldIndex);
      _favoriteApps.insert(newIndex, app);
      _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
    });
    final orderedPkgs = _favoriteApps.map((a) => a.packageName).toList();
    FavoritesService.saveFavoritesOrder(orderedPkgs);
  }

  void _launchApp(AndroidAppInfo app) async {
    await AndroidAppService.openApp(app.packageName);
  }

  void _toggleHiddenAppsInList() {
    final t = AppLocalizations.get;
    setState(() {
      if (_showingHiddenInList) {
        _showingHiddenInList = false;
        _selectedLetter = null;
        _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
      } else {
        _showingHiddenInList = true;
        _selectedLetter = '#';
        _displayedApps = _apps.where((app) => app.isHidden).toList();
        _displayedApps.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        if (_displayedApps.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t('noHiddenApps')),
              duration: const Duration(seconds: 1),
            ),
          );
          _showingHiddenInList = false;
          _selectedLetter = null;
          _displayedApps = List<AndroidAppInfo>.from(_favoriteApps);
        }
      }
    });
  }

  // ─── App Options ───

  void _showAppOptions(AndroidAppInfo app) {
    final t = AppLocalizations.get;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _optionItem(
              app.isFavorite ? Icons.star : Icons.star_border,
              app.isFavorite ? t('removeFromFavorites') : t('addToFavorites'),
              () {
                Navigator.pop(context);
                _toggleFavorite(app);
              },
              color: app.isFavorite ? Colors.amber : Colors.white70,
            ),
            if (app.isFavorite && _selectedLetter == null && !_showSearch)
              _optionItem(Icons.reorder, t('reorder'), () {
                Navigator.pop(context);
                _showReorderDialog(app);
              }),
            _optionItem(Icons.edit_outlined, t('rename'), () {
              Navigator.pop(context);
              _showRenameDialog(app);
            }),
            _optionItem(
              Icons.visibility_off_outlined,
              app.isHidden ? t('show') : t('hide'),
              () {
                Navigator.pop(context);
                _toggleHideApp(app);
              },
            ),
            _optionItem(Icons.info_outline, t('appInfo'), () {
              Navigator.pop(context);
              AndroidAppService.openAppInfo(app.packageName);
            }),
            _optionItem(Icons.delete_outline, t('uninstall'), () {
              Navigator.pop(context);
              AndroidAppService.uninstallApp(app.packageName);
            }, color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _optionItem(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white70}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(color: color.withValues(alpha: 0.9))),
      onTap: onTap,
    );
  }

  void _showReorderDialog(AndroidAppInfo app) {
    final t = AppLocalizations.get;
    final currentIndex = _favoriteApps.indexOf(app);
    final controller =
        TextEditingController(text: (currentIndex + 1).toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          '${app.displayName} - ${t('changeOrder')}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t('newOrder')} (1 - ${_favoriteApps.length}):',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final newPos = int.tryParse(controller.text);
              if (newPos != null &&
                  newPos > 0 &&
                  newPos <= _favoriteApps.length) {
                _onReorderFavorites(currentIndex, newPos - 1);
              }
              Navigator.pop(context);
            },
            child:
                Text(t('ok'), style: const TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(AndroidAppInfo app) {
    final t = AppLocalizations.get;
    final controller = TextEditingController(text: app.displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(t('renameApp'),
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: t('newName'),
            hintStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              _renameApp(app, controller.text);
              Navigator.pop(context);
            },
            child:
                Text(t('ok'), style: const TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Future<void> _renameApp(AndroidAppInfo app, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) {
      _renamedApps.remove(app.packageName);
    } else {
      _renamedApps[app.packageName] = name;
    }
    await SettingsService.setRenamedApps(_renamedApps);
    _loadApps();
  }

  Future<void> _toggleHideApp(AndroidAppInfo app) async {
    if (app.isHidden) {
      _hiddenApps.remove(app.packageName);
    } else {
      _hiddenApps.add(app.packageName);
    }
    await SettingsService.setHiddenApps(_hiddenApps);
    _loadApps();
  }

  // Back button: search → favorites → open search
  Future<bool> _onWillPop() async {
    if (_showSearch) {
      _closeSearch();
      return false;
    }
    if (_selectedLetter != null) {
      _selectLetter('★');
      return false;
    }
    _openSearch();
    return false;
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Stack(
            children: [
              _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Colors.white54))
                  : Row(
                      children: [
                        Expanded(child: _buildAppList()),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _buildAlphabetScroller(),
                        ),
                      ],
                    ),
              _buildPullDownIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppList() {
    final t = AppLocalizations.get;
    final isFavoritesView = _selectedLetter == null && !_showSearch;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isWideScreen = screenWidth > 500 || (screenWidth > screenHeight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Row(
            children: [
              if (_selectedLetter != null && _selectedLetter != '★')
                GestureDetector(
                  onTap: () => _selectLetter('★'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _selectedLetter == '#'
                              ? t('allApps')
                              : _selectedLetter!,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_showSearch)
                Expanded(
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _closeSearch,
                        child: const Icon(Icons.arrow_back,
                            color: Colors.white70, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                          decoration: InputDecoration(
                            hintText: t('searchApps'),
                            hintStyle: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.4)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          child: const Icon(Icons.close,
                              color: Colors.white54, size: 20),
                        ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Text(
                      t('favorites'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.search, color: Colors.white38),
                      onPressed: _openSearch,
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Note section (only on favorites view)
        if (isFavoritesView) _buildNoteSection(),

        // App list
        Expanded(
          child: _displayedApps.isEmpty && !_showSearch
              ? _buildEmptyState()
              : isFavoritesView
                  ? _buildFavoritesListWithPullDown(isWideScreen)
                  : isWideScreen
                      ? GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          physics: const ClampingScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 5,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: _displayedApps.length,
                          itemBuilder: (context, index) =>
                              _buildAppItem(_displayedApps[index]),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          physics: const ClampingScrollPhysics(),
                          itemCount: _displayedApps.length,
                          itemBuilder: (context, index) =>
                              _buildAppItem(_displayedApps[index]),
                        ),
        ),
      ],
    );
  }

  // Pull down on favorites to expand status bar
  Widget _buildFavoritesListWithPullDown(bool isWideScreen) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification ||
            notification is ScrollEndNotification) {
          setState(() => _totalOverscroll = 0);
        }
        if (notification is OverscrollNotification &&
            notification.overscroll < 0) {
          setState(() {
            _totalOverscroll += notification.overscroll.abs();
            if (_totalOverscroll > 150) {
              AndroidAppService.expandStatusBar();
              _totalOverscroll = 0;
            }
          });
          return true;
        }
        return false;
      },
      child: isWideScreen
          ? GridView.builder(
              controller: _scrollController,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              physics: const ClampingScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 5,
                crossAxisSpacing: 16,
              ),
              itemCount: _displayedApps.length,
              itemBuilder: (context, index) => _buildAppItem(
                _displayedApps[index],
                key: ValueKey(_displayedApps[index].packageName),
              ),
            )
          : ReorderableListView.builder(
              scrollController: _scrollController,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              physics: const ClampingScrollPhysics(),
              itemCount: _displayedApps.length,
              onReorder: _onReorderFavorites,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final app = _displayedApps[index];
                return _buildAppItem(
                  app,
                  key: ValueKey(app.packageName),
                  index: index,
                );
              },
            ),
    );
  }

  // ─── Notes ───

  Widget _buildNoteSection() {
    final t = AppLocalizations.get;
    final screenHeight = MediaQuery.of(context).size.height;
    final noteMaxHeight = screenHeight * 0.15;
    final fontSize = screenHeight > 700 ? 14.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show/Hide toggle
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 4),
          child: GestureDetector(
            onTap: () => setState(() => _showNotes = !_showNotes),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showNotes ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white24,
                  size: 18,
                ),
                Text(
                  _showNotes ? t('hideNotes') : t('showNotes'),
                  style: const TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ],
            ),
          ),
        ),

        // Note area
        if (_showNotes)
          GestureDetector(
            onTap: () {
              if (!_isEditingNote) {
                setState(() => _isEditingNote = true);
                _noteController.text = _userNote;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _noteFocusNode.requestFocus();
                });
              }
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 40, 8),
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(maxHeight: noteMaxHeight),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isEditingNote
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: _isEditingNote
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _noteController,
                            focusNode: _noteFocusNode,
                            maxLines: null,
                            minLines: 1,
                            style: TextStyle(
                              fontSize: fontSize,
                              color:
                                  Colors.white.withValues(alpha: 0.9),
                            ),
                            decoration: InputDecoration(
                              hintText: t('writeNote'),
                              hintStyle: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.3)),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            contextMenuBuilder:
                                (context, editableTextState) {
                              return AdaptiveTextSelectionToolbar
                                  .buttonItems(
                                anchors:
                                    editableTextState.contextMenuAnchors,
                                buttonItems: [
                                  ContextMenuButtonItem(
                                    label: t('bold'),
                                    onPressed: () {
                                      _applyStyleToSelection(
                                          isBold: true);
                                      editableTextState.hideToolbar();
                                    },
                                  ),
                                  ContextMenuButtonItem(
                                    label: t('ok'),
                                    onPressed: () {
                                      setState(
                                          () => _isEditingNote = false);
                                      _noteFocusNode.unfocus();
                                    },
                                  ),
                                ],
                              );
                            },
                            onChanged: (value) {
                              _adjustStylesForTextChange(value);
                              setState(() => _userNote = value);
                              _saveNoteWithStyles();
                            },
                            onTapOutside: (_) {
                              if (_isEditingNote) {
                                setState(() => _isEditingNote = false);
                                _noteFocusNode.unfocus();
                              }
                            },
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white38, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: const Color(0xFF1E1E1E),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) {
                            if (value == 'bold') {
                              _applyStyleToSelection(isBold: true);
                            }
                            if (value == 'done') {
                              setState(() => _isEditingNote = false);
                              _noteFocusNode.unfocus();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'bold',
                              child: Row(
                                children: [
                                  const Icon(Icons.format_bold,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 10),
                                  Text(t('bold'),
                                      style: const TextStyle(
                                          color: Colors.white)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'done',
                              child: Row(
                                children: [
                                  const Icon(Icons.check,
                                      color: Colors.blueAccent, size: 18),
                                  const SizedBox(width: 10),
                                  Text(t('ok'),
                                      style: const TextStyle(
                                          color: Colors.blueAccent)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : (_userNote.isEmpty
                      ? Text(
                          t('addNote'),
                          style: TextStyle(
                            fontSize: fontSize,
                            color:
                                Colors.white.withValues(alpha: 0.3),
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: _buildStyledNote(fontSize),
                        )),
            ),
          ),
      ],
    );
  }

  void _applyStyleToSelection({bool isBold = false}) {
    final selection = _noteController.selection;
    if (!selection.isValid || selection.start == selection.end) return;

    final start = selection.start;
    final end = selection.end;

    _noteStyles.removeWhere((s) => s['start'] == start && s['end'] == end);
    _noteStyles.add({'start': start, 'end': end, 'bold': isBold});

    _saveNoteWithStyles();
    setState(() {});
  }

  void _adjustStylesForTextChange(String newText) {
    _noteStyles.removeWhere(
        (s) => s['start'] >= newText.length || s['end'] > newText.length);
  }

  void _saveNoteWithStyles() {
    SettingsService.setNote(_userNote);
    final stylesJson = _noteStyles
        .map((s) => '${s['start']},${s['end']},${s['bold']}')
        .join(';');
    SettingsService.setNoteStyles(stylesJson);
  }

  Widget _buildStyledNote(double fontSize) {
    if (_userNote.isEmpty) return const SizedBox();

    List<InlineSpan> spans = [];
    for (int i = 0; i < _userNote.length; i++) {
      bool isBold = false;
      for (var style in _noteStyles) {
        if (i >= style['start'] && i < style['end']) {
          if (style['bold'] == true) isBold = true;
        }
      }
      spans.add(TextSpan(
        text: _userNote[i],
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ));
    }

    // Merge consecutive spans with same style for performance
    List<InlineSpan> merged = [];
    for (var span in spans) {
      if (merged.isNotEmpty) {
        final lastSpan = merged.last as TextSpan;
        final currentSpan = span as TextSpan;
        if (lastSpan.style == currentSpan.style) {
          merged[merged.length - 1] = TextSpan(
            text: (lastSpan.text ?? '') + (currentSpan.text ?? ''),
            style: lastSpan.style,
          );
          continue;
        }
      }
      merged.add(span);
    }

    return RichText(text: TextSpan(children: merged));
  }

  // ─── Indicators ───

  Widget _buildPullDownIndicator() {
    if (_totalOverscroll <= 10) return const SizedBox.shrink();

    final progress = (_totalOverscroll / 150).clamp(0.0, 1.0);
    final screenHeight = MediaQuery.of(context).size.height;

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 6,
      child: Center(
        child: Container(
          height: (screenHeight * 0.4) * progress,
          width: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2 + (progress * 0.4)),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = AppLocalizations.get;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_border,
              size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            t('noFavorites'),
            style: TextStyle(
                fontSize: 18, color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 8),
          Text(
            t('noFavoritesHint'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.25)),
          ),
        ],
      ),
    );
  }

  // ─── App Item ───

  Widget _buildAppItem(AndroidAppInfo app, {Key? key, int? index}) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isWideScreen = screenWidth > 500 || (screenWidth > screenHeight);
    final double fontSize = isWideScreen ? 15.0 : 17.0;

    return InkWell(
      key: key,
      onTap: () => _launchApp(app),
      onLongPress: () => _showAppOptions(app),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            if (app.isFavorite && _selectedLetter == '#')
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.star,
                    size: 14,
                    color: Colors.amber.withValues(alpha: 0.8)),
              ),
            Expanded(
              child: Text(
                app.displayName,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Zigzag Alphabet Scroller ───

  Widget _buildAlphabetScroller() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight > 0
            ? constraints.maxHeight
            : screenHeight * 0.8;

        if (availableHeight < 200) return const SizedBox.shrink();

        final isWideScreen = screenWidth > 600;
        final isFoldedScreen = screenWidth > 800;
        final letterCount = _alphabet.length;
        final verticalPadding = availableHeight * 0.08;
        final usableHeight = availableHeight - (verticalPadding * 2);
        final maxLetterHeight = usableHeight / letterCount;

        double baseFontSize;
        if (isFoldedScreen) {
          baseFontSize = (maxLetterHeight * 0.5).clamp(8.0, 14.0);
        } else if (isWideScreen) {
          baseFontSize = (maxLetterHeight * 0.5).clamp(8.0, 13.0);
        } else {
          baseFontSize = (maxLetterHeight * 0.55).clamp(7.0, 12.0);
        }

        final hoverFontSize = baseFontSize + 3;
        final zigzagWidth = isWideScreen ? 8.0 : 5.0;
        final outerWidth = isWideScreen ? 44.0 : 36.0;
        final innerWidth =
            _isDragging ? outerWidth : (isWideScreen ? 36.0 : 28.0);

        return SizedBox(
          width: outerWidth,
          child: GestureDetector(
            onVerticalDragStart: (_) =>
                setState(() => _isDragging = true),
            onVerticalDragUpdate: (details) {
              final adjustedY =
                  details.localPosition.dy - verticalPadding;
              final itemHeight = usableHeight / _alphabet.length;
              final index = (adjustedY / itemHeight)
                  .floor()
                  .clamp(0, _alphabet.length - 1);
              final letter = _alphabet[index];
              if (_dragHoverLetter != letter) {
                _selectLetterWhileDragging(letter);
                setState(() => _dragHoverLetter = letter);
              }
            },
            onVerticalDragEnd: (_) {
              if (_dragHoverLetter != null) {
                _selectLetter(_dragHoverLetter!);
              }
              setState(() {
                _isDragging = false;
                _dragHoverLetter = null;
              });
            },
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: innerWidth,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    EdgeInsets.symmetric(vertical: verticalPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children:
                      List.generate(_alphabet.length, (index) {
                    final letter = _alphabet[index];
                    final isAvailable = letter == '#' ||
                        _availableLetters.contains(letter);
                    final isSelected = _selectedLetter == letter ||
                        (letter == '★' && _selectedLetter == null);
                    final isHovered = _dragHoverLetter == letter;
                    final isEven = index % 2 == 0;
                    final staticOffset =
                        isEven ? zigzagWidth : -zigzagWidth;

                    return Expanded(
                      child: GestureDetector(
                        onTap: isAvailable
                            ? () => _selectLetter(letter)
                            : null,
                        onLongPress: letter == '#'
                            ? _toggleHiddenAppsInList
                            : null,
                        child: Transform.translate(
                          offset: Offset(staticOffset, 0),
                          child: Center(
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 100),
                              padding: EdgeInsets.symmetric(
                                horizontal: isHovered ? 6 : 3,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isHovered
                                    ? Colors.white
                                        .withValues(alpha: 0.3)
                                    : isSelected
                                        ? Colors.white
                                            .withValues(alpha: 0.15)
                                        : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(4),
                                boxShadow:
                                    isHovered || isSelected
                                        ? [
                                            BoxShadow(
                                              color: Colors.white
                                                  .withValues(
                                                      alpha: 0.1),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                              ),
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontSize: isHovered
                                      ? hoverFontSize
                                      : baseFontSize,
                                  fontWeight:
                                      isSelected || isHovered
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                  color: isAvailable
                                      ? (isSelected || isHovered
                                          ? Colors.white
                                          : isEven
                                              ? Colors.white
                                                  .withValues(
                                                      alpha: 0.9)
                                              : Colors.white
                                                  .withValues(
                                                      alpha: 0.5))
                                      : Colors.white24,
                                  shadows: isHovered
                                      ? [
                                          Shadow(
                                            color: Colors.white
                                                .withValues(
                                                    alpha: 0.5),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
