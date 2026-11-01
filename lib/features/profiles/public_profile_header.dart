import 'package:flutter/material.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../media/private_remote_image.dart';
import 'profile_rating_stars.dart';

class PublicProfileStats extends StatelessWidget {
  const PublicProfileStats({super.key, required this.values, this.rating});
  final Map<String, String> values;
  final double? rating;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final columns = bounds.maxWidth >= 560 ? 3 : bounds.maxWidth >= 300 ? 2 : 1;
    return Wrap(spacing: 12, runSpacing: 16, children: values.entries.map((entry) => SizedBox(
      width: (bounds.maxWidth - 12 * (columns - 1)) / columns,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(entry.key, style: TextStyle(fontSize: 12, color: HocalistPalette.text(context, BuyerUiTokens.muted))),
          if (entry.key == 'Rating' && rating != null) ProfileRatingStars(rating: rating!, size: 15),
        ]),
        const SizedBox(height: 4),
        Text(entry.value, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800,
          fontSize: 15, color: HocalistPalette.text(context, BuyerUiTokens.text))),
      ]),
    )).toList());
  });
}

/// Shared public presentation. All facts and badges come from visible profile data.
class PublicProfileHeader extends StatelessWidget {
  const PublicProfileHeader({super.key, required this.name, required this.role,
    this.subtitle, this.avatarId, this.badges = const [], required this.stats});
  final String name, role;
  final String? subtitle, avatarId;
  final List<String> badges;
  final Widget stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final bannerHeight = (bounds.maxWidth * .40).clamp(120.0, 190.0);
    final avatarSize = (bounds.maxWidth * .22).clamp(76.0, 96.0);
    final surface = HocalistPalette.surface(context, Colors.white);
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty)
        .take(2).map((p) => p.characters.first.toUpperCase()).join();
    return Container(
      key: ValueKey('public-profile-header-${role.toLowerCase()}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: HocalistPalette.border(context, BuyerUiTokens.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: bannerHeight + avatarSize / 2, child: Stack(children: [
          Positioned(top: 0, left: 0, right: 0, height: bannerHeight,
            child: Image.asset('assets/profile/purple-waves.png', fit: BoxFit.cover, excludeFromSemantics: true)),
          Positioned(left: 20, bottom: 0, child: Container(
            width: avatarSize, height: avatarSize, padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
            child: ClipOval(child: avatarId?.isNotEmpty == true
              ? PrivateRemoteImage(id: avatarId!)
              : ColoredBox(color: const Color(0xffe9ddff), child: Center(child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff381678)))))),
          )),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name, style: TextStyle(fontFamily: 'Nunito', fontSize: 24,
              fontWeight: FontWeight.w900, color: HocalistPalette.text(context, BuyerUiTokens.text))),
            const SizedBox(height: 4),
            Text([role, if (subtitle?.trim().isNotEmpty == true) subtitle!].join(' · ')),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: badges.map((label) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              )).toList()),
            ],
            const SizedBox(height: 16),
            Divider(color: HocalistPalette.border(context, BuyerUiTokens.border)),
            const SizedBox(height: 12),
            stats,
          ],
        )),
      ]),
    );
  });
}
