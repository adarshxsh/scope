import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_elevation.dart';
import 'package:scope/theme/app_spacing.dart';

/// Scope design tokens — Material 3 dark theme.
abstract final class AppTheme {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static ThemeData light() => _build();

  static ThemeData _build() {
    const brightness = Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
    ).copyWith(
      // Override generated values with our hand-tuned tokens.
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.scaffold,
      splashFactory: InkRipple.splashFactory,

      // Keep system status bar transparent so our bg shows through.
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.scaffold,
        foregroundColor: AppColors.onSurface,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
          letterSpacing: -0.2,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 64,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.onSurface.withValues(alpha: 0.08),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.1,
            color: selected
                ? AppColors.onSurface
                : AppColors.onSurface.withValues(alpha: 0.4),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected
                ? AppColors.onSurface
                : AppColors.onSurface.withValues(alpha: 0.4),
          );
        }),
      ),

      searchBarTheme: SearchBarThemeData(
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(AppColors.surface),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(color: AppColors.onSurface),
        ),
        hintStyle: WidgetStateProperty.all(
          TextStyle(color: AppColors.onSurface.withValues(alpha: 0.4)),
        ),
      ),

      textTheme: _textTheme(),

      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        minVerticalPadding: AppSpacing.sm,
        tileColor: Colors.transparent,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.onSurface,
          foregroundColor: AppColors.scaffold,
          minimumSize: const Size(64, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md - 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md - 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          side: const BorderSide(color: AppColors.borderStrong),
          foregroundColor: AppColors.onSurface.withValues(alpha: 0.85),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme() {
    const on = AppColors.onSurface;

    return GoogleFonts.interTextTheme(
      TextTheme(
        // Hero numbers (e.g. attention score)
        displaySmall: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          letterSpacing: -2.0,
          height: 1,
          color: on,
        ),
        // Used ONLY for the Home greeting — "Good morning"
        headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          height: 1.1,
          color: on,
        ),
        // Page titles (SectionHeader)
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          height: 1.2,
          color: on,
        ),
        // Card / section title
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: on,
        ),
        // Sub-item labels
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: on,
        ),
        // Default reading text
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: on.withValues(alpha: 0.88),
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: on.withValues(alpha: 0.65),
        ),
        // Timestamps, counts, meta
        bodySmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.4,
          letterSpacing: 0.1,
          color: on.withValues(alpha: 0.45),
        ),
        // ALL-CAPS section labels
        labelLarge: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
          color: on.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  static const LinearGradient focusBackground = AppColors.focusGradient;

  @Deprecated('Use radiusLg')
  static const double cardRadius = radiusLg;
  @Deprecated('Use radiusMd')
  static const double chipRadius = radiusMd;

  static Color urgencyColor(String? priority) => AppColors.urgency(priority);
  static Color urgencyBackground(String? priority) => AppColors.urgencyBg(priority);
}
