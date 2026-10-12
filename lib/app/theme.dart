import 'package:flutter/material.dart';

/// Design tokens from the Hipersign PRD (v2). Change colours here only.
class HsColors {
  static const background = Color(0xFF111111);
  static const card = Color(0xFF242424);
  static const cardHigh = Color(0xFF2E2E2E);
  static const accent = Color(0xFFFFE6B4);
  static const textPrimary = Color(0xFFF4F4F4);
  static const textSecondary = Color(0xFFB4B4B4);
  static const onPastel = Color(0xFF151515);
  static const danger = Color(0xFFFF8A80);

  // Activity states
  static const active = Color(0xFFBFE8FF); // scheduled, upcoming (light blue)
  static const pending = Color(0xFFF7E4B6); // overdue / not yet done (yellow-orange)
  static const completed = Color(0xFFBCE8CB); // green
  static const rescheduled = Color(0xFFDAD0F5); // muted violet
  static const cancelled = Color(0xFF8A8A8A);

  static const whatsapp = Color(0xFF25D366);
}

/// Visual state of an activity / booking. Colour is never the only signal:
/// every card also shows [label].
enum ActivityState { active, pending, completed, rescheduled, cancelled }

extension ActivityStateStyle on ActivityState {
  Color get color => switch (this) {
        ActivityState.active => HsColors.active,
        ActivityState.pending => HsColors.pending,
        ActivityState.completed => HsColors.completed,
        ActivityState.rescheduled => HsColors.rescheduled,
        ActivityState.cancelled => HsColors.cancelled,
      };

  String get label => switch (this) {
        ActivityState.active => 'Scheduled',
        ActivityState.pending => 'Pending',
        ActivityState.completed => 'Completed',
        ActivityState.rescheduled => 'Rescheduled',
        ActivityState.cancelled => 'Cancelled',
      };

  IconData get icon => switch (this) {
        ActivityState.active => Icons.schedule,
        ActivityState.pending => Icons.hourglass_bottom,
        ActivityState.completed => Icons.check_circle,
        ActivityState.rescheduled => Icons.update,
        ActivityState.cancelled => Icons.cancel,
      };

  static ActivityState parse(String? s) => switch (s) {
        'active' => ActivityState.active,
        'completed' => ActivityState.completed,
        'rescheduled' => ActivityState.rescheduled,
        'cancelled' => ActivityState.cancelled,
        _ => ActivityState.pending,
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HsColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HsColors.accent,
    onPrimary: HsColors.onPastel,
    secondary: HsColors.active,
    onSecondary: HsColors.onPastel,
    surface: HsColors.card,
    onSurface: HsColors.textPrimary,
    error: HsColors.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: HsColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: HsColors.background,
      foregroundColor: HsColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: HsColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HsColors.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HsColors.accent,
        foregroundColor: HsColors.onPastel,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: HsColors.card,
      selectedColor: HsColors.accent,
      labelStyle: const TextStyle(color: HsColors.textPrimary),
      secondaryLabelStyle: const TextStyle(color: HsColors.onPastel),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
