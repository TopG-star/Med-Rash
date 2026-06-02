import 'package:flutter/material.dart';

/// Sealed contract for what fills the body of a `GamifiedAvatar`.
///
/// MedRash currently ships nickname-only profiles (no PII photos), so the
/// default body is a `MonogramAvatarSpec` rendering 1–2 initials.
/// `NaviiAvatarSpec` is the foundation for the future Navii customizable
/// character system — its fields describe color tokens and expression so the
/// avatar widget can render a placeholder today and swap in real Navii art
/// later without changing the call-sites.
sealed class AvatarSpec {
  const AvatarSpec();
}

/// Initials-only avatar body. `source` is the nickname (or any free string);
/// `tint` lets callers override the default token-driven background.
class MonogramAvatarSpec extends AvatarSpec {
  const MonogramAvatarSpec({required this.source, this.tint});

  final String source;
  final Color? tint;
}

/// Placeholder spec for the upcoming Navii customizable character. Stores the
/// color tokens and expression chosen by the player. Until the Navii art
/// pipeline lands, the rendering widget falls back to a stylized circle.
class NaviiAvatarSpec extends AvatarSpec {
  const NaviiAvatarSpec({
    required this.bodyColor,
    required this.accentColor,
    this.expression = NaviiExpression.smile,
  });

  final Color bodyColor;
  final Color accentColor;
  final NaviiExpression expression;
}

/// Discrete expression poses for `NaviiAvatarSpec`. Maps to a single asset
/// frame today; later phases may animate transitions between poses.
enum NaviiExpression { smile, focus, cheer, idle }
