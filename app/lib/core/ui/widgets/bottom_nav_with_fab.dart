import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// One slot in a `BottomNavWithFab`. Either a normal nav tab (provide
/// [icon] + [label]) or — when [isFab] is true — the center primary action
/// (icon-only, rendered as a raised circular button).
@immutable
class BottomNavItem {
  const BottomNavItem({
    required this.icon,
    this.label = '',
    this.isFab = false,
  });

  final IconData icon;
  final String label;
  final bool isFab;
}

/// Bottom navigation strip with a centered primary action (UI 1 reference).
/// Exactly one item in [items] should set `isFab: true`; that slot is
/// rendered as a raised pill in the primary color. The remaining slots
/// behave as normal nav tabs with selected/unselected token treatment.
///
/// [currentIndex] should NEVER point at the FAB slot — that index is
/// reserved for the primary action and `onTap` is only fired for non-FAB
/// taps. FAB taps go to [onFabTap].
class BottomNavWithFab extends StatelessWidget {
  const BottomNavWithFab({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.onFabTap,
    this.height = 72,
  });

  final List<BottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onFabTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    assert(items.isNotEmpty, 'items must not be empty');
    assert(
      items.where((BottomNavItem i) => i.isFab).length == 1,
      'exactly one BottomNavItem must have isFab: true',
    );
    final tokens = context.arenaTokens;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          top: BorderSide(color: tokens.outline, width: tokens.borderWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: items[i].isFab
                    ? Center(
                        child: _FabSlot(
                          icon: items[i].icon,
                          onTap: onFabTap,
                        ),
                      )
                    : _TabSlot(
                        item: items[i],
                        isSelected: i == currentIndex,
                        onTap: () => onTap(i),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color color =
        isSelected ? tokens.primary : tokens.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(item.icon, color: color, size: 24),
          if (item.label.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FabSlot extends StatelessWidget {
  const _FabSlot({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Material(
      color: tokens.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
