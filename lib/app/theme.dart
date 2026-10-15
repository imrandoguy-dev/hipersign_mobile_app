import 'package:flutter/material.dart';

/// Design tokens. Light theme on the "Financial Stability" palette:
/// navy #0A3C6E, white #FFFFFF, blue #1783C1, charcoal #333333. Change colours here only.
class HsColors {
  // Brand
  static const navy = Color(0xFF0A3C6E);
  static const blue = Color(0xFF1783C1);
  static const charcoal = Color(0xFF333333);

  static const background = Color(0xFFFFFFFF);
  static const card = Color(0xFFF2F6FA); // soft blue-grey panel on white
  static const cardHigh = Color(0xFFE3ECF5);
  static const border = Color(0xFFDDE6EF);
  static const accent = navy; // primary actions, headings, selected items
  static const onAccent = Color(0xFFFFFFFF);
  static const textPrimary = charcoal;
  static const textSecondary = Color(0xFF6B7785);
  static const onPastel = Color(0xFF1F2A37); // text on the status colours
  static const danger = Color(0xFFC62828);
  static const warning = Color(0xFFB26A00);
  static const warningBg = Color(0xFFFFF4DC);
  static const dangerBg = Color(0xFFFDECEC);

  // Activity states (PRD: scheduled = light blue, pending = yellow-orange, completed = green)
  static const active = Color(0xFFCFE6F6);
  static const pending = Color(0xFFFCE0A6);
  static const completed = Color(0xFFCDEED6);
  static const rescheduled = Color(0xFFE3DBF6);
  static const cancelled = Color(0xFFDADFE5);
  static const overdue = Color(0xFFFAD2D2); // missed: open and its time has passed
  static const overdueEdge = Color(0xFFC62828);

  static const whatsapp = Color(0xFF25D366);
}

/// Visual state of an activity / booking. Colour is never the only signal:
/// every card also shows [label].
enum ActivityState { active, pending, overdue, completed, rescheduled, cancelled }

extension ActivityStateStyle on ActivityState {
  Color get color => switch (this) {
        ActivityState.active => HsColors.active,
        ActivityState.pending => HsColors.pending,
        ActivityState.overdue => HsColors.overdue,
        ActivityState.completed => HsColors.completed,
        ActivityState.rescheduled => HsColors.rescheduled,
        ActivityState.cancelled => HsColors.cancelled,
      };

  String get label => switch (this) {
        ActivityState.active => 'Scheduled',
        ActivityState.pending => 'Pending',
        ActivityState.overdue => 'Overdue',
        ActivityState.completed => 'Completed',
        ActivityState.rescheduled => 'Rescheduled',
        ActivityState.cancelled => 'Cancelled',
      };

  IconData get icon => switch (this) {
        ActivityState.active => Icons.schedule,
        ActivityState.pending => Icons.hourglass_bottom,
        ActivityState.overdue => Icons.error_outline,
        ActivityState.completed => Icons.check_circle,
        ActivityState.rescheduled => Icons.update,
        ActivityState.cancelled => Icons.cancel,
      };

  static ActivityState parse(String? s) => switch (s) {
        'active' => ActivityState.active,
        'completed' => ActivityState.completed,
        'rescheduled' => ActivityState.rescheduled,
        'cancelled' => ActivityState.cancelled,
        'overdue' => ActivityState.overdue,
        _ => ActivityState.pending,
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: HsColors.navy, brightness: Brightness.light).copyWith(
    primary: HsColors.navy,
    onPrimary: HsColors.onAccent,
    secondary: HsColors.blue,
    onSecondary: Colors.white,
    surface: HsColors.background,
    onSurface: HsColors.textPrimary,
    onSurfaceVariant: HsColors.textSecondary,
    surfaceContainerHighest: HsColors.card,
    outline: HsColors.border,
    outlineVariant: HsColors.border,
    error: HsColors.danger,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: HsColors.background,
    textTheme: base.textTheme.apply(bodyColor: HsColors.textPrimary, displayColor: HsColors.textPrimary),
    appBarTheme: const AppBarTheme(
      backgroundColor: HsColors.background,
      foregroundColor: HsColors.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Color(0x1A0A3C6E),
      centerTitle: false,
      titleTextStyle: TextStyle(color: HsColors.navy, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: HsColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: const DividerThemeData(color: HsColors.border, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HsColors.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: HsColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: HsColors.blue, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HsColors.navy,
        foregroundColor: HsColors.onAccent,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HsColors.navy,
        side: const BorderSide(color: HsColors.border),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: HsColors.blue)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: HsColors.navy,
      foregroundColor: HsColors.onAccent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: HsColors.blue, linearTrackColor: HsColors.cardHigh),
    tabBarTheme: const TabBarThemeData(
      labelColor: HsColors.navy,
      unselectedLabelColor: HsColors.textSecondary,
      indicatorColor: HsColors.blue,
      dividerColor: HsColors.border,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? HsColors.navy : HsColors.background),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? HsColors.onAccent : HsColors.textPrimary),
        iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? HsColors.onAccent : HsColors.textPrimary),
        side: const WidgetStatePropertyAll(BorderSide(color: HsColors.border)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? HsColors.blue : null),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: HsColors.background, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HsColors.background, surfaceTintColor: Colors.transparent),
    bottomAppBarTheme: const BottomAppBarThemeData(
        color: HsColors.background, surfaceTintColor: Colors.transparent, elevation: 8, shadowColor: Color(0x330A3C6E)),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: HsColors.charcoal,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: Color(0xFF8CCBF0),
    ),
    listTileTheme: const ListTileThemeData(iconColor: HsColors.navy, textColor: HsColors.textPrimary),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: HsColors.background,
      selectedColor: HsColors.active,
      checkmarkColor: HsColors.navy,
      side: const BorderSide(color: HsColors.border),
      labelStyle: const TextStyle(color: HsColors.textPrimary),
      secondaryLabelStyle: const TextStyle(color: HsColors.navy, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
