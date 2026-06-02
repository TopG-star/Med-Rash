import 'package:flutter/material.dart';

/// Sealed contract for what fills the body of a `GamifiedAvatar`.
///
/// MedRash currently ships nickname-only profiles (no PII photos), so the
/// fallback body is a `MonogramAvatarSpec` rendering 1–2 initials.
/// `NaviiAvatarSpec` carries a deterministic seed (Supabase
/// `participantId`); the rendering widget fetches the matching mascot SVG
/// from the self-hosted Navii endpoint and falls back to monogram on
/// network failure, missing seed, or disabled feature flag.
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

/// Seed-based Navii mascot spec. `seed` is the stable per-user identifier
/// (Supabase `participantId`); same seed always produces the same avatar.
/// `fallbackSource` is the monogram source used when the Navii SVG cannot
/// be loaded (offline, 4xx/5xx, feature flag off).
class NaviiAvatarSpec extends AvatarSpec {
  const NaviiAvatarSpec({
    required this.seed,
    required this.fallbackSource,
    this.fallbackTint,
  });

  /// Stable per-user seed. Trimmed at the call site; lowercased only when
  /// it matches a UUID shape (server-side normalization mirrors this).
  final String seed;

  /// Nickname (or free string) used to render the monogram fallback so the
  /// avatar is never empty.
  final String fallbackSource;

  /// Optional tint forwarded to the monogram fallback.
  final Color? fallbackTint;
}
