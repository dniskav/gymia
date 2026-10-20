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

final gymLightTheme = ThemeData(
  useMaterial3: true,
  filledButtonTheme: gymTheme.filledButtonTheme,
  outlinedButtonTheme: gymTheme.outlinedButtonTheme,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF426500),
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: const Color(0xFFF6F9F1),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF6F9F1),
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: gymTheme.inputDecorationTheme.copyWith(
    fillColor: const Color(0xFFEDF2E6),
  ),
  textTheme: ThemeData(brightness: Brightness.light).textTheme,
  primaryTextTheme: ThemeData(brightness: Brightness.light).primaryTextTheme,
);
