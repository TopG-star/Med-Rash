import 'package:flutter/services.dart';

/// Thin wrapper over [HapticFeedback] that gives MedRash a vocabulary
/// (`selection` / `submit` / `celebrate`) instead of platform-channel names.
/// Centralising here lets us mute or remap haptics in one place (e.g. if a
/// future "Quiet mode" setting is added).
///
/// All methods swallow `MissingPluginException` so widget tests and unsupported
/// platforms (web) don't crash.
class Haptics {
  const Haptics._();

  /// Light tap. Use for option highlighting, chip selection, toggles.
  static Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } on MissingPluginException {
      // No-op on platforms without haptics (web, test).
    }
  }

  /// Medium tap. Use for submit / confirm / commit moments.
  static Future<void> submit() async {
    try {
      await HapticFeedback.mediumImpact();
    } on MissingPluginException {
      // No-op.
    }
  }

  /// Heavy thump. Reserve for celebratory beats (rank up, podium reveal,
  /// final-question correct).
  static Future<void> celebrate() async {
    try {
      await HapticFeedback.heavyImpact();
    } on MissingPluginException {
      // No-op.
    }
  }
}
