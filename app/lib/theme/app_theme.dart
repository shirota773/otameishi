import 'package:flutter/material.dart';

/// Design tokens for otameishi.  Generated from docs/design/design-system.md.
class AppColors {
  // Brand
  static const brandPrimaryLight = Color(0xFFE91E8C);
  static const brandPrimaryDark = Color(0xFFF06292);
  static const brandSecondaryLight = Color(0xFF7B2FBE);
  static const brandSecondaryDark = Color(0xFFCE93D8);

  // Surface
  static const surfacePrimaryLight = Color(0xFFFFFFFF);
  static const surfacePrimaryDark = Color(0xFF121212);
  static const surfaceSecondaryLight = Color(0xFFF5F5F5);
  static const surfaceSecondaryDark = Color(0xFF1E1E1E);
  static const surfaceTertiaryLight = Color(0xFFEEEEEE);
  static const surfaceTertiaryDark = Color(0xFF2A2A2A);

  // Text
  static const textPrimaryLight = Color(0xFF1A1A1A);
  static const textPrimaryDark = Color(0xFFF0F0F0);
  static const textSecondaryLight = Color(0xFF555555);
  static const textSecondaryDark = Color(0xFFAAAAAA);
  static const textTertiaryLight = Color(0xFF888888);
  static const textTertiaryDark = Color(0xFF777777);
  static const textOnBrand = Color(0xFFFFFFFF);
  static const textLinkLight = Color(0xFF0066CC);
  static const textLinkDark = Color(0xFF5AAEFF);

  // Semantic
  static const successLight = Color(0xFF1B8A4C);
  static const successDark = Color(0xFF4CAF7D);
  static const warningLight = Color(0xFFB45309);
  static const warningDark = Color(0xFFF59E0B);
  static const errorLight = Color(0xFFC0392B);
  static const errorDark = Color(0xFFEF5350);
}

class AppSpacing {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;
}

class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 9999;
}

class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 250);
  static const enter = Duration(milliseconds: 300);
  static const exit = Duration(milliseconds: 200);
}

/// Builds the [ThemeData] for both brightness modes.
class AppTheme {
  /// Returns the light theme.  When [overrideAccent] is non-null it replaces
  /// [AppColors.brandPrimaryLight] as the primary color.
  static ThemeData light({Color? overrideAccent}) =>
      _build(Brightness.light, overrideAccent: overrideAccent);

  /// Returns the dark theme.  When [overrideAccent] is non-null it replaces
  /// [AppColors.brandPrimaryDark] as the primary color.
  static ThemeData dark({Color? overrideAccent}) =>
      _build(Brightness.dark, overrideAccent: overrideAccent);

  static ThemeData _build(Brightness brightness, {Color? overrideAccent}) {
    final isDark = brightness == Brightness.dark;
    final defaultPrimary =
        isDark ? AppColors.brandPrimaryDark : AppColors.brandPrimaryLight;
    final primary = overrideAccent ?? defaultPrimary;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: AppColors.textOnBrand,
      secondary: isDark ? AppColors.brandSecondaryDark : AppColors.brandSecondaryLight,
      onSecondary: AppColors.textOnBrand,
      error: isDark ? AppColors.errorDark : AppColors.errorLight,
      onError: AppColors.textOnBrand,
      surface: isDark ? AppColors.surfacePrimaryDark : AppColors.surfacePrimaryLight,
      onSurface: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
      surfaceContainerHighest:
          isDark ? AppColors.surfaceTertiaryDark : AppColors.surfaceTertiaryLight,
    );

    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryText = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final textTheme = TextTheme(
      displayLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.3, color: textColor),
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.35, color: textColor),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.4, color: textColor),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.55, color: textColor),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5, color: textColor),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4, color: textColor),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4, color: secondaryText),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      fontFamily: 'NotoSansJP',
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: scheme.primary, width: 2),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 6,
        sizeConstraints: const BoxConstraints.tightFor(width: 64, height: 64),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceTertiaryDark : AppColors.surfaceTertiaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor:
            isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}
