import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const _preferenceKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_preferenceKey);
    _themeMode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final previousMode = _themeMode;
    _themeMode = mode;
    notifyListeners();

    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      final saved = await (await SharedPreferences.getInstance()).setString(
        _preferenceKey,
        value,
      );
      if (!saved) throw StateError('Could not save your appearance setting.');
    } catch (_) {
      _themeMode = previousMode;
      notifyListeners();
      rethrow;
    }
  }
}

final appThemeController = AppThemeController();
