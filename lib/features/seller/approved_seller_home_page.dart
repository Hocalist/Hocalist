import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_status_fact.dart';

import '../../domain/phase2/discovery.dart';
import '../../domain/phase2/requests.dart';
import '../../theme/seller_ui_foundation.dart';
import 'approved_seller_leads_page.dart';

class ApprovedSellerHomePage extends StatefulWidget {
  const ApprovedSellerHomePage({
    required this.onLeads,
    required this.onBrowseRequests,
    this.onOfferHistory,
    this.sellerName,
    this.realLeads,
    this.leadsLoading = false,
    this.leadsError,
    this.onRefreshLeads,
    this.offersCount,
    this.offersLoading = false,
    this.offersError,
    this.onRefreshOffers,
    this.recommendedLeads,
    this.recommendedLoading = false,
    this.recommendedError,
    this.onRefreshRecommended,
    this.accountHealth,
    this.accountHealthLoading = false,
    this.accountHealthError,
    this.onRefreshAccountHealth,
    this.onOpenVerification,
    this.onAppealRestriction,
    super.key,
  });

  final VoidCallback onLeads;
  final VoidCallback onBrowseRequests;
  final VoidCallback? onOfferHistory;
  final String? sellerName;
  final List<SellerLeadView>? realLeads;
  final bool leadsLoading;
  final String? leadsError;
  final VoidCallback? onRefreshLeads;

  /// Authoritative seller offer count when the offers backend is configured.
  final int? offersCount;
  final bool offersLoading;
  final String? offersError;
  final VoidCallback? onRefreshOffers;

  /// Real recommended leads with their declared matching basis. Null keeps the
  /// prototype cards; a view with items renders real cards and a designed
  /// empty state keeps the section visible when nothing matches.
  final RecommendedLeadsView? recommendedLeads;
  final bool recommendedLoading;
  final String? recommendedError;
  final VoidCallback? onRefreshRecommended;

  /// Manual review status mapped from the trust projection. Null keeps the
  /// honest "Not available yet" slot.
  final SellerAccountHealthView? accountHealth;
  final bool accountHealthLoading;
  final String? accountHealthError;
  final VoidCallback? onRefreshAccountHealth;
  final VoidCallback? onOpenVerification;
  final ValueChanged<SellerHealthRestriction>? onAppealRestriction;

  bool get usesRealLeads => realLeads != null;

  @override
  State<ApprovedSellerHomePage> createState() => _ApprovedSellerHomePageState();
}

class _ApprovedSellerHomePageState extends State<ApprovedSellerHomePage> {
  @override
  void initState() {
    super.initState();
    final refresh = widget.onRefreshOffers;
    if (refresh != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final realLeads = widget.realLeads;
    return SellerResponsivePage(
      builder: (context, metrics) {
        return SingleChildScrollView(
          key: const Key('sellerHomeScroll'),
          padding: EdgeInsets.fromLTRB(
            metrics.pageHorizontalPadding(14),
            metrics.spacing(14),
            metrics.pageHorizontalPadding(14),
            metrics.spacing(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SellerHero(
                realName: realLeads == null ? null : widget.sellerName,
                accountHealth: widget.accountHealth,
                accountHealthLoading: widget.accountHealthLoading,
                accountHealthError: widget.accountHealthError,
                onRefreshAccountHealth: widget.onRefreshAccountHealth,
                onOpenVerification: widget.onOpenVerification,
                onAppealRestriction: widget.onAppealRestriction,
              ),
              SizedBox(height: metrics.spacing(14)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SellerMetricCard(
                      title: realLeads == null
                          ? 'Leads targeted'
                          : 'Available leads',
                      value: realLeads == null ? '56' : '${realLeads.length}',
                      periodLabel: realLeads == null
                          ? 'This month'
                          : (widget.leadsLoading ? 'Loading…' : null),
                      actionLabel: realLeads == null
                          ? 'View all leads'
                          : 'Browse leads',
                      asset: SellerAssets.homeTarget,
                      valueColor: SellerUiColors.primaryBright,
                      onTap: widget.onLeads,
                    ),
                  ),
                  SizedBox(width: metrics.spacing(10)),
                  Expanded(
                    child: _SellerMetricCard(
                      title: realLeads == null ? 'Deals closed' : 'Offers sent',
                      value: realLeads == null
                          ? '12'
                          : widget.offersCount == null
                          ? '—'
                          : '${widget.offersCount}',
                      periodLabel: realLeads == null
                          ? 'This month'
                          : widget.offersLoading
                          ? 'Loading…'
                          : widget.offersError != null
                          ? 'Unavailable'
                          : null,
                      actionLabel: 'View offers',
                      asset: SellerAssets.homeDeals,
                      valueColor: SellerUiColors.green,
                      onTap: widget.onOfferHistory ?? widget.onLeads,
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.spacing(13)),
              _FindBuyersBanner(onTap: widget.onBrowseRequests),
              SizedBox(height: metrics.spacing(14)),
              if (realLeads == null) ...[
                _SectionTitle(
                  title: 'Recent leads',
                  action: 'View all',
                  onAction: widget.onLeads,
                ),
                SizedBox(height: metrics.spacing(8)),
                _RecentLeadsCard(onTap: widget.onLeads),
                SizedBox(height: metrics.spacing(14)),
                _SectionTitle(
                  title: 'Recommended leads for you',
                  subtitle: 'Buyers looking for what you offer',
                  action: 'View all',
                  onAction: widget.onLeads,
                ),
                SizedBox(height: metrics.spacing(8)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _RecommendedLeadCard(
                        image: SellerAssets.homePressureWashing,
                        title: 'Pressure Washing',
                        location: 'Yonkers, NY  •  1.5 mi',
                        match: '95% Match',
                        budget: r'Budget: $250 - $400',
                        onTap: widget.onBrowseRequests,
                      ),
                    ),
                    SizedBox(width: metrics.spacing(8)),
                    Expanded(
                      child: _RecommendedLeadCard(
                        image: SellerAssets.homeRoofRepair,
                        title: 'Roof Repair',
                        location: 'Bronx, NY  •  2.1 mi',
                        match: '92% Match',
                        budget: r'Budget: $900 - $1,500',
                        onTap: widget.onBrowseRequests,
                      ),
                    ),
                    SizedBox(width: metrics.spacing(8)),
                    Expanded(
                      child: _RecommendedLeadCard(
                        image: SellerAssets.homeGamingPc,
                        title: 'Gaming PC',
                        location: 'Queens, NY  •  3.6 mi',
                        match: '90% Match',
                        budget: r'Budget: $1,200 - $1,800',
                        onTap: widget.onBrowseRequests,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                _SectionTitle(
                  title: 'Recent leads',
                  action: 'View all',
                  onAction: widget.onLeads,
                ),
                SizedBox(height: metrics.spacing(8)),
                if (widget.leadsLoading && realLeads.isEmpty)
                  const _RealSellerHomeNotice('Loading requests…')
                else if (widget.leadsError != null && realLeads.isEmpty)
                  _RealSellerHomeNotice(
                    widget.leadsError!,
                    onRetry: widget.onRefreshLeads,
                  )
                else if (realLeads.isEmpty)
                  _SellerHomeEmptyCard(
                    key: const Key('sellerHomeRecentLeadsEmpty'),
                    icon: Icons.inbox_outlined,
                    title: 'No recent leads yet',
                    body:
                        'Buyer requests that match your business appear here '
                        'as they are posted.',
                    actionLabel: 'Browse requests',
                    onAction: widget.onBrowseRequests,
                  )
                else
                  _RealRecentLeadsCard(
                    leads: realLeads.take(3).toList(growable: false),
                    onTap: widget.onLeads,
                  ),
                SizedBox(height: metrics.spacing(14)),
                _SectionTitle(
                  title: 'Recommended leads for you',
                  subtitle: 'Buyer requests that match what you offer',
                  action: 'View all',
                  onAction: widget.onLeads,
                ),
                SizedBox(height: metrics.spacing(8)),
                _RealRecommendedSection(
                  view: widget.recommendedLeads,
                  loading: widget.recommendedLoading,
                  error: widget.recommendedError,
                  onRetry: widget.onRefreshRecommended,
                  onBrowseRequests: widget.onBrowseRequests,
                  onOpenLeads: widget.onLeads,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Real recommended-leads section. Keeps the approved three-card geometry with
/// the buyer initials variant, and shows the declared matching basis or a
/// designed empty state instead of a permanently blank section.
class _RealRecommendedSection extends StatelessWidget {
  const _RealRecommendedSection({
    required this.view,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onBrowseRequests,
    required this.onOpenLeads,
  });

  final RecommendedLeadsView? view;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback onBrowseRequests;
  final VoidCallback onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final data = view;
    if (loading && (data == null || data.items.isEmpty)) {
      return const _RealSellerHomeNotice('Finding matching requests…');
    }
    if (error != null && (data == null || data.items.isEmpty)) {
      return _RealSellerHomeNotice(error!, onRetry: onRetry);
    }
    if (data == null || data.items.isEmpty) {
      final basis = data?.basis;
      final hasBasis = data?.hasBasis ?? false;
      return _SellerHomeEmptyCard(
        key: const Key('sellerHomeRecommendedEmpty'),
        icon: Icons.recommend_outlined,
        title: hasBasis
            ? 'No matching requests right now'
            : 'Add your business details for recommendations',
        body: hasBasis
            ? 'Your recommendations are based on '
                  '${_basisLabel(basis)}. New matching buyer requests '
                  'appear here as they are posted.'
            : 'Recommendations use your Store listing categories and your '
                  'service area. Add at least one of them to see matching '
                  'buyer requests here.',
        actionLabel: hasBasis ? 'Browse requests' : null,
        onAction: hasBasis ? onBrowseRequests : null,
      );
    }
    final leads = data.items.take(3).toList(growable: false);
    final reasons = data.matchReasons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < leads.length; index++) ...[
              if (index > 0) SizedBox(width: metrics.spacing(8)),
              Flexible(
                child: SizedBox(
                  width: leads.length == 1 ? metrics.geometry(174) : null,
                  child: _RecommendedLeadCard(
                    initial: _sellerInitials(leads[index].buyerDisplayName),
                    title: leads[index].title,
                    location: _leadLocationLabel(leads[index]),
                    match: (leads[index].matchPercent ?? 0) > 0
                        ? '${leads[index].matchPercent}% Match'
                        : 'New request',
                    budget: _leadBudgetLabel(leads[index]),
                    onTap: onOpenLeads,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (leads.length > 1 && reasons.any((row) => row.isNotEmpty)) ...[
          SizedBox(height: metrics.spacing(6)),
          Text(
            'Matched on your declared categories and service area.',
            key: const Key('sellerHomeRecommendedBasis'),
            style: sellerText(metrics, 10.5, color: SellerUiColors.body),
          ),
        ],
      ],
    );
  }

  String _basisLabel(RecommendedLeadsBasis? basis) {
    if (basis == null) return 'your declared business details';
    final parts = <String>[
      if (basis.declaredCategoryLabels.isNotEmpty)
        basis.declaredCategoryLabels.join(', '),
      if ((basis.areaLabel ?? '').trim().isNotEmpty) basis.areaLabel!,
      if (basis.radiusMiles != null) '${basis.radiusMiles} mi radius',
    ];
    return parts.isEmpty ? 'your declared business details' : parts.join(' • ');
  }
}

String _sellerInitials(String displayName) {
  final parts = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final single = parts.first;
    return (single.length >= 2 ? single.substring(0, 2) : single).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String _leadLocationLabel(SellerLeadProjection lead) {
  final area = lead.areaLabel ?? 'Area not shared';
  final distance = lead.distanceMiles;
  if (distance == null) return area;
  return '$area  •  ${distance.toStringAsFixed(1)} mi';
}

String _leadBudgetLabel(SellerLeadProjection lead) {
  final minimum = lead.budget.minimum;
  final maximum = lead.budget.maximum;
  if (minimum == null && maximum == null) return 'Budget not set';
  String format(int minor) {
    final major = minor ~/ 100;
    final cents = minor % 100;
    return cents == 0
        ? '\$$major'
        : '\$$major.${cents.toString().padLeft(2, '0')}';
  }

  if (minimum != null && maximum != null) {
    return 'Budget: ${format(minimum.minorUnits)} - ${format(maximum.minorUnits)}';
  }
  if (minimum != null) return 'Budget: from ${format(minimum.minorUnits)}';
  return 'Budget: up to ${format(maximum!.minorUnits)}';
}

class _SellerHero extends StatelessWidget {
  const _SellerHero({
    this.realName,
    this.accountHealth,
    this.accountHealthLoading = false,
    this.accountHealthError,
    this.onRefreshAccountHealth,
    this.onOpenVerification,
    this.onAppealRestriction,
  });

  final String? realName;
  final SellerAccountHealthView? accountHealth;
  final bool accountHealthLoading;
  final String? accountHealthError;
  final VoidCallback? onRefreshAccountHealth;
  final VoidCallback? onOpenVerification;
  final ValueChanged<SellerHealthRestriction>? onAppealRestriction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    if (realName != null) {
      final name = realName!.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Welcome to Hocalist' : 'Welcome, $name',
                      style: sellerText(metrics, 17, weight: FontWeight.w800),
                    ),
                    SizedBox(height: metrics.spacing(5)),
                    Text(
                      'Find requests that fit your business.',
                      style: sellerText(
                        metrics,
                        11.5,
                        color: SellerUiColors.body,
                      ),
                    ),
                  ],
                ),
              ),
              Image.asset(
                SellerAssets.homeHero,
                width: metrics.artSize(90),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ],
          ),
          SizedBox(height: metrics.spacing(10)),
          Text(
            'Account health',
            style: sellerText(metrics, 11.5, color: SellerUiColors.body),
          ),
          SizedBox(height: metrics.geometry(5)),
          _AccountHealthSlot(
            health: accountHealth,
            loading: accountHealthLoading,
            error: accountHealthError,
            onRetry: onRefreshAccountHealth,
            onOpenVerification: onOpenVerification,
            onAppealRestriction: onAppealRestriction,
          ),
        ],
      );
    }
    final greeting = Text(
      'Good morning, Alex! 👋',
      maxLines: metrics.accessibilityReflow ? null : 1,
      style: sellerText(metrics, 17, weight: FontWeight.w800),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        metrics.accessibilityReflow
            ? greeting
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: greeting,
              ),
        SizedBox(height: metrics.geometry(14)),
        Text(
          'Account health',
          style: sellerText(metrics, 11.5, color: SellerUiColors.body),
        ),
        SizedBox(height: metrics.geometry(5)),
        const _AccountHealthBar(),
      ],
    );
    final portrait = ClipOval(
      child: Image.asset(
        SellerAssets.homeAvatar,
        width: metrics.artSize(72),
        height: metrics.artSize(72),
        fit: BoxFit.cover,
        semanticLabel: 'Alex seller portrait',
      ),
    );
    final art = Image.asset(
      SellerAssets.homeHero,
      width: metrics.artSize(122),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    if (metrics.accessibilityReflow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [portrait, art],
          ),
          SizedBox(height: metrics.spacing(10)),
          copy,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        portrait,
        SizedBox(width: metrics.spacing(10)),
        Expanded(child: copy),
        SizedBox(width: metrics.geometry(4)),
        art,
      ],
    );
  }
}

class _RealSellerHomeNotice extends StatelessWidget {
  const _RealSellerHomeNotice(this.message, {this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      padding: EdgeInsets.all(metrics.spacing(14)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: sellerText(metrics, 12)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Account health slot. When the trust projection is available it shows the
/// manual review state and recorded restriction reasons with the appeal path;
/// otherwise it keeps the approved honest placeholder. It never shows a
/// computed numeric health score.
class _AccountHealthSlot extends StatefulWidget {
  const _AccountHealthSlot({
    this.health,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onOpenVerification,
    this.onAppealRestriction,
  });

  final SellerAccountHealthView? health;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenVerification;
  final ValueChanged<SellerHealthRestriction>? onAppealRestriction;

  @override
  State<_AccountHealthSlot> createState() => _AccountHealthSlotState();
}

class _AccountHealthSlotState extends State<_AccountHealthSlot> {
  final _sheetRevision = ValueNotifier<int>(0);
  SellerAccountHealthView? get health => widget.health;
  bool get loading => widget.loading;
  String? get error => widget.error;
  VoidCallback? get onRetry => widget.onRetry;
  VoidCallback? get onOpenVerification => widget.onOpenVerification;
  ValueChanged<SellerHealthRestriction>? get onAppealRestriction =>
      widget.onAppealRestriction;

  @override
  void didUpdateWidget(covariant _AccountHealthSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sheetRevision.value++;
    });
  }

  @override
  void dispose() {
    _sheetRevision.dispose();
    super.dispose();
  }

  String get _headline {
    if (loading) return 'Checking account health…';
    if (error != null) return 'Could not refresh account health';
    final value = health;
    if (value == null) return 'Not available yet';
    if (value.hasActiveRestriction) return 'Restricted · review required';
    return switch (value.reviewStatus) {
      'approved' => 'Identity review approved',
      'pending' => 'Review in progress',
      'rejected' => 'Review declined · appeal available',
      _ => 'No review submitted',
    };
  }

  IconData get _icon {
    final value = health;
    if (value == null) return Icons.info_outline;
    if (value.hasActiveRestriction) return Icons.report_gmailerrorred_outlined;
    return switch (value.reviewStatus) {
      'approved' => Icons.verified_outlined,
      'pending' => Icons.hourglass_top_outlined,
      'rejected' => Icons.error_outline,
      _ => Icons.info_outline,
    };
  }

  Future<void> _showDetail(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: _sheetRevision,
        builder: (context, _, _) {
          final value = health;
          return SellerModalSheet(
            key: const Key('sellerAccountHealthSheet'),
            icon: Icons.monitor_heart_outlined,
            title: 'Account health',
            subtitle: 'Manual review status and recorded decisions.',
            onClose: () => Navigator.of(sheetContext).pop(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (loading)
                  const SellerProgressStrip(label: 'Checking your account…'),
                if (error != null || value == null) ...[
                  SellerStateNotice(
                    key: const Key('sellerAccountHealthNotice'),
                    icon: error != null
                        ? Icons.error_outline
                        : Icons.info_outline,
                    title: error != null
                        ? 'Could not refresh account health'
                        : loading
                        ? 'Checking account health…'
                        : 'Not available yet',
                    body:
                        error ??
                        (loading
                            ? 'Your verification and review status will appear here.'
                            : 'Account review is not connected in this build.'),
                    tone: error != null
                        ? SellerNoticeTone.error
                        : SellerNoticeTone.brand,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Hocalist reviews verification evidence and account reports '
                    'manually. A single report never changes your status '
                    'automatically. This indicator shows the review state, the '
                    'recorded reason for any restriction and the appeal path.',
                    style: sellerText(
                      metrics,
                      12,
                      color: SellerUiColors.body,
                      height: 1.4,
                    ),
                  ),
                ],
                if (value != null) ...[
                  SellerStateNotice(
                    icon: _icon,
                    title: _headline,
                    body: value.hasActiveRestriction
                        ? 'Read the recorded decision below. You can appeal a decision that has no appeal yet.'
                        : 'Your contact verification and evidence review are separate. Each status below comes from your account record.',
                    tone: value.hasActiveRestriction
                        ? SellerNoticeTone.error
                        : SellerNoticeTone.brand,
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 10) / 2;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: width,
                            child: HocalistStatusFact(
                              seller: true,
                              icon: Icons.alternate_email_rounded,
                              label:
                                  'Email ${value.emailVerified ? 'verified' : 'not verified'}',
                              confirmed: value.emailVerified,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: width,
                            child: HocalistStatusFact(
                              seller: true,
                              icon: Icons.phone_outlined,
                              label:
                                  'Phone ${value.phoneVerified ? 'verified' : 'not verified'}',
                              confirmed: value.phoneVerified,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Evidence review: ${value.reviewStatus.replaceAll('_', ' ')}',
                    style: sellerText(metrics, 12, color: SellerUiColors.body),
                  ),
                  if (value.restrictions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final restriction in value.restrictions) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: SellerUiColors.white,
                          border: Border.all(color: SellerUiColors.line),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${restriction.scope} restriction',
                              style: sellerText(
                                metrics,
                                12,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              restriction.reason,
                              style: sellerText(
                                metrics,
                                11.5,
                                color: SellerUiColors.body,
                                height: 1.35,
                              ),
                            ),
                            if (restriction.appealStatus != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Appeal: ${restriction.appealStatus}',
                                  style: sellerText(
                                    metrics,
                                    11,
                                    color: SellerUiColors.body,
                                  ),
                                ),
                              )
                            else if (onAppealRestriction != null)
                              TextButton(
                                key: Key(
                                  'sellerAccountAppeal${restriction.id}',
                                ),
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  onAppealRestriction!(restriction);
                                },
                                child: const Text('Appeal this decision'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (onOpenVerification != null) ...[
                    const SizedBox(height: 4),
                    SellerPrimaryButton(
                      key: const Key('sellerAccountVerificationAction'),
                      label: 'Manage verification evidence',
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onOpenVerification!();
                      },
                    ),
                  ],
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  SellerSecondaryButton(
                    key: const Key('sellerAccountHealthRefresh'),
                    label: loading
                        ? 'Checking…'
                        : error != null
                        ? 'Retry'
                        : 'Refresh status',
                    onPressed: loading ? null : onRetry,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = health;
    final completed = value == null || !value.loaded
        ? null
        : (value.emailVerified ? 1 : 0) +
              (value.phoneVerified ? 1 : 0) +
              (value.reviewStatus == 'approved' ? 1 : 0);
    return Semantics(
      label: completed == null
          ? 'Verification progress unavailable'
          : '$completed of 3 verification steps complete',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('sellerAccountHealth'),
          onTap: () => _showDetail(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountHealthBar(
                progress: completed == null ? 0 : completed / 3,
              ),
              if (completed != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$completed of 3 verification steps complete · View steps',
                    style: sellerText(
                      ApprovedReplicaScope.of(context),
                      11,
                      color: SellerUiColors.body,
                    ),
                  ),
                ),
              if (value?.hasActiveRestriction == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Restricted · review required',
                    style: sellerText(
                      ApprovedReplicaScope.of(context),
                      11,
                      weight: FontWeight.w800,
                      color: const Color(0xFFB42318),
                    ),
                  ),
                ),
              if (completed == null)
                Text(
                  'Not available yet',
                  style: sellerText(
                    ApprovedReplicaScope.of(context),
                    10,
                    color: SellerUiColors.body,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seller-role empty card used when an approved section has no records.
class _SellerHomeEmptyCard extends StatelessWidget {
  const _SellerHomeEmptyCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          padding: EdgeInsets.all(metrics.spacing(14)),
          decoration: BoxDecoration(
            color: SellerUiColors.white,
            border: Border.all(color: SellerUiColors.line),
            borderRadius: BorderRadius.circular(metrics.geometry(11)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: metrics.artSize(28),
                    color: SellerUiColors.primaryBright,
                  ),
                  SizedBox(width: metrics.geometry(9)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: sellerText(
                            metrics,
                            13,
                            weight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(3)),
                        Text(
                          body,
                          style: sellerText(
                            metrics,
                            11.5,
                            color: SellerUiColors.body,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: metrics.geometry(8)),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: SellerUiColors.primaryBright,
                    backgroundColor: SellerUiColors.lavender,
                    minimumSize: Size(0, metrics.geometry(34)),
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.geometry(10),
                      vertical: metrics.geometry(4),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel!,
                    style: sellerText(
                      metrics,
                      11,
                      weight: FontWeight.w700,
                      color: SellerUiColors.primaryBright,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Real recent leads rendered with the approved recent-lead row geometry.
class _RealRecentLeadsCard extends StatelessWidget {
  const _RealRecentLeadsCard({required this.leads, required this.onTap});

  final List<SellerLeadView> leads;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerHomeRealRecentLeads'),
      padding: EdgeInsets.symmetric(horizontal: metrics.geometry(11)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
        boxShadow: const [BoxShadow(color: Color(0x080A0D38), blurRadius: 14)],
      ),
      child: Column(
        children: [
          for (var index = 0; index < leads.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: SellerUiColors.line),
            _RecentLeadRow(
              data: (
                leads[index].initials,
                leads[index].request,
                leads[index].city,
                leads[index].budget,
                'Available',
                '',
                SellerUiColors.primaryBright,
                SellerUiColors.lavender,
                const Color(0xFFF2EFFF),
              ),
              onTap: onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountHealthBar extends StatelessWidget {
  const _AccountHealthBar({this.progress = 14 / 17});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    const colors = [
      SellerUiColors.red,
      SellerUiColors.red,
      SellerUiColors.red,
      SellerUiColors.amber,
      SellerUiColors.amber,
      Color(0xFFE4D700),
      Color(0xFFE4D700),
      Color(0xFF82D51B),
      Color(0xFF82D51B),
      Color(0xFF82D51B),
      SellerUiColors.green,
      SellerUiColors.green,
      SellerUiColors.green,
      SellerUiColors.green,
      SellerUiColors.green,
      SellerUiColors.green,
      SellerUiColors.green,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var index = 0; index < colors.length; index++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: HocalistMotion.duration(context, 350),
                        height: metrics.geometry(8),
                        margin: EdgeInsets.only(right: metrics.geometry(2)),
                        decoration: BoxDecoration(
                          color: index < (progress * colors.length).ceil()
                              ? colors[index]
                              : const Color(0xFFE8E9F3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: metrics.geometry(7)),
            Icon(
              Icons.info_outline,
              size: metrics.geometry(18),
              color: SellerUiColors.ink,
            ),
          ],
        );
      },
    );
  }
}

class _SellerMetricCard extends StatelessWidget {
  const _SellerMetricCard({
    required this.title,
    required this.value,
    required this.asset,
    required this.valueColor,
    required this.onTap,
    this.periodLabel = 'This month',
    this.actionLabel = 'View all leads',
  });

  final String title;
  final String value;
  final String asset;
  final Color valueColor;
  final VoidCallback onTap;
  final String? periodLabel;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          constraints: BoxConstraints(minHeight: metrics.geometry(130)),
          padding: EdgeInsets.all(metrics.geometry(13)),
          decoration: BoxDecoration(
            color: SellerUiColors.white,
            border: Border.all(color: SellerUiColors.line),
            borderRadius: BorderRadius.circular(metrics.geometry(11)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0A0D38),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: metrics.accessibilityReflow ? null : 1,
                      overflow: metrics.accessibilityReflow
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: sellerText(metrics, 12.5, weight: FontWeight.w700),
                    ),
                  ),
                  Icon(
                    Icons.info_outline,
                    size: metrics.geometry(16),
                    color: SellerUiColors.muted,
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(5)),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: sellerText(
                            metrics,
                            24,
                            weight: FontWeight.w800,
                            color: valueColor,
                          ),
                        ),
                        if (periodLabel != null)
                          Text(
                            periodLabel!,
                            style: sellerText(
                              metrics,
                              11,
                              color: SellerUiColors.body,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Image.asset(
                    asset,
                    width: metrics.artSize(48),
                    height: metrics.artSize(48),
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ],
              ),
              SizedBox(height: metrics.geometry(8)),
              TextButton.icon(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: SellerUiColors.primaryBright,
                  backgroundColor: SellerUiColors.lavender,
                  minimumSize: Size(0, metrics.geometry(32)),
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.geometry(8),
                    vertical: metrics.geometry(3),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(metrics.geometry(8)),
                  ),
                ),
                label: Text(
                  actionLabel,
                  maxLines: metrics.accessibilityReflow ? null : 1,
                  style: sellerText(
                    metrics,
                    10.5,
                    weight: FontWeight.w700,
                    color: SellerUiColors.primaryBright,
                  ),
                ),
                iconAlignment: IconAlignment.end,
                icon: Icon(Icons.chevron_right, size: metrics.geometry(16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindBuyersBanner extends StatelessWidget {
  const _FindBuyersBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          constraints: BoxConstraints(minHeight: metrics.geometry(84)),
          padding: EdgeInsets.fromLTRB(
            metrics.geometry(17),
            metrics.geometry(13),
            metrics.geometry(7),
            metrics.geometry(13),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7FF),
            border: Border.all(color: SellerUiColors.lavenderBorder),
            borderRadius: BorderRadius.circular(metrics.geometry(10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find more buyers',
                      style: sellerText(
                        metrics,
                        14,
                        weight: FontWeight.w800,
                        color: SellerUiColors.primaryBright,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(5)),
                    Text(
                      'Browse new buyer requests\nand target more leads.',
                      style: sellerText(
                        metrics,
                        11,
                        color: SellerUiColors.body,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: metrics.artSize(112),
                child: SellerPrimaryButton(
                  label: 'Browse requests',
                  onPressed: onTap,
                  fontSize: 10,
                  compact: true,
                  trailing: Icon(
                    Icons.chevron_right,
                    size: metrics.geometry(12),
                    color: SellerUiColors.white,
                  ),
                ),
              ),
              SizedBox(width: metrics.geometry(5)),
              Image.asset(
                SellerAssets.homeFindBuyers,
                width: metrics.artSize(76),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onAction,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: sellerText(metrics, 15, weight: FontWeight.w800),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: sellerText(metrics, 10.5, color: SellerUiColors.body),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: SellerUiColors.primaryBright,
            padding: EdgeInsets.symmetric(horizontal: metrics.geometry(3)),
            minimumSize: Size(0, metrics.geometry(36)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action,
            style: sellerText(
              metrics,
              11.5,
              weight: FontWeight.w700,
              color: SellerUiColors.primaryBright,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentLeadsCard extends StatelessWidget {
  const _RecentLeadsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    const leads = [
      (
        'HP',
        'iPad Air 5, 256GB',
        'Yonkers, NY  •  1.2 mi away',
        r'Budget: $500 - $700',
        'Offer Accepted',
        '12m ago',
        SellerUiColors.green,
        SellerUiColors.greenSurface,
        Color(0xFFF2EFFF),
      ),
      (
        'JM',
        'PS5 Console',
        'Brooklyn, NY  •  2.3 mi away',
        r'Budget: $450 - $550',
        'Pending',
        '25m ago',
        SellerUiColors.amber,
        SellerUiColors.amberSurface,
        Color(0xFFECF8EE),
      ),
      (
        'SL',
        'iPhone 15 Pro Max',
        'Staten Island, NY  •  5.7 mi away',
        r'Budget: $800 - $1,000',
        'Declined',
        '1h ago',
        SellerUiColors.red,
        SellerUiColors.redSurface,
        Color(0xFFFFEFE6),
      ),
    ];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.geometry(11)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
        boxShadow: const [BoxShadow(color: Color(0x080A0D38), blurRadius: 14)],
      ),
      child: Column(
        children: [
          for (var index = 0; index < leads.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: SellerUiColors.line),
            _RecentLeadRow(data: leads[index], onTap: onTap),
          ],
        ],
      ),
    );
  }
}

class _RecentLeadRow extends StatelessWidget {
  const _RecentLeadRow({required this.data, required this.onTap});

  final (String, String, String, String, String, String, Color, Color, Color)
  data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final (
      initials,
      title,
      location,
      budget,
      status,
      time,
      statusColor,
      statusSurface,
      avatarSurface,
    ) = data;
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: metrics.geometry(10)),
            child: Row(
              children: [
                Container(
                  width: metrics.geometry(42),
                  height: metrics.geometry(42),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: avatarSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials,
                    style: sellerText(metrics, 17, color: statusColor),
                  ),
                ),
                SizedBox(width: metrics.geometry(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: metrics.accessibilityReflow ? null : 1,
                        overflow: metrics.accessibilityReflow
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: sellerText(
                          metrics,
                          12.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        location,
                        maxLines: metrics.accessibilityReflow ? null : 1,
                        overflow: metrics.accessibilityReflow
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: sellerText(
                          metrics,
                          10.5,
                          color: SellerUiColors.body,
                        ),
                      ),
                      Text(
                        budget,
                        maxLines: metrics.accessibilityReflow ? null : 1,
                        overflow: metrics.accessibilityReflow
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: sellerText(
                          metrics,
                          10.5,
                          color: SellerUiColors.body,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.geometry(5)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.geometry(7),
                        vertical: metrics.geometry(3),
                      ),
                      decoration: BoxDecoration(
                        color: statusSurface,
                        borderRadius: BorderRadius.circular(
                          metrics.geometry(6),
                        ),
                      ),
                      child: Text(
                        status,
                        style: sellerText(
                          metrics,
                          9.5,
                          color: statusColor,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: metrics.geometry(5)),
                    Text(
                      time,
                      style: sellerText(
                        metrics,
                        9.5,
                        color: SellerUiColors.body,
                      ),
                    ),
                  ],
                ),
                Icon(
                  Icons.chevron_right,
                  size: metrics.geometry(20),
                  color: SellerUiColors.body,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendedLeadCard extends StatelessWidget {
  const _RecommendedLeadCard({
    this.image,
    this.initial,
    required this.title,
    required this.location,
    required this.match,
    required this.budget,
    required this.onTap,
  });

  final String? image;

  /// Buyer initials variant used by real recommended leads. Supplied artwork is
  /// never substituted; real cards keep the approved geometry with the buyer
  /// initials circle instead of a prototype product photo.
  final String? initial;
  final String title;
  final String location;
  final String match;
  final String budget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final photo = initial != null
        ? Container(
            width: metrics.artSize(36),
            height: metrics.artSize(36),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFF2EFFF),
              shape: BoxShape.circle,
            ),
            child: Text(
              initial!,
              style: sellerText(
                metrics,
                13,
                weight: FontWeight.w800,
                color: SellerUiColors.primaryBright,
              ),
            ),
          )
        : ClipOval(
            child: Image.asset(
              image!,
              width: metrics.artSize(36),
              height: metrics.artSize(36),
              fit: BoxFit.cover,
            ),
          );
    final titleText = Text(
      title,
      maxLines: metrics.accessibilityReflow ? null : 2,
      overflow: metrics.accessibilityReflow
          ? TextOverflow.visible
          : TextOverflow.ellipsis,
      style: sellerText(metrics, 10, weight: FontWeight.w700, height: 1.15),
    );
    final hotBadge = Container(
      margin: EdgeInsets.only(top: metrics.geometry(2)),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.geometry(4),
        vertical: metrics.geometry(1),
      ),
      decoration: BoxDecoration(
        color: SellerUiColors.lavender,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: metrics.geometry(1),
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: metrics.geometry(9),
            color: SellerUiColors.primaryBright,
          ),
          Text(
            'Hot',
            style: sellerText(
              metrics,
              8.5,
              color: SellerUiColors.primaryBright,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Container(
          constraints: BoxConstraints(minHeight: metrics.geometry(145)),
          padding: EdgeInsets.all(metrics.geometry(9)),
          decoration: BoxDecoration(
            color: SellerUiColors.white,
            border: Border.all(color: SellerUiColors.line),
            borderRadius: BorderRadius.circular(metrics.geometry(10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (metrics.accessibilityReflow) ...[
                photo,
                SizedBox(height: metrics.geometry(5)),
                titleText,
                if (initial == null) hotBadge,
              ] else
                Row(
                  children: [
                    photo,
                    SizedBox(width: metrics.geometry(6)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [titleText, if (initial == null) hotBadge],
                      ),
                    ),
                  ],
                ),
              SizedBox(height: metrics.geometry(8)),
              Text(
                location,
                maxLines: metrics.accessibilityReflow ? null : 1,
                overflow: metrics.accessibilityReflow
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: sellerText(metrics, 9.5, color: SellerUiColors.body),
              ),
              SizedBox(height: metrics.geometry(6)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.geometry(5),
                  vertical: metrics.geometry(2),
                ),
                decoration: BoxDecoration(
                  color: SellerUiColors.greenSurface,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  match,
                  style: sellerText(
                    metrics,
                    9,
                    color: SellerUiColors.green,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: metrics.geometry(6)),
              Text(
                budget,
                maxLines: metrics.accessibilityReflow ? null : 1,
                overflow: metrics.accessibilityReflow
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: sellerText(metrics, 9.3, color: SellerUiColors.body),
              ),
              SizedBox(height: metrics.geometry(6)),
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.only(top: metrics.geometry(6)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Prepare offer',
                          maxLines: metrics.accessibilityReflow ? null : 1,
                          style: sellerText(
                            metrics,
                            10.5,
                            color: SellerUiColors.primaryBright,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: metrics.geometry(17),
                        color: SellerUiColors.primaryBright,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
