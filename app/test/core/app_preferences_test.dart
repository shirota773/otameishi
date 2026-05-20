import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/core/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppPreferencesImpl — ThemeMode', () {
    test('getThemeMode returns system when nothing stored', () async {
      final prefs = AppPreferencesImpl();
      final result = await prefs.getThemeMode();
      expect(result, ThemeMode.system);
    });

    test('round-trips ThemeMode.light', () async {
      final prefs = AppPreferencesImpl();
      await prefs.setThemeMode(ThemeMode.light);
      expect(await prefs.getThemeMode(), ThemeMode.light);
    });

    test('round-trips ThemeMode.dark', () async {
      final prefs = AppPreferencesImpl();
      await prefs.setThemeMode(ThemeMode.dark);
      expect(await prefs.getThemeMode(), ThemeMode.dark);
    });

    test('round-trips ThemeMode.system', () async {
      final prefs = AppPreferencesImpl();
      await prefs.setThemeMode(ThemeMode.dark);
      await prefs.setThemeMode(ThemeMode.system);
      expect(await prefs.getThemeMode(), ThemeMode.system);
    });

    test('each test starts fresh — previous write is isolated', () async {
      // SharedPreferences.setMockInitialValues({}) in setUp ensures isolation.
      final prefs = AppPreferencesImpl();
      expect(await prefs.getThemeMode(), ThemeMode.system);
    });
  });

  group('AppPreferencesImpl — accentColorIndex', () {
    test('getAccentColorIndex returns 0 when nothing stored', () async {
      final prefs = AppPreferencesImpl();
      expect(await prefs.getAccentColorIndex(), 0);
    });

    test('round-trips index 1', () async {
      final prefs = AppPreferencesImpl();
      await prefs.setAccentColorIndex(1);
      expect(await prefs.getAccentColorIndex(), 1);
    });

    test('round-trips index 5 (last preset)', () async {
      final prefs = AppPreferencesImpl();
      await prefs.setAccentColorIndex(5);
      expect(await prefs.getAccentColorIndex(), 5);
    });

    test('overwrite replaces previous value', () async {
      final prefs = AppPreferencesImpl();
      await prefs.setAccentColorIndex(3);
      await prefs.setAccentColorIndex(2);
      expect(await prefs.getAccentColorIndex(), 2);
    });
  });
}
