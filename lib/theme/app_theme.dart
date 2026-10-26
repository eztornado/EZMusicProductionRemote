import 'package:flutter/material.dart';

/// Colour language shared with the desktop DAW.
///
/// The DAW uses a near-black workspace, blue selection accents and a red brand
/// for recording. Keeping the same palette makes the remote feel like part of
/// the same product instead of a generic companion app.
abstract final class AppColors {
  static const background = Color(0xFF0B0C0F);
  static const backgroundElevated = Color(0xFF121419);
  static const surface = Color(0xFF171A20);
  static const panel = Color(0xFF1D2027);
  static const panelAlt = Color(0xFF22262E);
  static const panelHigh = Color(0xFF282D36);
  static const border = Color(0xFF2C313B);
  static const borderStrong = Color(0xFF3C4250);

  static const text = Color(0xFFF0F2F6);
  static const textDim = Color(0xFFA1A8B5);
  static const textFaint = Color(0xFF6B7382);

  static const accent = Color(0xFF4D9DF7);
  static const accentSoft = Color(0xFF1E3655);
  static const brand = Color(0xFFFF3B30);
  static const brandLight = Color(0xFFFF8A80);
  static const success = Color(0xFF3DD68C);
  static const warning = Color(0xFFF5A524);
  static const danger = Color(0xFFE5484D);
  static const record = Color(0xFFFF453A);

  /// Same 16-colour palette as the desktop timeline.
  static const trackPalette = <Color>[
    Color(0xFFE5484D),
    Color(0xFFE5622E),
    Color(0xFFF0A020),
    Color(0xFFB8C22A),
    Color(0xFF46A758),
    Color(0xFF26A69A),
    Color(0xFF22B3D1),
    Color(0xFF3E8FDB),
    Color(0xFF5B6EE1),
    Color(0xFF6E56CF),
    Color(0xFF9B59B6),
    Color(0xFFD6409F),
    Color(0xFFE93D82),
    Color(0xFF8E6A4E),
    Color(0xFF7C8B2D),
    Color(0xFF6E7191),
  ];

  static Color track(int index) =>
      trackPalette[index.clamp(0, trackPalette.length - 1)];
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Color(0xFF06121F),
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: Color(0xFFD9E9FF),
    secondary: AppColors.brand,
    onSecondary: Colors.black,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.panelAlt,
    onSurfaceVariant: AppColors.textDim,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
    onError: Colors.black,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  final baseText = ThemeData.dark(useMaterial3: true).textTheme;
  final textTheme = baseText
      .apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
        fontFamily: null,
      )
      .copyWith(
        displaySmall: baseText.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelLarge: baseText.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelMedium: baseText.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
        labelSmall: baseText.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.textDim,
        ),
        bodySmall: baseText.bodySmall?.copyWith(color: AppColors.textDim),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: AppColors.textDim, size: 20),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.panelHigh,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.borderStrong),
      ),
      textStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.panelHigh,
      thumbColor: AppColors.text,
      overlayColor: AppColors.accent.withValues(alpha: 0.14),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      valueIndicatorColor: AppColors.panelHigh,
      valueIndicatorTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? AppColors.text
                : AppColors.textFaint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.panelHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.border,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF06121F),
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size(44, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.textDim),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.backgroundElevated,
      indicatorColor: AppColors.accentSoft,
      height: 66,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color:
              states.contains(WidgetState.selected)
                  ? AppColors.text
                  : AppColors.textFaint,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color:
              states.contains(WidgetState.selected)
                  ? AppColors.accent
                  : AppColors.textFaint,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.backgroundElevated,
      indicatorColor: AppColors.accentSoft,
      selectedIconTheme: IconThemeData(color: AppColors.accent, size: 22),
      unselectedIconTheme: IconThemeData(color: AppColors.textFaint, size: 21),
      selectedLabelTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: AppColors.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      useIndicator: true,
      labelType: NavigationRailLabelType.all,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.panelHigh,
      contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.panelHigh,
      circularTrackColor: AppColors.panelHigh,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 13),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.backgroundElevated,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: AppColors.accentSoft,
      selectionHandleColor: AppColors.accent,
    ),
  );
}

BoxDecoration panelDecoration({
  Color color = AppColors.surface,
  Color borderColor = AppColors.border,
  double radius = 14,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor),
  );
}
