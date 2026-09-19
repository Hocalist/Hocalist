import 'package:flutter/material.dart';

import '../../theme/seller_ui_foundation.dart';

class ApprovedSellerHomePage extends StatelessWidget {
  const ApprovedSellerHomePage({
    required this.onLeads,
    required this.onBrowseRequests,
    super.key,
  });

  final VoidCallback onLeads;
  final VoidCallback onBrowseRequests;

  @override
  Widget build(BuildContext context) {
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
              const _SellerHero(),
              SizedBox(height: metrics.spacing(14)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SellerMetricCard(
                      title: 'Leads targeted',
                      value: '56',
                      asset: SellerAssets.homeTarget,
                      valueColor: SellerUiColors.primaryBright,
                      onTap: onLeads,
                    ),
                  ),
                  SizedBox(width: metrics.spacing(10)),
                  Expanded(
                    child: _SellerMetricCard(
                      title: 'Deals closed',
                      value: '12',
                      asset: SellerAssets.homeDeals,
                      valueColor: SellerUiColors.green,
                      onTap: onLeads,
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.spacing(13)),
              _FindBuyersBanner(onTap: onBrowseRequests),
              SizedBox(height: metrics.spacing(14)),
              _SectionTitle(
                title: 'Recent leads',
                action: 'View all',
                onAction: onLeads,
              ),
              SizedBox(height: metrics.spacing(8)),
              _RecentLeadsCard(onTap: onLeads),
              SizedBox(height: metrics.spacing(14)),
              _SectionTitle(
                title: 'Recommended leads for you',
                subtitle: 'Buyers looking for what you offer',
                action: 'View all',
                onAction: onLeads,
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
                      onTap: onBrowseRequests,
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
                      onTap: onBrowseRequests,
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
                      onTap: onBrowseRequests,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SellerHero extends StatelessWidget {
  const _SellerHero();

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
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

class _AccountHealthBar extends StatelessWidget {
  const _AccountHealthBar();

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
      Color(0xFFE8E9F3),
      Color(0xFFE8E9F3),
      Color(0xFFE8E9F3),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final color in colors)
                    Expanded(
                      child: Container(
                        height: metrics.geometry(8),
                        margin: EdgeInsets.only(right: metrics.geometry(2)),
                        decoration: BoxDecoration(
                          color: color,
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
  });

  final String title;
  final String value;
  final String asset;
  final Color valueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
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
                    Text(
                      'This month',
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
              'View all leads',
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
    );
  }
}

class _FindBuyersBanner extends StatelessWidget {
  const _FindBuyersBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
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
    return InkWell(
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
                    style: sellerText(metrics, 12.5, weight: FontWeight.w700),
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
                    borderRadius: BorderRadius.circular(metrics.geometry(6)),
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
                  style: sellerText(metrics, 9.5, color: SellerUiColors.body),
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
    );
  }
}

class _RecommendedLeadCard extends StatelessWidget {
  const _RecommendedLeadCard({
    required this.image,
    required this.title,
    required this.location,
    required this.match,
    required this.budget,
    required this.onTap,
  });

  final String image;
  final String title;
  final String location;
  final String match;
  final String budget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final photo = ClipOval(
      child: Image.asset(
        image,
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
    return Container(
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
            hotBadge,
          ] else
            Row(
              children: [
                photo,
                SizedBox(width: metrics.geometry(6)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [titleText, hotBadge],
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
    );
  }
}
