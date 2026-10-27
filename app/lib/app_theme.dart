import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AppTypography {
  // Latin first, Chinese without Hangul next, then the dedicated Korean face.
  static const family = 'Ysabeau Office';
  static const fallback = [
    'LXGW WenKai Lite',
    'LXGW WenKai KR',
    'Noto Sans KR',
    'Segoe UI Emoji',
    'Apple Color Emoji',
    'Noto Color Emoji',
    'Noto Emoji',
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ];
}

void registerAppFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'LXGW WenKai Lite': 'LXGWWenKai-LICENSE.txt',
      'LXGW WenKai KR': 'LXGWWenKaiKR-LICENSE.txt',
      'Ysabeau Office': 'YsabeauOffice-LICENSE.txt',
      'Noto Sans KR': 'NotoSansKR-LICENSE.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/fonts/${entry.value}'));
    }
  });
}

/// Production values matching the approved light-blue preview defaults.
abstract final class AppPalette {
  static const primary = Color(0xFF8FC8ED);
  static const onPrimary = Color(0xFF173B56);
  static const accent = Color(0xFF52809D);
  static const ink = Color(0xFF203E55);
  static const muted = Color(0xFF738696);
  static const background = Color(0xFFF3F8FC);
  static const soft = Color(0xFFE7F3FC);
  static const line = Color(0xFFDFE9F1);
  static const radius = 18.0;
}

ThemeData buildAppTheme() {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.primary,
      primary: AppPalette.accent,
      onPrimary: Colors.white,
      primaryContainer: AppPalette.primary,
      onPrimaryContainer: AppPalette.onPrimary,
      secondaryContainer: AppPalette.soft,
      onSecondaryContainer: AppPalette.accent,
      surface: Colors.white,
      onSurface: AppPalette.ink,
      outline: AppPalette.line,
    ),
    scaffoldBackgroundColor: AppPalette.background,
    fontFamily: AppTypography.family,
    fontFamilyFallback: AppTypography.fallback,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge!.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: AppPalette.ink,
      ),
      headlineSmall: base.textTheme.headlineSmall!.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.45,
        color: AppPalette.ink,
      ),
      titleLarge: base.textTheme.titleLarge!.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppPalette.ink,
      ),
      bodyLarge: base.textTheme.bodyLarge!.copyWith(
        fontSize: 16,
        height: 1.7,
        color: AppPalette.ink,
      ),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(
        fontSize: 14,
        height: 1.6,
        color: AppPalette.ink,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.background,
      foregroundColor: AppPalette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: AppTypography.family,
        fontFamilyFallback: AppTypography.fallback,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppPalette.ink,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppPalette.radius)),
        side: BorderSide(color: AppPalette.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.primary,
        foregroundColor: AppPalette.onPrimary,
        disabledBackgroundColor: AppPalette.line,
        disabledForegroundColor: AppPalette.muted,
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: AppTypography.family,
          fontFamilyFallback: AppTypography.fallback,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.ink,
        backgroundColor: Colors.white,
        minimumSize: const Size(44, 48),
        side: const BorderSide(color: AppPalette.line),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.accent,
        shape: shape,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppPalette.line,
      thickness: 1,
      space: 24,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppPalette.accent,
      unselectedLabelColor: AppPalette.muted,
      indicatorColor: AppPalette.accent,
      dividerColor: AppPalette.line,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppPalette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppPalette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppPalette.accent, width: 1.5),
      ),
      hintStyle: const TextStyle(
        color: AppPalette.muted,
        fontWeight: FontWeight.w400,
      ),
    ),
  );
}
