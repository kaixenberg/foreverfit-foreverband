import 'package:flutter/material.dart';

/// Warm, rounded visual language — deliberately not Material 3's default
/// tonal-seed look. Palette and shapes (large-radius cards, pill buttons,
/// circular icon badges) are inspired by OpenVitals (github.com/mmarca-tech/
/// OpenVitals, AGPL-3.0) but reimplemented from scratch here in Dart/Theme
/// terms, not ported code — no OpenVitals source was copied.
class AppTheme {
  AppTheme._();

  // Category accent colors for MetricCard's bottom strip — cycled across
  // the dashboard grids for the same "each stat has its own color" look.
  static const accentBlue = Color(0xFF4F86C6);
  static const accentCoral = Color(0xFFE2664B);
  static const accentGreen = Color(0xFF6FA85B);
  static const accentPurple = Color(0xFF8B6FB0);
  static const accentTeal = Color(0xFF3FA8A0);
  static const accentPink = Color(0xFFD46A8C);

  static const _lightScheme = ColorScheme.light(
    primary: Color(0xFFC1622A),
    onPrimary: Color(0xFFFFF6EE),
    primaryContainer: Color(0xFFF3C9A0),
    onPrimaryContainer: Color(0xFF4A2200),
    secondary: Color(0xFF4A2312),
    onSecondary: Color(0xFFFDECE0),
    secondaryContainer: Color(0xFFE7C9B8),
    onSecondaryContainer: Color(0xFF3A1B0C),
    surface: Color(0xFFF7DCC5),
    onSurface: Color(0xFF3A2013),
    surfaceContainerHighest: Color(0xFFF2D0B4),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFE8A99B),
    onErrorContainer: Color(0xFF5C0F06),
    outline: Color(0xFFB08A6E),
  );

  static const _darkScheme = ColorScheme.dark(
    primary: Color(0xFFE79A5C),
    onPrimary: Color(0xFF3A1D00),
    primaryContainer: Color(0xFF5C3313),
    onPrimaryContainer: Color(0xFFFFDCB8),
    secondary: Color(0xFFD8B49A),
    onSecondary: Color(0xFF2E1A0C),
    secondaryContainer: Color(0xFF4A2E1C),
    onSecondaryContainer: Color(0xFFF0DAC8),
    surface: Color(0xFF2B1C12),
    onSurface: Color(0xFFF0DFCF),
    surfaceContainerHighest: Color(0xFF3A2718),
    error: Color(0xFFCF6656),
    onError: Color(0xFF3A0500),
    errorContainer: Color(0xFF6B2116),
    onErrorContainer: Color(0xFFFFDAD2),
    outline: Color(0xFF8A6B54),
  );

  static ThemeData get light => _build(_lightScheme, const Color(0xFFFDECE0));
  static ThemeData get dark => _build(_darkScheme, const Color(0xFF1E140D));

  static ThemeData _build(ColorScheme scheme, Color scaffoldBg) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          )
          .copyWith(
            headlineMedium: base.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
            headlineSmall: base.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            titleLarge: base.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
            titleMedium: base.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            labelLarge: base.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        tileColor: scheme.surface,
        iconColor: scheme.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffoldBg,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurface.withValues(alpha: 0.6),
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurface.withValues(alpha: 0.6),
          );
        }),
      ),
      dividerTheme:
          DividerThemeData(color: scheme.outline.withValues(alpha: 0.3)),
    );
  }
}
