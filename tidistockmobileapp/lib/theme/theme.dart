import 'package:flutter/material.dart';

/// MONOCHROME COLOR SCHEME
final lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: const Color(0xFF000000),        // Black
  onPrimary: const Color(0xFFFFFFFF),      // White text on black
  secondary: const Color(0xFF4B5563),      // Dark Grey
  onSecondary: const Color(0xFFFFFFFF),
  error: const Color(0xFFEF4444),          // Red for errors
  onError: const Color(0xFFFFFFFF),
  background: const Color(0xFFFFFFFF),     // White background
  onBackground: const Color(0xFF111827),   // Almost black text
  surface: Color(0xFFFFFFFF),        // Dark grey cards
  onSurface: const Color(0xFF111827),
  shadow: const Color(0xFF4B5563).withValues(alpha: .05),
  outline: const Color(0xFFD1D5DB),        // Soft grey outlines
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFFFFFF),        // White
  onPrimary: Color(0xFF000000),      // Black text on white
  secondary: Color(0xFF9CA3AF),      // Light Grey
  onSecondary: Color(0xFF000000),
  error: Color(0xFFFCA5A5),          // Light red
  onError: Color(0xFF000000),
  background: Color(0xFF111827),     // Very dark background
  onBackground: Color(0xFFF3F4F6),   // Light text
  surface: Colors.white,        // Dark grey cards
  onSurface: Color(0xFFF3F4F6),
  shadow: Color(0xFF000000),
  outline: Color(0xFF4B5563),
);

/// LIGHT THEME
final ThemeData lightMode = ThemeData(
  useMaterial3: true,
  colorScheme: lightColorScheme,
  brightness: Brightness.light,
  scaffoldBackgroundColor: lightColorScheme.background,
  cardColor: lightColorScheme.surface,
  shadowColor: lightColorScheme.shadow,

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: MaterialStateProperty.all(lightColorScheme.primary),
      foregroundColor: MaterialStateProperty.all(lightColorScheme.onPrimary),
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevation: MaterialStateProperty.all(4),
    ),
  ),

/*  textTheme: TextTheme(
    headline1: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: lightColorScheme.onBackground),
    headline6: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: lightColorScheme.onBackground),
    bodyText1: TextStyle(fontSize: 16, color: lightColorScheme.onBackground),
    bodyText2: TextStyle(fontSize: 14, color: lightColorScheme.onBackground),
    button: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: lightColorScheme.onPrimary),
  ),*/
);

/// DARK THEME
final ThemeData darkMode = ThemeData(
  useMaterial3: true,
  colorScheme: darkColorScheme,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: darkColorScheme.background,
  cardColor: darkColorScheme.surface,
  shadowColor: darkColorScheme.shadow,

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: MaterialStateProperty.all(darkColorScheme.primary),
      foregroundColor: MaterialStateProperty.all(darkColorScheme.onPrimary),
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevation: MaterialStateProperty.all(3),
    ),
  ),

/*  textTheme: TextTheme(
    headline1: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: darkColorScheme.onBackground),
    headline6: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: darkColorScheme.onBackground),
    bodyText1: TextStyle(fontSize: 16, color: darkColorScheme.onBackground),
    bodyText2: TextStyle(fontSize: 14, color: darkColorScheme.onBackground),
    button: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkColorScheme.onPrimary),
  ),*/
);
