import 'package:flutter/material.dart';

const kipTaroziYashil = Color(0xFF0F6E56);

ThemeData yorugRejim() {
  final sxema = ColorScheme.fromSeed(seedColor: kipTaroziYashil, brightness: Brightness.light);
  return ThemeData(
    useMaterial3: true,
    colorScheme: sxema,
    scaffoldBackgroundColor: const Color(0xFFF4F7F6),
    appBarTheme: AppBarTheme(backgroundColor: kipTaroziYashil, foregroundColor: Colors.white, elevation: 0),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kipTaroziYashil,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade300)),
    ),
  );
}

ThemeData qorongiRejim() {
  final sxema = ColorScheme.fromSeed(seedColor: kipTaroziYashil, brightness: Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    colorScheme: sxema,
    scaffoldBackgroundColor: const Color(0xFF121615),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B4D3D), foregroundColor: Colors.white, elevation: 0),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kipTaroziYashil,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade800)),
    ),
  );
}
