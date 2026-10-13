import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntreggoColors {
  static const primary = Color(0xFF087BFA);
  static const accent = Color(0xFF00C5E8);
  static const navy = Color(0xFF07182E);
  static const background = Color(0xFFF4F7FB);
  static const slate = Color(0xFF64748B);

  static const darkBackground = Color(0xFF0B1420);
  static const darkSurface = Color(0xFF16202E);
  static const darkOnSurface = Color(0xFFE8EEF6);
}

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: EntreggoColors.primary,
    brightness: brightness,
    primary: EntreggoColors.primary,
    secondary: EntreggoColors.accent,
    surface: dark ? EntreggoColors.darkSurface : Colors.white,
    onSurface: dark ? EntreggoColors.darkOnSurface : EntreggoColors.navy,
  );
  final scaffold = dark
      ? EntreggoColors.darkBackground
      : EntreggoColors.background;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
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
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: scheme.onSurface),
      bodySmall: const TextStyle(color: EntreggoColors.slate),
    ),
  );
}

/// Preferência de aparência (claro/escuro/automático), salva no aparelho.
class ThemeController extends ChangeNotifier {
  static const _key = 'entreggo_theme_mode';

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  String get label => switch (_mode) {
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Escuro',
    ThemeMode.system => 'Automático',
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode =
        ThemeMode.values.asNameMap()[prefs.getString(_key)] ?? ThemeMode.system;
    notifyListeners();
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
