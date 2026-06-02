import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../features/profile/models/avatar_spec.dart';
import '../../config/app_config.dart';
import '../../theme/design_tokens.dart';
import '../../theme/theme_extensions.dart';
import 'monogram_avatar.dart';
import 'navii_svg_loader.dart';

/// Hero avatar used on Profile, Leaderboard podium, and Discover-friends
/// rows. Wraps an `AvatarSpec` body in a gradient ring (default = primary
/// header gradient) and supports an optional bottom-right flag emoji badge.
///
/// Body switching:
/// * `MonogramAvatarSpec` → `MonogramAvatar` (nickname initials).
/// * `NaviiAvatarSpec`     → deterministic Navii mascot SVG fetched via the
///   shared `NaviiSvgLoader`. Falls back to the spec's `fallbackSource`
///   monogram whenever the feature flag is off, the loader is unset, the
///   seed is empty, or the load fails.
class GamifiedAvatar extends StatefulWidget {
  const GamifiedAvatar({
    super.key,
    required this.spec,
    this.diameter = 96,
    this.ringWidth = 3,
    this.ringGradient,
    this.flagEmoji,
  });

  final AvatarSpec spec;
  final double diameter;
  final double ringWidth;

  /// Override the default ring gradient. When null the widget uses
  /// `MedRashGradient.primaryHeader(tokens)`.
  final Gradient? ringGradient;

  /// Optional country flag emoji rendered as a small circular badge at the
  /// bottom-right of the avatar.
  final String? flagEmoji;

  @override
  State<GamifiedAvatar> createState() => _GamifiedAvatarState();
}

class _GamifiedAvatarState extends State<GamifiedAvatar> {
  Future<Uint8List?>? _naviiBytes;
  String? _lastRequestKey;

  void _ensureNaviiRequested(double bodyDiameter, double devicePixelRatio) {
    final AvatarSpec spec = widget.spec;
    if (spec is! NaviiAvatarSpec ||
        !AppConfig.enableNaviiAvatars ||
        globalNaviiSvgLoader == null) {
      _naviiBytes = null;
      _lastRequestKey = null;
      return;
    }
    final String seed = spec.seed.trim();
    if (seed.isEmpty) {
      _naviiBytes = null;
      _lastRequestKey = null;
      return;
    }
    final int pixelSize = (bodyDiameter * devicePixelRatio).round();
    final String key = '$seed::$pixelSize';
    if (key == _lastRequestKey && _naviiBytes != null) return;
    _lastRequestKey = key;
    _naviiBytes = globalNaviiSvgLoader!.load(seed: seed, pixelSize: pixelSize);
  }

  @override
  Widget build(BuildContext context) {
    final ArenaDesignTokens tokens = context.arenaTokens;
    final Gradient ring =
        widget.ringGradient ?? MedRashGradient.primaryHeader(tokens);
    final double bodyDiameter = widget.diameter - (widget.ringWidth * 2);
    final double flagDiameter = widget.diameter * 0.32;
    final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    _ensureNaviiRequested(bodyDiameter, dpr);

    return SizedBox(
      width: widget.diameter,
      height: widget.diameter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: widget.diameter,
            height: widget.diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ring,
            ),
            alignment: Alignment.center,
            child: ClipOval(child: _buildBody(context, tokens, bodyDiameter)),
          ),
          if (widget.flagEmoji != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: flagDiameter,
                height: flagDiameter,
                decoration: BoxDecoration(
                  color: tokens.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tokens.surface,
                    width: widget.ringWidth,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.flagEmoji!,
                  style: TextStyle(fontSize: flagDiameter * 0.65),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ArenaDesignTokens tokens,
    double bodyDiameter,
  ) {
    final AvatarSpec spec = widget.spec;
    switch (spec) {
      case MonogramAvatarSpec(:final String source, :final Color? tint):
        return MonogramAvatar(
          source: source,
          diameter: bodyDiameter,
          backgroundColor: tint ?? tokens.secondary,
          foregroundColor: tokens.onSecondary,
        );
      case NaviiAvatarSpec(
          :final String fallbackSource,
          :final Color? fallbackTint,
        ):
        final Widget fallback = MonogramAvatar(
          source: fallbackSource,
          diameter: bodyDiameter,
          backgroundColor: fallbackTint ?? tokens.secondary,
          foregroundColor: tokens.onSecondary,
        );
        final Future<Uint8List?>? request = _naviiBytes;
        if (request == null) return fallback;
        return FutureBuilder<Uint8List?>(
          future: request,
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
            if (snap.connectionState != ConnectionState.done) return fallback;
            final Uint8List? bytes = snap.data;
            if (bytes == null || bytes.isEmpty) return fallback;
            return SvgPicture.memory(
              bytes,
              width: bodyDiameter,
              height: bodyDiameter,
              fit: BoxFit.cover,
              placeholderBuilder: (_) => fallback,
            );
          },
        );
    }
  }
}
