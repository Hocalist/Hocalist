import 'package:flutter/material.dart';

import '../../theme/buyer_ui_foundation.dart';
import 'approved_replica_metrics.dart';

class ApprovedBuyerNavigation {
  const ApprovedBuyerNavigation({
    required this.onHome,
    required this.onHocatrends,
    required this.onOffers,
    required this.onChats,
    required this.onMore,
  });

  final VoidCallback onHome;
  final VoidCallback onHocatrends;
  final VoidCallback onOffers;
  final VoidCallback onChats;
  final VoidCallback onMore;
}

enum ApprovedBuyerNavSelection { home, hocatrends, offers, chats, more }

class BuyerBottomNavigation extends StatelessWidget {
  const BuyerBottomNavigation({
    required this.selected,
    required this.callbacks,
    this.accentColor = BuyerUiTokens.action,
    this.navigationKey = const ValueKey('approved-bottom-navigation'),
    this.contentKey = const ValueKey('approved-bottom-navigation-content'),
    super.key,
  });

  final ApprovedBuyerNavSelection selected;
  final ApprovedBuyerNavigation callbacks;
  final Color accentColor;
  final Key navigationKey;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final items = <_BuyerNavItem>[
      _BuyerNavItem(
        ApprovedBuyerNavSelection.home,
        'Home',
        'assets/buyer_nav/buyer-nav-home.png',
        callbacks.onHome,
      ),
      _BuyerNavItem(
        ApprovedBuyerNavSelection.hocatrends,
        'Hocatrends',
        'assets/buyer_nav/buyer-nav-hocatrends.png',
        callbacks.onHocatrends,
      ),
      _BuyerNavItem(
        ApprovedBuyerNavSelection.offers,
        'Offers',
        'assets/buyer_nav/buyer-nav-offers.png',
        callbacks.onOffers,
      ),
      _BuyerNavItem(
        ApprovedBuyerNavSelection.chats,
        'Chats',
        'assets/buyer_nav/buyer-nav-chats.png',
        callbacks.onChats,
      ),
      _BuyerNavItem(
        ApprovedBuyerNavSelection.more,
        'More',
        'assets/buyer_nav/buyer-nav-more.png',
        callbacks.onMore,
      ),
    ];
    final accessibilityHeightGrowth = ((metrics.textScale - 1) * 24)
        .clamp(0.0, 24.0)
        .toDouble();
    final barHeight = metrics.accessibilityReflow
        ? 66.0 + accessibilityHeightGrowth
        : metrics.geometry(58.5);

    return DecoratedBox(
      key: navigationKey,
      decoration: const BoxDecoration(
        color: BuyerUiTokens.surface,
        border: Border(top: BorderSide(color: BuyerUiTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            key: contentKey,
            width: metrics.contentMaxWidth,
            height: barHeight,
            child: Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: _BuyerBottomNavItem(
                      item: item,
                      selected: item.selection == selected,
                      accentColor: accentColor,
                      metrics: metrics,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BuyerBottomNavItem extends StatelessWidget {
  const _BuyerBottomNavItem({
    required this.item,
    required this.selected,
    required this.accentColor,
    required this.metrics,
  });

  final _BuyerNavItem item;
  final bool selected;
  final Color accentColor;
  final ApprovedReplicaMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accentColor : BuyerUiTokens.muted;
    return Semantics(
      selected: selected,
      label: item.label,
      button: true,
      child: InkWell(
        key: Key('approved-nav-${item.label.toLowerCase()}'),
        onTap: item.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.geometry(2.5),
            vertical: metrics.geometry(3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: metrics.artSize(selected ? 52 : 42),
                height: metrics.artSize(29.5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? BuyerUiTokens.activeSurface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(metrics.geometry(8)),
                ),
                child: BuyerAssetIcon(
                  asset: item.asset,
                  slotSize: metrics.artSize(
                    selected
                        ? BuyerIconTokens.navigation
                        : BuyerIconTokens.navigation - 1,
                  ),
                  color: color,
                ),
              ),
              SizedBox(height: metrics.geometry(1.5)),
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: metrics.accessibilityReflow
                    ? TextOverflow.ellipsis
                    : TextOverflow.fade,
                textAlign: TextAlign.center,
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.navigationLabel,
                  color: color,
                  weight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _BuyerNavItem {
  const _BuyerNavItem(this.selection, this.label, this.asset, this.onTap);

  final ApprovedBuyerNavSelection selection;
  final String label;
  final String asset;
  final VoidCallback onTap;
}
