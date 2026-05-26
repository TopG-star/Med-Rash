import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/ui/responsive.dart';
import '../../../core/ui/widgets/arena_card.dart';
import '../../../core/ui/widgets/arena_chip.dart';
import '../../../core/ui/widgets/arena_scaffold.dart';

/// Design-only placeholder for the Badges & Achievements surface.
///
/// No schema exists yet — every tile shown here is a static preview marked
/// "Coming soon" so users can see the direction without us committing to
/// criteria. Real entries land once the badges schema is defined.
class BadgesPage extends StatelessWidget {
  const BadgesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Badges',
      showBack: true,
      bottomNav: true,
      child: MedRashConstrainedBody(
        child: ListView(
          children: const <Widget>[
            _BadgesHero(),
            SizedBox(height: MedRashSpace.lg),
            _SectionHeader(label: 'COLLECTION'),
            SizedBox(height: MedRashSpace.sm),
            _BadgeGrid(),
            SizedBox(height: MedRashSpace.xl),
            _SectionHeader(label: 'TIERS'),
            SizedBox(height: MedRashSpace.sm),
            _TierStrip(),
            SizedBox(height: MedRashSpace.lg),
          ],
        ),
      ),
    );
  }
}

class _BadgesHero extends StatelessWidget {
  const _BadgesHero();

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusLarge + 4),
              gradient: LinearGradient(
                colors: <Color>[
                  tokens.primary.withValues(alpha: 0.25),
                  tokens.secondary.withValues(alpha: 0.25),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        ArenaCard(
          padding: const EdgeInsets.all(MedRashSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: tokens.secondary,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: tokens.secondary.withValues(alpha: 0.45),
                          blurRadius: 18,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: tokens.onSecondary,
                      size: MedRashIconSize.xl,
                    ),
                  ),
                  const SizedBox(width: MedRashSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Earn Your Badges',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w800,
                                    color: tokens.textPrimary,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        const ArenaChip(label: 'COMING SOON'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MedRashSpace.md),
              Text(
                'Badges celebrate milestones across ranked attempts, learning streaks, and CME completion. The catalog is still being tuned — these previews show the direction.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Padding(
      padding: const EdgeInsets.only(left: MedRashSpace.xs),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              color: tokens.textSecondary,
              letterSpacing: 1.0,
            ),
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid();

  static const List<_BadgePreview> _badges = <_BadgePreview>[
    _BadgePreview(
      title: 'First Win',
      tier: _BadgeTier.bronze,
      icon: Icons.bolt_rounded,
      hint: 'Win your first ranked attempt.',
    ),
    _BadgePreview(
      title: 'Streak x3',
      tier: _BadgeTier.silver,
      icon: Icons.local_fire_department_rounded,
      hint: 'Three perfect attempts in a row.',
    ),
    _BadgePreview(
      title: 'Top 10',
      tier: _BadgeTier.gold,
      icon: Icons.emoji_events_rounded,
      hint: 'Land in the monthly Top 10.',
    ),
    _BadgePreview(
      title: 'CME 25',
      tier: _BadgeTier.bronze,
      icon: Icons.school_rounded,
      hint: 'Complete 25 CME questions.',
    ),
    _BadgePreview(
      title: 'Host x5',
      tier: _BadgeTier.silver,
      icon: Icons.podcasts_rounded,
      hint: 'Host five live sessions.',
    ),
    _BadgePreview(
      title: 'Legend',
      tier: _BadgeTier.gold,
      icon: Icons.workspace_premium_rounded,
      hint: 'Reach #1 on the all-time board.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int crossAxisCount = constraints.maxWidth >= 600 ? 4 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: MedRashSpace.md,
            mainAxisSpacing: MedRashSpace.md,
            childAspectRatio: 0.78,
          ),
          itemCount: _badges.length,
          itemBuilder: (BuildContext context, int index) =>
              _BadgeTile(badge: _badges[index]),
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final _BadgePreview badge;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final _TierStyle style = _styleFor(context, badge.tier);

    return Tooltip(
      message: badge.hint,
      child: ArenaCard(
        padding: const EdgeInsets.symmetric(
          horizontal: MedRashSpace.sm,
          vertical: MedRashSpace.md,
        ),
        child: Column(
          children: <Widget>[
            _LockedRing(style: style, icon: badge.icon),
            const SizedBox(height: MedRashSpace.sm),
            Text(
              badge.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              style.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: style.accent,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedRing extends StatelessWidget {
  const _LockedRing({required this.style, required this.icon});

  final _TierStyle style;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.surface,
              border: Border.all(color: style.accent, width: 2),
            ),
            alignment: Alignment.center,
            child: Opacity(
              opacity: 0.45,
              child: Icon(icon, color: style.accent, size: MedRashIconSize.xl),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.surface,
                border:
                    Border.all(color: tokens.outline, width: tokens.borderWidth),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_rounded,
                size: 14,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierStrip extends StatelessWidget {
  const _TierStrip();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(child: _TierCard(tier: _BadgeTier.bronze)),
        SizedBox(width: MedRashSpace.sm),
        Expanded(child: _TierCard(tier: _BadgeTier.silver)),
        SizedBox(width: MedRashSpace.sm),
        Expanded(child: _TierCard(tier: _BadgeTier.gold)),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier});

  final _BadgeTier tier;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final _TierStyle style = _styleFor(context, tier);
    return ArenaCard(
      color: style.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: MedRashSpace.sm,
        vertical: MedRashSpace.md,
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.accent,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.workspace_premium_rounded,
              color: tokens.surface,
              size: MedRashIconSize.md,
            ),
          ),
          const SizedBox(height: MedRashSpace.xs),
          Text(
            style.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  color: style.accent,
                  letterSpacing: 0.6,
                ),
          ),
        ],
      ),
    );
  }
}

enum _BadgeTier { bronze, silver, gold }

class _BadgePreview {
  const _BadgePreview({
    required this.title,
    required this.tier,
    required this.icon,
    required this.hint,
  });

  final String title;
  final _BadgeTier tier;
  final IconData icon;
  final String hint;
}

class _TierStyle {
  const _TierStyle({
    required this.label,
    required this.accent,
    required this.surface,
  });

  final String label;
  final Color accent;
  final Color surface;
}

_TierStyle _styleFor(BuildContext context, _BadgeTier tier) {
  final tokens = context.arenaTokens;
  switch (tier) {
    case _BadgeTier.bronze:
      return const _TierStyle(
        label: 'BRONZE',
        accent: Color(0xFFB87333),
        surface: Color(0xFFFFEBD6),
      );
    case _BadgeTier.silver:
      return _TierStyle(
        label: 'SILVER',
        accent: tokens.tertiary,
        surface: tokens.primarySoft,
      );
    case _BadgeTier.gold:
      return _TierStyle(
        label: 'GOLD',
        accent: tokens.onSecondary,
        surface: tokens.secondary,
      );
  }
}
