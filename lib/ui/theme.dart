import 'package:flutter/material.dart';

const lime = Color(0xFFD4F876);
const ink = Color(0xFF111716);
const panel = Color(0xFF1E2724);
const muted = Color(0xFFAEBBB4);

final gymTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: lime,
    brightness: Brightness.dark,
  ).copyWith(primary: lime, onPrimary: ink, surface: panel),
  appBarTheme: const AppBarTheme(
    backgroundColor: ink,
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: ink,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
);
