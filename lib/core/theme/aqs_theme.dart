import 'package:flutter/material.dart';

abstract final class AqsColors {
  static const primary = Color(0xFF155EEF);
  static const primaryDark = Color(0xFF0B2B67);
  static const primarySoft = Color(0xFFEFF4FF);
  static const ink = Color(0xFF101828);
  static const text = Color(0xFF344054);
  static const muted = Color(0xFF667085);
  static const subtle = Color(0xFF98A2B3);
  static const border = Color(0xFFEAECF0);
  static const canvas = Color(0xFFF7F9FC);
  static const success = Color(0xFF039855);
  static const successSoft = Color(0xFFECFDF3);
}

abstract final class AqsTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AqsColors.primary,
      brightness: Brightness.light,
      surface: Colors.white,
    ).copyWith(
      primary: AqsColors.primary,
      onPrimary: Colors.white,
      secondary: const Color(0xFF3E7BFA),
      surface: Colors.white,
      onSurface: AqsColors.ink,
      outline: AqsColors.border,
      outlineVariant: const Color(0xFFF2F4F7),
    );

    final rounded12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AqsColors.canvas,
      fontFamily: 'Roboto',
      dividerColor: AqsColors.border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: AqsColors.ink,
        surfaceTintColor: Colors.white,
        titleTextStyle: TextStyle(
          color: AqsColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: AqsColors.text),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AqsColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AqsColors.muted),
        hintStyle: const TextStyle(color: AqsColors.subtle),
        prefixIconColor: AqsColors.muted,
        suffixIconColor: AqsColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AqsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AqsColors.primary,
            width: 1.7,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD92D20)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AqsColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: rounded12,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AqsColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: rounded12,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AqsColors.text,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: const BorderSide(color: Color(0xFFD0D5DD)),
          shape: rounded12,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AqsColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 3,
        backgroundColor: AqsColors.primary,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titleTextStyle: const TextStyle(
          color: AqsColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AqsColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AqsColors.primary,
        unselectedLabelColor: AqsColors.muted,
        indicatorColor: AqsColors.primary,
        dividerColor: AqsColors.border,
        labelStyle: TextStyle(fontWeight: FontWeight.w800),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AqsColors.primary,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AqsColors.muted,
        textColor: AqsColors.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
