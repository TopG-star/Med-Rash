import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ignore_for_file: prefer_const_constructors
// Dev-only gallery file — prioritises readability of the showcase blocks
// over micro-optimising every _Section/inner Widget into a const literal.

import '../motion/count_up_number.dart';
import '../motion/press_scale.dart';
import '../motion/stagger_list.dart';
import '../theme/design_tokens.dart';
import '../theme/theme_extensions.dart';
import '../ui/responsive.dart';
import '../ui/skeleton.dart';
import '../ui/widgets/arena_button.dart';
import '../ui/widgets/arena_card.dart';
import '../ui/widgets/arena_chip.dart';
import '../ui/widgets/arena_scaffold.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/monogram_avatar.dart';
import '../ui/widgets/quiz_progress_bar.dart';

/// Dev-only Vibrant Pulse component catalog. Renders every primitive against
/// the current theme with a toggle that previews how it looks under the dark
/// token set. Registered only when `!kReleaseMode` so it never ships in
/// production builds.
class ComponentCatalogPage extends StatefulWidget {
  const ComponentCatalogPage({super.key});

  @override
  State<ComponentCatalogPage> createState() => _ComponentCatalogPageState();
}

class _ComponentCatalogPageState extends State<ComponentCatalogPage> {
  bool _darkPreview = false;

  @override
  Widget build(BuildContext context) {
    assert(
      !kReleaseMode,
      'ComponentCatalogPage must never be reachable in release builds.',
    );

    final ThemeData baseTheme = Theme.of(context);
    final ThemeData previewTheme = _darkPreview
        ? _buildPreviewTheme(baseTheme, ArenaDesignTokens.dark, Brightness.dark)
        : _buildPreviewTheme(baseTheme, ArenaDesignTokens.light, Brightness.light);

    return ArenaScaffold(
      title: 'Component catalog',
      showBack: true,
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.dark_mode_outlined, size: 18),
              Switch.adaptive(
                value: _darkPreview,
                onChanged: (bool value) => setState(() => _darkPreview = value),
              ),
            ],
          ),
        ),
      ],
      child: Theme(
        data: previewTheme,
        child: Container(
          color: previewTheme.scaffoldBackgroundColor,
          child: MedRashConstrainedBody(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Section(
                    title: 'ArenaButton',
                    child: ArenaButton(
                      label: 'Start ranked',
                      icon: Icons.flash_on,
                      onPressed: () {},
                    ),
                  ),
                  _Section(
                    title: 'ArenaCard',
                    child: const ArenaCard(
                      child: Text(
                        'Surface card with hairline outline + flat elevation.',
                      ),
                    ),
                  ),
                  _Section(
                    title: 'ArenaChip',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const <Widget>[
                        ArenaChip(label: 'Cardiology'),
                        ArenaChip(label: 'Live'),
                        ArenaChip(label: 'Ranked'),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'MonogramAvatar',
                    child: Row(
                      children: const <Widget>[
                        MonogramAvatar(source: 'Quiet Heron 314'),
                        SizedBox(width: 12),
                        MonogramAvatar(source: 'SwiftDoctor777', diameter: 56),
                        SizedBox(width: 12),
                        MonogramAvatar(source: 'ada', diameter: 40),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'QuizProgressBar',
                    child: Column(
                      children: const <Widget>[
                        QuizProgressBar(progress: 0.18),
                        SizedBox(height: 8),
                        QuizProgressBar(progress: 0.62),
                        SizedBox(height: 8),
                        QuizProgressBar(progress: 1.0),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'MedRashSkeleton',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const <Widget>[
                        MedRashSkeleton(height: 18),
                        SizedBox(height: 8),
                        MedRashSkeleton(height: 18, width: 220),
                        SizedBox(height: 8),
                        MedRashSkeleton(height: 56, radius: 16),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'MedRashEmptyState',
                    child: MedRashEmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'No ranked attempts yet',
                      body:
                          'Be the first on the board today — a single ranked run unlocks your rank.',
                      ctaLabel: 'Start ranked',
                      onCta: () {},
                    ),
                  ),
                  _Section(
                    title: 'PressScale',
                    child: PressScale(
                      onTap: () {},
                      child: const ArenaCard(
                        child: Text('Press and hold to feel the 0.97 spring.'),
                      ),
                    ),
                  ),
                  _Section(
                    title: 'CountUpNumber',
                    child: CountUpNumber(
                      value: 1280,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                  ),
                  _Section(
                    title: 'StaggerList',
                    child: StaggerList(
                      children: const <Widget>[
                        ArenaCard(child: Text('Row 1 — fades + slides in')),
                        SizedBox(height: 8),
                        ArenaCard(child: Text('Row 2 — 40ms after the first')),
                        SizedBox(height: 8),
                        ArenaCard(child: Text('Row 3 — and so on')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _buildPreviewTheme(
    ThemeData base,
    ArenaDesignTokens tokens,
    Brightness brightness,
  ) {
    final ColorScheme scheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: tokens.primary,
            onPrimary: tokens.textPrimary,
            primaryContainer: tokens.primarySoft,
            onPrimaryContainer: tokens.primaryStrong,
            secondary: tokens.secondary,
            onSecondary: tokens.onSecondary,
            surface: tokens.surface,
            onSurface: tokens.textPrimary,
            surfaceContainerHighest: tokens.surfaceContainer,
            outline: tokens.outline,
            outlineVariant: tokens.outlineMuted,
            error: tokens.error,
            onError: tokens.textPrimary,
          )
        : ColorScheme.light(
            primary: tokens.primary,
            onPrimary: Colors.white,
            primaryContainer: tokens.primarySoft,
            onPrimaryContainer: tokens.primaryStrong,
            secondary: tokens.secondary,
            onSecondary: tokens.onSecondary,
            surface: tokens.surface,
            onSurface: tokens.textPrimary,
            surfaceContainerHighest: tokens.surfaceContainer,
            outline: tokens.outline,
            outlineVariant: tokens.outlineMuted,
            error: tokens.error,
            onError: Colors.white,
          );

    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: tokens.background,
      colorScheme: scheme,
      textTheme: base.textTheme.apply(
        bodyColor: tokens.textPrimary,
        displayColor: tokens.textPrimary,
      ),
      extensions: <ThemeExtension<dynamic>>[
        ArenaTheme(tokens: tokens),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
