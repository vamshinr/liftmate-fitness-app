import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized design tokens. Polished dark + neon system with multiple
/// surface elevations, semantic accents, and reusable surface helpers.
class AppTheme {
  // ─── Backgrounds ──────────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF06070A);
  static const Color surface = Color(0xFF0E1117);
  static const Color cardBg = Color(0xFF141921);
  static const Color cardBgElevated = Color(0xFF1B2230);
  static const Color hairline = Color(0x14FFFFFF); // ~8% white

  // ─── Accent palette ───────────────────────────────────────────────────────
  static const Color neonLime = Color(0xFFCFFC30);
  static const Color neonLimeDeep = Color(0xFF9FCB1A);
  static const Color neonCyan = Color(0xFF38E1FF);
  static const Color neonCyanDeep = Color(0xFF00B8E0);
  static const Color neonViolet = Color(0xFFB388FF);

  // ─── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF8B95A5);
  static const Color textTertiary = Color(0xFF5A6373);

  // ─── Semantic ─────────────────────────────────────────────────────────────
  static const Color accentRed = Color(0xFFFF5C7A);
  static const Color accentAmber = Color(0xFFFFC857);
  static const Color accentGreen = Color(0xFF4ADE80);

  // ─── Gradients ────────────────────────────────────────────────────────────
  static const LinearGradient limeGradient = LinearGradient(
    colors: [neonLime, neonLimeDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient cyanGradient = LinearGradient(
    colors: [neonCyan, neonCyanDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF161C26), Color(0xFF0E1117)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ─── Radii & spacing ──────────────────────────────────────────────────────
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;

  // ─── ThemeData ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: neonLime,
        onPrimary: darkBackground,
        secondary: neonCyan,
        onSecondary: darkBackground,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: cardBgElevated,
        error: accentRed,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = TextTheme(
      displayLarge: GoogleFonts.outfit(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -1.0,
        height: 1.05,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.6,
        height: 1.1,
      ),
      headlineLarge: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.4,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.2,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.1,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        color: textPrimary,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        color: textSecondary,
        height: 1.45,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        color: textTertiary,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textSecondary,
        letterSpacing: 0.4,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: hairline, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: darkBackground,
        ),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
        actionsIconTheme: const IconThemeData(color: textPrimary, size: 22),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: neonLime,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonLime,
          foregroundColor: darkBackground,
          disabledBackgroundColor: cardBgElevated,
          disabledForegroundColor: textTertiary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: hairline, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: neonLime,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        hintStyle: GoogleFonts.inter(color: textSecondary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:
              const BorderSide(color: neonLime, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardBg,
        selectedColor: neonLime.withValues(alpha: 0.18),
        labelStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: hairline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBgElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: textSecondary,
          height: 1.45,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardBgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        contentTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 13,
        ),
      ),
      dividerColor: hairline,
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: neonLime,
        linearTrackColor: hairline,
      ),
    );
  }
}

/// Surface decorations used across cards, banners, and chips. Centralizing
/// these here keeps each screen DRY and consistent.
class AppSurfaces {
  static BoxDecoration card({Color border = AppTheme.hairline}) =>
      BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: border),
      );

  static BoxDecoration elevatedCard() => BoxDecoration(
        color: AppTheme.cardBgElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: const Border.fromBorderSide(
          BorderSide(color: AppTheme.hairline),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration accent({
    required Color color,
    double alpha = 0.10,
    double borderAlpha = 0.35,
    double radius = AppTheme.radiusMd,
  }) =>
      BoxDecoration(
        color: color.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: borderAlpha)),
      );

  static BoxDecoration glow({
    Color color = AppTheme.neonLime,
    double radius = AppTheme.radiusLg,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      );
}
