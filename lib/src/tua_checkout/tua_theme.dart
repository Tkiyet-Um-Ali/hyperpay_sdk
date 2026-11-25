import 'package:flutter/material.dart';

/// TUA design-system tokens, as used by the HyperPay Checkout Kit design.
abstract final class TuaColors {
  static const surface = Color(0xFFFFFFFF);
  static const field = Color(0xFFF5F7FA);
  static const line = Color(0xFFD9DFE8);
  static const ink = Color(0xFF041E42);
  static const ink2 = Color(0xFF1A2433);
  static const muted = Color(0xFF56617A);
  static const brand = Color(0xFF041E42);
  static const brandInk = Color(0xFFFFFFFF);
  static const accent = Color(0xFF54C0E8);
  static const hero = Color(0xFF041E42);
  static const ok = Color(0xFF2E9E62);

  // Not in the TUA system yet: declined cards and field errors.
  static const error = Color(0xFFC2362B);
  static const errorBg = Color(0xFFFDECEA);
}

abstract final class TuaText {
  /// Cairo, bundled with the plugin (SIL Open Font License).
  static const fontFamily = 'Cairo';
  static const fontPackage = 'hyperpay_sdk';

  static TextStyle cairo({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = TuaColors.ink,
    double? height,
    double? letterSpacing,
    List<FontFeature>? features,
  }) => TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: features,
  );

  static const tabular = [FontFeature.tabularFigures()];
}

/// The light, Cairo-based theme the checkout renders in (tua.jo has no dark
/// theme).
ThemeData tuaTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: TuaColors.surface,
    colorScheme: const ColorScheme.light(
      primary: TuaColors.brand,
      onPrimary: TuaColors.brandInk,
      secondary: TuaColors.accent,
      error: TuaColors.error,
      surface: TuaColors.surface,
      onSurface: TuaColors.ink,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'packages/${TuaText.fontPackage}/${TuaText.fontFamily}',
      bodyColor: TuaColors.ink,
      displayColor: TuaColors.ink,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: TuaColors.brand,
      selectionColor: Color(0x5554C0E8),
      selectionHandleColor: TuaColors.brand,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: TuaColors.hero,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TuaText.cairo(
        size: 17,
        weight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}
