# 📱 Wiki Launcher

A minimal, sorted Android launcher built with Flutter. Clean, fast, and privacy-focused.

> **OLED-friendly** pure black design · **No ads** · **No tracking** · **Open source**

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔤 **Alphabet Navigation** | Zigzag DNA-style alphabet scroller for fast app access |
| ⭐ **Favorites** | Pin and reorder your most used apps |
| 🔍 **Search** | Quick search across all installed apps |
| 📝 **Notes** | Add personal notes with bold text support on the home screen |
| 👁️ **Hide Apps** | Hide apps you don't want to see |
| ✏️ **Rename Apps** | Give apps custom display names |
| ⚙️ **Settings via `/set`** | Type `/set` in the search bar to access settings |
| 🌍 **Multi-language** | Turkish (Türkçe) and English support |
| 🖤 **OLED Black** | Pure black background saves battery on OLED screens |
| 📱 **Wide Screen** | 2-column grid on tablets and foldables |

## 📸 How It Works

- **Home Screen** → Your favorite apps, reorderable by long press
- **Pull Down** → Expand notification panel
- **Back Button** → Opens search
- **Alphabet Sidebar** → Tap a letter to filter apps
- **Long Press `#`** → Show hidden apps
- **Type `/set`** → Open settings panel

## 🔧 Settings

Access settings by typing `/set` in the search bar:

- 🌍 **Language** — Switch between Türkçe and English
- 🖼️ **Show Icons** — Toggle app icons on/off
- 👁️ **Hidden Apps** — View and manage hidden apps

## 🚀 Build

### Requirements

- Flutter SDK (3.10+)
- Android SDK
- JDK 17

### Steps

```bash
# Clone the repository
git clone https://github.com/dikenwiki/wiki-launcher.git
cd wiki-launcher

# Get dependencies
flutter pub get

# Build debug APK
flutter build apk --debug

# Build release APK
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`

## 📁 Project Structure

```
lib/
├── main.dart              # Platform router (Android/Linux)
├── main_android.dart      # Android launcher UI
├── main_linux.dart        # Linux launcher UI
├── android_app_service.dart   # Android platform channel service
├── linux_app_service.dart     # Linux app discovery service
├── services.dart          # Shared storage services (favorites, settings)
└── app_localizations.dart # i18n (Turkish/English)
```

## 🤝 Contributing

Contributions are welcome! Feel free to:

- 🐛 Report bugs
- 💡 Suggest new features
- 🔧 Submit pull requests
- 🌍 Add new language translations

## 📄 License

This project is open source
