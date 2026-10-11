import 'package:flutter/material.dart';

class EchoColors {
  static const ink = Color(0xFF0D2422);
  static const teal = Color(0xFF087E78);
  static const mint = Color(0xFF58DCCB);
  static const canvas = Color(0xFFF3F7F6);
  static const soft = Color(0xFFE2F1EF);
}

ThemeData echoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: EchoColors.teal,
    surface: EchoColors.canvas,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: EchoColors.canvas,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: EchoColors.canvas,
      foregroundColor: EchoColors.ink,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EchoColors.teal,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD9E6E4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD9E6E4)),
      ),
    ),
  );
}
