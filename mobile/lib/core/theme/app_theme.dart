import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF2563EB);

  static ColorScheme get lightScheme => ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      );

  static ColorScheme get darkScheme => ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      );

  static ThemeData light() => _build(lightScheme);
  static ThemeData dark() => _build(darkScheme);

  static ThemeData _build(ColorScheme cs) => ThemeData(
        useMaterial3: true,
        colorScheme: cs,
        scaffoldBackgroundColor: cs.surface,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: cs.surfaceContainerLowest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: cs.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 0,
          indicatorColor: cs.primaryContainer,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 0,
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: BottomSheetThemeData(
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          backgroundColor: cs.surface,
        ),
        dividerTheme: DividerThemeData(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          space: 1,
        ),
        chipTheme: ChipThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
}
