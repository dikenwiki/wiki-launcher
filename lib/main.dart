// Wiki Launcher
// Platform: Linux (KDE Plasma) / Android
import 'dart:io' show Platform;

import 'main_linux.dart' as linux;
import 'main_android.dart' as android;

void main() {
  if (Platform.isLinux) {
    linux.main();
  } else {
    android.main();
  }
}
