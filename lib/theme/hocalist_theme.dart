part of '../main.dart';

class HocalistTheme {
  static const primary = Color(0xff00036c);
  static const primaryContainer = Color(0xff20258f);
  static const actionBlue = BuyerUiTokens.action;
  static const sellerGreen = Color(0xff078b2d);
  static const giftPurple = Color(0xff8d10ca);
  static const rewardGold = Color(0xffffb331);
  static const buyer = primary;
  static const seller = primary;
  static const background = Color(0xfff7f9ff);
  static const surface = BuyerUiTokens.surface;
  static const softSurface = BuyerUiTokens.softSurface;
  static const roleSurface = BuyerUiTokens.activeSurface;
  static const sellerSurface = Color(0xffeefaf2);
  static const text = BuyerUiTokens.text;
  static const muted = BuyerUiTokens.muted;
  static const outline = Color(0xffc7c9d8);
  static const danger = Color(0xffb42318);
  static const success = Color(0xff08765f);
  static const warning = Color(0xff9a5b00);
  static const focus = Color(0xff5b63e8);
  static const darkBackground = Color(0xff0b0c1f);
  static const darkSurface = Color(0xff15172d);
  static const darkSoftSurface = Color(0xff202344);
  static const darkText = Color(0xfff3f3ff);
  static const darkMuted = Color(0xffc4c5d6);
  static const darkOutline = Color(0xff454867);
  static const darkBuyer = Color(0xffbec2ff);
  static const darkSeller = Color(0xffbec2ff);
  static const darkPrimary = primary;
  static const appFontFamily = 'Nunito';
  static const appFontFallback = ['Arial', 'Helvetica', 'sans-serif'];
  static const displaySize = 30.0;
  static const pageTitleSize = 26.0;
  static const sectionTitleSize = 20.0;
  static const titleSize = 16.0;
  static const prominentTitleSize = 18.0;
  static const bodySize = 14.0;
  static const captionSize = 13.0;
  static const smallSize = 12.0;
  static const badgeSize = 11.0;
  static const buttonSize = 14.0;
  static const metricSize = 26.0;

  static TextTheme _textTheme({
    required Color primaryText,
    required Color mutedText,
    String fontFamily = appFontFamily,
    FontWeight titleWeight = FontWeight.w800,
  }) {
    return TextTheme(
      displayLarge: TextStyle(
        color: primaryText,
        fontSize: displaySize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      displayMedium: TextStyle(
        color: primaryText,
        fontSize: pageTitleSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      displaySmall: TextStyle(
        color: primaryText,
        fontSize: pageTitleSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineLarge: TextStyle(
        color: primaryText,
        fontSize: pageTitleSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: primaryText,
        fontSize: sectionTitleSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        color: primaryText,
        fontSize: sectionTitleSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        color: primaryText,
        fontSize: prominentTitleSize,
        fontWeight: titleWeight,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: primaryText,
        fontSize: titleSize,
        fontWeight: titleWeight,
        letterSpacing: 0,
      ),
      titleSmall: TextStyle(
        color: primaryText,
        fontSize: bodySize,
        fontWeight: titleWeight,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: primaryText,
        fontSize: bodySize,
        letterSpacing: 0,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        color: primaryText,
        fontSize: captionSize,
        letterSpacing: 0,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        color: mutedText,
        fontSize: smallSize,
        letterSpacing: 0,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        color: primaryText,
        fontSize: captionSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelMedium: TextStyle(
        color: mutedText,
        fontSize: smallSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelSmall: TextStyle(
        color: mutedText,
        fontSize: smallSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    ).apply(fontFamily: fontFamily);
  }

  static TextStyle _controlText(
    Color color, {
    String fontFamily = appFontFamily,
  }) {
    return TextStyle(
      color: color,
      fontFamily: fontFamily,
      fontSize: buttonSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  static TextStyle _fieldText(
    Color color, {
    String fontFamily = appFontFamily,
  }) {
    return TextStyle(
      color: color,
      fontFamily: fontFamily,
      fontSize: captionSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
  }

  static WidgetStateProperty<TextStyle?> _navLabelStyle({
    required Color selected,
    required Color unselected,
    String fontFamily = appFontFamily,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      final active = states.contains(WidgetState.selected);
      return TextStyle(
        color: active ? selected : unselected,
        fontFamily: fontFamily,
        fontSize: smallSize,
        fontWeight: active ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: 0,
      );
    });
  }

  static ThemeData get light => lightFor(AccessibilityPreferences.defaults);

  static ThemeData lightFor(AccessibilityPreferences preferences) {
    final fontFamily = preferences.fontFamily;
    final highContrastFont =
        preferences.fontStyle == AccessibilityFontStyle.highContrast;
    final visuals =
        preferences.buttonStyle == AccessibilityButtonStyle.highContrast
        ? const HocalistAccessibilityVisuals(
            buttonRadius: 3,
            buttonBackground: Color(0xff2b11aa),
            buttonForeground: Colors.white,
            buttonBorderWidth: 2,
          )
        : const HocalistAccessibilityVisuals(
            buttonRadius: HocalistButtonTokens.radius,
            buttonBackground: primary,
            buttonForeground: Colors.white,
            buttonBorderWidth: 1,
          );
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      fontFamilyFallback: appFontFallback,
      extensions: [visuals],
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: buyer,
        tertiary: seller,
        surface: surface,
        error: danger,
      ),
      textTheme: _textTheme(
        primaryText: text,
        mutedText: muted,
        fontFamily: fontFamily,
        titleWeight: highContrastFont ? FontWeight.w900 : FontWeight.w800,
      ),
      primaryTextTheme: _textTheme(
        primaryText: text,
        mutedText: muted,
        fontFamily: fontFamily,
        titleWeight: highContrastFont ? FontWeight.w900 : FontWeight.w800,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffdbe5ef)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: false,
        filled: true,
        fillColor: surface,
        constraints: const BoxConstraints(
          minHeight: HocalistInputTokens.minimumHeight,
        ),
        contentPadding: HocalistInputTokens.contentPadding,
        labelStyle: _fieldText(muted, fontFamily: fontFamily),
        hintStyle: _fieldText(muted, fontFamily: fontFamily),
        floatingLabelStyle: _fieldText(primary, fontFamily: fontFamily),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: _controlText(Colors.white, fontFamily: fontFamily),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: _controlText(primary, fontFamily: fontFamily),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: _controlText(primary, fontFamily: fontFamily),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _fieldText(Colors.white, fontFamily: fontFamily),
        actionTextColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: _textTheme(
          primaryText: text,
          mutedText: muted,
          fontFamily: fontFamily,
        ).headlineSmall,
        contentTextStyle: _textTheme(
          primaryText: text,
          mutedText: muted,
          fontFamily: fontFamily,
        ).bodyMedium,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: _textTheme(
          primaryText: text,
          mutedText: muted,
          fontFamily: fontFamily,
        ).titleMedium,
        subtitleTextStyle: _textTheme(
          primaryText: text,
          mutedText: muted,
          fontFamily: fontFamily,
        ).bodyMedium?.copyWith(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: _navLabelStyle(
          selected: primary,
          unselected: muted,
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  static ThemeData get dark => darkFor(AccessibilityPreferences.defaults);

  static ThemeData darkFor(AccessibilityPreferences preferences) {
    final fontFamily = preferences.fontFamily;
    final highContrastFont =
        preferences.fontStyle == AccessibilityFontStyle.highContrast;
    final visuals =
        preferences.buttonStyle == AccessibilityButtonStyle.highContrast
        ? const HocalistAccessibilityVisuals(
            buttonRadius: 3,
            buttonBackground: Color(0xff2b11aa),
            buttonForeground: Colors.white,
            buttonBorderWidth: 2,
          )
        : const HocalistAccessibilityVisuals(
            buttonRadius: HocalistButtonTokens.radius,
            buttonBackground: primary,
            buttonForeground: Colors.white,
            buttonBorderWidth: 1,
          );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      fontFamilyFallback: appFontFallback,
      extensions: [visuals],
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: darkPrimary,
        primary: darkPrimary,
        onPrimary: Colors.white,
        secondary: darkBuyer,
        tertiary: darkSeller,
        surface: darkSurface,
        error: Color(0xffffb4ab),
      ),
      textTheme: _textTheme(
        primaryText: darkText,
        mutedText: darkMuted,
        fontFamily: fontFamily,
        titleWeight: highContrastFont ? FontWeight.w900 : FontWeight.w800,
      ),
      primaryTextTheme: _textTheme(
        primaryText: darkText,
        mutedText: darkMuted,
        fontFamily: fontFamily,
        titleWeight: highContrastFont ? FontWeight.w900 : FontWeight.w800,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkOutline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: false,
        filled: true,
        fillColor: darkSurface,
        constraints: const BoxConstraints(
          minHeight: HocalistInputTokens.minimumHeight,
        ),
        contentPadding: HocalistInputTokens.contentPadding,
        labelStyle: _fieldText(darkMuted, fontFamily: fontFamily),
        hintStyle: _fieldText(darkMuted, fontFamily: fontFamily),
        floatingLabelStyle: _fieldText(darkBuyer, fontFamily: fontFamily),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkPrimary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: _controlText(Colors.white, fontFamily: fontFamily),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: _controlText(darkBuyer, fontFamily: fontFamily),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: _controlText(darkBuyer, fontFamily: fontFamily),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _fieldText(Colors.white, fontFamily: fontFamily),
        actionTextColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: _textTheme(
          primaryText: darkText,
          mutedText: darkMuted,
          fontFamily: fontFamily,
          titleWeight: FontWeight.w700,
        ).headlineSmall,
        contentTextStyle: _textTheme(
          primaryText: darkText,
          mutedText: darkMuted,
          fontFamily: fontFamily,
          titleWeight: FontWeight.w700,
        ).bodyMedium,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: _textTheme(
          primaryText: darkText,
          mutedText: darkMuted,
          fontFamily: fontFamily,
          titleWeight: FontWeight.w700,
        ).titleMedium,
        subtitleTextStyle: _textTheme(
          primaryText: darkText,
          mutedText: darkMuted,
          fontFamily: fontFamily,
          titleWeight: FontWeight.w700,
        ).bodyMedium?.copyWith(color: darkMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: primary.withValues(alpha: 0.42),
        labelTextStyle: _navLabelStyle(
          selected: darkBuyer,
          unselected: darkMuted,
          fontFamily: fontFamily,
        ),
      ),
    );
  }
}
