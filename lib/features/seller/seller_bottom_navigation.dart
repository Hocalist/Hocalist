import 'package:flutter/material.dart';

import '../../theme/seller_ui_foundation.dart';

enum SellerNavDestination { home, leads, meets, chats, more }

class SellerNavigationCallbacks {
  const SellerNavigationCallbacks({
    required this.onHome,
    required this.onLeads,
    required this.onMeets,
    required this.onChats,
    required this.onMore,
  });

  final VoidCallback onHome;
  final VoidCallback onLeads;
  final VoidCallback onMeets;
  final VoidCallback onChats;
  final VoidCallback onMore;
}

class SellerBottomNavigation extends StatelessWidget {
  const SellerBottomNavigation({
    required this.selected,
    required this.callbacks,
    this.navigationKey,
    super.key,
  });

  final SellerNavDestination? selected;
  final SellerNavigationCallbacks callbacks;
  final Key? navigationKey;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context);
    final items =
        <
          ({
            SellerNavDestination destination,
            String label,
            String asset,
            double opticalSize,
            double verticalOffset,
            VoidCallback onTap,
          })
        >[
          (
            destination: SellerNavDestination.home,
            label: 'Home',
            asset: SellerAssets.navHome,
            opticalSize: 25,
            verticalOffset: 0,
            onTap: callbacks.onHome,
          ),
          (
            destination: SellerNavDestination.leads,
            label: 'Leads',
            asset: SellerAssets.navLeads,
            opticalSize: 42,
            verticalOffset: -6,
            onTap: callbacks.onLeads,
          ),
          (
            destination: SellerNavDestination.meets,
            label: 'Meets',
            asset: SellerAssets.navMeets,
            opticalSize: 34,
            verticalOffset: -3,
            onTap: callbacks.onMeets,
          ),
          (
            destination: SellerNavDestination.chats,
            label: 'Chats',
            asset: SellerAssets.navChats,
            opticalSize: 44,
            verticalOffset: -7,
            onTap: callbacks.onChats,
          ),
          (
            destination: SellerNavDestination.more,
            label: 'More',
            asset: SellerAssets.navMore,
            opticalSize: 25,
            verticalOffset: 0,
            onTap: callbacks.onMore,
          ),
        ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final indicatorWidth =
            metrics?.geometry(narrow ? 48 : 54) ?? (narrow ? 48.0 : 54.0);
        final horizontal =
            metrics?.geometry(narrow ? 2 : 5) ?? (narrow ? 2.0 : 5.0);
        final top = metrics?.geometry(5) ?? 5.0;
        final bottom = metrics?.geometry(3) ?? 3.0;
        return Material(
          key: navigationKey ?? const Key('sellerBottomNavigation'),
          color: SellerUiColors.white,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: SellerUiColors.line)),
            ),
            child: SafeArea(
              top: false,
              minimum: EdgeInsets.only(bottom: bottom),
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 0),
                child: Row(
                  children: [
                    for (final item in items)
                      Expanded(
                        child: _SellerNavigationItem(
                          destination: item.destination,
                          label: item.label,
                          asset: item.asset,
                          selected: selected == item.destination,
                          opticalSize:
                              metrics?.artSize(
                                item.opticalSize * (narrow ? .92 : 1),
                              ) ??
                              item.opticalSize * (narrow ? .92 : 1),
                          verticalOffset:
                              metrics?.geometry(item.verticalOffset) ??
                              item.verticalOffset,
                          indicatorWidth: indicatorWidth,
                          onTap: item.onTap,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SellerNavigationItem extends StatelessWidget {
  const _SellerNavigationItem({
    required this.destination,
    required this.label,
    required this.asset,
    required this.selected,
    required this.opticalSize,
    required this.verticalOffset,
    required this.indicatorWidth,
    required this.onTap,
  });

  final SellerNavDestination destination;
  final String label;
  final String asset;
  final bool selected;
  final double opticalSize;
  final double verticalOffset;
  final double indicatorWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context);
    final activeColor = SellerUiColors.primaryBright;
    final inactiveColor = SellerUiColors.body;
    final color = selected ? activeColor : inactiveColor;
    final vertical = metrics?.geometry(3) ?? 3.0;
    final indicatorRadius = metrics?.geometry(12) ?? 12.0;

    return Semantics(
      selected: selected,
      button: true,
      label: '$label tab',
      child: InkWell(
        key: Key('sellerNav$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(indicatorRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vertical),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: indicatorWidth,
                height: metrics?.geometry(34) ?? 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? SellerUiColors.lavender
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(indicatorRadius),
                ),
                child: Transform.translate(
                  offset: Offset(0, verticalOffset),
                  child: Image.asset(
                    key: Key('sellerNav${label}Icon'),
                    asset,
                    width: opticalSize,
                    height: opticalSize,
                    fit: BoxFit.contain,
                    color: color,
                    colorBlendMode: BlendMode.srcIn,
                    semanticLabel: '$label navigation icon',
                  ),
                ),
              ),
              SizedBox(height: metrics?.geometry(1) ?? 1),
              Text(
                label,
                maxLines: 1,
                style: metrics == null
                    ? TextStyle(
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.labelSmall?.fontFamily,
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: color,
                      )
                    : sellerText(
                        metrics,
                        10,
                        weight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: color,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
