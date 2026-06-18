import 'package:flutter/material.dart';

const appPrimary = Color(0xFF7B2FF7);
const appSecondary = Color(0xFFB76EFF);
const appAccent = Color(0xFFE9D8FF);
const appSurface = Color(0xFFF8F3FF);
const appMuted = Color(0xFF6C6078);
const appBorder = Color(0xFFE8DAFF);

ThemeData buildTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: appPrimary,
        primary: appPrimary,
        secondary: appSecondary,
        tertiary: appAccent,
        surface: Colors.white,
        error: const Color(0xFFB3261E),
      ),
      scaffoldBackgroundColor: appSurface,
      useMaterial3: true,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: const Color(0xFF1F1F1F),
        displayColor: const Color(0xFF1F1F1F),
      ),
      chipTheme: ChipThemeData(
        selectedColor: appAccent,
        backgroundColor: Colors.white,
        side: const BorderSide(color: appBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF261C2B),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        indicatorColor: appAccent.withAlpha(180),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color:
                states.contains(WidgetState.selected) ? appPrimary : appMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: appPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: appMuted),
        labelStyle: const TextStyle(color: appMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: appBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: appBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: appPrimary, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: appBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
