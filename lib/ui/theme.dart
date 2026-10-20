import 'package:flutter/material.dart';

const lime = Color(0xFF63D9E2);
const ink = Color(0xFF0C2027);
const panel = Color(0xFF17333B);
const muted = Color(0xFFACC4C8);
const trackiaOrange = Color(0xFFFF8A57);

final gymTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: lime,
    brightness: Brightness.dark,
  ).copyWith(
    primary: lime,
    onPrimary: ink,
    secondary: trackiaOrange,
    onSecondary: ink,
    surface: panel,
  ),
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
    seedColor: const Color(0xFF08788A),
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF08788A),
    onPrimary: Colors.white,
    secondary: const Color(0xFFBB471D),
  ),
  scaffoldBackgroundColor: const Color(0xFFF6FAFA),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF6FAFA),
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: gymTheme.inputDecorationTheme.copyWith(
    fillColor: const Color(0xFFE9F3F4),
  ),
  textTheme: ThemeData(brightness: Brightness.light).textTheme,
  primaryTextTheme: ThemeData(brightness: Brightness.light).primaryTextTheme,
);
