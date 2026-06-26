import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Palette
  static const Color bg         = Color(0xFF0A0B14); // deep near-black
  static const Color surface    = Color(0xFF13141F); // card bg
  static const Color surface2   = Color(0xFF1C1D2E); // elevated card
  static const Color surface3   = Color(0xFF252636); // input bg

  static const Color primary    = Color(0xFF7C6EFA); // violet
  static const Color primaryDim = Color(0xFF5A4DCC); // pressed violet
  static const Color accent     = Color(0xFFFF6B9D); // pink accent

  static const Color msgOwn     = Color(0xFF6C5CE7); // own bubble base
  static const Color msgOwnEnd  = Color(0xFF9B8CFF); // own bubble end
  static const Color msgOther   = Color(0xFF1C1D2E); // other bubble

  static const Color online     = Color(0xFF4EDE8C); // green
  static const Color unread     = Color(0xFF7C6EFA); // badge

  static const Color textPrimary   = Color(0xFFF0F0FF);
  static const Color textSecondary = Color(0xFF8E8EA8);
  static const Color textHint      = Color(0xFF52526A);

  static const Color divider = Color(0xFF1E1F2E);
  static const Color border  = Color(0xFF2A2B3D);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark();
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 32, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary, letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 17, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w500,
        color: AppColors.textHint, letterSpacing: 0.4,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface3,
        hintStyle: GoogleFonts.inter(
          fontSize: 15, color: AppColors.textHint,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 0,
      ),

      iconTheme: const IconThemeData(color: AppColors.textSecondary),
    );
  }
}

// Gradient for own messages
const LinearGradient kMsgGradient = LinearGradient(
  colors: [AppColors.msgOwn, AppColors.msgOwnEnd],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Gradient for primary buttons
const LinearGradient kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF6C5CE7), Color(0xFF9B8CFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
