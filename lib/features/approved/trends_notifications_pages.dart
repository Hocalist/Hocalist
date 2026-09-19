import 'package:flutter/material.dart';

import '../../theme/accessibility_visuals.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/control_foundation.dart';
import 'approved_replica_metrics.dart';
import 'onboarding_home_pages.dart';

const _approvedPrimary = BuyerUiTokens.trendsText;
const _approvedAction = BuyerUiTokens.trendsAction;
const _approvedMuted = BuyerUiTokens.muted;
const _approvedGreen = Color(0xff15952e);
const _approvedGold = BuyerUiTokens.rewardGold;
const _approvedBorder = BuyerUiTokens.border;
const _approvedAssetRoot = 'assets/approved_trends_notifications';

Color _pageText(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge?.color ?? _approvedPrimary;

Color _pageMuted(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.color ?? _approvedMuted;

Color _pageSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

ApprovedReplicaMetrics _replicaMetrics(BuildContext context) {
  return ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        availableWidth: MediaQuery.sizeOf(context).width,
        textScaler: MediaQuery.textScalerOf(context),
      );
}

double _pickedSellerFontSize(
  ApprovedReplicaMetrics metrics,
  double referencePixels,
) {
  final scaled = metrics.fontSize(referencePixels);
  if (metrics.screenshotLocked) return scaled;
  final readableFloor = switch (referencePixels) {
    <= 11 => 10.0,
    <= 13 => 10.5,
    <= 14.5 => 11.5,
    _ => 12.0,
  };
  return scaled < readableFloor ? readableFloor : scaled;
}

double _sellerDimension(
  ApprovedReplicaMetrics metrics,
  double referencePixels, {
  required double floor,
}) {
  final scaled = metrics.geometry(referencePixels);
  if (metrics.screenshotLocked) return scaled;
  return scaled < floor ? floor : scaled;
}

class _ApprovedReplicaSurface extends StatelessWidget {
  const _ApprovedReplicaSurface({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('approved-replica-content'),
          constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
          child: Builder(builder: builder),
        ),
      ),
    );
  }
}

Widget _approvedAsset(
  String name, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  String? semanticLabel,
}) {
  if (name.startsWith('transparent/') &&
      width != null &&
      height != null &&
      (width - height).abs() < .01 &&
      fit == BoxFit.contain) {
    return BuyerAssetIcon(
      asset: '$_approvedAssetRoot/$name',
      slotSize: width,
      semanticLabel: semanticLabel,
    );
  }
  return Image.asset(
    '$_approvedAssetRoot/$name',
    width: width,
    height: height,
    fit: fit,
    filterQuality: FilterQuality.high,
    semanticLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) {
      return SizedBox(
        width: width,
        height: height,
        child: semanticLabel == null
            ? null
            : Semantics(
                label: '$semanticLabel unavailable',
                child: const SizedBox.shrink(),
              ),
      );
    },
  );
}

/// Screenshot-approved Hocatrends body. The app shell continues to own its
/// global header, scrolling, and buyer bottom navigation.
class ApprovedPublicHocatrendsPage extends StatelessWidget {
  const ApprovedPublicHocatrendsPage({
    required this.accent,
    required this.onSeeSellers,
    required this.onHome,
    required this.onHocatrends,
    required this.onWinners,
    required this.onSignup,
    super.key,
  });

  final Color accent;
  final VoidCallback onSeeSellers;
  final VoidCallback onHome;
  final VoidCallback onHocatrends;
  final VoidCallback onWinners;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Material(
      color: const Color(0xfffbfcff),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('public-hocatrends-scroll'),
                padding: metrics.geometryInsets(
                  const EdgeInsets.fromLTRB(16, 10, 16, 24),
                ),
                children: [
                  ApprovedHocatrendsPage(
                    accent: accent,
                    onSeeSellers: onSeeSellers,
                  ),
                ],
              ),
            ),
            ApprovedNoAccountBottomNavigation(
              selectedIndex: 1,
              onHome: onHome,
              onHocatrends: onHocatrends,
              onWinners: onWinners,
              onSignup: onSignup,
            ),
          ],
        ),
      ),
    );
  }
}

class ApprovedHocatrendsPage extends StatefulWidget {
  const ApprovedHocatrendsPage({
    required this.accent,
    required this.onSeeSellers,
    super.key,
  });

  final Color accent;
  final VoidCallback onSeeSellers;

  @override
  State<ApprovedHocatrendsPage> createState() => _ApprovedHocatrendsPageState();
}

enum _TrendCompetitionFilter { all, veryHigh, medium }

class _ApprovedHocatrendsPageState extends State<ApprovedHocatrendsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _TrendCompetitionFilter _competition = _TrendCompetitionFilter.all;

  List<_ApprovedTrendData> get _visibleCategories {
    final query = _query.trim().toLowerCase();
    return _trendCategories.where((item) {
      final matchesQuery =
          query.isEmpty ||
          '${item.title} ${item.competition} ${item.sellerCopy}'
              .toLowerCase()
              .contains(query);
      final matchesCompetition = switch (_competition) {
        _TrendCompetitionFilter.all => true,
        _TrendCompetitionFilter.veryHigh => item.competition == 'Very High',
        _TrendCompetitionFilter.medium => item.competition == 'Medium',
      };
      return matchesQuery && matchesCompetition;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    var draft = _competition;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => BuyerModalSheet(
          title: 'Filter opportunities',
          subtitle: 'Choose which competition levels you want to see.',
          icon: Icons.tune_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _TrendCompetitionFilter.values)
                    HocalistFilterChip(
                      role: HocalistControlRole.buyer,
                      label: switch (option) {
                        _TrendCompetitionFilter.all => 'All levels',
                        _TrendCompetitionFilter.veryHigh => 'Very high',
                        _TrendCompetitionFilter.medium => 'Medium',
                      },
                      selected: draft == option,
                      onSelected: (_) => setSheetState(() => draft = option),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              BuyerPrimaryButton(
                label: 'Apply filters',
                onPressed: () {
                  setState(() => _competition = draft);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSearch() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => BuyerModalSheet(
          title: 'Search Hocatrends',
          subtitle: 'Find products, services, or competitive categories.',
          icon: Icons.search_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HocalistSearchField(
                key: const Key('approved-hocatrends-search-input'),
                role: HocalistControlRole.buyer,
                controller: _searchController,
                hintText: 'Search products or services',
                autofocus: true,
                onChanged: (value) {
                  setState(() => _query = value);
                  setSheetState(() {});
                },
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 14),
              BuyerPrimaryButton(
                label: 'Show results',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ApprovedReplicaSurface(
      builder: (context) {
        final metrics = _replicaMetrics(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedTrendsHero(accent: widget.accent),
            SizedBox(height: metrics.geometry(8)),
            const _ApprovedSavingsNotice(),
            SizedBox(height: metrics.geometry(10)),
            _ApprovedSearchField(
              query: _query,
              onSearch: _openSearch,
              onFilter: _openFilters,
              filtersActive: _competition != _TrendCompetitionFilter.all,
            ),
            SizedBox(height: metrics.geometry(6)),
            _ApprovedCompetitiveHeader(accent: widget.accent),
            SizedBox(height: metrics.geometry(6)),
            if (_visibleCategories.isEmpty)
              _ApprovedTrendsEmptyState(
                onClear: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _competition = _TrendCompetitionFilter.all;
                  });
                },
              )
            else
              for (
                var index = 0;
                index < _visibleCategories.length;
                index++
              ) ...[
                _ApprovedTrendCard(
                  item: _visibleCategories[index],
                  accent: widget.accent,
                  onSeeSellers: widget.onSeeSellers,
                ),
                if (index != _visibleCategories.length - 1)
                  SizedBox(height: metrics.geometry(8)),
              ],
          ],
        );
      },
    );
  }
}

class _ApprovedTrendsHero extends StatelessWidget {
  const _ApprovedTrendsHero({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _replicaMetrics(context);
        final stack = constraints.maxWidth < 280 && metrics.textScale >= 1.6;
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Saving',
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.displayTitle,
                color: _pageText(context),
                height: metrics.lineHeight(
                  referenceFontSize: 20,
                  referenceLineHeight: 21,
                ),
              ),
            ),
            SizedBox(width: metrics.geometry(4)),
            Text(
              'Opportunities',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: _approvedAction,
                fontSize: metrics.fontSize(20),
                fontWeight: FontWeight.w800,
                height: metrics.lineHeight(
                  referenceFontSize: 20,
                  referenceLineHeight: 21,
                ),
              ),
            ),
            SizedBox(width: metrics.geometry(4)),
            _approvedAsset(
              'transparent/trend-up.png',
              width: metrics.geometry(19),
              height: metrics.geometry(18),
            ),
          ],
        );
        final copy = Column(
          key: const ValueKey('approved-saving-opportunities-copy'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (metrics.textScale <= 1.3)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: title,
              )
            else
              Wrap(
                spacing: metrics.geometry(4),
                runSpacing: metrics.geometry(2),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: title.children,
              ),
            SizedBox(height: metrics.geometry(8)),
            Text(
              'Explore verified sellers offering\ndiscounts on products & services.',
              key: const ValueKey('approved-saving-opportunities-description'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _pageMuted(context),
                fontSize: metrics.fontSize(12),
                fontWeight: FontWeight.w500,
                height: metrics.lineHeight(
                  referenceFontSize: 12,
                  referenceLineHeight: 16.2,
                ),
              ),
            ),
          ],
        );
        final art = _approvedAsset(
          'saving-gift.png',
          width: metrics.geometry(stack ? 120 : 150),
          height: metrics.geometry(stack ? 92 : 108),
          semanticLabel: 'Gift box and savings coin',
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              SizedBox(height: metrics.geometry(4)),
              Align(
                key: const ValueKey('approved-saving-opportunities-art'),
                alignment: Alignment.centerRight,
                child: art,
              ),
            ],
          );
        }

        return SizedBox(
          key: const ValueKey('approved-saving-opportunities-hero'),
          height: metrics.geometry(104),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: metrics.geometry(18),
                width: metrics.geometry(230),
                child: copy,
              ),
              Positioned(
                right: metrics.geometry(-4),
                top: metrics.geometry(-2),
                child: SizedBox(
                  key: const ValueKey('approved-saving-opportunities-art'),
                  child: art,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ApprovedSavingsNotice extends StatelessWidget {
  const _ApprovedSavingsNotice();

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      padding: metrics.geometryInsets(const EdgeInsets.fromLTRB(10, 9, 12, 9)),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : const Color(0xfff5f2ff),
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              metrics.accessibilityReflow && constraints.maxWidth < 370;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Skip the Rewards & save on current offers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _pageText(context),
                  fontSize: metrics.fontSize(12),
                  fontWeight: FontWeight.w800,
                  height: metrics.lineHeight(
                    referenceFontSize: 12,
                    referenceLineHeight: 14.4,
                  ),
                ),
              ),
              SizedBox(height: metrics.geometry(3)),
              Text(
                'Hocatrends shows exclusive offers and discounts created by sellers for other buyers.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _pageMuted(context),
                  fontSize: metrics.fontSize(10.5),
                  height: metrics.lineHeight(
                    referenceFontSize: 10.5,
                    referenceLineHeight: 13.125,
                  ),
                ),
              ),
            ],
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _approvedAsset(
                  'transparent/trend-shield.png',
                  width: metrics.geometry(42),
                  height: metrics.geometry(42),
                ),
                SizedBox(height: metrics.geometry(6)),
                copy,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _approvedAsset(
                'transparent/trend-shield.png',
                width: metrics.geometry(42),
                height: metrics.geometry(42),
              ),
              SizedBox(width: metrics.geometry(10)),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedSearchField extends StatelessWidget {
  const _ApprovedSearchField({
    required this.query,
    required this.onSearch,
    required this.onFilter,
    required this.filtersActive,
  });

  final String query;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  final bool filtersActive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final metrics = _replicaMetrics(context);
        return Semantics(
          textField: true,
          label: 'Search products or services',
          child: InkWell(
            key: const Key('approved-hocatrends-search'),
            onTap: onSearch,
            borderRadius: BorderRadius.circular(metrics.geometry(9)),
            child: Container(
              constraints: BoxConstraints(minHeight: metrics.geometry(42)),
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
              decoration: BoxDecoration(
                color: _pageSurface(context),
                borderRadius: BorderRadius.circular(metrics.geometry(9)),
                border: Border.all(
                  color: const Color(0xffdedcef),
                  width: metrics.geometry(1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x0c0b1047),
                    blurRadius: metrics.geometry(8),
                    offset: Offset(0, metrics.geometry(3)),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _approvedAsset(
                    'transparent/trend-search.png',
                    width: metrics.geometry(22),
                    height: metrics.geometry(24),
                  ),
                  SizedBox(width: metrics.geometry(9)),
                  Expanded(
                    child: Text(
                      query.isEmpty ? 'Search products or services' : query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: query.isEmpty
                            ? _pageMuted(context)
                            : _pageText(context),
                        fontSize: metrics.fontSize(13),
                        fontWeight: query.isEmpty
                            ? FontWeight.w500
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.geometry(8)),
                  Semantics(
                    button: true,
                    label: filtersActive
                        ? 'Change active filters'
                        : 'Filter opportunities',
                    child: GestureDetector(
                      key: const Key('approved-hocatrends-filter'),
                      onTap: onFilter,
                      behavior: HitTestBehavior.opaque,
                      child: _approvedAsset(
                        'transparent/trend-filter.png',
                        width: metrics.geometry(23),
                        height: metrics.geometry(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ApprovedTrendsEmptyState extends StatelessWidget {
  const _ApprovedTrendsEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: const Key('approved-hocatrends-empty'),
      padding: EdgeInsets.all(metrics.spacing(18)),
      decoration: BoxDecoration(
        color: _pageSurface(context),
        border: Border.all(color: _approvedBorder),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: metrics.artSize(32),
            color: _approvedAction,
          ),
          SizedBox(height: metrics.spacing(7)),
          Text(
            'No matching opportunities',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _pageText(context),
              fontSize: metrics.fontSize(14),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: metrics.spacing(4)),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear search and filters'),
          ),
        ],
      ),
    );
  }
}

class _ApprovedCompetitiveHeader extends StatelessWidget {
  const _ApprovedCompetitiveHeader({required this.accent});

  final Color accent;

  Future<void> _openHowItWorks(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => BuyerModalSheet(
        title: 'How Hocatrends works',
        subtitle:
            'Compare opportunities where sellers are competing for buyers.',
        icon: Icons.trending_up_rounded,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ApprovedHowItWorksPoint(
              icon: Icons.insights_outlined,
              title: 'Competition level',
              body:
                  'Shows how actively sellers are competing in each category.',
            ),
            SizedBox(height: 10),
            _ApprovedHowItWorksPoint(
              icon: Icons.savings_outlined,
              title: 'Savings opportunity',
              body:
                  'Open a category to compare current seller offers and savings.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final metrics = _replicaMetrics(context);
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _approvedAsset(
              'transparent/competitive-flame.png',
              width: metrics.geometry(16),
              height: metrics.geometry(22),
            ),
            SizedBox(width: metrics.geometry(5)),
            Flexible(
              child: Text(
                'Most Competitive Categories Today',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _pageText(context),
                  fontSize: metrics.fontSize(11.5),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(width: metrics.geometry(4)),
            _approvedAsset(
              'transparent/trend-info.png',
              width: metrics.geometry(13),
              height: metrics.geometry(15),
            ),
          ],
        );
        final action = TextButton(
          onPressed: () => _openHowItWorks(context),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            minimumSize: Size(metrics.geometry(44), metrics.geometry(36)),
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(horizontal: 3),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: TextStyle(
              fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
              fontSize: metrics.fontSize(11.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('How it works'),
        );
        return Row(
          children: [
            Expanded(child: title),
            SizedBox(width: metrics.geometry(4)),
            action,
          ],
        );
      },
    );
  }
}

class _ApprovedHowItWorksPoint extends StatelessWidget {
  const _ApprovedHowItWorksPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: metrics.artSize(20), color: _approvedAction),
        SizedBox(width: metrics.spacing(9)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _pageText(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                body,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: _pageMuted(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApprovedTrendCard extends StatelessWidget {
  const _ApprovedTrendCard({
    required this.item,
    required this.accent,
    required this.onSeeSellers,
  });

  final _ApprovedTrendData item;
  final Color accent;
  final VoidCallback onSeeSellers;

  @override
  Widget build(BuildContext context) {
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, _) {
        return Container(
          key: ValueKey('approved-trend-card-${item.rank}'),
          constraints: BoxConstraints(minHeight: metrics.geometry(84)),
          padding: metrics.geometryInsets(
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          decoration: BoxDecoration(
            color: _pageSurface(context),
            borderRadius: BorderRadius.circular(metrics.geometry(9)),
            border: Border.all(
              color: _approvedBorder,
              width: metrics.geometry(1),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x0c0b1047),
                blurRadius: metrics.geometry(8),
                offset: Offset(0, metrics.geometry(3)),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stackAction =
                  constraints.maxWidth < 220 || metrics.accessibilityReflow;
              final imageSize = metrics.geometry(58);
              final details = _ApprovedTrendDetails(item: item, accent: accent);
              final leading = Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ApprovedRankBadge(item: item),
                  SizedBox(width: metrics.geometry(6)),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(metrics.geometry(6)),
                    child: _approvedAsset(
                      item.image,
                      width: imageSize,
                      height: imageSize,
                      fit: BoxFit.contain,
                      semanticLabel: item.title,
                    ),
                  ),
                ],
              );
              final button = _ApprovedTrendAction(
                background: accessibility.backgroundOr(accent),
                foreground: accessibility.foregroundOr(Colors.white),
                radius: metrics.geometry(accessibility.radiusOr(7)),
                borderWidth: accessibility.usesHighContrastButton
                    ? metrics.geometry(accessibility.buttonBorderWidth)
                    : 0,
                onPressed: onSeeSellers,
              );

              if (stackAction) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leading,
                        SizedBox(width: metrics.geometry(10)),
                        Expanded(child: details),
                      ],
                    ),
                    SizedBox(height: metrics.geometry(6)),
                    button,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  SizedBox(width: metrics.geometry(8)),
                  Expanded(child: details),
                  SizedBox(width: metrics.geometry(6)),
                  SizedBox(width: metrics.geometry(78), child: button),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ApprovedTrendAction extends StatelessWidget {
  const _ApprovedTrendAction({
    required this.background,
    required this.foreground,
    required this.radius,
    required this.borderWidth,
    required this.onPressed,
  });

  final Color background;
  final Color foreground;
  final double radius;
  final double borderWidth;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: metrics.geometry(44),
          child: Center(
            child: Container(
              width: double.infinity,
              height: metrics.geometry(30),
              alignment: Alignment.center,
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 8),
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(radius),
                border: borderWidth > 0
                    ? Border.all(color: foreground, width: borderWidth)
                    : null,
              ),
              child: Text(
                'See Sellers',
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontSize: metrics.fontSize(11),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedRankBadge extends StatelessWidget {
  const _ApprovedRankBadge({required this.item});

  final _ApprovedTrendData item;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      width: metrics.geometry(24),
      height: metrics.geometry(24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: item.rankColor,
        borderRadius: BorderRadius.circular(metrics.geometry(6)),
      ),
      child: Text(
        '${item.rank}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: _approvedPrimary,
          fontSize: metrics.fontSize(12),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ApprovedTrendDetails extends StatelessWidget {
  const _ApprovedTrendDetails({required this.item, required this.accent});

  final _ApprovedTrendData item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final progressColor = item.medium ? _approvedGold : accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _pageText(context),
            fontSize: metrics.fontSize(11),
            fontWeight: FontWeight.w800,
            height: metrics.lineHeight(
              referenceFontSize: 11,
              referenceLineHeight: 11.55,
            ),
          ),
        ),
        SizedBox(height: metrics.geometry(1)),
        Row(
          children: [
            Flexible(
              child: Text(
                'Competition: ${item.competition}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _pageText(context),
                  fontSize: metrics.fontSize(8),
                  fontWeight: FontWeight.w600,
                  height: metrics.lineHeight(
                    referenceFontSize: 8,
                    referenceLineHeight: 8.8,
                  ),
                ),
              ),
            ),
            SizedBox(width: metrics.geometry(2)),
            _approvedAsset(
              item.medium
                  ? 'transparent/trend-medium.png'
                  : 'transparent/trend-hot.png',
              width: metrics.geometry(item.medium ? 10 : 9),
              height: metrics.geometry(10),
            ),
          ],
        ),
        SizedBox(height: metrics.geometry(2)),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(metrics.geometry(999)),
                child: LinearProgressIndicator(
                  value: item.percent / 100,
                  minHeight: metrics.geometry(3),
                  backgroundColor: const Color(0xffe8e8ef),
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
            ),
            SizedBox(width: metrics.geometry(4)),
            Text(
              '${item.percent}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _approvedAction,
                fontSize: metrics.fontSize(8),
                fontWeight: FontWeight.w800,
                height: metrics.lineHeight(
                  referenceFontSize: 8,
                  referenceLineHeight: 9.6,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: metrics.geometry(1)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _approvedAsset(
              'transparent/trend-people.png',
              width: metrics.geometry(10),
              height: metrics.geometry(11),
            ),
            SizedBox(width: metrics.geometry(3)),
            Expanded(
              child: Text(
                item.sellerCopy,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _pageMuted(context),
                  fontSize: metrics.fontSize(9.5),
                  height: metrics.lineHeight(
                    referenceFontSize: 9.5,
                    referenceLineHeight: 10.925,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ApprovedTrendData {
  const _ApprovedTrendData({
    required this.rank,
    required this.title,
    required this.competition,
    required this.percent,
    required this.sellerCopy,
    required this.image,
    required this.rankColor,
    this.medium = false,
  });

  final int rank;
  final String title;
  final String competition;
  final int percent;
  final String sellerCopy;
  final String image;
  final Color rankColor;
  final bool medium;
}

const _trendCategories = [
  _ApprovedTrendData(
    rank: 1,
    title: 'iPad Air',
    competition: 'Very High',
    percent: 96,
    sellerCopy: '23 sellers are actively competing for iPad buyers.',
    image: 'trend-ipad-air.png',
    rankColor: Color(0xffffb900),
  ),
  _ApprovedTrendData(
    rank: 2,
    title: 'Gaming Laptops',
    competition: 'High',
    percent: 82,
    sellerCopy: '17 sellers are actively competing for laptop buyers.',
    image: 'trend-gaming-laptop.png',
    rankColor: Color(0xffeef0fa),
  ),
  _ApprovedTrendData(
    rank: 3,
    title: 'Pressure Washing',
    competition: 'High',
    percent: 74,
    sellerCopy: '14 businesses are actively competing for new customers.',
    image: 'trend-pressure-washer.png',
    rankColor: Color(0xffff6c20),
  ),
  _ApprovedTrendData(
    rank: 4,
    title: 'Living Room Furniture',
    competition: 'Medium',
    percent: 58,
    sellerCopy: '9 sellers are actively competing for furniture buyers.',
    image: 'trend-living-room.png',
    rankColor: Color(0xffeef0fa),
    medium: true,
  ),
  _ApprovedTrendData(
    rank: 5,
    title: 'Used SUVs',
    competition: 'Medium',
    percent: 46,
    sellerCopy: '6 dealerships are actively competing for SUV buyers.',
    image: 'trend-used-suv.png',
    rankColor: Color(0xffeef0fa),
    medium: true,
  ),
];

/// Screenshot-approved seller results opened from the Hocatrends iPad card.
class ApprovedHocatrendsPickedSellersPage extends StatefulWidget {
  const ApprovedHocatrendsPickedSellersPage({
    required this.onBack,
    required this.onChatSeller,
    this.onNotifications,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onChatSeller;
  final VoidCallback? onNotifications;

  @override
  State<ApprovedHocatrendsPickedSellersPage> createState() =>
      _ApprovedHocatrendsPickedSellersPageState();
}

class _ApprovedHocatrendsPickedSellersPageState
    extends State<ApprovedHocatrendsPickedSellersPage> {
  bool verifiedOnly = false;
  bool withinFourMiles = false;
  bool savesAtLeast160 = false;
  bool gridView = false;
  String sortLabel = 'Best deal';

  bool get filtersOn => verifiedOnly || withinFourMiles || savesAtLeast160;

  List<_ApprovedSellerData> get visibleSellers {
    final sellers = _approvedSellers.where((seller) {
      final distance = double.tryParse(seller.distance.split(' ').first) ?? 0;
      final savings =
          int.tryParse(seller.savings.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return (!verifiedOnly || seller.badge.isNotEmpty) &&
          (!withinFourMiles || distance <= 4) &&
          (!savesAtLeast160 || savings >= 160);
    }).toList();
    switch (sortLabel) {
      case 'Lowest price':
        sellers.sort((a, b) => _sellerPrice(a).compareTo(_sellerPrice(b)));
        break;
      case 'Top rated':
        sellers.sort((a, b) => _sellerRating(b).compareTo(_sellerRating(a)));
        break;
      case 'Nearest':
        sellers.sort(
          (a, b) => _sellerDistance(a).compareTo(_sellerDistance(b)),
        );
        break;
      default:
        sellers.sort((a, b) => _sellerSavings(b).compareTo(_sellerSavings(a)));
        break;
    }
    return sellers;
  }

  int _sellerPrice(_ApprovedSellerData seller) =>
      int.tryParse(seller.price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  int _sellerSavings(_ApprovedSellerData seller) =>
      int.tryParse(seller.savings.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  double _sellerRating(_ApprovedSellerData seller) =>
      double.tryParse(seller.rating.split(' ').first) ?? 0;
  double _sellerDistance(_ApprovedSellerData seller) =>
      double.tryParse(seller.distance.split(' ').first) ?? 0;

  Future<void> _openSellerFilters() async {
    var draftVerified = verifiedOnly;
    var draftDistance = withinFourMiles;
    var draftSavings = savesAtLeast160;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => BuyerModalSheet(
          title: 'Filter sellers',
          subtitle: 'Narrow these results without leaving Hocatrends.',
          icon: Icons.tune_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HocalistFilterChip(
                    role: HocalistControlRole.buyer,
                    label: 'Verified sellers',
                    selected: draftVerified,
                    onSelected: (value) =>
                        setSheetState(() => draftVerified = value),
                  ),
                  HocalistFilterChip(
                    role: HocalistControlRole.buyer,
                    label: 'Within 4 mi',
                    selected: draftDistance,
                    onSelected: (value) =>
                        setSheetState(() => draftDistance = value),
                  ),
                  HocalistFilterChip(
                    role: HocalistControlRole.buyer,
                    label: 'Saves \$160+',
                    selected: draftSavings,
                    onSelected: (value) =>
                        setSheetState(() => draftSavings = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: BuyerSecondaryButton(
                      label: 'Clear',
                      onPressed: () => setSheetState(() {
                        draftVerified = false;
                        draftDistance = false;
                        draftSavings = false;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BuyerPrimaryButton(
                      label: 'Show sellers',
                      onPressed: () {
                        setState(() {
                          verifiedOnly = draftVerified;
                          withinFourMiles = draftDistance;
                          savesAtLeast160 = draftSavings;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return _ApprovedReplicaSurface(
      builder: (context) {
        final metrics = _replicaMetrics(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApprovedSellerHeader(
              onBack: widget.onBack,
              onNotifications: widget.onNotifications,
            ),
            SizedBox(height: metrics.geometry(12)),
            const _ApprovedSellerProductSummary(),
            SizedBox(height: metrics.geometry(12)),
            _ApprovedSellerControls(
              filtersOn: filtersOn,
              sortLabel: sortLabel,
              gridView: gridView,
              onFilters: _openSellerFilters,
              onSort: (value) {
                setState(() => sortLabel = value);
                _message('Sorted by $value.');
              },
              onView: (value) {
                setState(() => gridView = value);
                _message(value ? 'Grid view selected.' : 'List view selected.');
              },
            ),
            if (filtersOn) ...[
              SizedBox(height: metrics.geometry(10)),
              Wrap(
                spacing: metrics.geometry(8),
                runSpacing: metrics.geometry(8),
                children: [
                  if (verifiedOnly)
                    const _ApprovedFilterChip(label: 'Verified sellers'),
                  if (withinFourMiles)
                    const _ApprovedFilterChip(label: 'Within 4 mi'),
                  if (savesAtLeast160)
                    const _ApprovedFilterChip(label: 'Saves \$160+'),
                ],
              ),
            ],
            SizedBox(height: metrics.geometry(10)),
            LayoutBuilder(
              builder: (context, constraints) {
                final sellers = visibleSellers;
                final useGrid = gridView && metrics.availableWidth >= 620;
                if (sellers.isEmpty) {
                  return _ApprovedSellerEmptyState(
                    onClear: () => setState(() {
                      verifiedOnly = false;
                      withinFourMiles = false;
                      savesAtLeast160 = false;
                    }),
                  );
                }
                if (useGrid) {
                  return Wrap(
                    spacing: metrics.geometry(12),
                    runSpacing: metrics.geometry(12),
                    children: [
                      for (final seller in sellers)
                        SizedBox(
                          width:
                              (constraints.maxWidth - metrics.geometry(12)) / 2,
                          child: _ApprovedSellerCard(
                            seller: seller,
                            onChat: widget.onChatSeller,
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < sellers.length; index++) ...[
                      _ApprovedSellerCard(
                        seller: sellers[index],
                        onChat: widget.onChatSeller,
                      ),
                      if (index != sellers.length - 1)
                        SizedBox(height: metrics.geometry(8)),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ApprovedSellerHeader extends StatelessWidget {
  const _ApprovedSellerHeader({
    required this.onBack,
    required this.onNotifications,
  });

  final VoidCallback onBack;
  final VoidCallback? onNotifications;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ApprovedBitmapButton(
          tooltip: 'Back to Hocatrends',
          onPressed: onBack,
          asset: 'transparent/seller-back.png',
          size: metrics.geometry(44),
          imageWidth: metrics.geometry(18),
          imageHeight: metrics.geometry(18),
        ),
        SizedBox(width: metrics.geometry(8)),
        Expanded(
          child: Column(
            children: [
              Text(
                'iPad Air Sellers',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: _pageText(context),
                  fontSize: _pickedSellerFontSize(metrics, 16),
                  fontWeight: FontWeight.w800,
                  height: metrics.lineHeight(
                    referenceFontSize: 16,
                    referenceLineHeight: 19.2,
                  ),
                ),
              ),
              SizedBox(height: metrics.geometry(3)),
              Text(
                '23 sellers are offering deals',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _pageMuted(context),
                  fontSize: _pickedSellerFontSize(metrics, 12),
                  height: metrics.lineHeight(
                    referenceFontSize: 12,
                    referenceLineHeight: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: metrics.geometry(8)),
        _ApprovedBitmapButton(
          tooltip: 'Notifications',
          onPressed: onNotifications,
          asset: 'transparent/seller-notification.png',
          size: metrics.geometry(44),
          imageWidth: metrics.geometry(22),
          imageHeight: metrics.geometry(24),
        ),
      ],
    );
  }
}

class _ApprovedBitmapButton extends StatelessWidget {
  const _ApprovedBitmapButton({
    required this.tooltip,
    required this.onPressed,
    required this.asset,
    required this.size,
    required this.imageWidth,
    required this.imageHeight,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final String asset;
  final double size;
  final double imageWidth;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: _approvedAsset(asset, width: imageWidth, height: imageHeight),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.all(_replicaMetrics(context).geometry(5)),
      icon: _approvedAsset(asset, width: imageWidth, height: imageHeight),
    );
  }
}

class _ApprovedSellerProductSummary extends StatelessWidget {
  const _ApprovedSellerProductSummary();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final metrics = _replicaMetrics(context);
        final image = _approvedAsset(
          'seller-ipad-air.png',
          width: metrics.geometry(63),
          height: metrics.geometry(80),
          semanticLabel: 'iPad Air',
        );
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'iPad Air',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: _pageText(context),
                fontSize: _pickedSellerFontSize(metrics, 18),
                fontWeight: FontWeight.w800,
                height: metrics.lineHeight(
                  referenceFontSize: 18,
                  referenceLineHeight: 21.6,
                ),
              ),
            ),
            SizedBox(height: metrics.geometry(6)),
            Text(
              'Category: Tablets',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _pageMuted(context),
                fontSize: _pickedSellerFontSize(metrics, 13),
                height: metrics.lineHeight(
                  referenceFontSize: 13,
                  referenceLineHeight: 16.25,
                ),
              ),
            ),
            SizedBox(height: metrics.geometry(10)),
            Container(
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              ),
              decoration: BoxDecoration(
                color: const Color(0xfff2efff),
                borderRadius: BorderRadius.circular(metrics.geometry(9)),
              ),
              child: Wrap(
                spacing: metrics.geometry(5),
                runSpacing: metrics.geometry(4),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _approvedAsset(
                    'transparent/seller-competition.png',
                    width: metrics.geometry(10),
                    height: metrics.geometry(11),
                  ),
                  Text(
                    'Competition: Very High',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _approvedAction,
                      fontSize: _pickedSellerFontSize(metrics, 11),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  _approvedAsset(
                    'transparent/trend-hot.png',
                    width: metrics.geometry(11),
                    height: metrics.geometry(13),
                  ),
                ],
              ),
            ),
          ],
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            image,
            SizedBox(width: metrics.geometry(20)),
            Expanded(child: copy),
          ],
        );
      },
    );
  }
}

class _ApprovedSellerControls extends StatelessWidget {
  const _ApprovedSellerControls({
    required this.filtersOn,
    required this.sortLabel,
    required this.gridView,
    required this.onFilters,
    required this.onSort,
    required this.onView,
  });

  final bool filtersOn;
  final String sortLabel;
  final bool gridView;
  final VoidCallback onFilters;
  final ValueChanged<String> onSort;
  final ValueChanged<bool> onView;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final border = Border.all(
      color: _approvedBorder,
      width: metrics.geometry(1),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final reflow =
            constraints.maxWidth < 220 || metrics.accessibilityReflow;
        final filter = SizedBox(
          width: _sellerDimension(metrics, 78, floor: 72),
          height: _sellerDimension(metrics, 38, floor: 36),
          child: OutlinedButton(
            onPressed: onFilters,
            style: OutlinedButton.styleFrom(
              foregroundColor: _pageText(context),
              backgroundColor: filtersOn
                  ? const Color(0xfff1efff)
                  : _pageSurface(context),
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 4),
              ),
              side: BorderSide(
                color: _approvedBorder,
                width: metrics.geometry(1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.geometry(7)),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _approvedAsset(
                  'transparent/seller-filter.png',
                  width: metrics.geometry(18),
                  height: metrics.geometry(18),
                ),
                SizedBox(width: metrics.geometry(4)),
                Text(
                  'Filters',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: _pickedSellerFontSize(metrics, 11),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
        final sort = PopupMenuButton<String>(
          key: const Key('approved-trends-seller-sort'),
          initialValue: sortLabel,
          position: PopupMenuPosition.under,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.geometry(12)),
            side: const BorderSide(color: _approvedBorder),
          ),
          onSelected: onSort,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'Best deal', child: Text('Best deal')),
            PopupMenuItem(value: 'Lowest price', child: Text('Lowest price')),
            PopupMenuItem(value: 'Top rated', child: Text('Top rated')),
            PopupMenuItem(value: 'Nearest', child: Text('Nearest')),
          ],
          child: Container(
            constraints: BoxConstraints(
              minHeight: _sellerDimension(metrics, 38, floor: 36),
            ),
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(horizontal: 10),
            ),
            decoration: BoxDecoration(
              color: _pageSurface(context),
              border: border,
              borderRadius: BorderRadius.circular(metrics.geometry(7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sort by: $sortLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _pageText(context),
                      fontSize: _pickedSellerFontSize(metrics, 11),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _approvedAsset(
                  'transparent/seller-sort-down.png',
                  width: metrics.geometry(14),
                  height: metrics.geometry(11),
                ),
              ],
            ),
          ),
        );
        final toggle = Container(
          height: _sellerDimension(metrics, 38, floor: 36),
          decoration: BoxDecoration(
            color: _pageSurface(context),
            border: border,
            borderRadius: BorderRadius.circular(metrics.geometry(7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ApprovedViewChoice(
                tooltip: 'List view',
                selected: !gridView,
                asset: 'transparent/seller-list.png',
                onTap: () => onView(false),
              ),
              _ApprovedViewChoice(
                tooltip: 'Grid view',
                selected: gridView,
                asset: 'transparent/seller-grid.png',
                onTap: () => onView(true),
              ),
            ],
          ),
        );

        if (reflow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: filter),
                  SizedBox(width: metrics.geometry(9)),
                  toggle,
                ],
              ),
              SizedBox(height: metrics.geometry(9)),
              sort,
            ],
          );
        }

        return Row(
          children: [
            filter,
            SizedBox(width: metrics.geometry(9)),
            Expanded(child: sort),
            SizedBox(width: metrics.geometry(9)),
            toggle,
          ],
        );
      },
    );
  }
}

class _ApprovedViewChoice extends StatelessWidget {
  const _ApprovedViewChoice({
    required this.tooltip,
    required this.selected,
    required this.asset,
    required this.onTap,
  });

  final String tooltip;
  final bool selected;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(6)),
        child: Container(
          width: metrics.artSize(35),
          height: metrics.geometry(32),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xfff1efff) : Colors.transparent,
            borderRadius: BorderRadius.circular(metrics.geometry(6)),
          ),
          child: _approvedAsset(
            asset,
            width: metrics.geometry(17),
            height: metrics.geometry(18),
          ),
        ),
      ),
    );
  }
}

class _ApprovedFilterChip extends StatelessWidget {
  const _ApprovedFilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      padding: metrics.geometryInsets(
        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      ),
      decoration: BoxDecoration(
        color: const Color(0xfff1efff),
        borderRadius: BorderRadius.circular(metrics.geometry(999)),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: _approvedAction,
          fontSize: _pickedSellerFontSize(metrics, 11),
        ),
      ),
    );
  }
}

class _ApprovedSellerEmptyState extends StatelessWidget {
  const _ApprovedSellerEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: const Key('approved-trends-sellers-empty'),
      padding: EdgeInsets.all(metrics.spacing(18)),
      decoration: BoxDecoration(
        color: _pageSurface(context),
        border: Border.all(color: _approvedBorder),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: metrics.artSize(32),
            color: _approvedAction,
          ),
          SizedBox(height: metrics.spacing(7)),
          Text(
            'No sellers match these filters',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _pageText(context),
              fontSize: metrics.fontSize(14),
              fontWeight: FontWeight.w800,
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

class _ApprovedSellerCard extends StatelessWidget {
  const _ApprovedSellerCard({required this.seller, required this.onChat});

  final _ApprovedSellerData seller;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      key: ValueKey('approved-seller-card-${seller.name}'),
      padding: EdgeInsets.all(_sellerDimension(metrics, 8, floor: 8)),
      decoration: BoxDecoration(
        color: _pageSurface(context),
        borderRadius: BorderRadius.circular(metrics.geometry(8)),
        border: Border.all(color: _approvedBorder, width: metrics.geometry(1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0d0b1047),
            blurRadius: metrics.geometry(8),
            offset: Offset(0, metrics.geometry(3)),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 220 || metrics.accessibilityReflow;
          final identity = _ApprovedSellerIdentity(seller: seller);
          final commerce = _ApprovedSellerCommerce(
            seller: seller,
            onChat: onChat,
            fullWidth: stack,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stack) ...[
                identity,
                SizedBox(height: metrics.geometry(10)),
                _ApprovedSellerBadge(seller: seller),
                SizedBox(height: metrics.geometry(10)),
                commerce,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    SizedBox(width: metrics.geometry(8)),
                    SizedBox(
                      width: _sellerDimension(metrics, 138, floor: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: _ApprovedSellerBadge(seller: seller),
                          ),
                          SizedBox(height: metrics.geometry(4)),
                          commerce,
                        ],
                      ),
                    ),
                  ],
                ),
              SizedBox(height: metrics.geometry(6)),
              Divider(
                height: metrics.geometry(1),
                thickness: metrics.geometry(1),
                color: _approvedBorder,
              ),
              SizedBox(height: metrics.geometry(6)),
              _ApprovedSellerStats(seller: seller),
            ],
          );
        },
      ),
    );
  }
}

class _ApprovedSellerIdentity extends StatelessWidget {
  const _ApprovedSellerIdentity({required this.seller});

  final _ApprovedSellerData seller;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _approvedAsset(
          seller.avatar,
          width: _sellerDimension(metrics, 49, floor: 44),
          height: _sellerDimension(metrics, 52, floor: 47),
          semanticLabel: '${seller.name} profile photo',
        ),
        SizedBox(width: metrics.geometry(8)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      seller.name,
                      maxLines: metrics.accessibilityReflow ? 2 : 1,
                      softWrap: metrics.accessibilityReflow,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _pageText(context),
                        fontSize: _pickedSellerFontSize(metrics, 16),
                        fontWeight: FontWeight.w800,
                        height: metrics.lineHeight(
                          referenceFontSize: 16,
                          referenceLineHeight: 17.92,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.geometry(4)),
                  _approvedAsset(
                    'transparent/seller-verified.png',
                    width: metrics.geometry(11),
                    height: metrics.geometry(12),
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(6)),
              Row(
                children: [
                  _approvedAsset(
                    'transparent/seller-star.png',
                    width: metrics.geometry(11),
                    height: metrics.geometry(12),
                  ),
                  Expanded(
                    child: Text(
                      seller.rating,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _pageMuted(context),
                        fontSize: _pickedSellerFontSize(metrics, 11),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(5)),
              Text(
                '${seller.location}  •  ${seller.distance}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _pageMuted(context),
                  fontSize: _pickedSellerFontSize(metrics, 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApprovedSellerBadge extends StatelessWidget {
  const _ApprovedSellerBadge({required this.seller});

  final _ApprovedSellerData seller;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Container(
      constraints: BoxConstraints(minHeight: metrics.geometry(20)),
      padding: metrics.geometryInsets(
        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      ),
      decoration: BoxDecoration(
        color: seller.badgeColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(metrics.geometry(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _approvedAsset(
            seller.badgeIcon,
            width: metrics.geometry(10),
            height: metrics.geometry(11),
          ),
          SizedBox(width: metrics.geometry(4)),
          Flexible(
            child: Text(
              seller.badge,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: seller.badgeColor,
                fontSize: _pickedSellerFontSize(metrics, 9),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedSellerCommerce extends StatelessWidget {
  const _ApprovedSellerCommerce({
    required this.seller,
    required this.onChat,
    required this.fullWidth,
  });

  final _ApprovedSellerData seller;
  final VoidCallback onChat;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final metrics = _replicaMetrics(context);
    final values = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          seller.price,
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _pageText(context),
            fontSize: _pickedSellerFontSize(metrics, 16),
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          seller.savings,
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _approvedGreen,
            fontSize: _pickedSellerFontSize(metrics, 11),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final chat = SizedBox(
      height: _sellerDimension(metrics, 30, floor: 29),
      child: FilledButton(
        onPressed: onChat,
        style: FilledButton.styleFrom(
          backgroundColor: accessibility.backgroundOr(_approvedAction),
          foregroundColor: accessibility.foregroundOr(Colors.white),
          padding: metrics.geometryInsets(
            const EdgeInsets.symmetric(horizontal: 2),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              metrics.geometry(accessibility.radiusOr(9)),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _approvedAsset(
              'transparent/seller-chat.png',
              width: metrics.geometry(13),
              height: metrics.geometry(13),
            ),
            SizedBox(width: metrics.geometry(3)),
            Flexible(
              child: Text(
                'Chat Seller',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: _pickedSellerFontSize(metrics, 10.5),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          values,
          SizedBox(height: metrics.geometry(9)),
          chat,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: values),
        SizedBox(width: metrics.geometry(3)),
        SizedBox(width: _sellerDimension(metrics, 80, floor: 72), child: chat),
      ],
    );
  }
}

class _ApprovedSellerStats extends StatelessWidget {
  const _ApprovedSellerStats({required this.seller});

  final _ApprovedSellerData seller;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: _pageMuted(context),
      fontSize: _pickedSellerFontSize(metrics, 9.5),
      height: metrics.lineHeight(
        referenceFontSize: 10,
        referenceLineHeight: 11.5,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final deals = _ApprovedIconText(
          icon: 'transparent/seller-deals.png',
          label: seller.deals,
          style: style,
        );
        final response = _ApprovedIconText(
          icon: 'transparent/seller-response.png',
          label: seller.response,
          style: style,
        );
        if (constraints.maxWidth < 220 || metrics.accessibilityReflow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              deals,
              SizedBox(height: metrics.geometry(8)),
              response,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: metrics.geometry(112), child: deals),
            SizedBox(width: metrics.geometry(16)),
            Expanded(child: response),
          ],
        );
      },
    );
  }
}

class _ApprovedIconText extends StatelessWidget {
  const _ApprovedIconText({
    required this.icon,
    required this.label,
    required this.style,
  });

  final String icon;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _approvedAsset(
          icon,
          width: metrics.geometry(9),
          height: metrics.geometry(10),
        ),
        SizedBox(width: metrics.geometry(5)),
        Expanded(
          child: Text(
            label,
            maxLines: metrics.accessibilityReflow ? 2 : 1,
            softWrap: metrics.accessibilityReflow,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _ApprovedSellerData {
  const _ApprovedSellerData({
    required this.name,
    required this.avatar,
    required this.rating,
    required this.location,
    required this.distance,
    required this.price,
    required this.savings,
    required this.badge,
    required this.badgeIcon,
    required this.badgeColor,
    required this.deals,
    required this.response,
  });

  final String name;
  final String avatar;
  final String rating;
  final String location;
  final String distance;
  final String price;
  final String savings;
  final String badge;
  final String badgeIcon;
  final Color badgeColor;
  final String deals;
  final String response;
}

const _approvedSellers = [
  _ApprovedSellerData(
    name: 'Northside Tech',
    avatar: 'seller-northside-tech.png',
    rating: '4.9 (128 reviews)',
    location: 'Yonkers, NY',
    distance: '2.1 mi',
    price: '\$820',
    savings: 'Save \$180',
    badge: 'Top Rated Seller',
    badgeIcon: 'transparent/badge-trophy.png',
    badgeColor: _approvedAction,
    deals: '230+ deals completed',
    response: 'Usually responds in a few hours',
  ),
  _ApprovedSellerData(
    name: 'Gadget Hub',
    avatar: 'seller-gadget-hub.png',
    rating: '4.7 (96 reviews)',
    location: 'Yonkers, NY',
    distance: '3.4 mi',
    price: '\$835',
    savings: 'Save \$165',
    badge: 'Great Deal',
    badgeIcon: 'transparent/badge-deal.png',
    badgeColor: _approvedGreen,
    deals: '150+ deals completed',
    response: 'Responds within 2 hours',
  ),
  _ApprovedSellerData(
    name: 'Prime Tech Solutions',
    avatar: 'seller-prime-tech.png',
    rating: '4.6 (78 reviews)',
    location: 'Yonkers, NY',
    distance: '4.7 mi',
    price: '\$845',
    savings: 'Save \$155',
    badge: 'Fast Responder',
    badgeIcon: 'transparent/badge-fast.png',
    badgeColor: Color(0xff1769ff),
    deals: '120+ deals completed',
    response: 'Usually responds in a few hours',
  ),
  _ApprovedSellerData(
    name: 'Tech World NY',
    avatar: 'seller-tech-world.png',
    rating: '4.5 (64 reviews)',
    location: 'Yonkers, NY',
    distance: '5.2 mi',
    price: '\$860',
    savings: 'Save \$140',
    badge: 'Good Value',
    badgeIcon: 'transparent/badge-value.png',
    badgeColor: Color(0xffdf8500),
    deals: '90+ deals completed',
    response: 'Responds within 3 hours',
  ),
  _ApprovedSellerData(
    name: 'Digital Depot',
    avatar: 'seller-digital-depot.png',
    rating: '4.4 (52 reviews)',
    location: 'Yonkers, NY',
    distance: '6.0 mi',
    price: '\$875',
    savings: 'Save \$125',
    badge: 'Trusted Seller',
    badgeIcon: 'transparent/badge-trusted.png',
    badgeColor: _approvedAction,
    deals: '110+ deals completed',
    response: 'Usually responds in a few hours',
  ),
];

/// Screenshot-approved buyer notification history (the existing Recent
/// activity destination) with the current back callback and working filters.
class ApprovedBuyerNotificationsPage extends StatefulWidget {
  const ApprovedBuyerNotificationsPage({
    required this.onBack,
    this.title = 'Recent activity',
    super.key,
  });

  final VoidCallback onBack;
  final String title;

  @override
  State<ApprovedBuyerNotificationsPage> createState() =>
      _ApprovedBuyerNotificationsPageState();
}

class _ApprovedBuyerNotificationsPageState
    extends State<ApprovedBuyerNotificationsPage> {
  String selected = 'All';

  @override
  Widget build(BuildContext context) {
    final visible = selected == 'All'
        ? _approvedActivities
        : _approvedActivities.where((item) => item.category == selected);
    return _ApprovedReplicaSurface(
      builder: (context) {
        final metrics = _replicaMetrics(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ApprovedBitmapButton(
                  tooltip: 'Back to home',
                  onPressed: widget.onBack,
                  asset: 'activity-back.png',
                  size: metrics.geometry(44),
                  imageWidth: metrics.geometry(18),
                  imageHeight: metrics.geometry(18),
                ),
                SizedBox(width: metrics.geometry(4)),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.pageTitle,
                      color: _pageText(context),
                      height: metrics.lineHeight(
                        referenceFontSize: 16,
                        referenceLineHeight: 19.2,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: metrics.geometry(44)),
              ],
            ),
            SizedBox(height: metrics.geometry(20)),
            _ApprovedActivityTabs(
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
            SizedBox(height: metrics.geometry(20)),
            for (final item in visible) ...[
              _ApprovedActivityRow(item: item),
              if (item != visible.last)
                Divider(
                  height: metrics.geometry(1),
                  thickness: metrics.geometry(1),
                  color: _approvedBorder,
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ApprovedActivityTabs extends StatelessWidget {
  const _ApprovedActivityTabs({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  static const tabs = ['All', 'Offers', 'Rewards', 'Reviews', 'Payouts'];

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scroll =
            constraints.maxWidth < 220 || metrics.accessibilityReflow;
        final children = [
          for (final tab in tabs)
            _ApprovedActivityTab(
              label: tab,
              selected: selected == tab,
              onTap: () => onChanged(tab),
              expand: !scroll,
            ),
        ];
        final content = scroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
              )
            : Row(children: children);
        return Container(
          constraints: BoxConstraints(minHeight: metrics.geometry(29)),
          decoration: BoxDecoration(
            color: _pageSurface(context),
            border: Border.all(
              color: _approvedBorder,
              width: metrics.geometry(1),
            ),
            borderRadius: BorderRadius.circular(metrics.geometry(7)),
          ),
          child: content,
        );
      },
    );
  }
}

class _ApprovedActivityTab extends StatelessWidget {
  const _ApprovedActivityTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.expand,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final metrics = _replicaMetrics(context);
    final child = Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(6)),
        child: Container(
          constraints: BoxConstraints(
            minWidth: expand ? 0 : metrics.geometry(72),
            minHeight: metrics.geometry(26),
          ),
          padding: metrics.geometryInsets(
            const EdgeInsets.symmetric(horizontal: 6),
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _approvedAction : Colors.transparent,
            borderRadius: BorderRadius.circular(metrics.geometry(6)),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : _pageMuted(context),
              fontSize: metrics.fontSize(10.5),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
    return expand ? Expanded(child: child) : child;
  }
}

class _ApprovedActivityRow extends StatelessWidget {
  const _ApprovedActivityRow({required this.item});

  final _ApprovedActivityData item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _replicaMetrics(context);
        final tight = constraints.maxWidth < 220 || metrics.accessibilityReflow;
        final trailing = item.stars
            ? Wrap(
                spacing: metrics.geometry(1),
                children: List.generate(
                  5,
                  (_) => _approvedAsset(
                    'activity-rating-star.png',
                    width: metrics.geometry(17),
                    height: metrics.geometry(17),
                  ),
                ),
              )
            : Text(
                item.value!,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: item.valueColor,
                  fontSize: metrics.fontSize(16),
                  fontWeight: FontWeight.w800,
                ),
              );
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _pageText(context),
                fontSize: metrics.fontSize(12.5),
                fontWeight: FontWeight.w800,
                height: metrics.lineHeight(
                  referenceFontSize: 12.5,
                  referenceLineHeight: 15.625,
                ),
              ),
            ),
            SizedBox(height: metrics.geometry(3)),
            Text(
              item.time,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _pageMuted(context),
                fontSize: metrics.fontSize(10.5),
                height: metrics.lineHeight(
                  referenceFontSize: 10.5,
                  referenceLineHeight: 12.6,
                ),
              ),
            ),
            if (tight) ...[SizedBox(height: metrics.geometry(5)), trailing],
          ],
        );
        return Padding(
          key: ValueKey('approved-activity-${item.time}'),
          padding: EdgeInsets.symmetric(vertical: metrics.geometry(8)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _approvedAsset(
                item.icon,
                width: metrics.geometry(36),
                height: metrics.geometry(36),
              ),
              SizedBox(width: metrics.geometry(10)),
              Expanded(child: copy),
              if (!tight) ...[
                SizedBox(width: metrics.geometry(8)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: metrics.geometry(104)),
                  child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ApprovedActivityData {
  const _ApprovedActivityData({
    required this.category,
    required this.icon,
    required this.title,
    required this.time,
    this.value,
    this.valueColor = _approvedGreen,
    this.stars = false,
  });

  final String category;
  final String icon;
  final String title;
  final String time;
  final String? value;
  final Color valueColor;
  final bool stars;
}

const _approvedActivities = [
  _ApprovedActivityData(
    category: 'Offers',
    icon: 'activity-chat.png',
    title: 'Northside Tech sent you a new offer',
    time: '2 minutes ago',
    value: '\$420',
  ),
  _ApprovedActivityData(
    category: 'Offers',
    icon: 'activity-check.png',
    title: 'Loop Resale accepted your request',
    time: '1 hour ago',
    value: '\$390',
  ),
  _ApprovedActivityData(
    category: 'Reviews',
    icon: 'activity-star.png',
    title: 'You earned a new review',
    time: 'Yesterday',
    stars: true,
  ),
  _ApprovedActivityData(
    category: 'Payouts',
    icon: 'activity-wallet.png',
    title: 'Rewards will be paid on May 20',
    time: '2 days ago',
    value: '\$24.80',
    valueColor: _approvedAction,
  ),
  _ApprovedActivityData(
    category: 'Rewards',
    icon: 'activity-check.png',
    title: 'Tech World NY confirmed your purchase',
    time: '3 days ago',
    value: '+ \$8.60',
  ),
  _ApprovedActivityData(
    category: 'Offers',
    icon: 'activity-chat.png',
    title: 'Gadget Hub sent you a new offer',
    time: '4 days ago',
    value: '\$350',
  ),
  _ApprovedActivityData(
    category: 'Reviews',
    icon: 'activity-star.png',
    title: 'You earned a new review',
    time: '5 days ago',
    stars: true,
  ),
  _ApprovedActivityData(
    category: 'Payouts',
    icon: 'activity-wallet.png',
    title: 'Rewards will be paid on May 13',
    time: '6 days ago',
    value: '\$19.40',
    valueColor: _approvedAction,
  ),
];
