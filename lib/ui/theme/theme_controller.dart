import 'package:flutter/material.dart';

/// Drives light/dark switching for the whole app via [Provider].
class ThemeController extends ChangeNotifier {
  /// Starts in dark mode (default listening experience).
  ThemeMode _mode = ThemeMode.dark;

  /// Current Flutter [ThemeMode].
  ThemeMode get mode => _mode;

  /// True when using the dark palette.
  bool get isDark => _mode == ThemeMode.dark;

  /// Toggles between light and dark.
  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  /// Sets an explicit mode.
  void setMode(ThemeMode mode) {
    _mode = mode;
    notifyListeners();
  }
}
