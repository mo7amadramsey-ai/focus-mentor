import 'package:flutter/material.dart';

// Calm palette: light brown + beige + olive
const kBg = Color(0xFFF4ECDC);       // beige
const kSurface = Color(0xFFFBF6EA);  // light beige card
const kSurface2 = Color(0xFFEADFC8); // deeper beige
const kBrown = Color(0xFFA9855F);    // light brown (primary)
const kBrownDark = Color(0xFF4B3B2A);// text
const kOlive = Color(0xFF7B8450);    // olive accent
const kOutline = Color(0xFFDCCFB4);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kBrown, brightness: Brightness.light).copyWith(
    primary: kBrown,
    onPrimary: Colors.white,
    secondary: kOlive,
    onSecondary: Colors.white,
    surface: kSurface,
    onSurface: kBrownDark,
    outline: kOutline,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kBrownDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBrownDark),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kOlive,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kBrownDark,
        side: const BorderSide(color: kOutline),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kBrownDark,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerColor: kOutline,
  );
}

BoxDecoration cardBox([double r = 18]) => BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: kOutline),
    );
