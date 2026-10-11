import 'package:flutter/material.dart';

class EntreggoColors {
  static const primary = Color(0xFF087BFA);
  static const accent = Color(0xFF00C5E8);
  static const navy = Color(0xFF07182E);
  static const background = Color(0xFFF4F7FB);
  static const slate = Color(0xFF64748B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: EntreggoColors.primary,
    primary: EntreggoColors.primary,
    secondary: EntreggoColors.accent,
    surface: Colors.white,
    onSurface: EntreggoColors.navy,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: EntreggoColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: EntreggoColors.background,
      foregroundColor: EntreggoColors.navy,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: EntreggoColors.navy),
      bodySmall: TextStyle(color: EntreggoColors.slate),
    ),
  );
}
