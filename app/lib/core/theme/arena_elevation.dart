import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Ambient, purple-tinted elevation system that replaces the legacy
/// brutalist hard-shadow offset. Use these helpers to ensure cards,
/// floating CTAs, and overlays carry a consistent depth vocabulary.
class ArenaElevation {
  const ArenaElevation._();

  /// Subtle resting elevation for cards and chips.
  static List<BoxShadow> level1(ArenaDesignTokens tokens) => <BoxShadow>[
        BoxShadow(
          color: tokens.shadow.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// Mid elevation for hovered cards, sticky headers, and primary CTAs.
  static List<BoxShadow> level2(ArenaDesignTokens tokens) => <BoxShadow>[
        BoxShadow(
          color: tokens.shadow.withValues(alpha: 0.12),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  /// High elevation for modal sheets, dialogs, and floating overlays.
  static List<BoxShadow> level3(ArenaDesignTokens tokens) => <BoxShadow>[
        BoxShadow(
          color: tokens.shadow.withValues(alpha: 0.18),
          blurRadius: 36,
          offset: const Offset(0, 16),
        ),
      ];
}
