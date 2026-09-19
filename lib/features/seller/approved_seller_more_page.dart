import 'package:flutter/material.dart';

import '../../theme/seller_ui_foundation.dart';

class ApprovedSellerMorePage extends StatelessWidget {
  const ApprovedSellerMorePage({
    required this.sellerName,
    required this.onProfile,
    required this.onEditProfile,
    required this.onSettings,
    required this.onNotifications,
    required this.onAccessibility,
    required this.onSafety,
    required this.onHelp,
    required this.onLogout,
    this.onOfferHistory,
    this.onBilling,
    this.sellerEmail = 'northside.tech@example.com',
    super.key,
  });

  final String sellerName;
  final String sellerEmail;
  final VoidCallback onProfile;
  final VoidCallback onEditProfile;
  final VoidCallback onSettings;
  final VoidCallback onNotifications;
  final VoidCallback onAccessibility;
  final VoidCallback onSafety;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback? onOfferHistory;
  final VoidCallback? onBilling;

  @override
  Widget build(BuildContext context) {
    return SellerResponsivePage(
      builder: (context, metrics) {
        return ListView(
          key: const Key('sellerMoreList'),
          padding: EdgeInsets.fromLTRB(
            metrics.pageHorizontalPadding(14),
            metrics.spacing(14),
            metrics.pageHorizontalPadding(14),
            metrics.spacing(18),
          ),
          children: [
            Text(
              'More',
              textAlign: TextAlign.left,
              style: sellerText(metrics, 17, weight: FontWeight.w800),
            ),
            SizedBox(height: metrics.spacing(10)),
            _ProfileCard(
              sellerName: sellerName,
              sellerEmail: sellerEmail,
              onProfile: onProfile,
              onEditProfile: onEditProfile,
            ),
            if (onOfferHistory != null || onBilling != null) ...[
              SizedBox(height: metrics.spacing(14)),
              _MoreSection(
                title: 'Seller tools',
                items: [
                  if (onOfferHistory != null)
                    _MoreItem(
                      keyName: 'sellerMoreOfferHistory',
                      icon: Icons.local_offer_outlined,
                      label: 'Offer history',
                      onTap: onOfferHistory!,
                    ),
                  if (onBilling != null)
                    _MoreItem(
                      keyName: 'sellerMoreBilling',
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Plans & credits',
                      onTap: onBilling!,
                    ),
                ],
              ),
            ],
            SizedBox(height: metrics.spacing(14)),
            _MoreSection(
              title: 'Account',
              items: [
                _MoreItem(
                  keyName: 'sellerMoreSettings',
                  icon: Icons.settings_outlined,
                  label: 'Account settings',
                  onTap: onSettings,
                ),
                _MoreItem(
                  keyName: 'sellerMoreNotifications',
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  onTap: onNotifications,
                ),
                _MoreItem(
                  keyName: 'sellerMoreAccessibility',
                  icon: Icons.accessibility_new,
                  label: 'Accessibility',
                  onTap: onAccessibility,
                ),
              ],
            ),
            SizedBox(height: metrics.spacing(12)),
            _MoreSection(
              title: 'Safety & help',
              items: [
                _MoreItem(
                  keyName: 'sellerMoreSafety',
                  icon: Icons.shield_outlined,
                  label: 'Safety guide',
                  onTap: onSafety,
                ),
                _MoreItem(
                  keyName: 'sellerMoreHelp',
                  icon: Icons.help_outline,
                  label: 'Help & support',
                  onTap: onHelp,
                ),
              ],
            ),
            SizedBox(height: metrics.spacing(16)),
            OutlinedButton.icon(
              key: const Key('sellerMoreLogout'),
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SellerUiColors.red,
                minimumSize: Size(0, metrics.geometry(50)),
                side: const BorderSide(color: SellerUiColors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.sellerName,
    required this.sellerEmail,
    required this.onProfile,
    required this.onEditProfile,
  });

  final String sellerName;
  final String sellerEmail;
  final VoidCallback onProfile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final avatar = CircleAvatar(
      radius: metrics.artSize(22),
      backgroundColor: SellerUiColors.lavender,
      foregroundColor: SellerUiColors.primaryBright,
      child: Icon(Icons.person_outline, size: metrics.artSize(23)),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sellerName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sellerText(metrics, 14, weight: FontWeight.w800),
        ),
        SizedBox(height: metrics.spacing(2)),
        Text(
          sellerEmail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sellerText(metrics, 11, color: SellerUiColors.muted),
        ),
      ],
    );
    final identity = InkWell(
      key: const Key('sellerMoreProfile'),
      onTap: onProfile,
      borderRadius: BorderRadius.circular(metrics.geometry(9)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: metrics.spacing(3)),
        child: Row(
          children: [
            avatar,
            SizedBox(width: metrics.spacing(11)),
            Expanded(child: details),
          ],
        ),
      ),
    );
    final edit = TextButton(
      key: const Key('sellerMoreEditProfile'),
      onPressed: onEditProfile,
      style: TextButton.styleFrom(
        minimumSize: Size(metrics.geometry(44), metrics.geometry(40)),
        foregroundColor: SellerUiColors.primaryBright,
        padding: EdgeInsets.symmetric(horizontal: metrics.spacing(8)),
      ),
      child: Text(
        'Edit profile',
        style: sellerText(
          metrics,
          12,
          weight: FontWeight.w800,
          color: SellerUiColors.primaryBright,
        ),
      ),
    );
    return Container(
      key: const Key('sellerMoreIdentityCard'),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101054),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(metrics.geometry(10)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(metrics.spacing(13)),
          child: metrics.accessibilityReflow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    SizedBox(height: metrics.spacing(6)),
                    Align(alignment: Alignment.centerRight, child: edit),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    SizedBox(width: metrics.spacing(8)),
                    edit,
                  ],
                ),
        ),
      ),
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({required this.title, required this.items});
  final String title;
  final List<_MoreItem> items;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: metrics.geometry(3)),
          child: Text(
            title,
            style: sellerText(metrics, 13, weight: FontWeight.w800),
          ),
        ),
        SizedBox(height: metrics.geometry(6)),
        Material(
          color: SellerUiColors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: SellerUiColors.line),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                items[index],
                if (index != items.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    color: SellerUiColors.line,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.keyName,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return ListTile(
      key: Key(keyName),
      onTap: onTap,
      minTileHeight: metrics.geometry(54),
      leading: Icon(icon, color: SellerUiColors.primaryBright),
      title: Text(
        label,
        style: sellerText(metrics, 13, weight: FontWeight.w700),
      ),
      trailing: const Icon(Icons.chevron_right, color: SellerUiColors.muted),
    );
  }
}
