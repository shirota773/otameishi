import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Typed, async interface over [SharedPreferences] for persisting user
/// preferences that do not affect business logic.
abstract class AppPreferences {
  Future<ThemeMode> getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);

  Future<int> getAccentColorIndex();
  Future<void> setAccentColorIndex(int index);
}

const _kThemeModeKey = 'theme_mode';
const _kAccentColorIndexKey = 'accent_color_index';

class AppPreferencesImpl implements AppPreferences {
  AppPreferencesImpl();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<ThemeMode> getThemeMode() async {
    final prefs = await _prefs;
    final index = prefs.getInt(_kThemeModeKey);
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await _prefs;
    await prefs.setInt(_kThemeModeKey, mode.index);
  }

  @override
  Future<int> getAccentColorIndex() async {
    final prefs = await _prefs;
    return prefs.getInt(_kAccentColorIndexKey) ?? 0;
  }

  @override
  Future<void> setAccentColorIndex(int index) async {
    final prefs = await _prefs;
    await prefs.setInt(_kAccentColorIndexKey, index);
  }
}
