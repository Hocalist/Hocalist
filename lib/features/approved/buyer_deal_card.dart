import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../../theme/adaptive_palette.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../domain/phase2/commercial/commercial.dart' show PlanCode;
import '../media/private_remote_image.dart';
import '../media/listing_image_placeholder.dart';
import 'approved_replica_metrics.dart';

/// Public, server-provided seller information. Missing data never becomes a
/// fabricated rating, verified badge or sales count.
class BuyerDealSeller {
  const BuyerDealSeller({this.avatarId, this.verified = false,
    this.rating, this.reviewCount, this.sales, this.plan});
  final String? avatarId;
  final bool verified;
  final double? rating;
  final int? reviewCount, sales;
  final PlanCode? plan;
}

typedef BuyerDealSellerLoader = Future<BuyerDealSeller> Function(String profileId);

ApprovedReplicaMetrics _dealMetrics(BuildContext context) =>
  ApprovedReplicaScope.maybeOf(context) ?? ApprovedReplicaMetrics.resolve(
    availableWidth: MediaQuery.sizeOf(context).width,
    textScaler: MediaQuery.textScalerOf(context), brightness: Theme.of(context).brightness);
TextStyle dealText(BuildContext context, double size, {bool bold = false, Color? color, FontWeight? weight}) {
  final metrics = _dealMetrics(context);
  return BuyerTypography.homeStyle(context, metrics, size: size,
    weight: weight ?? (bold ? FontWeight.w800 : FontWeight.w400),
    color: color ?? BuyerUiTokens.text);
}

Widget dealArtwork(String name, {double size = 20}) => BuyerAssetIcon(
  asset: 'assets/approved_offers_chat/$name.png', slotSize: size);

class BuyerDealSellerHeader extends StatelessWidget {
  const BuyerDealSellerHeader({super.key, required this.name, this.profileId,
    this.load, this.onProfile, this.trailing, this.showSales = true, this.compact = false,
    this.prominent = false, this.dense = false, this.stackedIdentity = false});
  final String name;
  final String? profileId;
  final BuyerDealSellerLoader? load;
  final VoidCallback? onProfile;
  final Widget? trailing;
  final bool showSales, compact, prominent, dense, stackedIdentity;

  @override
  Widget build(BuildContext context) => FutureBuilder<BuyerDealSeller>(
    future: profileId == null ? null : load?.call(profileId!),
    builder: (context, snapshot) {
      final seller = snapshot.data;
      final initials = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty)
        .take(2).map((s) => s[0]).join().toUpperCase();
      final large = prominent && !compact;
      final avatarSize = stackedIdentity ? 40.0 : compact ? 32.0 : dense ? 36.0 : large ? 56.0 : 44.0;
      final avatar = ClipOval(
        child: seller?.avatarId != null
            ? PrivateRemoteImage(id: seller!.avatarId!, size: avatarSize)
            : Container(width: avatarSize, height: avatarSize, alignment: Alignment.center,
                color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
                child: Text(initials, style: dealText(context, 15, bold: true, color: BuyerUiTokens.action))),
      );
      if (stackedIdentity) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            foregroundDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xff201e33) : Colors.white,
                width: 2,
              ),
            ),
            child: avatar,
          ),
          const SizedBox(height: 3),
          Text(name, textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis, style: TextStyle(
              fontFamily: 'Roboto', fontSize: 12, height: 1.35, fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xfffaf8ff) : const Color(0xff19152f),
            )),
        ]);
      }
      final salesStyle = dealText(context, large && !dense ? 11 : 10, bold: true);
      final salesWord = TextPainter(text: TextSpan(text: 'Confirmed', style: salesStyle),
        textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
      final baseSalesWidth = dense ? 64.0 : large ? 82.0 : 76.0;
      final salesWidth = salesWord.width + 1 > baseSalesWidth ? salesWord.width + 1 : baseSalesWidth;
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Semantics(button: onProfile != null, label: 'View $name profile', child: InkWell(
          onTap: onProfile, borderRadius: BorderRadius.circular(24),
          child: avatar)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (compact) Text('Seller', style: dealText(context, 9, color: BuyerUiTokens.muted)),
          Row(children: [
            Flexible(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: dealText(context, compact ? 11 : 14, bold: true))),
          ]),
          if (!compact && seller?.verified == true) Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            dealArtwork('detail-verified', size: 14),
            Text('Verified seller', style: dealText(context, 11, weight: FontWeight.w700, color: BuyerUiTokens.action)),
          ]),
          if (!compact && seller?.reviewCount != null) Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (seller?.rating != null) dealArtwork('detail-star', size: 13),
            Text(seller!.rating == null ? 'No reviews yet' :
              '${seller.rating!.toStringAsFixed(1)} (${seller.reviewCount} ${seller.reviewCount == 1 ? 'review' : 'reviews'})',
              style: dealText(context, large && !dense ? 12 : 11, color: BuyerUiTokens.muted)),
          ]),
          if (!compact && snapshot.hasError) Text('Seller details unavailable', style: dealText(context, 10, color: BuyerUiTokens.muted)),
        ])),
        if (trailing != null) trailing!
        else if (showSales && seller?.sales != null) ...[
          const SizedBox(width: 10),
          Container(padding: EdgeInsets.only(left: large ? 10 : 0),
            decoration: large ? BoxDecoration(border: Border(left: BorderSide(
              color: HocalistPalette.border(context, BuyerUiTokens.border)))) : null,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: salesWidth), child: Column(children: [
              Text('${seller!.sales}', style: dealText(context, 20, bold: true)),
              Text('Confirmed sales', textAlign: TextAlign.center, style: salesStyle),
            ]))),
        ],
      ]);
    });
}

/// Shared approved offer composition for Offers and Deals in progress.
/// Width controls the photo size; text scales progressively and actions reflow
/// only when two readable buttons cannot fit.
class BuyerDealCard extends StatefulWidget {
  const BuyerDealCard({super.key, required this.sellerName, required this.title,
    required this.price, required this.meeting, required this.place,
    required this.message, required this.onChat, this.onDecline, this.onAccept,
    this.onOptions, this.onProfile, this.sellerProfileId, this.loadSeller,
    this.photos = const [], this.busy = false, this.readImage, this.distanceLabel,
    this.comparison = false, this.availability});
  final String sellerName, title, price, meeting, place, message;
  final String? sellerProfileId;
  final String? distanceLabel;
  final String? availability;
  final bool comparison;
  final BuyerDealSellerLoader? loadSeller;
  final List<String> photos;
  final VoidCallback? onChat, onDecline, onAccept, onOptions, onProfile;
  final bool busy;
  final Future<Uint8List> Function(String)? readImage;
  @override
  State<BuyerDealCard> createState() => _BuyerDealCardState();
}

class _BuyerDealCardState extends State<BuyerDealCard> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    if (widget.comparison) {
      return _BuyerOfferComparison(
        offer: widget, expanded: expanded,
        onTogglePhotos: () => setState(() => expanded = !expanded),
      );
    }
    final width = constraints.maxWidth;
    final metrics = _dealMetrics(context);
    final receivedOffer = widget.onAccept == null;
    final hasDetails = widget.photos.length > 1;
    final photoSize = (width * .22).clamp(64.0, 84.0);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stackActions = width < 330 && scale > 1.2 || scale >= 1.5;
    final primary = BuyerPrimaryButton(label: widget.busy ? 'Opening…' : widget.onAccept != null
      ? 'Accept offer and meet' : 'Chat with seller', fontSize: 13,
      minimumHeight: 48,
      onLongPress: widget.onAccept == null ? null : widget.onOptions,
      onPressed: widget.busy ? null : widget.onAccept ?? widget.onChat);
    final secondary = Theme(data: Theme.of(context).copyWith(
      visualDensity: VisualDensity.standard, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: BuyerSecondaryButton(label: 'Decline offer', fontSize: 13,
        minimumHeight: 48, onPressed: widget.busy ? null : widget.onDecline));
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HocalistPalette.surface(context, BuyerUiTokens.surface),
        borderRadius: BorderRadius.circular(receivedOffer ? 22 : 18),
        border: Border.all(color: HocalistPalette.border(context, BuyerUiTokens.border)),
        boxShadow: receivedOffer ? [BoxShadow(color: BuyerUiTokens.action.withValues(alpha: .06),
          blurRadius: 12, offset: const Offset(0, 4))] : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BuyerDealSellerHeader(name: widget.sellerName, profileId: widget.sellerProfileId,
          load: widget.loadSeller, onProfile: widget.onProfile, prominent: receivedOffer, dense: true,
          trailing: widget.onAccept == null ? null : IconButton(
            tooltip: 'Chat with seller', onPressed: widget.busy ? null : widget.onChat,
            icon: dealArtwork('nav-chats', size: 24))),
        const Divider(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: widget.photos.isEmpty
            ? ListingImagePlaceholder(size: photoSize)
            : PrivateRemoteImage(id: widget.photos.first, size: photoSize, showWholeImage: true, read: widget.readImage)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: dealText(context, 14, bold: true)),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
                borderRadius: BorderRadius.circular(12)),
              child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const BuyerAssetIcon(asset: 'assets/post_request/field-title-tag.png', slotSize: 20),
                Text(widget.price, style: dealText(context, 20, bold: true, color: BuyerUiTokens.action)),
              ])),
          ])),
        ]),
        const SizedBox(height: 8),
        Container(padding: metrics.geometryInsets(const EdgeInsets.symmetric(horizontal: 8, vertical: 7)), decoration: BoxDecoration(
          color: HocalistPalette.surface(context, BuyerUiTokens.softSurface), borderRadius: BorderRadius.circular(metrics.geometry(12))),
          child: LayoutBuilder(builder: (context, factConstraints) {
            final facts = [
              _DealFact('offers-calendar', 'Meet-up', widget.meeting),
              _DealFact('detail-location', receivedOffer ? 'Meet-up place' : 'Available',
                receivedOffer ? widget.place : widget.meeting),
              _DealFact('detail-clock', receivedOffer ? 'Available' : 'Distance',
                receivedOffer ? widget.meeting : widget.distanceLabel ?? 'Unavailable'),
            ];
            // Keep the approved row at normal/slightly enlarged text sizes.
            // Larger accessibility settings can reflow if measured space needs it.
            final minimumWidth = facts.map((fact) => fact.minimumWidth(context))
              .reduce((a, b) => a > b ? a : b);
            var columns = 3;
            while (metrics.accessibilityReflow && columns > 1 &&
                (factConstraints.maxWidth - (columns - 1) * metrics.geometry(8)) / columns < minimumWidth) {
              columns--;
            }
            return Column(children: [
              for (var start = 0; start < facts.length; start += columns) ...[
                if (start > 0) SizedBox(height: metrics.geometry(8)),
                IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var index = start; index < start + columns && index < facts.length; index++) ...[
                    if (index > start) VerticalDivider(width: metrics.geometry(8), thickness: metrics.geometry(1), indent: metrics.geometry(3), endIndent: metrics.geometry(3),
                      color: HocalistPalette.border(context, BuyerUiTokens.border)),
                    Expanded(child: facts[index]),
                  ],
                ])),
              ],
            ]);
          })),
        const SizedBox(height: 8),
        if (widget.onAccept != null) primary
        else if (widget.onDecline != null)
          if (stackActions) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            primary, const SizedBox(height: 8), secondary])
          else IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: primary), const SizedBox(width: 8), Expanded(child: secondary)]))
        else primary,
        if (hasDetails) ...[
        const SizedBox(height: 4),
        Align(alignment: Alignment.center, child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: BuyerUiTokens.action,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ).copyWith(overlayColor: WidgetStateProperty.resolveWith((states) =>
              states.any({WidgetState.hovered, WidgetState.focused, WidgetState.pressed}.contains)
                ? BuyerUiTokens.action.withValues(alpha: .06) : Colors.transparent)),
            onPressed: () => setState(() => expanded = !expanded),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(expanded ? 'Less details' : 'More details', style: dealText(context, 13, weight: FontWeight.w700, color: BuyerUiTokens.action)),
              const SizedBox(width: 6), RotatedBox(quarterTurns: expanded ? 2 : 0, child: dealArtwork('offers-sort-down', size: 18)),
            ]))),
        ],
        if (expanded && hasDetails) ...[
          if (widget.photos.length > 1) Padding(padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: widget.photos.skip(1).map((id) =>
              ClipRRect(borderRadius: BorderRadius.circular(10), child: PrivateRemoteImage(id: id, size: 76, read: widget.readImage))).toList())),
        ],
      ]));
  });
}

class _BuyerOfferComparison extends StatelessWidget {
  const _BuyerOfferComparison({
    required this.offer,
    required this.expanded,
    required this.onTogglePhotos,
  });

  final BuyerDealCard offer;
  final bool expanded;
  final VoidCallback onTogglePhotos;

  static const _photoWidth = 76.0;
  static const _photoHeight = 82.0;
  static const _portraitSize = 40.0;

  TextStyle _text(double size, Color color, {FontWeight weight = FontWeight.w400, double height = 1.4}) =>
      TextStyle(fontFamily: 'Roboto', fontSize: size, color: color, fontWeight: weight, height: height);

  Widget _itemPhoto(String? id) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: id == null
        ? const ListingImagePlaceholder(size: _photoWidth, height: _photoHeight)
        : PrivateRemoteImage(
            id: id, size: _photoWidth, height: _photoHeight,
            showWholeImage: true, read: offer.readImage,
          ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xff19192a) : Colors.white;
    final page = dark ? const Color(0xff111120) : const Color(0xfff7f7fc);
    final ink = dark ? const Color(0xfffaf8ff) : const Color(0xff17152e);
    final sub = dark ? const Color(0xffb7b2ce) : const Color(0xff625e78);
    final border = dark ? const Color(0xff35314e) : const Color(0xffe9e6f4);
    final brand = dark ? const Color(0xffc5b5ff) : const Color(0xff3920ba);
    final soft = dark ? const Color(0xff332652) : const Color(0xffeee9ff);
    final accent = dark ? const Color(0xff472d9c) : const Color(0xff3220b9);
    final green = dark ? const Color(0xffb1edcd) : const Color(0xff196346);
    final profileId = offer.sellerProfileId;
    final initials = offer.sellerName.trim().split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty).take(2)
        .map((part) => part.characters.first.toUpperCase()).join();

    Widget button(String label, VoidCallback? onPressed, {bool primary = false}) =>
        TextButton(
          onPressed: offer.busy ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: primary ? Colors.white : brand,
            backgroundColor: primary ? accent : paper,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.all(5),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: primary ? accent : brand),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: _text(12, primary ? Colors.white : brand, weight: FontWeight.w600),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (primary) ...[
              const Icon(Icons.chat_bubble_outline_rounded, size: 15),
              const SizedBox(width: 5),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ]),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: paper, border: Border.all(color: border), borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 6),
          child: FutureBuilder<BuyerDealSeller>(
            future: profileId == null ? null : offer.loadSeller?.call(profileId),
            builder: (context, snapshot) {
              final seller = snapshot.data;
              final plan = seller?.plan;
              final premium = plan == PlanCode.pro || plan == PlanCode.elite;
              final elite = plan == PlanCode.elite;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _itemPhoto(offer.photos.firstOrNull),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(offer.price, style: _text(18, brand, weight: FontWeight.w700)),
                  InkWell(
                    onTap: offer.onProfile,
                    child: Text(offer.sellerName, style: _text(17, ink, weight: FontWeight.w700, height: 1.25)
                        .copyWith(letterSpacing: -.28)),
                  ),
                  if (premium) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: elite ? (dark ? const Color(0xff4b3722) : const Color(0xfffff0d7)) : soft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(elite ? 'Elite' : 'Pro', style: _text(11,
                            elite ? (dark ? const Color(0xffffe2ae) : const Color(0xff6d4217)) : brand,
                            weight: FontWeight.w600)),
                        ),
                        if (seller?.verified == true)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.verified_outlined, size: 14, color: green),
                            const SizedBox(width: 3),
                            Flexible(child: Text('Verified seller', style: _text(11, green, weight: FontWeight.w600))),
                          ]),
                      ],
                    ),
                    if (seller?.sales case final sales?) ...[
                      const SizedBox(height: 2),
                      Text(sales == 1 ? '1 confirmed sale' : '$sales confirmed sales', style: _text(12, sub)),
                    ],
                  ],
                ])),
                const SizedBox(width: 9),
                Container(
                  foregroundDecoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: border)),
                  child: ClipOval(
                    child: seller?.avatarId != null
                        ? PrivateRemoteImage(id: seller!.avatarId!, size: _portraitSize)
                        : Container(
                            width: _portraitSize, height: _portraitSize,
                            color: soft, alignment: Alignment.center,
                            child: Text(initials, style: _text(13, brand, weight: FontWeight.w600)),
                          ),
                  ),
                ),
              ]);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(color: page, border: Border(top: BorderSide(color: border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _fact(Icons.event_outlined, 'Proposed meetup', offer.meeting, sub, ink),
            const SizedBox(height: 4),
            _fact(Icons.location_on_outlined, 'Meetup place', offer.place, sub, ink),
            const SizedBox(height: 4),
            _fact(Icons.event_available_outlined, 'Available from', offer.availability ?? 'Not specified', sub, ink),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(flex: 23, child: button(offer.busy ? 'Opening…' : 'Chat with seller', offer.onChat, primary: true)),
            if (offer.onDecline != null) ...[
              const SizedBox(width: 7),
              Expanded(flex: 20, child: button('Decline offer', offer.onDecline)),
            ],
          ]),
        ),
        if (offer.photos.length > 1) ...[
          Center(child: TextButton(
            onPressed: onTogglePhotos,
            style: TextButton.styleFrom(foregroundColor: brand),
            child: Text(expanded ? 'Hide additional photos' : 'More photos'),
          )),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 9),
              child: Wrap(spacing: 8, runSpacing: 8, children: offer.photos.skip(1).map(_itemPhoto).toList()),
            ),
        ],
      ]),
    );
  }

  Widget _fact(IconData icon, String label, String value, Color sub, Color ink) =>
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: sub),
            const SizedBox(width: 5),
            Flexible(child: Text(label, style: _text(12, sub))),
          ]),
          Text(value, style: _text(12, ink, weight: FontWeight.w600)),
        ],
      );
}
class _DealFact extends StatelessWidget {
  const _DealFact(this.asset, this.label, this.value);
  final String asset, label, value;
  TextStyle textStyle(BuildContext context, {bool label = false}) {
    final metrics = _dealMetrics(context);
    return BuyerTypography.homeStyle(context, metrics, size: label ? 10 : 11,
      color: label ? BuyerUiTokens.muted : BuyerUiTokens.text);
  }
  double minimumWidth(BuildContext context) {
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }
    final body = textStyle(context);
    var textWidth = measure(label, textStyle(context, label: true));
    for (final word in value.split(RegExp(r'\s+'))) {
      final width = measure(word, body);
      if (width > textWidth) textWidth = width;
    }
    if (value.contains('·')) {
      for (final segment in value.split('·')) {
        final width = measure(segment.trim(), body);
        if (width > textWidth) textWidth = width;
      }
    }
    // Give dates enough space to wrap over two readable lines.
    final halfValue = measure(value, body) / 2;
    if (halfValue > textWidth) textWidth = halfValue;
    return _dealMetrics(context).geometry(20) + textWidth.ceilToDouble() + 2;
  }
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
    dealArtwork(asset, size: _dealMetrics(context).geometry(16)),
    SizedBox(width: _dealMetrics(context).geometry(4)),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: textStyle(context, label: true)),
      SizedBox(height: _dealMetrics(context).geometry(3)),
      Text(value, style: textStyle(context)),
    ])),
  ]);
}
