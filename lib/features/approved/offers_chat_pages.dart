import '../../theme/marketplace_ui_foundation.dart';
import 'package:hocalist/components/hocalist_loading_indicator.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../commercial/money_help.dart';
import '../chat/chat_meetup_proposal_notice.dart';
import '../../theme/approved_interface_icons.dart';
import '../../theme/preserved_raster_glyph.dart';
import '../../theme/control_foundation.dart';
import '../media/private_remote_image.dart';
import 'package:flutter/services.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/chat/chat_safety_coordinator.dart';
import '../../domain/phase2/common.dart';
import '../../domain/phase2/communication_completion.dart';
import '../../domain/phase2/conversations.dart';
import '../../domain/phase2/money.dart';
import '../../domain/phase2/offers.dart';
import '../../domain/phase2/requests.dart';
import '../../data/phase2/meetings/meeting_codecs.dart';
import '../../domain/phase2/schedule.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/input_foundation.dart';
import '../../theme/seller_ui_foundation.dart' show SellerPrimaryButton;
import 'approved_replica_metrics.dart';
import 'buyer_bottom_navigation.dart';
import 'buyer_deal_card.dart';

export 'buyer_bottom_navigation.dart';

const _assetRoot = 'assets/approved_offers_chat';

const _navy = BuyerUiTokens.offerChatText;
const _blue = BuyerUiTokens.offerChatAction;
const _offersBlue = BuyerUiTokens.offersAction;
const _muted = BuyerUiTokens.muted;
const _line = BuyerUiTokens.border;
const _lavender = BuyerUiTokens.softSurface;
const _green = BuyerUiTokens.success;

ApprovedReplicaMetrics _chatMetrics(BuildContext context) {
  return ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        brightness: Theme.of(context).brightness,
        availableWidth: MediaQuery.sizeOf(context).width,
        textScaler: MediaQuery.textScalerOf(context),
      );
}

String _initialsFor(String name) {
  final initials = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
  return initials.isEmpty ? 'NT' : initials;
}

/// Compare calendar days in the viewer's timezone, including DST boundaries.
bool sameConversationDay(DateTime? first, DateTime? second) {
  if (first == null || second == null) return false;
  final a = first.toLocal();
  final b = second.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String conversationTimeLabel(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}

String conversationDateLabel(DateTime timestamp, {DateTime? now}) {
  final date = timestamp.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

@immutable
class ApprovedConversationEntry {
  const ApprovedConversationEntry({
    required this.isOutgoing,
    required this.time,
    this.text = '',
    this.sentAt,
    this.attachmentLabel,
    this.attachmentIsImage = false,
    this.attachmentMediaIds = const <String>[],
    this.isRead = false,
  });

  final bool isOutgoing;
  final bool isRead;
  final String time;
  final DateTime? sentAt;
  final String text;
  final String? attachmentLabel;
  final bool attachmentIsImage;

  /// Authorized chat image ids for real entries. Empty keeps the text bubble.
  final List<String> attachmentMediaIds;

  String get displayText {
    final attachment = attachmentLabel;
    if (attachment == null) return text;
    final prefix = attachmentIsImage ? 'Photo' : 'Attachment';
    if (text.isEmpty) return '$prefix: $attachment';
    return '$prefix: $attachment\n$text';
  }
}

/// Buyer-facing projection of one real offer revision.
///
/// Display-only values are derived from the authoritative offer; identity and
/// revision fields stay available so a selection sends exactly what the server
/// returned.
@immutable
class BuyerOfferView {
  const BuyerOfferView({
    required this.offerId,
    required this.requestId,
    required this.revisionId,
    required this.offerRevision,
    required this.sellerName,
    required this.initials,
    required this.priceLabel,
    required this.message,
    required this.meetingLabel,
    required this.placeLabel,
    required this.status,
    this.conversationId,
    this.sellerProfileId,
    this.imageMediaIds = const [],
    this.purchaseSelected = false,
    this.requestAcceptanceExpiresAt,
    this.requestTitle = 'Your request',
    this.distanceLabel,
    this.availabilityLabel,
    this.comparisonPlaceLabel,
  });

  factory BuyerOfferView.fromOffer(Offer offer, {bool agreedTerms = false,
      MeetingView? meeting, RequestCoordinates? origin}) {
    final revision = agreedTerms || offer.status != OfferStatus.submitted
        ? offer.acceptedRevision ?? offer.latestRevision
        : offer.latestRevision;
    final terms = revision.terms;
    final name = offer.sellerDisplayName ?? 'Hocalist seller';
    final agreed = meeting?.offerId == offer.id && meeting?.requestId == offer.requestId &&
        meeting?.isCancelled == false ? meeting?.acceptedSchedule : null;
    final schedule = agreed == null ? terms.schedule : LocalSchedule(
      date: agreed.date, startTime: agreed.startTime, timezoneId: agreed.timezoneId,
      occurrence: agreed.occurrence);
    final lat = agreed == null ? terms.place.latitude : agreed.latitude;
    final lng = agreed == null ? terms.place.longitude : agreed.longitude;
    String? distance;
    if (origin != null && lat != null && lng != null && lat.isFinite && lng.isFinite &&
        lat.abs() <= 90 && lng.abs() <= 180) {
      double radians(double value) => value * math.pi / 180;
      final a = math.pow(math.sin(radians(lat - origin.latitude) / 2), 2) +
          math.cos(radians(origin.latitude)) * math.cos(radians(lat)) *
          math.pow(math.sin(radians(lng - origin.longitude) / 2), 2);
      final miles = 3958.7613 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
      distance = '~${miles.toStringAsFixed(1)} mi away';
    }
    return BuyerOfferView(
      requestTitle: offer.requestTitle ?? 'Your request',
      offerId: offer.id,
      requestId: offer.requestId,
      revisionId: revision.id,
      offerRevision: offer.stamp.revision,
      sellerName: name,
      sellerProfileId: offer.sellerProfileId,
      initials: _initialsFor(name),
      priceLabel: BuyerOfferView.formatOfferPrice(terms.price),
      message: terms.message.trim(),
      meetingLabel: formatSchedule(schedule),
      availabilityLabel: formatSchedule(schedule),
      placeLabel: formatPlaceLabel(address: agreed?.placeAddress, label: agreed?.placeLabel, fallback: BuyerOfferView._formatPlace(terms.place)),
      comparisonPlaceLabel: formatPlaceLabel(address: agreed?.placeAddress, label: agreed?.placeLabel, fallback: BuyerOfferView._formatPlace(terms.place)),
      distanceLabel: distance,
      status: offer.status,
      conversationId: offer.conversationId,
      imageMediaIds: List.unmodifiable(terms.imageMediaIds),
      purchaseSelected: offer.purchaseSelected,
      requestAcceptanceExpiresAt: offer.requestAcceptanceExpiresAt,
    );
  }

  final String requestTitle;
  final String offerId;
  final String requestId;
  final String revisionId;
  final int offerRevision;
  final String sellerName;
  final String? sellerProfileId;
  final String initials;
  final String priceLabel;
  final String message;
  final String meetingLabel;
  final String placeLabel;
  final String? distanceLabel, availabilityLabel, comparisonPlaceLabel;
  final OfferStatus status;
  final String? conversationId;
  final List<String> imageMediaIds;

  /// True when the buyer designated this negotiation as the final purchase.
  final bool purchaseSelected;

  /// Exclusive end of the request acceptance window, when the server supplied
  /// it. Shown to both sides; new offers stop here while accepted meetings keep
  /// their own next-local-midnight cutoff.
  final DateTime? requestAcceptanceExpiresAt;

  bool get isSelectable =>
      status == OfferStatus.submitted && revisionId.isNotEmpty;

  /// Accepted offers can be designated as the final purchase until one purchase
  /// is confirmed.
  bool get isPurchaseSelectable => status == OfferStatus.selected;

  /// Prototype display record for the approved detail widgets.
  LocalOfferRecord toDisplayRecord({required String requestTitle}) {
    return LocalOfferRecord(
      id: offerId,
      requestId: requestId,
      buyerName: 'You',
      sellerName: sellerName,
      requestTitle: requestTitle,
      price: priceLabel,
      location: placeLabel,
      meetingDate: meetingLabel,
      meetingTime: meetingLabel,
      message: message,
      imageNames: const <String>[],
      status: switch (status) {
        OfferStatus.selected => LocalOfferStatus.selected,
        OfferStatus.completed => LocalOfferStatus.completed,
        _ => LocalOfferStatus.sent,
      },
    );
  }

  static String formatOfferPrice(Money money) {
    final units = money.minorUnits / 100;
    final text = units.truncateToDouble() == units
        ? units.toStringAsFixed(0)
        : units.toStringAsFixed(2);
    return '\$$text';
  }

  static String formatOfferDate(LocalDate localDate) {
    final date = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[localDate.month - 1]} ${localDate.day}';
  }

  static String formatSchedule(LocalSchedule schedule) {
    final hour = schedule.startTime.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final minute = schedule.startTime.minute.toString().padLeft(2, '0');
    return '${formatOfferDate(schedule.date)} · $displayHour:$minute $period';
  }

  /// Use only the meeting location returned for this participant. Public
  /// projections without an address continue to show their safe label.
  static String formatPlaceLabel({String? address, String? label, String fallback = 'View meeting location'}) {
    for (final value in [address, label]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  static String _formatPlace(MeetingPlace place) {
    final address = place.address?.trim();
    if (address != null && address.isNotEmpty) return address;
    final label = place.label?.trim();
    if (label != null && label.isNotEmpty) return label;
    return switch (place.choice) {
      MeetupPlaceChoice.sellerBusiness => 'Seller business location',
      MeetupPlaceChoice.buyerLocation => 'Buyer location',
      MeetupPlaceChoice.specificPlace => 'Public meetup place',
    };
  }
}

/// Buyer/seller-facing inbox row built from one authoritative conversation
/// summary. Display values are derived; the conversation id stays the identity.
@immutable
class ChatThreadView {
  const ChatThreadView({
    required this.conversationId,
    required this.counterpartName,
    required this.initials,
    required this.preview,
    required this.timeLabel,
    required this.unreadCount,
    this.counterpartProfileId,
    this.muted = false,
  });

  factory ChatThreadView.fromSummary(
    ConversationSummary summary, {
    required String viewerUserId,
    DateTime? now,
  }) {
    final counterpart = summary.counterpartDisplayName;
    final latest = summary.latestMessage;
    final text = latest?.text.trim() ?? '';
    return ChatThreadView(
      conversationId: summary.conversation.id,
      counterpartName: counterpart,
      counterpartProfileId: summary.counterpartProfileId,
      initials: _initialsFor(counterpart),
      preview: latest == null
          ? 'No messages yet.'
          : text.isNotEmpty
          ? text
          : 'Attachment',
      timeLabel: _relativeTime(latest?.sentAt, now ?? DateTime.now()),
      unreadCount: summary.unreadCount,
      muted: summary.conversation.memberFor(viewerUserId)?.isMuted ?? false,
    );
  }

  final String conversationId;
  final String counterpartName;

  /// Authoritative public profile id of the other participant, when the server
  /// projects one. Null keeps profile actions visibly unavailable.
  final String? counterpartProfileId;
  final String initials;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final bool muted;

  static String _relativeTime(DateTime? sentAt, DateTime now) {
    if (sentAt == null) return '';
    final local = sentAt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final difference = today.difference(day).inDays;
    if (difference <= 0) {
      final hour = local.hour;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      return '$displayHour:$minute $period';
    }
    if (difference == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }
}

/// Approved offers-received replica. It owns the page header, scroll surface,
/// offer actions, and buyer bottom navigation so integration does not depend on
/// private widgets in the existing app shell.
class ApprovedOffersReceivedPage extends StatefulWidget {
  const ApprovedOffersReceivedPage({
    this.comparisonRequestTitle,
    this.rewardRequestId,
    this.loadPotentialReward,
    required this.onBack,
    required this.onNotifications,
    required this.onViewOffer,
    required this.onChat,
    required this.onFilter,
    required this.navigation,
    this.latestOffer,
    this.realOffers,
    this.budgetMaximum,
    this.requestClosed = false,
    this.offersLoading = false,
    this.offersError,
    this.onRefreshOffers,
    this.onOpenOffer,
    this.onViewSeller,
    this.onDeclineOffer,
    this.loadSeller,
    this.selectionBusy = false,
    this.selectionUncertain = false,
    this.selectionError,
    super.key,
  });

  final String? comparisonRequestTitle;
  final String? rewardRequestId;
  final Future<int> Function(String requestId)? loadPotentialReward;

  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onViewOffer;
  final VoidCallback onChat;
  final VoidCallback onFilter;
  final ApprovedBuyerNavigation navigation;
  final LocalOfferRecord? latestOffer;

  /// Real per-request offers. Null keeps the approved prototype cards.
  final List<BuyerOfferView>? realOffers;
  final double? budgetMaximum;
  final bool requestClosed;
  final bool offersLoading;
  final String? offersError;
  final VoidCallback? onRefreshOffers;

  /// Selects the seller if needed, then opens this offer's conversation.
  final ValueChanged<BuyerOfferView>? onOpenOffer;
  final ValueChanged<BuyerOfferView>? onViewSeller;
  final ValueChanged<BuyerOfferView>? onDeclineOffer;
  final BuyerDealSellerLoader? loadSeller;
  final bool selectionBusy;
  final bool selectionUncertain;
  final String? selectionError;

  bool get usesRealOffers => realOffers != null;

  @override
  State<ApprovedOffersReceivedPage> createState() =>
      _ApprovedOffersReceivedPageState();
}

class _ApprovedOffersReceivedPageState
    extends State<ApprovedOffersReceivedPage> {
  String _sort = 'Best match';
  bool _underFourHundredOnly = false;
  Future<int>? _potentialReward;

  @override
  void initState() {
    super.initState();
    if (widget.usesRealOffers) _sort = 'Newest first';
    _loadEstimate();
  }

  void _loadEstimate() {
    final id = widget.rewardRequestId;
    _potentialReward = id == null ? null : widget.loadPotentialReward?.call(id);
  }

  @override
  void didUpdateWidget(covariant ApprovedOffersReceivedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.realOffers;
    final current = widget.realOffers;
    if (widget.rewardRequestId != oldWidget.rewardRequestId ||
        (oldWidget.offersLoading && !widget.offersLoading && widget.offersError == null) ||
        previous?.length != current?.length) {
      _loadEstimate();
    }
  }

  Future<void> _showFilters() async {
    var draft = _underFourHundredOnly;
    final metrics = _chatMetrics(context);
    final applied = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => BuyerModalSheet(
          key: const Key('approved-offers-filter-sheet'),
          title: 'Filter offers',
          subtitle: 'Narrow the offers shown for this request.',
          icon: Icons.filter_alt_outlined,
          onClose: () => Navigator.pop(sheetContext, false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: HocalistPalette.surface(context, _lavender),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(metrics.geometry(12)),
                  side: BorderSide(color: HocalistPalette.border(context, _line)),
                ),
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  key: const Key('approved-offers-under-400-filter'),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: metrics.geometry(12),
                    vertical: metrics.geometry(8),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  checkboxShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(metrics.geometry(4)),
                  ),
                  value: draft,
                  onChanged:
                      widget.usesRealOffers && widget.budgetMaximum == null
                      ? null
                      : (value) => setSheetState(() => draft = value ?? false),
                  activeColor: BuyerUiTokens.action,
                  title: Text(
                    widget.usesRealOffers
                        ? 'Within your request budget'
                        : r'Offers under $400',
                    style: _text(context, size: 13, weight: FontWeight.w800, color: _navy),
                  ),
                  subtitle: Text(
                    widget.usesRealOffers
                        ? widget.budgetMaximum == null
                              ? 'This request has no maximum budget.'
                              : 'Show offers up to \$${widget.budgetMaximum!.toStringAsFixed(2)}.'
                        : 'Show offers within the lower end of the budget.',
                    style: _text(context, size: 11.5, color: _muted),
                  ),
                ),
              ),
              SizedBox(height: metrics.spacing(16)),
              BuyerPrimaryButton(
                key: const Key('approved-offers-apply-filter'),
                label: 'Apply filters',
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
              SizedBox(height: metrics.spacing(8)),
              BuyerSecondaryButton(
                key: const Key('approved-offers-clear-filter'),
                label: 'Clear filters',
                onPressed: () {
                  draft = false;
                  Navigator.pop(sheetContext, true);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() => _underFourHundredOnly = draft);
      widget.onFilter();
    }
  }

  List<Widget> _realOfferCards(BuildContext context) {
    final source = widget.requestClosed
        ? const <BuyerOfferView>[]
        : (widget.realOffers ?? const <BuyerOfferView>[]).where((offer) =>
            offer.status == OfferStatus.submitted).toList();
    final visible = _underFourHundredOnly
        ? source.where((offer) {
            final value = double.tryParse(
              offer.priceLabel.replaceAll(RegExp(r'[^0-9.]'), ''),
            );
            return value != null &&
                widget.budgetMaximum != null &&
                value <= widget.budgetMaximum!;
          }).toList()
        : List<BuyerOfferView>.of(source);
    if (_sort == 'Lowest price') {
      visible.sort((left, right) {
        double value(BuyerOfferView offer) =>
            double.tryParse(
              offer.priceLabel.replaceAll(RegExp(r'[^0-9.]'), ''),
            ) ??
            double.infinity;
        return value(left).compareTo(value(right));
      });
    }
    return [
      if (widget.selectionError != null)
        BuyerStateNotice(title: 'Could not open the conversation', body: widget.selectionError, icon: Icons.info_outline, tone: BuyerNoticeTone.error),
      for (var index = 0; index < visible.length; index++)
        BuyerDealCard(
          key: ValueKey('approved-real-offer-${visible[index].offerId}'),
          busy: widget.selectionBusy,
          sellerProfileId: visible[index].sellerProfileId,
          loadSeller: widget.loadSeller,
          onProfile: widget.onViewSeller == null ? null : () => widget.onViewSeller!(visible[index]),
          comparison: true,
          availability: visible[index].availabilityLabel,
          photos: visible[index].imageMediaIds,
          sellerName: visible[index].sellerName,
          title: visible[index].requestTitle,
          price: visible[index].priceLabel,
          message: visible[index].message,
          meeting: visible[index].meetingLabel,
          place: visible[index].comparisonPlaceLabel?.trim().isNotEmpty == true
              ? visible[index].comparisonPlaceLabel!.trim()
              : visible[index].placeLabel,
          distanceLabel: visible[index].distanceLabel,
          onDecline: widget.onDeclineOffer == null ||
            !{OfferStatus.submitted, OfferStatus.selected}.contains(visible[index].status)
              ? null : () => widget.onDeclineOffer!(visible[index]),
          onChat: () {
            final open = widget.onOpenOffer;
            if (open != null) {
              open(visible[index]);
            } else {
              widget.onViewOffer();
            }
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.latestOffer;
    final latestPrice = latest?.price ?? r'$420';
    final latestPriceValue = double.tryParse(
      latestPrice.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    final latestSeller = latest?.sellerName ?? 'Northside Tech';
    final latestInitials = latestSeller
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final northside = _ApprovedOfferCard(
      topMatch: true,
      seller: latestSeller,
      initials: latestInitials.isEmpty ? 'NT' : latestInitials,
      reviews: '4.9 (128 reviews)',
      status: 'Verified seller',
      statusColor: _green,
      price: latestPrice,
      description: latest?.message.isNotEmpty == true
          ? latest!.message
          : 'iPad Air 5, 256GB, keyboard case, public pickup, Saturday.',
      firstFactAsset: 'offers-identity.png',
      firstFactTitle: 'Identity verified',
      firstFactBody: 'Verified',
      distance: '1.2 mi away',
      availability: latest?.meetingDate ?? 'Sat, May 17',
      onDetails: widget.onViewOffer,
    );
    final loop = _ApprovedOfferCard(
      seller: 'Loop Resale',
      initials: 'LR',
      reviews: '4.9 (86 reviews)',
      status: 'Verified seller',
      statusColor: _green,
      price: '\$390',
      description: 'iPad Air 5, 64GB, same-day pickup, no accessories.',
      firstFactAsset: 'offers-identity.png',
      firstFactTitle: 'Identity verified',
      firstFactBody: 'Verified',
      distance: '0.8 mi away',
      availability: 'Today',
      onDetails: widget.onViewOffer,
    );
    final offers = widget.usesRealOffers
        ? _realOfferCards(context)
        : _underFourHundredOnly
        ? <Widget>[if ((latestPriceValue ?? 420) < 400) northside, loop]
        : (_sort == 'Lowest price' || _sort == 'Closest')
        ? <Widget>[loop, northside]
        : <Widget>[northside, loop];
    return _ApprovedPageScaffold(
      onBack: widget.onBack,
      selection: ApprovedBuyerNavSelection.offers,
      accentColor: _offersBlue,
      navigation: widget.navigation,
      bodyKey: const Key('approved-offers-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          sliver: SliverList.list(
            children: [
              BuyerTopLevelHeader(onNotifications: widget.onNotifications),
              const SizedBox(height: 6),
              _OffersHero(
                requestTitle: widget.comparisonRequestTitle,
                offerCount: widget.usesRealOffers && !widget.offersLoading && widget.offersError == null
                    ? offers.whereType<BuyerDealCard>().length
                    : null,
              ),
              const SizedBox(height: 8),
              if (widget.usesRealOffers)
                _PotentialBuyerRewardRow(
                  key: ValueKey(widget.rewardRequestId),
                  estimate: _potentialReward,
                  onOpen: () => setState(_loadEstimate),
                )
              else
                const _OffersRewardsCard(),
              const SizedBox(height: 10),
              _OffersToolbar(
                value: _sort,
                onChanged: (value) => setState(() => _sort = value),
                onFilter: _showFilters,
                filtersActive: _underFourHundredOnly,
                realMode: widget.usesRealOffers,
              ),
              const SizedBox(height: 8),
              if (widget.usesRealOffers) ...[
                if (widget.offersLoading)
                  const _OffersStateNotice(
                    key: Key('approvedOffersLoading'),
                    message: 'Loading offers…',
                  )
                else if (widget.offersError != null)
                  _OffersStateNotice(
                    key: const Key('approvedOffersError'),
                    message: widget.offersError!,
                    onRetry: widget.onRefreshOffers,
                  )
                else if (offers.isEmpty)
                  _OffersStateNotice(
                    key: const Key('approvedOffersEmpty'),
                    title: widget.requestClosed
                        ? 'No offers for this closed request'
                        : (widget.realOffers?.any((offer) => offer.status == OfferStatus.selected) == true ? 'No new offers' : 'No offers yet'),
                    icon: Icons.mark_email_unread_outlined,
                    message: widget.requestClosed
                        ? 'This request is closed and cannot receive new offers. Your existing request remains in your history.'
                        : widget.realOffers?.any((offer) => offer.status == OfferStatus.selected) == true
                            ? 'Your negotiations are in Deals in progress and Chats. New offers will appear here.'
                            : 'Sellers nearby will appear here when they respond to your request.',
                  ),
              ],
              for (var index = 0; index < offers.length; index++) ...[
                offers[index],
                if (index != offers.length - 1) const SizedBox(height: 8),
              ],
              const SizedBox(height: 5),
              const _SecurePrivateNotice(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Approved seller-offer detail replica. The unsafe protection claim in the
/// raster reference is intentionally replaced by the current offline-payment
/// boundary copy.
class ApprovedViewOfferPage extends StatelessWidget {
  const ApprovedViewOfferPage({
    required this.onBack,
    required this.onNotifications,
    required this.onSelectSeller,
    required this.onViewProfile,
    required this.navigation,
    this.latestOffer,
    this.realOffer,
    this.requestTitle = 'Your request',
    this.selectionBusy = false,
    this.selectionError,
    this.selectionUncertain = false,
    this.onChoosePurchaseSeller,
    this.onArrangeMeeting,
    this.purchaseBusy = false,
    this.purchaseError,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onSelectSeller;
  final VoidCallback onViewProfile;
  final ApprovedBuyerNavigation navigation;
  final LocalOfferRecord? latestOffer;

  /// Authoritative offer shown in real mode.
  final BuyerOfferView? realOffer;
  final String requestTitle;

  /// Selection state owned by the composing screen.
  final bool selectionBusy;
  final String? selectionError;
  final bool selectionUncertain;

  /// Buyer designates the accepted seller as the final purchase. Null hides
  /// the action (prototype mode or an unavailable server path).
  final VoidCallback? onChoosePurchaseSeller;
  final VoidCallback? onArrangeMeeting;
  final bool purchaseBusy;
  final String? purchaseError;

  LocalOfferRecord? get _displayOffer =>
      realOffer?.toDisplayRecord(requestTitle: requestTitle) ?? latestOffer;

  @override
  Widget build(BuildContext context) {
    final offer = _displayOffer;
    final selectable = realOffer?.isSelectable ?? true;
    final real = realOffer;
    return _ApprovedPageScaffold(
      onBack: onBack,
      selection: ApprovedBuyerNavSelection.offers,
      navigation: navigation,
      bodyKey: const Key('approved-view-offer-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
          sliver: SliverList.list(
            children: [
              _OfferDetailHeader(
                onBack: onBack,
                onNotifications: onNotifications,
              ),
              const SizedBox(height: 8),
              if (real?.requestAcceptanceExpiresAt != null) ...[
                _OfferCountdownNotice(
                  expiresAt: real!.requestAcceptanceExpiresAt!,
                ),
                const SizedBox(height: 8),
              ],
              _OfferSellerSummary(offer: offer, realMode: real != null),
              const SizedBox(height: 8),
              _OfferRewardWindow(realMode: real != null),
              const SizedBox(height: 8),
              _OfferDescription(
                offer: offer,
                realMode: real != null,
                requestTitle: requestTitle,
              ),
              if (real != null && real.imageMediaIds.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: real.imageMediaIds
                      .map((id) => PrivateRemoteImage(id: id, showWholeImage: true))
                      .toList(),
                ),
              const SizedBox(height: 6),
              _OfferPinNotice(realMode: real != null),
              const SizedBox(height: 6),
              _AboutSeller(
                onViewProfile: onViewProfile,
                realMode: real != null,
              ),
              const SizedBox(height: 6),
              _OfferOfflineNotice(
                sellerSelected: real?.status == OfferStatus.selected,
              ),
              const SizedBox(height: 6),
              if (real == null)
                _SelectSellerPanel(
                  onSelect: onSelectSeller,
                  busy: selectionBusy,
                  error: selectionError,
                  enabled: selectable,
                )
              else if (real.status == OfferStatus.selected)
                _PurchaseSellerPanel(
                  purchaseSelected: real.purchaseSelected,
                  onChoose: onChoosePurchaseSeller,
                  busy: purchaseBusy,
                  error: purchaseError,
                )
              else if (real.status == OfferStatus.submitted)
                _SelectSellerPanel(
                  onSelect: onSelectSeller,
                  busy: selectionBusy,
                  error: selectionError,
                  enabled: selectable,
                )
              else
                _OfferClosedNotice(status: real.status),
              if (real?.purchaseSelected == true && onArrangeMeeting != null)
                BuyerPrimaryButton(
                  label: 'Review meeting details',
                  onPressed: onArrangeMeeting,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Authoritative close of the request acceptance window for both sides.
class _OfferCountdownNotice extends StatelessWidget {
  const _OfferCountdownNotice({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    final local = expiresAt.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return _Surface(
      key: const Key('approved-offer-countdown'),
      padding: EdgeInsets.all(compact ? 5 : 7),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: HocalistPalette.text(context, _muted),
          ),
          SizedBox(width: compact ? 4 : 6),
          Expanded(
            child: Text(
              'New offers close ${months[local.month - 1]} ${local.day}, '
              '$displayHour:$minute $period. '
              'Accepted meetings stay valid to their own cutoff.',
              style: _text(
                context,
                size: compact ? 6 : 8,
                weight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buyer's final-purchase choice inside the approved detail composition.
class _PurchaseSellerPanel extends StatelessWidget {
  const _PurchaseSellerPanel({
    required this.purchaseSelected,
    required this.onChoose,
    this.busy = false,
    this.error,
  });

  final bool purchaseSelected;
  final VoidCallback? onChoose;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width <= 320 &&
        !_usesAccessibilityReflow(context);
    final title = purchaseSelected ? 'Seller chosen for purchase' : 'Choose a seller for purchase';
    final body = purchaseSelected
        ? 'Only this seller can confirm the purchase with your request PIN. '
              'Other negotiations close if you confirm with them.'
        : 'Choose the seller who can confirm your completed purchase with the PIN. '
              'You’ll pay the seller directly.';
    return _Surface(
      padding: EdgeInsets.all(compact ? 5 : 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            key: const Key('approved-purchase-seller-title'),
            style: _text(
              context,
              size: compact ? 8 : 10,
              weight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 2 : 3),
          Text(
            body,
            style: _text(
              context,
              size: compact ? 6 : 8,
              weight: FontWeight.w500,
              color: _muted,
            ),
          ),
          if (!purchaseSelected && onChoose != null) ...[
            SizedBox(height: compact ? 4 : 6),
            _PrimaryButton(
              key: const Key('approved-choose-purchase-seller'),
              label: busy ? 'Saving…' : 'Choose seller for purchase',
              onPressed: busy ? null : onChoose,
              height: compact ? 32 : 44,
            ),
          ],
          if (purchaseSelected) ...[
            SizedBox(height: compact ? 3 : 4),
            Row(
              children: [
                Icon(
                  Icons.verified,
                  size: 16,
                  color: HocalistPalette.text(context, _blue),
                ),
                SizedBox(width: compact ? 3 : 5),
                Expanded(
                  child: Text(
                    'The buyer chose this negotiation for the final purchase.',
                    style: _text(
                      context,
                      size: compact ? 6 : 8,
                      weight: FontWeight.w700,
                      color: _blue,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            SizedBox(height: compact ? 2 : 3),
            Text(
              error!,
              key: const Key('approvedChoosePurchaseSellerError'),
              textAlign: TextAlign.center,
              style: _text(
                context,
                size: compact ? 6 : 8.5,
                weight: FontWeight.w700,
                color: const Color(0xFFD32F2F),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Honest state for an offer that can no longer be acted on.
class _OfferClosedNotice extends StatelessWidget {
  const _OfferClosedNotice({required this.status});

  final OfferStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      OfferStatus.withdrawn => 'This seller withdrew this offer.',
      OfferStatus.declined => 'This negotiation is closed.',
      OfferStatus.completed => 'The purchase was confirmed with this seller.',
      OfferStatus.cancelled => 'This offer was cancelled.',
      OfferStatus.expired => 'This offer expired.',
      _ => 'This offer is no longer available.',
    };
    return _Surface(
      key: const Key('approved-offer-closed-notice'),
      padding: const EdgeInsets.all(6),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: _text(context, size: 8, weight: FontWeight.w600, color: _muted),
      ),
    );
  }
}

/// Buyer route wrapper for the shared approved conversation experience.
/// One authoritative active-deal card for a conversation.
///
/// The host builds this projection from the participant meeting read. A
/// missing offer summary keeps an honest unavailable label instead of a
/// fabricated title or price, and no verification or presence is implied.
class ApprovedDealView {
  const ApprovedDealView({
    this.meetingId,
    this.offerId,
    required this.title,
    required this.priceLabel,
    required this.statusLabel,
    this.statusTone = BuyerNoticeTone.brand,
    this.scheduleLabel,
    this.zoneLabel,
    this.placeLabel,
    this.pendingLabel,
    this.purchaseSelected = false,
    this.actionLabel,
    this.completed = false,
    this.meetingAccepted = false,
    this.unreadCount = 0,
    this.canSuggestMeetup = false,
    this.canShareMeetup = false,
  }) : assert(meetingId != null || offerId != null);

  final String? meetingId;
  final String? offerId;
  String get id => meetingId ?? offerId!;

  factory ApprovedDealView.fromSelectedOffer(Offer offer, {bool buyer = true}) {
    final terms = (offer.acceptedRevision ?? offer.latestRevision).terms;
    final historical = offer.status != OfferStatus.selected;
    return ApprovedDealView(
      offerId: offer.id,
      title: offer.requestTitle ?? 'Selected offer',
      priceLabel: BuyerOfferView.formatOfferPrice(terms.price),
      statusLabel: offer.requestClosed && offer.status != OfferStatus.completed ? 'Request closed' : historical
          ? (offer.status == OfferStatus.completed ? 'Purchase completed' : 'Deal closed')
          : offer.purchaseSelected
          ? 'Seller chosen · review meetup details'
          : 'Awaiting buyer confirmation',
      actionLabel: historical
          ? 'View offer details'
          : offer.purchaseSelected
          ? (buyer ? 'Accept offer and meet' : 'Review offered meeting')
          : buyer
          ? 'Accept offer and meet'
          : 'Waiting for buyer',
      scheduleLabel: "${terms.schedule.date} · ${terms.schedule.startTime}",
      zoneLabel: terms.schedule.timezoneId,
      placeLabel: BuyerOfferView._formatPlace(terms.place),
      purchaseSelected: offer.purchaseSelected,
      canSuggestMeetup: !historical && !offer.requestClosed && offer.purchaseSelected,
    );
  }
  final String title;
  final String priceLabel;
  final String statusLabel;
  final BuyerNoticeTone statusTone;
  final String? scheduleLabel;
  final String? zoneLabel;
  final String? placeLabel;
  final String? pendingLabel;
  final bool purchaseSelected;
  final String? actionLabel;
  final bool completed;
  final bool meetingAccepted;
  final int unreadCount;
  final bool canSuggestMeetup;
  final bool canShareMeetup;

  ApprovedDealView withUnreadCount(int count) => ApprovedDealView(
    meetingId: meetingId, offerId: offerId, title: title,
    priceLabel: priceLabel, statusLabel: statusLabel, statusTone: statusTone,
    scheduleLabel: scheduleLabel, zoneLabel: zoneLabel, placeLabel: placeLabel,
    pendingLabel: pendingLabel, purchaseSelected: purchaseSelected,
    actionLabel: actionLabel, completed: completed,
    meetingAccepted: meetingAccepted, unreadCount: count,
    canSuggestMeetup: canSuggestMeetup, canShareMeetup: canShareMeetup,
  );
}

class ApprovedBuyerChatPage extends StatelessWidget {
  const ApprovedBuyerChatPage({
    required this.onBack,
    required this.onPrimary,
    this.onMeetingOptions,
    required this.onCall,
    required this.onMore,
    required this.onRequestChange,
    required this.onChangeLocation,
    required this.onAttach,
    required this.onSend,
    required this.onLearnMore,
    required this.navigation,
    this.onViewProfile,
    this.primaryLabel = 'Accept to meet',
    this.meetingConfirmed = false,
    this.offerRevisionPending = false,
    this.onOfferRevisionAccepted,
    this.sentEntries = const <ApprovedConversationEntry>[],
    this.onEntrySent,
    this.offer,
    this.realEntries,
    this.realContactName,
    this.realDeals,
    this.realDealsLoading = false,
    this.realDealsError,
    this.realDealsTruncated = false,
    this.previousDeals,
    this.onRefreshRealDeals,
    this.onOpenRealDeal,
    this.selectedDealId,
    this.enquiries = const [],
    this.selectedEnquiryId,
    this.onSelectEnquiry,
    this.onSelectRealDeal,
    this.meetupProposals = const [],
    this.onRespondToMeetup,
    this.priceProposals = const [],
    this.onRespondToPrice,
    this.onProposePrice,
    this.onSuggestMeetup,
    this.onTakePhoto,
    this.messagesLoading = false,
    this.messagesError,
    this.onRefreshMessages,
    this.onLoadOlder,
    this.olderLoading = false,
    this.olderError,
    this.sending = false,
    this.sendError,
    this.onSubmitMessage,
    this.initialDraft,
    this.muted,
    this.onMuteChanged,
    this.attachmentsEnabled = false,
    this.pendingAttachmentMediaId,
    this.attachmentRetryBusy = false,
    this.onRetryAttachment,
    this.onDiscardAttachment,
    this.blockState,
    this.blockWritePending = false,
    this.onBlockChanged,
    this.onSearchMessages,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPrimary;
  final VoidCallback? onMeetingOptions;
  final VoidCallback onCall;
  final VoidCallback onMore;
  final VoidCallback onRequestChange;
  final VoidCallback onChangeLocation;
  final VoidCallback onAttach;
  final ValueChanged<String> onSend;
  final VoidCallback onLearnMore;
  final VoidCallback? onViewProfile;
  final ApprovedBuyerNavigation navigation;
  final String primaryLabel;
  final bool meetingConfirmed;
  final bool offerRevisionPending;
  final VoidCallback? onOfferRevisionAccepted;
  final List<ApprovedConversationEntry> sentEntries;
  final ValueChanged<ApprovedConversationEntry>? onEntrySent;
  final LocalOfferRecord? offer;
  final List<ApprovedConversationEntry>? realEntries;
  final String? realContactName;

  /// Authoritative active deals for this conversation. Null means the host has
  /// no deal projection yet (designed unavailable state), not "no deals".
  final List<ApprovedDealView>? realDeals;
  final bool realDealsLoading;
  final String? realDealsError;

  /// True when the meeting-page scan stopped at its page cap with more pages
  /// unread, so the list may be incomplete.
  final bool realDealsTruncated;

  /// Previous (completed or cancelled) deals for this conversation. Null means
  /// the history read is not available; the approved group stays visible with
  /// a designed unavailable state instead of invented records.
  final List<ApprovedDealView>? previousDeals;
  final VoidCallback? onRefreshRealDeals;

  /// Opens the authoritative meeting/management surface for one deal card.
  final ValueChanged<String>? onOpenRealDeal;
  final String? selectedDealId;
  final List<ChatEnquiry> enquiries;
  final String? selectedEnquiryId;
  final ValueChanged<String>? onSelectEnquiry;
  final ValueChanged<String>? onSelectRealDeal;
  final List<ChatMeetupProposal> meetupProposals;
  final ChatMeetupResponse? onRespondToMeetup;
  final List<ChatPriceProposal> priceProposals;
  final ChatPriceResponse? onRespondToPrice;
  final ValueChanged<String>? onProposePrice;
  final ValueChanged<String>? onSuggestMeetup;
  final VoidCallback? onTakePhoto;
  final bool messagesLoading;
  final String? messagesError;
  final VoidCallback? onRefreshMessages;
  final VoidCallback? onLoadOlder;
  final bool olderLoading;
  final String? olderError;
  final bool sending;
  final String? sendError;
  final Future<bool> Function(String)? onSubmitMessage;
  final String? initialDraft;
  final bool? muted;
  final Future<void> Function(bool)? onMuteChanged;

  /// True only when the deployed chat attachment RPC is available. The picker
  /// stays visibly unavailable otherwise.
  final bool attachmentsEnabled;

  /// Retained unconfirmed attachment media id for the active conversation.
  final String? pendingAttachmentMediaId;
  final bool attachmentRetryBusy;
  final VoidCallback? onRetryAttachment;
  final VoidCallback? onDiscardAttachment;

  /// Server-owned block state in real mode, when known.
  final ConversationBlockState? blockState;

  /// True while a block/unblock write is outstanding.
  final bool blockWritePending;

  /// Records or reverses the caller's own block. Null keeps the prototype
  /// behavior; real mode never fakes a block.
  final Future<bool> Function(bool blocked)? onBlockChanged;

  /// Server-side paged search. Null keeps the loaded-message filter.
  final Future<PageSlice<ChatSearchHit>> Function(String query, String? cursor)?
  onSearchMessages;

  @override
  Widget build(BuildContext context) {
    return _ApprovedPageScaffold(
      onBack: onBack,
      selection: ApprovedBuyerNavSelection.chats,
      navigation: navigation,
      bodyKey: const Key('approved-chat-scroll'),
      body: ApprovedConversationBody(
        onBack: onBack,
        onPrimary: onPrimary,
        onMeetingOptions: onMeetingOptions,
        onCall: onCall,
        onMore: onMore,
        onRequestChange: onRequestChange,
        onChangeLocation: onChangeLocation,
        onAttach: onAttach,
        onSend: onSend,
        onLearnMore: onLearnMore,
        onViewProfile: onViewProfile,
        primaryLabel: primaryLabel,
        meetingConfirmed: meetingConfirmed,
        offerRevisionPending: offerRevisionPending,
        onOfferRevisionAccepted: onOfferRevisionAccepted,
        sentEntries: sentEntries,
        onEntrySent: onEntrySent,
        offer: offer,
        realEntries: realEntries,
        realContactName: realContactName,
        realDeals: realDeals,
        realDealsLoading: realDealsLoading,
        realDealsError: realDealsError,
        realDealsTruncated: realDealsTruncated,
        previousDeals: previousDeals,
        onRefreshRealDeals: onRefreshRealDeals,
        onOpenRealDeal: onOpenRealDeal,
        selectedDealId: selectedDealId,
        enquiries: enquiries,
        selectedEnquiryId: selectedEnquiryId,
        onSelectEnquiry: onSelectEnquiry,
        onSelectRealDeal: onSelectRealDeal,
        meetupProposals: meetupProposals,
        onRespondToMeetup: onRespondToMeetup,
        priceProposals: priceProposals,
        onRespondToPrice: onRespondToPrice,
        onProposePrice: onProposePrice,
        onSuggestMeetup: onSuggestMeetup,
        onTakePhoto: onTakePhoto,
        messagesLoading: messagesLoading,
        messagesError: messagesError,
        onRefreshMessages: onRefreshMessages,
        onLoadOlder: onLoadOlder,
        olderLoading: olderLoading,
        olderError: olderError,
        sending: sending,
        sendError: sendError,
        onSubmitMessage: onSubmitMessage,
        initialDraft: initialDraft,
        muted: muted,
        onMuteChanged: onMuteChanged,
        blockState: blockState,
        blockWritePending: blockWritePending,
        onBlockChanged: onBlockChanged,
        onSearchMessages: onSearchMessages,
        attachmentsEnabled: attachmentsEnabled,
        pendingAttachmentMediaId: pendingAttachmentMediaId,
        attachmentRetryBusy: attachmentRetryBusy,
        onRetryAttachment: onRetryAttachment,
        onDiscardAttachment: onDiscardAttachment,
      ),
    );
  }
}

/// Role-aware conversation body shared by Buyer and Seller route shells.
class ApprovedConversationBody extends StatefulWidget {
  const ApprovedConversationBody({
    required this.onBack,
    required this.onPrimary,
    this.onMeetingOptions,
    required this.onCall,
    required this.onMore,
    required this.onRequestChange,
    required this.onChangeLocation,
    required this.onAttach,
    required this.onSend,
    required this.onLearnMore,
    this.primaryLabel = 'Accept to meet',
    this.contactName = 'John D.',
    this.contactRoleLabel = 'Sample chat',
    this.contactInitials,
    this.incomingMessage =
        'Hi! The iPad is in perfect condition like we discussed.',
    this.outgoingMessage = 'Looks good! I’m ready to move\nforward 👍',
    this.viewerIsSeller = false,
    this.meetingConfirmed = false,
    this.offerRevisionPending = false,
    this.onOfferRevised,
    this.onOfferRevisionAccepted,
    this.requestChangePending = false,
    this.onContinueWithRequest,
    this.onWithdrawFromRequest,
    this.onViewProfile,
    this.onViewOriginalRequest,
    this.sentEntries = const <ApprovedConversationEntry>[],
    this.onEntrySent,
    this.offer,
    this.realEntries,
    this.realContactName,
    this.realDeals,
    this.realDealsLoading = false,
    this.realDealsError,
    this.realDealsTruncated = false,
    this.previousDeals,
    this.onRefreshRealDeals,
    this.onOpenRealDeal,
    this.selectedDealId,
    this.entryOfferId,
    this.enquiries = const [],
    this.selectedEnquiryId,
    this.onSelectEnquiry,
    this.onSelectRealDeal,
    this.meetupProposals = const [],
    this.onRespondToMeetup,
    this.priceProposals = const [],
    this.onRespondToPrice,
    this.onProposePrice,
    this.onSuggestMeetup,
    this.onTakePhoto,
    this.messagesLoading = false,
    this.messagesError,
    this.onRefreshMessages,
    this.onLoadOlder,
    this.olderLoading = false,
    this.olderError,
    this.sending = false,
    this.sendError,
    this.onManagePayment,
    this.onSubmitMessage,
    this.initialDraft,
    this.muted,
    this.onMuteChanged,
    this.attachmentsEnabled = false,
    this.pendingAttachmentMediaId,
    this.attachmentRetryBusy = false,
    this.onRetryAttachment,
    this.onDiscardAttachment,
    this.blockState,
    this.blockWritePending = false,
    this.onBlockChanged,
    this.onSearchMessages,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPrimary;
  final VoidCallback? onMeetingOptions;
  final VoidCallback onCall;
  final VoidCallback onMore;
  final VoidCallback onRequestChange;
  final VoidCallback onChangeLocation;
  final VoidCallback onAttach;
  final ValueChanged<String> onSend;
  final VoidCallback onLearnMore;
  final String primaryLabel;
  final String contactName;
  final String contactRoleLabel;
  final String? contactInitials;
  final String incomingMessage;
  final String outgoingMessage;
  final bool viewerIsSeller;
  final bool meetingConfirmed;
  final bool offerRevisionPending;
  final VoidCallback? onOfferRevised;
  final VoidCallback? onOfferRevisionAccepted;
  final bool requestChangePending;
  final VoidCallback? onContinueWithRequest;
  final VoidCallback? onWithdrawFromRequest;
  final VoidCallback? onViewProfile;
  final VoidCallback? onViewOriginalRequest;
  final List<ApprovedConversationEntry> sentEntries;
  final ValueChanged<ApprovedConversationEntry>? onEntrySent;
  final LocalOfferRecord? offer;

  /// Authoritative history in real mode. Null keeps the prototype messages.
  final List<ApprovedConversationEntry>? realEntries;
  final String? realContactName;

  /// Authoritative active deals for this conversation. Null means the host has
  /// no deal projection yet (designed unavailable state), not "no deals".
  final List<ApprovedDealView>? realDeals;
  final bool realDealsLoading;
  final String? realDealsError;

  /// True when the meeting-page scan stopped at its page cap with more pages
  /// unread, so the list may be incomplete.
  final bool realDealsTruncated;

  /// Previous (completed or cancelled) deals for this conversation. Null means
  /// the history read is not available; the approved group stays visible with
  /// a designed unavailable state instead of invented records.
  final List<ApprovedDealView>? previousDeals;
  final VoidCallback? onRefreshRealDeals;

  /// Opens the authoritative meeting/management surface for one deal card.
  final ValueChanged<String>? onOpenRealDeal;
  final String? selectedDealId;
  final String? entryOfferId;
  final List<ChatEnquiry> enquiries;
  final String? selectedEnquiryId;
  final ValueChanged<String>? onSelectEnquiry;
  final ValueChanged<String>? onSelectRealDeal;
  final List<ChatMeetupProposal> meetupProposals;
  final ChatMeetupResponse? onRespondToMeetup;
  final List<ChatPriceProposal> priceProposals;
  final ChatPriceResponse? onRespondToPrice;
  final ValueChanged<String>? onProposePrice;
  final ValueChanged<String>? onSuggestMeetup;
  final VoidCallback? onTakePhoto;
  final bool messagesLoading;
  final String? messagesError;
  final VoidCallback? onRefreshMessages;
  final VoidCallback? onLoadOlder;
  final bool olderLoading;
  final String? olderError;
  final bool sending;
  final String? sendError;
  final VoidCallback? onManagePayment;
  final Future<bool> Function(String)? onSubmitMessage;
  final String? initialDraft;

  /// Server-owned mute state in real mode, when known.
  final bool? muted;
  final Future<void> Function(bool)? onMuteChanged;

  /// True only when the deployed chat attachment RPC is available. With it
  /// false (default) the attach action keeps its honest unavailable message.
  final bool attachmentsEnabled;

  /// Retained unconfirmed attachment for the active conversation. The bar stays
  /// reachable until Retry succeeds or Discard clears it.
  final String? pendingAttachmentMediaId;
  final bool attachmentRetryBusy;
  final VoidCallback? onRetryAttachment;
  final VoidCallback? onDiscardAttachment;

  /// Server-owned block state in real mode, when known.
  final ConversationBlockState? blockState;

  /// True while a block/unblock write is outstanding.
  final bool blockWritePending;

  /// Records or reverses the caller's own block. Null keeps the prototype
  /// behavior; real mode never fakes a block.
  final Future<bool> Function(bool blocked)? onBlockChanged;

  /// Server-side paged search. Null keeps the loaded-message filter.
  final Future<PageSlice<ChatSearchHit>> Function(String query, String? cursor)?
  onSearchMessages;

  bool get usesRealEntries => realEntries != null;

  @override
  State<ApprovedConversationBody> createState() =>
      _ApprovedConversationBodyState();
}

class _ApprovedConversationBodyState extends State<ApprovedConversationBody> {
  ApprovedDealView? get _selectedRealDeal => widget.selectedEnquiryId!=null ? null :
      <ApprovedDealView>[...?widget.realDeals, ...?widget.previousDeals]
          .where(
            (deal) =>
                deal.id == widget.selectedDealId ||
                deal.offerId == widget.selectedDealId,
          )
          .firstOrNull ??
      widget.realDeals?.firstOrNull;
  final _controller = TextEditingController();
  final Map<String?,String> _dealDrafts = {};
  // Current deals open first; history remains available from Manage.
  bool? _showPastDeals = false;
  bool _dealsExpanded = true;
  bool _restoredDealView = false;

  void _setDealView(bool? past, bool expanded) {
    setState(() {
      _showPastDeals = past;
      _dealsExpanded = expanded;
    });
    PageStorage.maybeOf(context)?.writeState(context, (past, expanded),
      identifier: (widget.key, 'deal-view'));
  }
  List<ApprovedDealView>? get _visibleDeals {
    if (_showPastDeals == true) return widget.previousDeals;
    if (_showPastDeals == false) return widget.realDeals;
    if (widget.realDeals == null && widget.previousDeals == null) return null;
    return <String, ApprovedDealView>{
      for (final deal in [...?widget.realDeals, ...?widget.previousDeals]) deal.id: deal,
    }.values.toList();
  }
  void _chooseDealGroup(bool? past) {
    final effectivePast = past == false && widget.realDeals?.isEmpty == true &&
        widget.previousDeals?.isNotEmpty == true ? true : past;
    _setDealView(effectivePast, _dealsExpanded);
    final deals = _visibleDeals;
    if (deals != null && deals.isNotEmpty) widget.onSelectRealDeal?.call(deals.first.id);
  }
  bool _messagesMuted = false;
  bool _muteWritePending = false;
  bool _secondDealAdded = false;
  String? _pendingAttachment;
  bool _pendingAttachmentIsImage = false;
  late final List<ApprovedConversationEntry> _sentEntries;

  bool get _effectiveMuted => widget.muted ?? _messagesMuted;

  @override
  void initState() {
    super.initState();
    if (widget.entryOfferId != null) _showPastDeals = null;
    _sentEntries = List<ApprovedConversationEntry>.of(widget.sentEntries);
    if (widget.usesRealEntries) _controller.text = widget.initialDraft ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredDealView) return;
    _restoredDealView = true;
    final saved = PageStorage.maybeOf(context)?.readState(context,
      identifier: (widget.key, 'deal-view'));
    if (saved is (bool?, bool)) {
      _showPastDeals = saved.$1;
      _dealsExpanded = saved.$2;
    }
  }

  @override
  void didUpdateWidget(covariant ApprovedConversationBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(widget.usesRealEntries && (widget.selectedEnquiryId ?? widget.selectedDealId)!=(oldWidget.selectedEnquiryId ?? oldWidget.selectedDealId)) {
      _dealDrafts[oldWidget.selectedEnquiryId ?? oldWidget.selectedDealId]=_controller.text;
      _controller.text=widget.initialDraft ?? _dealDrafts[widget.selectedEnquiryId ?? widget.selectedDealId] ?? '';
    }
    for (final entry in widget.sentEntries) {
      final alreadyPresent = _sentEntries.any(
        (existing) =>
            existing.isOutgoing == entry.isOutgoing &&
            existing.time == entry.time &&
            existing.text == entry.text &&
            existing.attachmentLabel == entry.attachmentLabel,
      );
      if (!alreadyPresent) _sentEntries.add(entry);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _submittingMessage = false;

  bool get _canMessage =>
      widget.blockState?.canMessage != false &&
      (!widget.usesRealEntries ||
          (!widget.messagesLoading && widget.messagesError == null));

  Future<void> _send() async {
    if (_submittingMessage || widget.sending) return;
    if (!_canMessage) {
      _message('You can’t send messages in this conversation right now.');
      return;
    }
    final text = _controller.text.trim();
    final attachment = _pendingAttachment;
    if (text.isEmpty && attachment == null) return;
    if (widget.usesRealEntries) {
      // Real mode: the authoritative message list comes from the server. The
      // composer only reports the intent; attachments stay unavailable.
      if (text.isEmpty) return;
      final submit = widget.onSubmitMessage;
      if (submit == null) {
        widget.onSend(text);
        return;
      }
      _submittingMessage = true;
      final submittedDealId = widget.selectedEnquiryId ?? widget.selectedDealId;
      try {
        final acknowledged = await submit(text);
        if (mounted && acknowledged) {
          if ((widget.selectedEnquiryId ?? widget.selectedDealId) == submittedDealId &&
              _controller.text.trim() == text) {
            _controller.clear();
          }
          if (_dealDrafts[submittedDealId]?.trim() == text) {
            _dealDrafts.remove(submittedDealId);
          }
        }
      } finally {
        _submittingMessage = false;
      }
      return;
    }
    final entry = ApprovedConversationEntry(
      isOutgoing: true,
      time: 'Now',
      text: text,
      attachmentLabel: attachment,
      attachmentIsImage: _pendingAttachmentIsImage,
    );
    setState(() {
      _sentEntries.add(entry);
      _pendingAttachment = null;
    });
    if (text.isNotEmpty) widget.onSend(text);
    widget.onEntrySent?.call(entry);
    _controller.clear();
  }

  void _message(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showConversationMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final role = widget.viewerIsSeller ? 'buyer' : 'seller';
        return _ApprovedChatSheetFrame(
          key: const ValueKey('approved-conversation-menu'),
          title: 'Conversation options',
          subtitle: 'Manage this chat without leaving the active deal.',
          icon: Icons.tune_rounded,
          onClose: () => Navigator.pop(sheetContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ApprovedMenuAction(
                asset: widget.viewerIsSeller ? 'detail-identity.png' : null,
                icon: widget.viewerIsSeller ? null : Icons.shield_outlined,
                title: 'View $role profile',
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onViewProfile?.call();
                },
              ),
              if (widget.viewerIsSeller && widget.selectedEnquiryId == null)
                _ApprovedMenuAction(
                  asset: 'detail-description.png',
                  title: widget.usesRealEntries
                      ? 'View request details'
                      : 'View original request',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    (widget.onViewOriginalRequest ?? widget.onRequestChange)();
                  },
                ),
              _ApprovedMenuAction(
                icon: Icons.search_rounded,
                title: 'Search conversation',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showSearchDialog();
                },
              ),
              _ApprovedMenuAction(
                icon: _effectiveMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                title: _effectiveMuted
                    ? 'Unmute chat messages'
                    : 'Mute chat messages',
                subtitle: 'Critical deal and safety alerts stay on.',
                onTap: () {
                  final next = !_effectiveMuted;
                  final persist = widget.onMuteChanged;
                  Navigator.pop(sheetContext);
                  if (persist == null) {
                    setState(() => _messagesMuted = next);
                    _message(
                      next ? 'Chat messages muted.' : 'Chat messages unmuted.',
                    );
                    return;
                  }
                  // Real mode: one awaited server result owns the message. The
                  // switch state stays as-is until the authoritative read
                  // rebuilds this thread, and repeat taps are ignored while a
                  // write is outstanding.
                  if (_muteWritePending) return;
                  _muteWritePending = true;
                  unawaited(
                    Future<void>(() async {
                      try {
                        await persist(next);
                      } catch (_) {
                        if (mounted) {
                          _message('Mute could not be saved. Try again.');
                        }
                      } finally {
                        _muteWritePending = false;
                      }
                    }),
                  );
                },
              ),
              _ApprovedMenuAction(
                asset: 'chat-safety.png',
                title: 'Safety & help',
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onLearnMore();
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Divider(color: _line),
              ),
              _ApprovedMenuAction(
                icon: Icons.flag_outlined,
                title: 'Report $role',
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onMore();
                },
              ),
              if (widget.blockState?.isBlockedByMe == true)
                _ApprovedMenuAction(
                  icon: Icons.lock_open_rounded,
                  title: 'Unblock $role',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showUnblockConfirmation(role);
                  },
                )
              else
                _ApprovedMenuAction(
                  icon: Icons.block_rounded,
                  title: 'Block $role',
                  foregroundColor: const Color(0xffc62828),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showBlockConfirmation(role);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSearchDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedSearchConversationSheet(
        messages: widget.realEntries
            ?.map((entry) => entry.text)
            .toList(growable: false),
        search: widget.onSearchMessages,
        onClose: () => Navigator.pop(sheetContext),
        onMessage: _message,
      ),
    );
  }

  Future<void> _showAttachmentPicker() async {
    if (!_canMessage) return;
    if (widget.usesRealEntries) {
      if (widget.onRespondToMeetup == null) {
        if (widget.attachmentsEnabled) {
          widget.onAttach();
        } else {
          _message('Attachments are not connected yet.');
        }
        return;
      }
      final deal = _selectedRealDeal;
      final canSuggest = deal?.canSuggestMeetup == true &&
          widget.onSuggestMeetup != null;
      final canShare = deal?.canShareMeetup == true && deal?.scheduleLabel != null;
      final pricePending = widget.priceProposals.any((proposal) => proposal.offerId == deal?.offerId);
      final canProposePrice = deal?.offerId != null &&
          widget.realDeals?.any((row) => row.id == deal?.id) == true &&
          widget.onProposePrice != null && !pricePending;
      final action = await showModalBottomSheet<int>(
        context: context,
        sheetAnimationStyle: HocalistMotion.sheetStyle(context),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheet) => _ApprovedChatSheetFrame(
          title: 'Chat actions',
          subtitle: 'Share a photo, discuss the price, or arrange your meetup.',
          icon: Icons.add_circle_outline,
          onClose: () => Navigator.pop(sheet),
          child: Column(
            children: [
              _ApprovedMenuAction(icon: Icons.photo_library_outlined,
                title: 'Choose photos', subtitle: 'Select a photo from your device.',
                onTap: widget.attachmentsEnabled ? () => Navigator.pop(sheet, 0) : null),
              _ApprovedMenuAction(icon: Icons.photo_camera_outlined,
                title: 'Take photo', subtitle: 'Open your camera.',
                onTap: widget.onTakePhoto != null ? () => Navigator.pop(sheet, 1) : null),
              if (deal != null) ...[
                _ApprovedMenuAction(icon: Icons.location_on_outlined,
                  title: 'Share meetup details', subtitle: 'Add the confirmed details to your message draft.',
                  onTap: canShare ? () => Navigator.pop(sheet, 2) : null),
                _ApprovedMenuAction(icon: Icons.event_outlined,
                  title: 'Reschedule meetup', subtitle: 'Propose a new date or time for approval.',
                  onTap: canSuggest ? () => Navigator.pop(sheet, 3) : null),
                _ApprovedMenuAction(icon: Icons.sell_outlined,
                  title: widget.viewerIsSeller ? 'Update price' : 'Request a price change',
                  subtitle: pricePending ? 'A price proposal is awaiting a response.' : 'Propose a price for the other person to review.',
                  onTap: canProposePrice ? () => Navigator.pop(sheet, 4) : null),
              ],
            ],
          ),
        ),
      );
      if (!mounted || !_canMessage || action == null || _selectedRealDeal?.id != deal?.id) return;
      switch (action) {
        case 0: widget.onAttach();
        case 1: widget.onTakePhoto?.call();
        case 2:
          final details = [deal!.scheduleLabel, deal.zoneLabel, deal.placeLabel]
              .whereType<String>().where((part) => part.isNotEmpty).join(' · ');
          final draft = _controller.text.trimRight();
          final value = draft.isEmpty ? details : '$draft\n$details';
          _controller.value = TextEditingValue(
            text: value, selection: TextSelection.collapsed(offset: value.length),
          );
        case 3: widget.onSuggestMeetup?.call(deal!.id);
        case 4: widget.onProposePrice?.call(deal!.offerId!);
      }
      return;
    }
    final attachment = await showModalBottomSheet<_ApprovedChatAttachment>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedAttachmentPickerSheet(
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
    if (!mounted || attachment == null) return;
    setState(() {
      _pendingAttachment = attachment.label;
      _pendingAttachmentIsImage = attachment.isImage;
    });
    widget.onAttach();
  }

  Future<void> _showBlockConfirmation(String role) async {
    final persist = widget.onBlockChanged;
    if (persist == null) {
      if (widget.usesRealEntries) {
        _message('Blocking is not connected yet. No account has been blocked.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: HocalistMotion.sheetStyle(context),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _ApprovedChatSheetFrame(
          key: const ValueKey('approved-block-conversation-sheet'),
          title: 'Block $role?',
          subtitle:
              'An active deal may need to be cancelled or resolved first. Deal and safety records will remain available.',
          icon: Icons.block_rounded,
          iconColor: const Color(0xffc62828),
          iconSurface: const Color(0xffffeeee),
          onClose: () => Navigator.pop(sheetContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: BuyerSecondaryButton(
                      label: 'Cancel',
                      color: _navy,
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BuyerPrimaryButton(
                      label: 'Block',
                      colors: const [Color(0xffc62828), Color(0xffd62f29)],
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _message(
                          'Block request will complete when accounts are connected.',
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      return;
    }
    await _runBlockWrite(
      role: role,
      blocked: true,
      title: 'Block $role?',
      subtitle:
          'You and this person will not be able to send new messages or start calls in this chat. The deal, meeting and message history stay unchanged, and you can unblock later.',
      confirmLabel: 'Block',
      busyLabel: 'Blocking…',
      successMessage: 'You blocked $role. They can’t send new messages here.',
      failureMessage:
          'Blocking could not be saved. Check your connection and try again.',
      persist: persist,
    );
  }

  Future<void> _showUnblockConfirmation(String role) async {
    final persist = widget.onBlockChanged;
    if (persist == null) return;
    await _runBlockWrite(
      role: role,
      blocked: false,
      title: 'Unblock $role?',
      subtitle:
          'You will be able to send messages and start calls in this chat again. Block and safety records stay for review.',
      confirmLabel: 'Unblock',
      busyLabel: 'Unblocking…',
      successMessage: 'You unblocked $role. You can message each other again.',
      failureMessage:
          'Unblocking could not be saved. Check your connection and try again.',
      persist: persist,
    );
  }

  Future<void> _runBlockWrite({
    required String role,
    required bool blocked,
    required String title,
    required String subtitle,
    required String confirmLabel,
    required String busyLabel,
    required String successMessage,
    required String failureMessage,
    required Future<bool> Function(bool blocked) persist,
  }) async {
    var busy = widget.blockWritePending;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => _ApprovedChatSheetFrame(
          key: ValueKey(
            blocked
                ? 'approved-block-conversation-sheet'
                : 'approved-unblock-conversation-sheet',
          ),
          title: title,
          subtitle: subtitle,
          icon: blocked ? Icons.block_rounded : Icons.lock_open_rounded,
          iconColor: blocked ? const Color(0xffc62828) : _blue,
          iconSurface: blocked
              ? const Color(0xffffeeee)
              : BuyerUiTokens.softSurface,
          onClose: () => Navigator.pop(sheetContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                Text(
                  error!,
                  key: const Key('approved-block-write-error'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: BuyerSecondaryButton(
                      label: 'Cancel',
                      color: _navy,
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(sheetContext),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BuyerPrimaryButton(
                      label: busy ? busyLabel : confirmLabel,
                      colors: blocked
                          ? const [Color(0xffc62828), Color(0xffd62f29)]
                          : null,
                      onPressed: busy
                          ? null
                          : () async {
                              update(() {
                                busy = true;
                                error = null;
                              });
                              var acknowledged = false;
                              try {
                                acknowledged = await persist(blocked);
                              } catch (_) {
                                acknowledged = false;
                              }
                              if (!sheetContext.mounted) return;
                              if (acknowledged) {
                                Navigator.pop(sheetContext);
                                _message(successMessage);
                              } else {
                                update(() {
                                  busy = false;
                                  error = failureMessage;
                                });
                              }
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

  Future<void> _showOfferEditor() async {
    final priceController = TextEditingController(text: '650');
    final locationController = TextEditingController(text: 'Yonkers, NY');
    final timeController = TextEditingController(text: 'Today • 5:00 PM');
    final revised = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedOfferEditorSheet(
        priceController: priceController,
        locationController: locationController,
        timeController: timeController,
        onClose: () => Navigator.pop(sheetContext, false),
        onSave: () => Navigator.pop(sheetContext, true),
      ),
    );
    priceController.dispose();
    locationController.dispose();
    timeController.dispose();
    if (revised == true && mounted) {
      widget.onOfferRevised?.call();
      _message('Updated offer sent to the buyer.');
    }
  }

  Future<void> _showDealDetails() async {
    if (widget.usesRealEntries) {
      widget.onPrimary();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedDealDetailsSheet(
        offer: widget.offer,
        viewerIsSeller: widget.viewerIsSeller,
        meetingConfirmed: widget.meetingConfirmed,
        offerRevisionPending: widget.offerRevisionPending,
        onClose: () => Navigator.pop(sheetContext),
        onAccept: () {
          Navigator.pop(sheetContext);
          if (widget.viewerIsSeller) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showOfferEditor();
              }
            });
            return;
          }
          if (widget.offerRevisionPending) {
            widget.onOfferRevisionAccepted?.call();
          } else {
            widget.onPrimary();
          }
        },
        onRequestChange: () {
          Navigator.pop(sheetContext);
          widget.onRequestChange();
        },
      ),
    );
  }

  Future<void> _showRealDealDetails(String meetingId) async {
    final deals = <ApprovedDealView>[
      ...?widget.realDeals,
      ...?widget.previousDeals,
    ];
    if (deals.isEmpty) return;
    ApprovedDealView? deal;
    for (final candidate in deals) {
      if (candidate.id == meetingId) {
        deal = candidate;
        break;
      }
    }
    if (deal == null) return;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ApprovedRealDealDetailsSheet(
        deal: deal!,
        viewerIsSeller: widget.viewerIsSeller,
        onClose: () => Navigator.pop(sheetContext),
        onOpenMeeting: widget.onOpenRealDeal == null
            ? null
            : () {
                Navigator.pop(sheetContext);
                widget.onOpenRealDeal!.call(deal!.id);
              },
        onViewOriginalRequest: widget.onViewOriginalRequest == null
            ? null
            : () {
                Navigator.pop(sheetContext);
                widget.onViewOriginalRequest!();
              },
      ),
    );
  }

  Future<void> _showDealCount(int count) async {
    if (count != 1) {
      await _showConversationDeals(selectOnly: true);
      return;
    }
    final seller = widget.viewerIsSeller;
    final showPast = await showDialog<bool>(
      context: context,
      animationStyle: HocalistMotion.dialogStyle(context),
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('1 active deal'),
        content: Text(
          seller
              ? 'You have one active deal with this buyer. When the buyer accepts another of your offers, tap this number to switch deals. You can have up to 3 active deals with this buyer.'
              : 'You have one active deal with this seller. When you accept another offer from this seller, tap this number to switch deals. You can have up to 3 active deals with this seller.',
        ),
        actions: [
          if (widget.previousDeals?.isNotEmpty == true)
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Past deals'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    if (mounted && showPast == true) {
      await _showConversationDeals(selectOnly: true);
    }
  }

  Future<void> _showConversationDeals({bool selectOnly = false}) async {
    if (widget.usesRealEntries) {
      await showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: HocalistMotion.sheetStyle(context),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _ApprovedRealDealsSheet(
          pastSelected: _showPastDeals,
          onChooseGroup: (past) {
            Navigator.pop(sheetContext);
            _chooseDealGroup(past);
          },
          deals: widget.realDeals,
          loading: widget.realDealsLoading,
          error: widget.realDealsError,
          truncated: widget.realDealsTruncated,
          previousDeals: widget.previousDeals,
          selectOnly: selectOnly,
          onRefresh: widget.onRefreshRealDeals,
          onProposeMeeting: () {
            Navigator.pop(sheetContext);
            widget.onPrimary();
          },
          onClose: () => Navigator.pop(sheetContext),
          onOpenDeal: (meetingId) {
            Navigator.pop(sheetContext);
            _setDealView(null, true);
            widget.onSelectRealDeal?.call(meetingId);
            if (selectOnly && widget.onSelectRealDeal != null) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_showRealDealDetails(meetingId));
            });
          },
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedConversationDealsSheet(
        offer: widget.offer,
        secondDealAdded: _secondDealAdded,
        onClose: () => Navigator.pop(sheetContext),
        onOpenActiveDeal: () {
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showDealDetails();
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactDeal = widget.usesRealEntries && widget.onRespondToMeetup != null
        ? _selectedRealDeal
        : null;
    final dealCount = widget.realDeals?.map((deal) => deal.id).toSet().length ?? 0;
    final content = IconButtonTheme(
      data: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              key: const Key('approved-chat-scroll'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  sliver: PinnedHeaderSliver(
                    child: ColoredBox(
                      color: HocalistPalette.surface(context, Colors.white),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              (MediaQuery.sizeOf(context).height -
                                  MediaQuery.viewInsetsOf(context).bottom) *
                              (MediaQuery.textScalerOf(context).scale(16) / 16 >
                                      1.3
                                  ? .8
                                  : .65),
                        ),
                        child: SingleChildScrollView(
                          key: const Key('chat-pinned-header-scroll'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ChatHeader(
                                prototypeStatus: !widget.usesRealEntries,
                                onBack: widget.onBack,
                                onCall: widget.onCall,
                                callLabel: widget.viewerIsSeller
                                    ? 'Call buyer'
                                    : 'Call seller',
                                onMore: _showConversationMenu,
                                contactName: widget.usesRealEntries
                                    ? (widget.realContactName
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? widget.realContactName!.trim()
                                          : (widget.viewerIsSeller
                                                ? 'Buyer'
                                                : 'Seller'))
                                    : widget.contactName,
                                contactRoleLabel: widget.usesRealEntries
                                    ? 'Conversation'
                                    : widget.contactRoleLabel,
                                contactInitials: widget.usesRealEntries
                                    ? (widget.viewerIsSeller ? 'B' : 'S')
                                    : widget.contactInitials,
                              ),
                              if (!widget.usesRealEntries &&
                                  widget.viewerIsSeller &&
                                  widget.requestChangePending) ...[
                                const SizedBox(height: 10),
                                _RequestUpdatedNotice(
                                  onContinue:
                                      widget.onContinueWithRequest ?? () {},
                                  onWithdraw:
                                      widget.onWithdrawFromRequest ?? () {},
                                ),
                              ],
                              if (widget.enquiries.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  ChoiceChip(showCheckmark: false, label: const Text('Deals'),
                                    selected: widget.selectedEnquiryId == null,
                                    onSelected: (widget.realDeals?.isNotEmpty == true || widget.previousDeals?.isNotEmpty == true)
                                      ? (_) => _chooseDealGroup(false) : null),
                                  ChoiceChip(showCheckmark: false, label: const Text('Enquiries'),
                                    selected: widget.selectedEnquiryId != null,
                                    onSelected: widget.onSelectEnquiry == null ? null : (_) => widget.onSelectEnquiry!(widget.enquiries.first.id)),
                                ]),
                                if (widget.selectedEnquiryId != null)
                                  Padding(padding: const EdgeInsets.only(top: 8),
                                    child: _EnquiryContextPanel(enquiries: widget.enquiries,
                                      selectedId: widget.selectedEnquiryId, onSelect: widget.onSelectEnquiry)),
                              ],
                              if (compactDeal != null) ...[
                                const SizedBox(height: 8),
                                _CurrentChatDeal(
                                  deal: compactDeal,
                                  count: dealCount,
                                  onChoose: () => _showDealCount(dealCount),
                                  onExplore: () {
                                    final open = widget.onOpenRealDeal;
                                    if (open != null) {
                                      open(compactDeal.id);
                                    } else {
                                      unawaited(_showRealDealDetails(compactDeal.id));
                                    }
                                  },
                                  onLongPress: widget.onMeetingOptions,
                                ),
                              ] else if (widget.selectedEnquiryId == null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Tooltip(
                                      message: _dealsExpanded ? 'Hide deals' : 'Show deals',
                                      child: TextButton(
                                        key: const Key('chat-toggle-deals'),
                                        onPressed: () => _setDealView(_showPastDeals, !_dealsExpanded),
                                        style: TextButton.styleFrom(
                                          alignment: Alignment.centerLeft,
                                          minimumSize: const Size(0, 44),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          backgroundColor: HocalistPalette.surface(context, _lavender),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          foregroundColor: HocalistPalette.text(context, _blue),
                                        ),
                                        child: Row(children: [
                                          Expanded(child: Text(
                                            widget.usesRealEntries
                                              ? (_showPastDeals == null ? 'All deals' : _showPastDeals! ? 'Past deals' : 'Current deals')
                                              : 'Active deals (${_secondDealAdded ? 2 : 1})',
                                            style: BuyerTypography.style(context, _chatMetrics(context),
                                              BuyerTextRole.buttonLabel, weight: FontWeight.w700),
                                          )),
                                          const SizedBox(width: 6),
                                          Icon(_dealsExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                                        ]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    key: const Key(
                                      'approved-manage-conversation-deals',
                                    ),
                                    onPressed: _showConversationDeals,
                                    style: TextButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: BorderSide(color: HocalistPalette.border(context, _line)),
                                      foregroundColor: HocalistPalette.text(
                                        context,
                                        _blue,
                                      ),
                                      minimumSize: const Size(44, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                    ),
                                    icon: BuyerGlyphIcon(
                                      icon: Icons.tune_rounded,
                                      slotSize: 18,
                                      glyphSize: 18,
                                      color: HocalistPalette.text(
                                        context,
                                        _blue,
                                      ),
                                    ),
                                    label: Text(
                                      'Manage',
                                      style: _text(
                                        context,
                                        size: 11,
                                        weight: FontWeight.w800,
                                        color: _blue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_dealsExpanded) ...[
                              const SizedBox(height: 6),
                              if (!widget.usesRealEntries)
                                _ActiveDealsPanel(
                                  offer: widget.offer,
                                  viewerIsSeller: widget.viewerIsSeller,
                                  meetingConfirmed: widget.meetingConfirmed,
                                  offerRevisionPending:
                                      widget.offerRevisionPending,
                                  secondDealAdded: _secondDealAdded,
                                  onOpenDeal: _showDealDetails,
                                  onLongPressDeal: _showDealDetails,
                                  onAddDeal: () {
                                    setState(() => _secondDealAdded = true);
                                    _message(
                                      'A second deal was added to this conversation.',
                                    );
                                  },
                                )
                              else
                                _RealActiveDealsPanel(
                                  deals: _visibleDeals,
                                  entryOfferId: widget.entryOfferId,
                                  past: _showPastDeals == true,
                                  selectedDealId: widget.selectedDealId,
                                  loading: widget.realDealsLoading,
                                  error: widget.realDealsError,
                                  onRefresh: widget.onRefreshRealDeals,
                                  onViewDeal: (id) {
                                    final open = widget.onOpenRealDeal;
                                    if (open != null) {
                                      open(id);
                                    } else {
                                      unawaited(_showRealDealDetails(id));
                                    }
                                  },
                                  onOpenDeal: (meetingId) {
                                    if (widget.onSelectRealDeal != null) {
                                      widget.onSelectRealDeal!(meetingId);
                                    } else {
                                      unawaited(
                                        _showRealDealDetails(meetingId),
                                      );
                                    }
                                  },
                                ),
                              ],
                              ],
                              Divider(height: 20, thickness: 1,
                                color: HocalistPalette.border(context, const Color(0xffd8d9e5)).withValues(alpha: .45)),
                              if (compactDeal == null && widget.usesRealEntries && _selectedRealDeal != null)
                                Semantics(
                                  key: const Key('chat-selected-deal'),
                                  label: 'Selected deal: ${_selectedRealDeal!.title}',
                                  excludeSemantics: true,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Selected deal', style: BuyerTypography.style(
                                        context, _chatMetrics(context), BuyerTextRole.metadata)),
                                      const SizedBox(height: 2),
                                      Tooltip(
                                        message: _selectedRealDeal!.title,
                                        child: Text(_selectedRealDeal!.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: BuyerTypography.style(context, _chatMetrics(context),
                                            BuyerTextRole.cardTitle, weight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (compactDeal == null && widget.usesRealEntries && !widget.viewerIsSeller &&
                                  _showPastDeals != true && _selectedRealDeal != null &&
                                  !_selectedRealDeal!.completed &&
                                  (widget.realDeals?.any((deal) => deal.id == _selectedRealDeal!.id) ?? false)) ...[
                                const SizedBox(height: 12),
                                BuyerPrimaryButton(key: const Key('buyer-chat-meeting-action'),
                                  label: widget.primaryLabel, minimumHeight: 48,
                                  onPressed: widget.onPrimary,
                                  onLongPress: widget.onMeetingOptions),
                                const SizedBox(height: 12),
                              ],
                              if (widget.onRespondToMeetup != null)
                                ChatMeetupProposalNotice(
                                  proposals: widget.meetupProposals,
                                  respond: widget.onRespondToMeetup!,
                                  viewerIsSeller: widget.viewerIsSeller,
                                  priceProposals: widget.priceProposals,
                                  respondToPrice: widget.onRespondToPrice,
                                ),
                              for (final proposal in widget.priceProposals)
                                if (!proposal.incoming && proposal.offerId == compactDeal?.offerId)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Price proposal ${proposal.proposedPrice} · waiting for ${widget.viewerIsSeller ? 'buyer' : 'seller'}',
                                      style: _text(context, size: 12, color: _muted),
                                    ),
                                  ),
                              if (widget.usesRealEntries &&
                                  widget.blockState != null &&
                                  (widget.blockState!.isBlockedByMe ||
                                      widget
                                          .blockState!
                                          .blockedByCounterpart)) ...[
                                _BlockedConversationNotice(
                                  blockedByMe: widget.blockState!.isBlockedByMe,
                                  onUnblock: widget.blockState!.isBlockedByMe
                                      ? () => _showUnblockConfirmation(
                                          widget.viewerIsSeller
                                              ? 'buyer'
                                              : 'seller',
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  sliver: SliverList.list(
                    children: [
                      if (widget.usesRealEntries) ...[
                        if (widget.olderError != null) Text(widget.olderError!),
                        if (widget.onLoadOlder != null)
                          TextButton(
                            onPressed:
                                widget.olderLoading || widget.messagesLoading
                                ? null
                                : widget.onLoadOlder,
                            child: Text(
                              widget.olderLoading
                                  ? 'Loading older messages…'
                                  : 'Load older messages',
                            ),
                          ),
                        if (widget.messagesLoading)
                          const _ChatStateNotice(
                            key: Key('approvedChatLoading'),
                            message: 'Loading messages…',
                          )
                        else if (widget.messagesError != null)
                          _ChatStateNotice(
                            key: const Key('approvedChatError'),
                            message: widget.messagesError!,
                            onRetry: widget.onRefreshMessages,
                          )
                        else if (widget.realEntries!.isEmpty)
                          const _ChatStateNotice(
                            key: Key('approvedChatEmpty'),
                            message:
                                'No messages yet. Send a message to start the '
                                'conversation.',
                          )
                        else
                          for (final (index, entry)
                              in widget.realEntries!.indexed) ...[
                            if (entry.sentAt != null &&
                                (index == 0 ||
                                    !sameConversationDay(
                                      widget.realEntries![index - 1].sentAt,
                                      entry.sentAt,
                                    )))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Center(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: HocalistPalette.surface(
                                        context,
                                        _lavender,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        conversationDateLabel(entry.sentAt!),
                                        style: _text(
                                          context,
                                          size: 11,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            if (entry.isOutgoing)
                              _OutgoingMessage(
                                text: entry.attachmentMediaIds.isEmpty
                                    ? entry.displayText
                                    : entry.text,
                                time: entry.time,
                                attachmentMediaIds: entry.attachmentMediaIds,
                                isRead: entry.isRead,
                              )
                            else
                              _IncomingMessage(
                                text: entry.attachmentMediaIds.isEmpty
                                    ? entry.displayText
                                    : entry.text,
                                time: entry.time,
                                contactInitials: widget.viewerIsSeller
                                    ? 'B'
                                    : 'S',
                                prototypeStatus: false,
                                attachmentMediaIds: entry.attachmentMediaIds,
                              ),
                          ],
                        if (widget.sendError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.sendError!,
                            key: const Key('approvedChatSendError'),
                            textAlign: TextAlign.center,
                            style: _text(
                              context,
                              size: 9,
                              weight: FontWeight.w700,
                              color: const Color(0xFFD32F2F),
                            ),
                          ),
                          if (widget.viewerIsSeller && widget.onManagePayment != null) ...[
                            const SizedBox(height: 8),
                            BuyerPrimaryButton(
                              key: const Key('approvedChatManagePayment'),
                              onPressed: widget.onManagePayment,
                              label: 'Manage payment',
                            ),
                          ],
                        ],
                      ] else ...[
                        const _DateDivider(),
                        const SizedBox(height: 10),
                        _IncomingMessage(
                          key: const Key('approved-chat-message-incoming-1'),
                          text: widget.incomingMessage,
                          time: '9:30 AM',
                          contactInitials: widget.contactInitials,
                        ),
                        const SizedBox(height: 6),
                        _OutgoingMessage(
                          key: const Key('approved-chat-message-outgoing-1'),
                          text: widget.outgoingMessage,
                          time: '9:31 AM',
                        ),
                        const SizedBox(height: 6),
                        _IncomingMessage(
                          key: const Key('approved-chat-message-incoming-2'),
                          text:
                              'Great! I’m at the Yonkers location. See you at 5:00 PM today.',
                          time: '9:32 AM',
                          contactInitials: widget.contactInitials,
                        ),
                        const SizedBox(height: 6),
                        const _OutgoingMessage(
                          text: 'Perfect. I’ll be there around 4:55 PM.',
                          time: '9:33 AM',
                        ),
                        const SizedBox(height: 6),
                        _IncomingMessage(
                          text:
                              'Sounds good. I’ll have the iPad charged and ready for you to check.',
                          time: '9:34 AM',
                          contactInitials: widget.contactInitials,
                        ),
                        const SizedBox(height: 6),
                        const _OutgoingMessage(
                          text: 'Awesome, thanks! Talk to you soon.',
                          time: '9:35 AM',
                        ),
                        const SizedBox(height: 6),
                        _IncomingMessage(
                          text: 'You got it. See you soon!',
                          time: '9:35 AM',
                          contactInitials: widget.contactInitials,
                        ),
                        for (final entry in _sentEntries) ...[
                          const SizedBox(height: 6),
                          if (entry.isOutgoing)
                            _OutgoingMessage(
                              text: entry.displayText,
                              time: entry.time,
                            )
                          else
                            _IncomingMessage(
                              text: entry.displayText,
                              time: entry.time,
                              contactInitials: widget.contactInitials,
                            ),
                        ],
                      ],
                      const SizedBox(height: 8),
                      if (_pendingAttachment != null) ...[
                        _ApprovedPendingAttachment(
                          label: _pendingAttachment!,
                          isImage: _pendingAttachmentIsImage,
                          onRemove: () =>
                              setState(() => _pendingAttachment = null),
                        ),
                        const SizedBox(height: 7),
                      ],
                      if (widget.usesRealEntries &&
                          widget.pendingAttachmentMediaId != null) ...[
                        _ApprovedPendingRemoteAttachment(
                          mediaId: widget.pendingAttachmentMediaId!,
                          busy: widget.attachmentRetryBusy,
                          onRetry: widget.onRetryAttachment,
                          onDiscard: widget.onDiscardAttachment,
                        ),
                        const SizedBox(height: 7),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: _MessageComposer(
                controller: _controller,
                onAttach: _showAttachmentPicker,
                onSend: _send,
                enabled: _canMessage,
                hintText: !_canMessage
                    ? (widget.blockState?.isBlockedByMe == true
                          ? 'You blocked this person'
                          : 'Messaging is unavailable')
                    : 'Type a message...',
              ),
            ),
          ),
        ],
      ),
    );
    if (ApprovedReplicaScope.maybeOf(context) != null) return content;

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: constraints.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return ApprovedReplicaScope(metrics: metrics, child: content);
      },
    );
  }
}

class _ApprovedPageScaffold extends StatelessWidget {
  const _ApprovedPageScaffold({
    required this.onBack,
    required this.selection,
    required this.navigation,
    required this.bodyKey,
    this.slivers,
    this.body,
    this.accentColor = _blue,
  }) : assert((slivers == null) != (body == null));

  final VoidCallback onBack;
  final ApprovedBuyerNavSelection selection;
  final ApprovedBuyerNavigation navigation;
  final Key bodyKey;
  final List<Widget>? slivers;
  final Widget? body;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media.size.width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media.size.height;
        final metrics = ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: availableWidth,
          textScaler: media.textScaler,
        );

        if (metrics.usesScaledReplicaCanvas) {
          final canvasSize = Size(
            ApprovedReplicaMetrics.referenceCanvasWidth,
            availableHeight / metrics.geometryScale,
          );
          final canvasMetrics = ApprovedReplicaMetrics.resolve(
            brightness: Theme.of(context).brightness,
            availableWidth: ApprovedReplicaMetrics.referenceCanvasWidth,
            textScaler: media.textScaler,
          );
          return ColoredBox(
            color: HocalistPalette.surface(context, Colors.white),
            child: Center(
              child: SizedBox(
                key: const Key('approved-replica-viewport'),
                width: metrics.contentMaxWidth,
                height: availableHeight,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox.fromSize(
                      key: const Key('approved-replica-canvas'),
                      size: canvasSize,
                      child: _buildScaffold(
                        context,
                        media,
                        canvasMetrics,
                        canvasSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final canvasSize = Size(metrics.contentMaxWidth, availableHeight);
        return ColoredBox(
          color: HocalistPalette.surface(context, Colors.white),
          child: Center(
            child: SizedBox.fromSize(
              key: const Key('approved-replica-viewport'),
              size: canvasSize,
              child: _buildScaffold(context, media, metrics, canvasSize),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    MediaQueryData media,
    ApprovedReplicaMetrics metrics,
    Size canvasSize,
  ) {
    return ApprovedReplicaScope(
      metrics: metrics,
      child: MediaQuery(
        data: media.copyWith(size: canvasSize),
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) onBack();
          },
          child: Scaffold(
            backgroundColor: HocalistPalette.surface(context, Colors.white),
            body: SafeArea(
              bottom: false,
              child: body ?? CustomScrollView(key: bodyKey, slivers: slivers!),
            ),
            bottomNavigationBar: BuyerBottomNavigation(
              selected: selection,
              callbacks: navigation,
              accentColor: accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _text(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color color = _navy,
  double height = 1.25,
}) {
  return (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: size,
    fontWeight: weight,
    color: HocalistPalette.text(context, color),
    height: height,
    letterSpacing: 0,
  );
}

bool _usesAccessibilityReflow(BuildContext context) {
  return ApprovedReplicaScope.of(context).accessibilityReflow;
}

Widget _asset(
  String name, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  String? semanticLabel,
}) {
  if (name == 'chat-more.png') {
    return Builder(builder: (context) => PreservedRasterGlyph(
      asset: '$_assetRoot/$name', width: width ?? 14, height: height ?? 27,
      fit: BoxFit.cover, color: HocalistPalette.text(context, const Color(0xff101443)),
      semanticLabel: semanticLabel));
  }
  if (name == 'offers-envelope.png') {
    return Builder(builder: (context) => Image.asset(
      BuyerAssetIcon.themedAsset(context, '$_assetRoot/$name'), width: width,
      height: height, fit: fit, semanticLabel: semanticLabel));
  }
  if (ApprovedInterfaceIcon.kindFor('$_assetRoot/$name') != null) {
    return SizedBox(width: width, height: height, child: Center(child:
      ApprovedInterfaceIcon(asset: '$_assetRoot/$name', size: height ?? width ?? 24,
        semanticLabel: semanticLabel)));
  }
  if (width != null &&
      height != null &&
      (width - height).abs() < .01 &&
      fit == BoxFit.contain) {
    return BuyerAssetIcon(
      asset: '$_assetRoot/$name',
      slotSize: width,
      semanticLabel: semanticLabel,
    );
  }
  return _ApprovedRasterAsset(
    asset: '$_assetRoot/$name',
    width: width,
    height: height,
    fit: fit,
    semanticLabel: semanticLabel,
  );
}

class _ApprovedRasterAsset extends StatefulWidget {
  const _ApprovedRasterAsset({
    required this.asset,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  });

  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  State<_ApprovedRasterAsset> createState() => _ApprovedRasterAssetState();
}

class _ApprovedRasterAssetState extends State<_ApprovedRasterAsset> {
  AssetBundle? _bundle;
  Future<ByteData>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (_bundle != bundle) {
      _bundle = bundle;
      _bytes = bundle.load(widget.asset);
    }
  }

  @override
  void didUpdateWidget(covariant _ApprovedRasterAsset oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _bytes = _bundle!.load(widget.asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FutureBuilder<ByteData>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorWidget.withDetails(
              message: 'Missing approved asset: ${widget.asset}',
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const SizedBox.shrink();
          }
          return Image.memory(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            color: Theme.of(context).brightness == Brightness.dark &&
                    widget.asset.endsWith('/header-notification.png')
                ? HocalistPalette.text(context, _blue) : null,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            filterQuality: FilterQuality.high,
            semanticLabel: widget.semanticLabel,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }
}

class _OffersHero extends StatelessWidget {
  const _OffersHero({this.requestTitle, this.offerCount});
  final String? requestTitle;
  final int? offerCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 330;
        final request = requestTitle;
        if (request != null) {
          final palette = MarketplaceColors.of(context);
          final ink = palette.ink;
          final sub = palette.muted;
          final count = offerCount;
          final detailStyle = MarketplaceTypography.text(context, 12, sub);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Compare offers', style: MarketplaceTypography.text(context, 21, ink, weight: FontWeight.w700, height: 1.18).copyWith(letterSpacing: -.65)),
              const SizedBox(height: 3),
              Text(request, style: detailStyle),
            ])),
            if (count != null) ...[
              const SizedBox(width: 7),
              Text(count == 1 ? '1 offer' : '$count offers', style: detailStyle),
            ],
          ]);
        }
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offers received',
              style: BuyerTypography.style(
                context,
                ApprovedReplicaScope.of(context),
                BuyerTextRole.displayTitle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Compare offers and choose the best seller for you.',
              style: _text(
                context,
                size: narrow ? 10 : 13,
                color: _muted,
                height: 1.3,
              ),
            ),
          ],
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 6, child: copy),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: _asset(
                'offers-envelope.png',
                height: narrow ? 70 : 96,
                semanticLabel: 'Offer arriving in an envelope',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PotentialBuyerRewardRow extends StatefulWidget {
  const _PotentialBuyerRewardRow({required this.estimate, required this.onOpen, super.key});

  final Future<int>? estimate;
  final VoidCallback onOpen;

  @override
  State<_PotentialBuyerRewardRow> createState() => _PotentialBuyerRewardRowState();
}

class _PotentialBuyerRewardRowState extends State<_PotentialBuyerRewardRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = MarketplaceColors.of(context);
    final paper = palette.paper;
    final ink = palette.ink;
    final sub = palette.muted;
    final border = palette.border;
    final brand = palette.brand;
    final soft = palette.soft;
    final headingStyle = MarketplaceTypography.text(context, 13, ink, weight: FontWeight.w700, height: null);
    final detailStyle = MarketplaceTypography.text(context, 12, sub);
    final radius = BorderRadius.circular(12);
    return Material(
      color: paper,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          expanded: _expanded,
          child: InkWell(
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded) widget.onOpen();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(children: [
                  Container(
                    width: 24, height: 24, alignment: Alignment.center,
                    decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(7)),
                    child: Icon(Icons.card_giftcard_outlined, size: 14, color: brand),
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text('Potential reward', style: headingStyle)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: FutureBuilder<int>(
                      future: widget.estimate,
                      builder: (context, snapshot) {
                        final amount = snapshot.data;
                        final value = amount != null && amount > 0 && !snapshot.hasError
                            ? 'Up to \$${(amount / 100).toStringAsFixed(2)}'
                            : snapshot.hasError ? 'Estimate unavailable'
                            : snapshot.connectionState == ConnectionState.waiting
                                ? 'Checking…' : 'No estimate yet';
                        return Semantics(liveRegion: true, child: Text(
                          value, style: headingStyle.copyWith(color: brand), textAlign: TextAlign.end,
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 14, color: brand),
                ]),
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(39, 0, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chat with sellers to compare offers. When you buy from one of them and confirm '
                'the purchase with your PIN, you can earn the combined reward from eligible '
                'sellers you interacted with.', style: detailStyle),
              const SizedBox(height: 6),
              Text('Refunded targeting fees are excluded from the total.', style: detailStyle),
            ]),
          ),
      ]),
    );
  }
}

class _OffersRewardsCard extends StatelessWidget {
  const _OffersRewardsCard();

  @override
  Widget build(BuildContext context) {
    return _Surface(
      color: const Color(0xfffaf9ff),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxWidth < 300;
          final gift = Container(
            width: tight ? 54 : 70,
            height: tight ? 54 : 70,
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, Colors.white),
              shape: BoxShape.circle,
              border: Border.all(color: HocalistPalette.border(context, _line)),
            ),
            padding: EdgeInsets.all(tight ? 6 : 8),
            child: _asset('rewards-gift.png', fit: BoxFit.contain),
          );
          final total = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Sample reward estimate',
                style: _text(
                  context,
                  size: tight ? 9 : 12,
                  weight: FontWeight.w800,
                ),
              ),
              Text(
                r'$0.40',
                style: _text(
                  context,
                  size: tight ? 24 : 31,
                  weight: FontWeight.w900,
                  color: _offersBlue,
                ),
              ),
              Text(
                'From 2 sample sellers',
                style: _text(context, size: tight ? 8 : 10, color: _muted),
              ),
            ],
          );
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            gift,
            SizedBox(width: tight ? 8 : 12),
            Expanded(child: total),
            IconButton(tooltip: 'How offer rewards work', icon: const Icon(Icons.info_outline_rounded),
              color: HocalistPalette.text(context, _offersBlue),
              onPressed: () => showMoneyHelp(context, title: 'Offer rewards', answers: const {
                'When do I earn a reward?': 'Earn rewards on eligible purchases after PIN confirmation and seller fee collection.',
              })),
          ]);
        },
      ),
    );
  }
}

class _OffersToolbar extends StatelessWidget {
  const _OffersToolbar({
    required this.value,
    required this.onChanged,
    required this.onFilter,
    required this.filtersActive,
    this.realMode = false,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;
  final bool filtersActive;
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 320;
        return Row(
          children: [
            Text(
              'Sort by',
              style: _text(
                context,
                size: compact ? 9 : 12,
                weight: FontWeight.w800,
              ),
            ),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: HocalistSelectMenu<String>(
                key: const Key('approved-offers-sort'),
                role: HocalistControlRole.buyer,
                value: value,
                labelBuilder: (item) => item,
                options: realMode
                    ? const ['Newest first', 'Lowest price']
                    : const ['Best match', 'Lowest price', 'Closest'],
                onSelected: onChanged,
                trigger: Container(
                  constraints: BoxConstraints(minHeight: compact
                      ? HocalistInputTokens.compactMinimumHeight : HocalistInputTokens.minimumHeight),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(context, Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HocalistPalette.border(context, _line)),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: _text(context, size: compact ? 9 : 11, weight: FontWeight.w800))),
                    _asset('offers-sort-down.png', width: compact ? 13 : 16, height: compact ? 13 : 16),
                  ]),
                ),
              ),
            ),
            SizedBox(width: compact ? 5 : 8),
            OutlinedButton(
              key: const Key('approved-offers-filter'),
              onPressed: onFilter,
              style: OutlinedButton.styleFrom(
                minimumSize: Size(
                  compact ? 58 : 72,
                  compact
                      ? HocalistInputTokens.compactMinimumHeight
                      : HocalistInputTokens.minimumHeight,
                ),
                tapTargetSize: compact
                    ? MaterialTapTargetSize.shrinkWrap
                    : MaterialTapTargetSize.padded,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                side: BorderSide(color: HocalistPalette.border(context, _line)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                filtersActive ? 'Filter (1)' : 'Filter',
                style: _text(
                  context,
                  size: compact ? 9 : 11,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact loading/error/empty notice for the real chat history.
class _ChatStateNotice extends StatelessWidget {
  const _ChatStateNotice({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: _text(
              context,
              size: 10,
              weight: FontWeight.w700,
              color: _navy,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 2),
            TextButton(
              key: const Key('approvedChatRetry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: EdgeInsets.zero,
                foregroundColor: HocalistPalette.text(context, _offersBlue),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact loading/error/empty notice for the real offers list.
class _OffersStateNotice extends StatelessWidget {
  const _OffersStateNotice({
    required this.message,
    this.onRetry,
    this.title,
    this.icon,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;

  /// Designed empty-state heading and icon; loading and error keep the compact
  /// text-only treatment.
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HocalistPalette.surface(context, _lavender),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 22,
                color: HocalistPalette.text(context, _offersBlue),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (title != null) ...[
            Text(
              title!,
              style: _text(
                context,
                size: 13,
                weight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 3),
          ],
          Text(
            message,
            style: _text(
              context,
              size: 11,
              weight: FontWeight.w700,
              color: title == null ? _navy : _muted,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 4),
            TextButton(
              key: const Key('approvedOffersRetry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: EdgeInsets.zero,
                foregroundColor: HocalistPalette.text(context, _offersBlue),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedOfferCard extends StatelessWidget {
  const _ApprovedOfferCard({required this.seller, required this.initials, required this.reviews,
    required this.status, required this.statusColor, required this.price, required this.description,
    required this.firstFactAsset, required this.firstFactTitle, required this.firstFactBody,
    required this.distance, required this.availability, required this.onDetails, this.topMatch = false});
  final String seller, initials, reviews, status, price, description, firstFactAsset, firstFactTitle, firstFactBody, distance, availability;
  final Color statusColor;
  final bool topMatch;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) => BuyerDealCard(sellerName: seller, title: description,
    price: price, meeting: availability, place: 'View offer location', message: '', onChat: onDetails);
}
class _SecurePrivateNotice extends StatelessWidget {
  const _SecurePrivateNotice();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      key: const Key('approved-secure-private-notice'),
      padding: EdgeInsets.all(compact ? 5 : 9),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfff1faf5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _asset(
            'offers-lock.png',
            width: compact ? 24 : 34,
            height: compact ? 24 : 34,
          ),
          SizedBox(width: compact ? 4 : 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure & private',
                  style: _text(
                    context,
                    size: compact ? 8 : 11,
                    weight: FontWeight.w900,
                    color: _green,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Your information is safe. Chat opens only after you select a seller.',
                  style: _text(
                    context,
                    size: compact ? 6 : 9,
                    weight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferDetailHeader extends StatelessWidget {
  const _OfferDetailHeader({
    required this.onBack,
    required this.onNotifications,
  });
  final VoidCallback onBack;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BuyerTopLevelHeader(
          onNotifications: onNotifications,
          backButton: IconButton(
            key: const Key('approved-offer-back'),
            tooltip: 'Back',
            onPressed: onBack,
            icon: _asset('detail-back.png', width: 24, height: 24),
          ),
        ),
        Text(
          'Offer details',
          style: BuyerTypography.style(
            context,
            ApprovedReplicaScope.of(context),
            BuyerTextRole.pageTitle,
            color: _navy,
          ),
        ),
      ],
    );
  }
}

class _OfferSellerSummary extends StatelessWidget {
  const _OfferSellerSummary({this.offer, this.realMode = false});

  final LocalOfferRecord? offer;

  /// Real mode renders only authoritative seller facts. Verification, ratings,
  /// distance and fixed availability are prototype-only fixtures.
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return _Surface(
      padding: EdgeInsets.all(compact ? 7 : 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = _usesAccessibilityReflow(context);
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InitialsAvatar(
                    initials: _initialsFor(
                      offer?.sellerName ?? 'Northside Tech',
                    ),
                    size: compact ? 36 : 44,
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                offer?.sellerName ?? 'Northside Tech',
                                style: BuyerTypography.style(
                                  context,
                                  ApprovedReplicaScope.of(context),
                                  BuyerTextRole.cardTitle,
                                  color: _navy,
                                ),
                              ),
                            ),
                            if (!realMode) ...[
                              const SizedBox(width: 5),
                              _asset(
                                'detail-verified.png',
                                width: compact ? 14 : 17,
                                height: compact ? 14 : 17,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (realMode)
                          Text(
                            offer?.status == LocalOfferStatus.completed
                                ? 'Purchase completed with this seller.'
                                : offer?.status == LocalOfferStatus.selected ||
                                      offer?.status ==
                                          LocalOfferStatus.meetingConfirmed
                                ? 'Selected for discussion. Review the agreed deal details below.'
                                : 'Offer received. Start a deal chat to discuss it.',
                            style: _text(
                              context,
                              size: compact ? 8 : 9,
                              weight: FontWeight.w600,
                              color: _muted,
                              height: 1.3,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _asset(
                                'detail-star.png',
                                width: compact ? 11 : 14,
                                height: compact ? 11 : 14,
                              ),
                              Text(
                                '4.9 (128 reviews)',
                                style: _text(
                                  context,
                                  size: compact ? 8 : 9,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              _asset(
                                'detail-seller-shield.png',
                                width: compact ? 11 : 14,
                                height: compact ? 11 : 14,
                              ),
                              Text(
                                'Verified seller',
                                style: _text(
                                  context,
                                  size: compact ? 8 : 9,
                                  weight: FontWeight.w700,
                                  color: _green,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        offer?.price ?? r'$420',
                        style: _text(
                          context,
                          size: compact ? 16 : 19,
                          weight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Total price',
                        style: _text(
                          context,
                          size: compact ? 7 : 9,
                          weight: FontWeight.w500,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 10),
              LayoutBuilder(
                builder: (context, inner) {
                  final facts = realMode
                      ? [
                          if ((offer?.location ?? '').trim().isNotEmpty)
                            _DetailFact(
                              asset: 'detail-location.png',
                              title: 'Meet-up place',
                              body: offer!.location,
                            ),
                          if ((offer?.meetingDate ?? '').trim().isNotEmpty)
                            _DetailFact(
                              asset: 'detail-clock.png',
                              title: 'Meet-up time',
                              body: offer!.meetingDate,
                            ),
                        ]
                      : const [
                          _DetailFact(
                            asset: 'detail-identity.png',
                            title: 'Identity verified',
                          ),
                          _DetailFact(
                            asset: 'detail-location.png',
                            title: '1.2 mi away',
                            body: 'from you',
                          ),
                          _DetailFact(
                            asset: 'detail-clock.png',
                            title: 'Available',
                            body: 'Sat, May 17',
                          ),
                        ];
                  if (facts.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  if (narrow) {
                    return Column(
                      children: [
                        for (final fact in facts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: fact,
                          ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < facts.length; i++) ...[
                        Expanded(child: facts[i]),
                        if (i < facts.length - 1)
                          const VerticalDivider(width: 14, color: _line),
                      ],
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.asset, required this.title, this.body});
  final String asset;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 95;
        return Row(
          children: [
            BuyerAssetIconSurface(
              asset: '$_assetRoot/$asset',
              surfaceSize: compact ? 26 : 32,
              iconSize: compact ? 17 : 21,
              shape: BuyerIconSurfaceShape.circle,
            ),
            SizedBox(width: compact ? 3 : 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _text(
                      context,
                      size: compact ? 7 : 9,
                      weight: FontWeight.w800,
                    ),
                  ),
                  if (body != null)
                    Text(
                      body!,
                      style: _text(
                        context,
                        size: compact ? 7 : 9,
                        weight: FontWeight.w500,
                        color: _muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OfferRewardWindow extends StatelessWidget {
  const _OfferRewardWindow({this.realMode = false});

  /// Real mode explains the documented reward policy instead of a fixture
  /// estimate and deadline. An authoritative per-offer estimate is not yet
  /// projected to the client.
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      padding: EdgeInsets.all(compact ? 6 : 9),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfffff8eb)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _usesAccessibilityReflow(context);
          final copy = Row(
            children: [
              _asset(
                'detail-gift.png',
                width: compact ? 42 : 52,
                height: compact ? 42 : 52,
              ),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      realMode
                          ? 'Rewards after a confirmed purchase'
                          : 'Sample reward estimate',
                      style: _text(
                        context,
                        size: compact ? 11 : 14,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      realMode
                          ? 'Share your request PIN only after you complete the '
                                'purchase. Eligible rewards are earned after '
                                'PIN confirmation and seller fee collection.'
                          : 'An eligible purchase earns a reward after PIN confirmation and seller fee collection.',
                      style: _text(
                        context,
                        size: compact ? 8 : 10,
                        weight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (realMode) return copy;
          final reward = Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 11,
              vertical: compact ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xffffedc8)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              children: [
                Text(
                  'Sample estimate',
                  style: _text(
                    context,
                    size: compact ? 7 : 9,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r'$12.40',
                  style: _text(
                    context,
                    size: compact ? 15 : 18,
                    weight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
          if (stacked) {
            return Column(
              children: [
                copy,
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(child: reward),
                    const SizedBox(width: 6),
                    _asset('info.png', width: 21, height: 21),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              SizedBox(width: compact ? 5 : 8),
              reward,
              SizedBox(width: compact ? 4 : 6),
              _asset(
                'info.png',
                width: compact ? 16 : 20,
                height: compact ? 16 : 20,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OfferDescription extends StatelessWidget {
  const _OfferDescription({
    this.offer,
    this.realMode = false,
    this.requestTitle = '',
  });

  final LocalOfferRecord? offer;

  /// Real mode drops the fixture iPad artwork and request copy. It shows the
  /// authoritative request title and the seller's own pitch.
  final bool realMode;
  final String requestTitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return _Surface(
      padding: EdgeInsets.all(compact ? 7 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BuyerAssetIconSurface(
                asset: '$_assetRoot/detail-description.png',
                surfaceSize: compact ? 24 : 29,
                iconSize: compact ? 16 : 19,
                radius: compact ? 6 : 7,
              ),
              SizedBox(width: compact ? 4 : 6),
              Expanded(
                child: Text(
                  'Description Details',
                  style: _text(
                    context,
                    size: compact ? 11 : 14,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 5 : 8),
          if (realMode)
            Column(
              children: [
                if (requestTitle.trim().isNotEmpty)
                  _DescriptionBlock(
                    title: 'Your Request:',
                    body: requestTitle.trim(),
                  ),
                if (requestTitle.trim().isNotEmpty) const SizedBox(height: 7),
                _DescriptionBlock(
                  title: 'Seller\'s Pitch:',
                  body: offer?.message.isNotEmpty == true
                      ? offer!.message
                      : 'No message was included with this offer.',
                ),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = _usesAccessibilityReflow(context);
                final image = ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _asset(
                    'chat-ipad.png',
                    width: double.infinity,
                    height: stacked ? 176 : (compact ? 135 : 145),
                    fit: BoxFit.cover,
                  ),
                );
                final copy = Column(
                  children: [
                    const _DescriptionBlock(
                      title: 'Your Request Description:',
                      body:
                          'Looking for an iPad Air 5th generation or newer in good condition or like new.',
                    ),
                    const SizedBox(height: 7),
                    _DescriptionBlock(
                      title: 'Seller\'s Pitch:',
                      body: offer?.message.isNotEmpty == true
                          ? offer!.message
                          : 'Hi, I have an iPad Air in excellent condition. It is gently used, works perfectly, and I can meet locally.',
                    ),
                  ],
                );
                if (stacked) {
                  return Column(
                    children: [image, const SizedBox(height: 8), copy],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: image),
                    const SizedBox(width: 8),
                    Expanded(child: copy),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfff8f7ff)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xffecebfa)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _text(
              context,
              size: compact ? 8 : 9,
              weight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            body,
            style: _text(
              context,
              size: compact ? 7 : 9,
              weight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferPinNotice extends StatelessWidget {
  const _OfferPinNotice({this.realMode = false});

  /// Real mode never renders a sample PIN. The purchase PIN is issued to the
  /// buyer and surfaces with the confirmed meeting/outcome flow.
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfff5f1ff)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xffdfd8ff)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _usesAccessibilityReflow(context);
          final copy = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BuyerAssetIconSurface(
                asset: '$_assetRoot/detail-pin.png',
                surfaceSize: compact ? 36 : 44,
                iconSize: compact ? 28 : 34,
                shape: BuyerIconSurfaceShape.circle,
              ),
              SizedBox(width: compact ? 4 : 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      realMode
                          ? 'Your purchase PIN'
                          : 'Seller PIN for your rewards',
                      style: _text(
                        context,
                        size: compact ? 8 : 10,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      realMode
                          ? 'Your PIN appears with your confirmed meeting. Share it only after completing the sale. It expires at the end of the accepted meeting day in the meeting timezone.'
                          : 'Share your purchase PIN only after completing the sale. It expires at the end of the accepted meeting day in the meeting timezone. Rewards remain pending until applicable fees are collected.',
                      style: _text(
                        context,
                        size: compact ? 6 : 8,
                        weight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final pin = Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xffe8e0ff)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              realMode ? '•••••' : '15230',
              semanticsLabel: realMode
                  ? 'View your PIN in the confirmed meeting'
                  : null,
              textAlign: TextAlign.center,
              style: _text(
                context,
                size: compact ? 14 : 16,
                weight: FontWeight.w900,
                color: _blue,
              ),
            ),
          );
          if (stacked) {
            return Column(
              children: [
                copy,
                const SizedBox(height: 7),
                SizedBox(width: double.infinity, child: pin),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 8),
              pin,
            ],
          );
        },
      ),
    );
  }
}

class _AboutSeller extends StatelessWidget {
  const _AboutSeller({required this.onViewProfile, this.realMode = false});
  final VoidCallback onViewProfile;

  /// Real mode does not repeat an unverified deal count or response claim.
  final bool realMode;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return _Surface(
      padding: EdgeInsets.all(compact ? 7 : 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _usesAccessibilityReflow(context);
          final copy = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BuyerAssetIconSurface(
                asset: '$_assetRoot/detail-about.png',
                surfaceSize: compact ? 28 : 34,
                iconSize: compact ? 18 : 22,
                radius: compact ? 7 : 8,
              ),
              SizedBox(width: compact ? 5 : 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About the Seller',
                      style: _text(
                        context,
                        size: compact ? 10 : 12,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      realMode
                          ? 'Seller details and ratings are currently unavailable. Please try again later.'
                          : 'Local seller with 230+ successful deals. Usually responds in a few hours.',
                      style: _text(
                        context,
                        size: compact ? 7 : 9,
                        weight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final button = TextButton(
            key: const Key('approved-view-profile'),
            onPressed: onViewProfile,
            style: TextButton.styleFrom(
              backgroundColor: HocalistPalette.surface(context, _lavender),
              minimumSize: Size(compact ? 86 : 104, compact ? 38 : 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'View profile',
              style: _text(
                context,
                size: compact ? 8 : 10,
                weight: FontWeight.w800,
                color: _blue,
              ),
            ),
          );
          if (stacked) {
            return Column(
              children: [
                copy,
                const SizedBox(height: 7),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 8),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _OfferOfflineNotice extends StatelessWidget {
  const _OfferOfflineNotice({this.sellerSelected = false});

  final bool sellerSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      padding: EdgeInsets.all(compact ? 3 : 7),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfff6f4ff)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _asset(
            'detail-chat-notice.png',
            width: compact ? 20 : 29,
            height: compact ? 20 : 29,
          ),
          SizedBox(width: compact ? 4 : 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sellerSelected
                      ? 'Your chat with this seller is open.'
                      : 'Chat opens only after you select this seller.',
                  style: _text(
                    context,
                    size: compact ? 7 : 10,
                    weight: FontWeight.w900,
                    color: _blue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your PIN protects reward completion during meetup. Item payment stays offline.',
                  style: _text(
                    context,
                    size: compact ? 5 : 8,
                    weight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectSellerPanel extends StatelessWidget {
  const _SelectSellerPanel({
    required this.onSelect,
    this.busy = false,
    this.error,
    this.enabled = true,
  });
  final VoidCallback onSelect;
  final bool busy;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width <= 320 &&
        !_usesAccessibilityReflow(context);
    return _Surface(
      padding: EdgeInsets.all(compact ? 4 : 6),
      child: Column(
        children: [
          Row(
            children: [
              BuyerAssetIconSurface(
                asset: '$_assetRoot/detail-select.png',
                surfaceSize: compact ? 30 : 38,
                iconSize: compact ? 21 : 27,
                radius: compact ? 7 : 9,
              ),
              SizedBox(width: compact ? 5 : 7),
              Expanded(
                child: _PrimaryButton(
                  key: const Key('approved-select-seller'),
                  label: busy
                      ? 'Opening…'
                      : enabled
                      ? 'Start deal chat'
                      : 'Offer unavailable',
                  onPressed: busy || !enabled ? null : onSelect,
                  height: compact ? 32 : 44,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            SizedBox(height: compact ? 2 : 3),
            Text(
              error!,
              key: const Key('approvedSelectSellerError'),
              textAlign: TextAlign.center,
              style: _text(
                context,
                size: compact ? 6 : 8.5,
                weight: FontWeight.w700,
                color: const Color(0xFFD32F2F),
              ),
            ),
          ],
          SizedBox(height: compact ? 1 : 2),
          Text(
            'Discuss the offer and meetup with this seller in Hocalist chat.',
            textAlign: TextAlign.center,
            style: _text(
              context,
              size: compact ? 6 : 8,
              weight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.onBack,
    required this.onCall,
    required this.onMore,
    required this.contactName,
    required this.contactRoleLabel,
    this.contactInitials,
    this.prototypeStatus = true,
    this.callLabel = 'Call seller',
  });
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onMore;
  final String contactName;
  final String contactRoleLabel;
  final String? contactInitials;
  final bool prototypeStatus;
  final String callLabel;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    final back = IconButton(
      key: const Key('approved-chat-back'),
      tooltip: 'Back',
      onPressed: onBack,
      constraints: BoxConstraints.tightFor(
        width: compact ? 36 : 48,
        height: compact ? 36 : 48,
      ),
      padding: EdgeInsets.all(compact ? 6 : 8),
      icon: _asset(
        'chat-back.png',
        width: compact ? 20 : 24,
        height: compact ? 20 : 24,
      ),
    );
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        if (contactInitials == null)
          ClipOval(
            child: _asset(
              'john-avatar.png',
              width: compact ? 30 : 40,
              height: compact ? 30 : 40,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: compact ? 30 : 40,
            height: compact ? 30 : 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, _lavender),
              shape: BoxShape.circle,
            ),
            child: Text(
              contactInitials!,
              style: _text(
                context,
                size: compact ? 9 : 12,
                weight: FontWeight.w900,
              ),
            ),
          ),
        if (prototypeStatus)
          Positioned(
            right: -1,
            bottom: 0,
            child: Container(
              width: compact ? 9 : 11,
              height: compact ? 9 : 11,
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  const Color(0xff12b759),
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: HocalistPalette.border(context, Colors.white),
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
    final badge = !prototypeStatus
        ? const SizedBox.shrink()
        : Container(
            key: const Key('approved-chat-role-badge'),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 3 : 6,
              vertical: compact ? 2 : 3,
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, _lavender),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _asset(
                  'chat-verified.png',
                  width: compact ? 10 : 14,
                  height: compact ? 10 : 14,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    contactRoleLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      context,
                      size: compact ? 6 : 9,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
    final call = IconButton(
      key: const Key('approved-call-seller'),
      tooltip: callLabel,
      onPressed: onCall,
      constraints: BoxConstraints.tightFor(
        width: compact ? 36 : 48,
        height: compact ? 36 : 48,
      ),
      padding: EdgeInsets.all(compact ? 7 : 8),
      icon: _asset(
        'chat-call.png',
        width: compact ? 21 : 25,
        height: compact ? 21 : 25,
      ),
    );
    final more = IconButton(
      key: const Key('approved-chat-more'),
      tooltip: 'Chat options',
      onPressed: onMore,
      constraints: BoxConstraints.tightFor(
        width: compact ? 36 : 48,
        height: compact ? 36 : 48,
      ),
      padding: EdgeInsets.all(compact ? 7 : 8),
      icon: _asset(
        'chat-more.png',
        width: compact ? 11 : 14,
        height: compact ? 22 : 27,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = _usesAccessibilityReflow(context);
        final name = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contactName,
              style: _text(
                context,
                size: compact ? 11 : 14,
                weight: FontWeight.w900,
              ),
            ),
            Text(
              prototypeStatus ? 'Active now' : 'Conversation',
              style: _text(
                context,
                size: compact ? 8 : 10,
                weight: FontWeight.w500,
                color: _muted,
              ),
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  back,
                  avatar,
                  SizedBox(width: compact ? 4 : 7),
                  Expanded(child: name),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(width: compact ? 36 : 42),
                  Flexible(child: badge),
                  const Spacer(),
                  call,
                  more,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            back,
            avatar,
            SizedBox(width: compact ? 3 : 7),
            Expanded(
              child: Wrap(
                spacing: compact ? 2 : 6,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [name, badge],
              ),
            ),
            call,
            more,
          ],
        );
      },
    );
  }
}

class _ActiveDealsPanel extends StatelessWidget {
  const _ActiveDealsPanel({
    this.offer,
    required this.viewerIsSeller,
    required this.meetingConfirmed,
    required this.offerRevisionPending,
    required this.secondDealAdded,
    required this.onOpenDeal,
    required this.onLongPressDeal,
    required this.onAddDeal,
  });

  final LocalOfferRecord? offer;
  final bool viewerIsSeller;
  final bool meetingConfirmed;
  final bool offerRevisionPending;
  final bool secondDealAdded;
  final VoidCallback onOpenDeal;
  final VoidCallback onLongPressDeal;
  final VoidCallback onAddDeal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth < 330 ? 6.0 : 9.0;
        final baseHeight = constraints.maxWidth < 330 ? 118.0 : 134.0;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final height = baseHeight + ((textScale - 1).clamp(0, 1) * 68);
        final firstDeal = _ActiveDealCard(
          key: const Key('active-deal-ipad'),
          viewerIsSeller: viewerIsSeller,
          title: offer?.requestTitle ?? 'iPad Air 5th Gen 64GB',
          price: offer?.price ?? r'$650',
          status: offerRevisionPending
              ? 'Offer updated'
              : meetingConfirmed
              ? 'Meeting set'
              : 'Offer accepted',
          time: meetingConfirmed
              ? (offer == null
                    ? 'Today 5:00 PM'
                    : '${offer!.meetingDate} ${offer!.meetingTime}')
              : 'Review details',
          asset: 'chat-ipad.png',
          onTap: onOpenDeal,
          onLongPress: onLongPressDeal,
        );
        if (secondDealAdded) {
          final dealWidth = (constraints.maxWidth * .43).clamp(132.0, 168.0);
          final addWidth = constraints.maxWidth < 350 ? 72.0 : 82.0;
          return SizedBox(
            height: height,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(width: dealWidth, child: firstDeal),
                SizedBox(width: spacing),
                SizedBox(
                  width: dealWidth,
                  child: _ActiveDealCard(
                    key: const Key('active-deal-second'),
                    viewerIsSeller: viewerIsSeller,
                    title: 'Samsung 65” QLED 4K TV',
                    price: '\$480',
                    status: 'Offer accepted',
                    time: 'Tomorrow 2:00 PM',
                    asset: 'chat-tv.png',
                    onTap: onOpenDeal,
                    onLongPress: onLongPressDeal,
                  ),
                ),
                SizedBox(width: spacing),
                SizedBox(
                  width: addWidth,
                  child: _NewDealCard(onTap: onAddDeal, compact: true),
                ),
              ],
            ),
          );
        }
        return SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: firstDeal),
              SizedBox(width: spacing),
              Expanded(child: _NewDealCard(onTap: onAddDeal)),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveDealCard extends StatelessWidget {
  const _ActiveDealCard({
    required this.viewerIsSeller,
    required this.title,
    required this.price,
    required this.status,
    required this.time,
    required this.onTap,
    required this.onLongPress,
    this.asset,
    super.key,
  });

  final bool viewerIsSeller;
  final String title;
  final String price;
  final String status;
  final String time;
  final String? asset;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: HocalistPalette.surface(context, Colors.white),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            onLongPress: viewerIsSeller ? onLongPress : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 118 : 134),
              padding: EdgeInsets.all(compact ? 7 : 9),
              decoration: BoxDecoration(
                border: Border.all(
                  color: HocalistPalette.border(context, _blue),
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: compact ? 42 : 50,
                        height: compact ? 48 : 58,
                        padding: EdgeInsets.all(compact ? 3 : 4),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            const Color(0xfff8f8ff),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: asset == null
                            ? BuyerGlyphIcon(
                                icon: Icons.tv_outlined,
                                slotSize: compact ? 22 : 28,
                                glyphSize: compact ? 22 : 28,
                                color: HocalistPalette.text(context, _blue),
                              )
                            : _asset(
                                asset!,
                                width: compact ? 36 : 42,
                                height: compact ? 42 : 50,
                                fit: BoxFit.contain,
                              ),
                      ),
                      SizedBox(width: compact ? 6 : 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _text(
                                context,
                                size: compact ? 9 : 11,
                                weight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              price,
                              style: _text(
                                context,
                                size: compact ? 13 : 16,
                                weight: FontWeight.w900,
                                color: _blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: HocalistPalette.surface(
                        context,
                        status == 'Offer updated'
                            ? const Color(0xfffff4df)
                            : _lavender,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        size: compact ? 7 : 8,
                        weight: FontWeight.w700,
                        color: status == 'Offer updated'
                            ? const Color(0xff9b5b00)
                            : _blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      BuyerGlyphIcon(
                        icon: Icons.event_outlined,
                        slotSize: compact ? 11 : 13,
                        glyphSize: compact ? 11 : 13,
                        color: HocalistPalette.text(context, _blue),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(context, size: compact ? 7 : 8.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewDealCard extends StatelessWidget {
  const _NewDealCard({this.onTap, this.compact = false});

  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistPalette.surface(context, Colors.white),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: const Key('active-deal-new'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 134),
          decoration: BoxDecoration(
            border: Border.all(
              color: HocalistPalette.border(context, _line),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BuyerAssetIcon(
                asset: '$_assetRoot/chat-plus.png',
                slotSize: compact ? 34 : 48,
              ),
              const SizedBox(height: 10),
              Text(
                compact ? 'New Deal' : 'More deals will appear here',
                textAlign: TextAlign.center,
                style: _text(context, size: 9, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentChatDeal extends StatelessWidget {
  const _CurrentChatDeal({
    required this.deal,
    required this.count,
    required this.onChoose,
    required this.onExplore,
    this.onLongPress,
  });

  final ApprovedDealView deal;
  final int count;
  final VoidCallback onChoose;
  final VoidCallback onExplore;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: HocalistPalette.border(context, _line));
    final actionColor = HocalistPalette.text(context, _blue);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextButton(
              key: ValueKey('deal-details-${deal.id}'),
              onPressed: onExplore,
              onLongPress: onLongPress,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 58),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                side: border,
                backgroundColor: HocalistPalette.surface(context, const Color(0xfff8f8fd)),
                foregroundColor: actionColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                children: [
                  const Icon(Icons.sell_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      key: const Key('chat-selected-deal'),
                      label: 'Selected deal: ${deal.title}',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deal.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: _text(context, size: 12, weight: FontWeight.w800)),
                          Text('${deal.priceLabel} · ${deal.statusLabel}',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: _text(context, size: 11, color: _muted)),
                          if (deal.unreadCount > 0)
                            Text('${deal.unreadCount} unread',
                              style: _text(context, size: 11, color: _blue)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        'Explore deal',
                        textAlign: TextAlign.end,
                        style: _text(context, size: 11, weight: FontWeight.w800, color: _blue),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            ),
          ),
          ...[
            const SizedBox(width: 7),
            Tooltip(
              message: count == 1 ? '1 active deal' : '$count active deals',
              child: TextButton(
                key: const Key('chat-deal-count'),
                onPressed: onChoose,
                style: TextButton.styleFrom(
                  minimumSize: const Size(52, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: HocalistPalette.surface(context, _lavender),
                  foregroundColor: actionColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  side: border,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$count'),
                    if (count > 1) const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RealActiveDealsPanel extends StatelessWidget {
  const _RealActiveDealsPanel({
    required this.deals,
    this.past = false,
    this.selectedDealId,
    this.entryOfferId,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpenDeal,
    required this.onViewDeal,
  });

  final bool past;
  final List<ApprovedDealView>? deals;
  final String? selectedDealId;
  final String? entryOfferId;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onOpenDeal;
  final ValueChanged<String> onViewDeal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth < 330 ? 6.0 : 9.0;
        final baseHeight = constraints.maxWidth < 330 ? 156.0 : 172.0;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final height = baseHeight + ((textScale - 1).clamp(0, 1) * 104);
        final rows = deals;
        final entry = entryOfferId == null ? null : rows?.where(
          (deal) => deal.offerId == entryOfferId || deal.id == entryOfferId,
        ).firstOrNull;
        final list = entry == null ? rows : [entry, ...rows!.where((row) => row.id != entry.id)];
        final showState = list == null || (list.isEmpty && error != null);
        if (showState) {
          return SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _RealDealStateCard(
                    key: ValueKey(
                      loading
                          ? 'active-deals-loading'
                          : error != null
                          ? 'active-deals-error'
                          : 'active-deals-unavailable',
                    ),
                    loading: loading,
                    message:
                        error ??
                        (past ? 'Your past deals could not be loaded. Try again.' : 'Your deals could not be loaded. Try again.'),
                    onRetry: onRefresh,
                  ),
                ),
                if (!past) ...[
                  SizedBox(width: spacing),
                  const Expanded(child: _NewDealCard()),
                ],
              ],
            ),
          );
        }
        if (list.isEmpty) {
          return past ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No past deals yet.', style: _text(context, size: 13))) : SizedBox(height: height, child: const _NewDealCard());
        }
        if (list.length == 1) {
          final deal = list.first;
          return SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _RealDealCard(
                    key: ValueKey('active-deal-${deal.id}'),
                    emphasizeExplore: entry == deal && (selectedDealId == deal.offerId || selectedDealId == deal.id),
                    deal: deal,
                    selected:
                        selectedDealId == null ||
                        deal.id == selectedDealId ||
                        deal.offerId == selectedDealId,
                    onTap: () => onOpenDeal(deal.id),
                    onViewDetails: () => onViewDeal(deal.id),
                  ),
                ),
                if (!past) ...[
                  SizedBox(width: spacing),
                  const Expanded(child: _NewDealCard()),
                ],
              ],
            ),
          );
        }
        final dealWidth = (constraints.maxWidth * .43).clamp(132.0, 168.0);
        final addWidth = constraints.maxWidth < 350 ? 72.0 : 82.0;
        return SizedBox(
          height: height,
          child: ListView(
            key: const PageStorageKey('chat-deal-cards'),
            scrollDirection: Axis.horizontal,
            children: [
              for (final deal in list) ...[
                SizedBox(
                  width: dealWidth,
                  child: _RealDealCard(
                    key: ValueKey('active-deal-${deal.id}'),
                    emphasizeExplore: entry == deal && (selectedDealId == deal.offerId || selectedDealId == deal.id),
                    deal: deal,
                    selected:
                        deal.id == selectedDealId ||
                        deal.offerId == selectedDealId ||
                        (selectedDealId == null && deal == list.first),
                    onTap: () => onOpenDeal(deal.id),
                    onViewDetails: () => onViewDeal(deal.id),
                  ),
                ),
                SizedBox(width: spacing),
              ],
              if (!past) SizedBox(
                width: addWidth,
                child: const _NewDealCard(compact: true),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RealDealStateCard extends StatelessWidget {
  const _RealDealStateCard({
    required this.message,
    required this.loading,
    this.onRetry,
    super.key,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 118 : 134),
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        border: Border.all(color: HocalistPalette.border(context, _line)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const Flexible(
              child: BuyerProgressStrip(label: 'Loading active deals…'),
            )
          else ...[
            BuyerGlyphIcon(
              icon: Icons.hourglass_empty_rounded,
              slotSize: compact ? 22 : 28,
              glyphSize: compact ? 22 : 28,
              color: HocalistPalette.text(context, _blue),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _text(
                  context,
                  size: compact ? 8.5 : 9.5,
                  color: _muted,
                  height: 1.3,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                key: const Key('active-deals-retry'),
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: HocalistPalette.text(context, _blue),
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Approved deal card bound to authoritative meeting data.
///
/// The product artwork is intentionally the approved fallback glyph: the
/// meeting/offer projection carries no media reference, and a prototype image
/// must never stand in for real inventory.
class _RealDealCard extends StatelessWidget {
  const _RealDealCard({
    required this.deal,
    required this.onTap,
    required this.onViewDetails,
    this.selected = false,
    this.emphasizeExplore = false,
    super.key,
  });

  final ApprovedDealView deal;
  final bool selected;
  final bool emphasizeExplore;
  final VoidCallback onTap;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    final (statusBackground, statusForeground) = switch (deal.statusTone) {
      BuyerNoticeTone.success => (
        const Color(0xffecf8ee),
        const Color(0xff0f7b34),
      ),
      BuyerNoticeTone.warning => (
        const Color(0xfffff6e5),
        const Color(0xff9b5b00),
      ),
      BuyerNoticeTone.error => (
        const Color(0xffffeef0),
        const Color(0xffc62828),
      ),
      BuyerNoticeTone.neutral => (_lavender, _muted),
      BuyerNoticeTone.brand => (_lavender, _blue),
    };
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: HocalistPalette.surface(context, Colors.white),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 118 : 134),
              padding: EdgeInsets.all(compact ? 7 : 9),
              decoration: BoxDecoration(
                border: Border.all(
                  color: HocalistPalette.border(
                    context,
                    selected ? _blue : const Color(0xffd8d9e5),
                  ),
                  width: selected ? 2.2 : 1.2,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: compact ? 42 : 50,
                        height: compact ? 48 : 58,
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            const Color(0xfff8f8ff),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: BuyerGlyphIcon(
                            icon: Icons.devices_other_outlined,
                            slotSize: compact ? 22 : 28,
                            glyphSize: compact ? 22 : 28,
                            color: HocalistPalette.text(context, _blue),
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 6 : 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(
                                deal.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _text(context, size: compact ? 9 : 11,
                                  weight: FontWeight.w900),
                              )),
                              if (deal.unreadCount > 0) ...[
                                const SizedBox(width: 4),
                                Tooltip(message: '${deal.unreadCount} unread messages',
                                  child: Semantics(
                                    label: '${deal.unreadCount} unread messages',
                                    child: Container(
                                      key: ValueKey('deal-unread-${deal.id}'),
                                      width: 10, height: 10,
                                      decoration: const BoxDecoration(
                                        color: Color(0xffd32f2f), shape: BoxShape.circle),
                                    ),
                                  ),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              deal.priceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(
                                context,
                                size: compact ? 13 : 16,
                                weight: FontWeight.w900,
                                color: _blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 10, thickness: 1,
                    color: HocalistPalette.border(context, const Color(0xffd8d9e5)).withValues(alpha: .45)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: HocalistPalette.surface(context, statusBackground),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      deal.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        size: compact ? 7 : 8,
                        weight: FontWeight.w700,
                        color: statusForeground,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  if (!deal.completed && deal.scheduleLabel != null)
                    Text(deal.scheduleLabel!, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(context, size: compact ? 7 : 8.5)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: ValueKey('deal-details-${deal.id}'),
                      onPressed: onViewDetails,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: emphasizeExplore ? 6 : 0),
                        minimumSize: const Size(0, 32),
                        backgroundColor: emphasizeExplore ? HocalistPalette.surface(context, _lavender) : Colors.transparent,
                        side: BorderSide.none,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: HocalistPalette.text(context, _blue),
                        textStyle: _text(
                          context,
                          size: compact ? 10 : 11,
                          weight: FontWeight.w800,
                        ),
                      ),
                      child: const Row(children: [
                        Expanded(child: Text('Explore deal', maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 14),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Approved deal-management sheet bound to authoritative deals.
///
/// The approved frame, Active/Previous grouping and row design are preserved.
/// Active rows come from the participant meeting read; Previous rows come from
/// a conversation-scoped history read that is not available yet, so the group
/// stays visible with a designed unavailable state instead of invented rows.
class _ApprovedRealDealsSheet extends StatelessWidget {
  const _ApprovedRealDealsSheet({
    required this.pastSelected,
    required this.onChooseGroup,
    required this.deals,
    required this.loading,
    required this.error,
    required this.truncated,
    required this.previousDeals,
    this.selectOnly = false,
    required this.onRefresh,
    required this.onProposeMeeting,
    required this.onClose,
    required this.onOpenDeal,
  });

  final List<ApprovedDealView>? deals;
  final bool? pastSelected;
  final ValueChanged<bool?> onChooseGroup;
  final bool loading;
  final String? error;
  final bool truncated;
  final List<ApprovedDealView>? previousDeals;
  final bool selectOnly;
  final VoidCallback? onRefresh;
  final VoidCallback onProposeMeeting;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenDeal;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    final list = deals;
    final previous = previousDeals;
    return _ApprovedChatSheetFrame(
      key: const Key('approved-conversation-deals-sheet'),
      title: 'Deals in this conversation',
      subtitle:
          'Choose an active deal or review an earlier deal without leaving this chat.',
      icon: Icons.receipt_long_outlined,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!selectOnly) ...[
          Text('Show in chat', style: _text(context, size: 12,
            weight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            HocalistFilterChip(key: const Key('chat-all-deals'),
              role: HocalistControlRole.buyer, label: 'All',
              selected: pastSelected == null, onSelected: (_) => onChooseGroup(null)),
            HocalistFilterChip(key: const Key('chat-current-deals'),
              role: HocalistControlRole.buyer, label: 'Current',
              selected: pastSelected == false, onSelected: (_) => onChooseGroup(false)),
            HocalistFilterChip(key: const Key('chat-past-deals'),
              role: HocalistControlRole.buyer, label: 'Past',
              selected: pastSelected == true, onSelected: (_) => onChooseGroup(true)),
          ]),
          const SizedBox(height: 16),
          ],
          if (list == null) ...[
            if (loading)
              const BuyerProgressStrip(label: 'Loading active deals…')
            else ...[
              BuyerStateNotice(
                key: const ValueKey('approved-real-deals-unavailable'),
                icon: Icons.hourglass_empty_rounded,
                tone: BuyerNoticeTone.warning,
                title: 'Active deals are unavailable',
                body:
                    error ??
                    'Your deals could not be loaded. Please try again.',
              ),
              if (onRefresh != null) ...[
                SizedBox(height: metrics.geometry(8)),
                BuyerSecondaryButton(
                  key: const ValueKey('approved-real-deals-retry'),
                  compact: true,
                  label: 'Retry',
                  onPressed: onRefresh,
                ),
              ],
            ],
          ] else if (list.isEmpty)
            Column(
              key: const ValueKey('approved-real-deals-empty'),
              children: [
                BuyerGlyphIcon(
                  icon: Icons.receipt_long_outlined,
                  slotSize: BuyerIconTokens.feature,
                  color: HocalistPalette.text(context, _blue),
                ),
                SizedBox(height: metrics.geometry(8)),
                Text(
                  'No active deals in this conversation yet.',
                  textAlign: TextAlign.center,
                  style: _text(
                    context,
                    size: 12.5,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                SizedBox(height: metrics.geometry(4)),
                Text(
                  'Deals appear here when an offer is accepted and a meeting is arranged.',
                  textAlign: TextAlign.center,
                  style: _text(
                    context,
                    size: 10.5,
                    color: _muted,
                    height: 1.35,
                  ),
                ),
                if (!loading && error == null && !truncated) ...[
                  SizedBox(height: metrics.geometry(12)),
                  BuyerPrimaryButton(
                    key: const ValueKey('approved-real-deals-propose'),
                    label: previous != null && previous.isNotEmpty
                        ? 'View previous deal'
                        : 'Propose meeting',
                    onPressed: previous != null && previous.isNotEmpty
                        ? () => onOpenDeal(previous.first.id)
                        : onProposeMeeting,
                  ),
                ],
              ],
            )
          else
            _ConversationDealGroup(
              title: 'Active',
              count: list.length,
              children: [
                for (final deal in list)
                  _ConversationDealRow(
                    key: ValueKey('approved-real-deal-row-${deal.id}'),
                    icon: Icons.devices_other_outlined,
                    title: deal.title,
                    price: deal.priceLabel,
                    status: deal.statusLabel,
                    onTap: () => onOpenDeal(deal.id),
                  ),
              ],
            ),
          if (list != null && error != null) ...[
            SizedBox(height: metrics.geometry(10)),
            BuyerStateNotice(
              key: const ValueKey('approved-real-deals-refresh-error'),
              icon: Icons.cloud_off_rounded,
              tone: BuyerNoticeTone.error,
              title: 'Active deals may be out of date',
              body: error,
              actionLabel: onRefresh == null ? null : 'Try again',
              onAction: onRefresh,
            ),
          ],
          if (truncated && list != null && list.isNotEmpty) ...[
            SizedBox(height: metrics.geometry(8)),
            Text(
              'More deals may be available. Refresh to load them.',
              key: const ValueKey('approved-real-deals-truncated'),
              textAlign: TextAlign.center,
              style: _text(context, size: 10, color: _muted, height: 1.35),
            ),
          ],
          SizedBox(height: metrics.geometry(12)),
          _ConversationDealGroup(
            title: 'Previous',
            count: previous?.length,
            children: previous == null
                ? [
                    const _ConversationDealStateRow(
                      key: ValueKey('approved-real-previous-unavailable'),
                      icon: Icons.history_rounded,
                      title: 'Previous deals are not available yet',
                      body:
                          'Refresh to load your completed and cancelled deals.',
                    ),
                  ]
                : previous.isEmpty
                ? [
                    const _ConversationDealStateRow(
                      key: ValueKey('approved-real-previous-empty'),
                      icon: Icons.history_rounded,
                      title: 'No previous deals in this conversation yet.',
                    ),
                  ]
                : [
                    for (final deal in previous)
                      _ConversationDealRow(
                        key: ValueKey('approved-real-previous-row-${deal.id}'),
                        icon: Icons.devices_other_outlined,
                        title: deal.title,
                        price: deal.priceLabel,
                        status: deal.statusLabel,
                        onTap: () => onOpenDeal(deal.id),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// Designed unavailable/empty row inside one approved deal group.
class _ConversationDealStateRow extends StatelessWidget {
  const _ConversationDealStateRow({
    required this.icon,
    required this.title,
    this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Padding(
      padding: metrics.geometryInsets(const EdgeInsets.all(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerGlyphIcon(
            icon: icon,
            slotSize: metrics.artSize(20),
            glyphSize: metrics.artSize(20),
            color: HocalistPalette.text(context, _blue),
          ),
          SizedBox(width: metrics.geometry(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _text(
                    context,
                    size: 11.5,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                if (body != null) ...[
                  SizedBox(height: metrics.geometry(3)),
                  Text(
                    body!,
                    style: _text(
                      context,
                      size: 10,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Approved deal-details sheet bound to authoritative meeting data.
class ApprovedRealDealDetailsSheet extends StatelessWidget {
  const ApprovedRealDealDetailsSheet({
    this.hideUnavailableAction = false,
    this.offerMessage,
    required this.deal,
    required this.viewerIsSeller,
    required this.onClose,
    required this.onOpenMeeting,
    this.onMeetingOptions,
    this.onViewOriginalRequest,
  });

  final bool hideUnavailableAction;
  final String? offerMessage;
  final ApprovedDealView deal;
  final bool viewerIsSeller;
  final VoidCallback onClose;
  final VoidCallback? onOpenMeeting;
  final VoidCallback? onMeetingOptions;
  final VoidCallback? onViewOriginalRequest;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final (statusBackground, statusForeground) = switch (deal.statusTone) {
      BuyerNoticeTone.success => (
        const Color(0xffecf8ee),
        const Color(0xff0f7b34),
      ),
      BuyerNoticeTone.warning => (
        const Color(0xfffff6e5),
        const Color(0xff9b5b00),
      ),
      BuyerNoticeTone.error => (
        const Color(0xffffeef0),
        const Color(0xffc62828),
      ),
      BuyerNoticeTone.neutral => (_lavender, _muted),
      BuyerNoticeTone.brand => (_lavender, _blue),
    };
    return _ApprovedChatSheetFrame(
      key: const ValueKey('approved-active-deal-sheet'),
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: metrics.artSize(76),
                height: metrics.artSize(88),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    const Color(0xfff8f8ff),
                  ),
                  borderRadius: BorderRadius.circular(metrics.geometry(14)),
                  border: Border.all(
                    color: HocalistPalette.border(context, _line),
                  ),
                ),
                child: Center(
                  child: BuyerGlyphIcon(
                    icon: Icons.devices_other_outlined,
                    slotSize: metrics.artSize(34),
                    glyphSize: metrics.artSize(34),
                    color: HocalistPalette.text(context, _blue),
                  ),
                ),
              ),
              SizedBox(width: metrics.geometry(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deal.title,
                      style: _text(
                        context,
                        size: 17,
                        weight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(5)),
                    Text(
                      deal.priceLabel,
                      style: _text(
                        context,
                        size: 24,
                        weight: FontWeight.w900,
                        color: _blue,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(6)),
                    Wrap(
                      spacing: metrics.geometry(6),
                      runSpacing: metrics.geometry(6),
                      children: [
                        Container(
                          padding: metrics.geometryInsets(
                            const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                          ),
                          decoration: BoxDecoration(
                            color: HocalistPalette.surface(
                              context,
                              statusBackground,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            deal.statusLabel,
                            style: _text(
                              context,
                              size: 9.5,
                              weight: FontWeight.w800,
                              color: statusForeground,
                            ),
                          ),
                        ),
                        if (deal.purchaseSelected) ...[
                          Container(
                            padding: metrics.geometryInsets(
                              const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                            ),
                            decoration: BoxDecoration(
                              color: HocalistPalette.surface(
                                context,
                                _lavender,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'Final purchase selection',
                              key: const ValueKey(
                                'approved-real-deal-purchase-selected',
                              ),
                              style: _text(
                                context,
                                size: 9.5,
                                weight: FontWeight.w800,
                                color: _blue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.geometry(18)),
          Container(
            padding: metrics.geometryInsets(const EdgeInsets.all(12)),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
              borderRadius: BorderRadius.circular(metrics.geometry(14)),
              border: Border.all(color: HocalistPalette.border(context, _line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DealChangeRow(
                  label: 'Meeting',
                  value: deal.scheduleLabel ?? 'Not scheduled yet',
                ),
                _DealChangeRow(
                  label: 'Time zone',
                  value: deal.zoneLabel ?? 'Not available',
                ),
                _DealChangeRow(
                  label: 'Place',
                  value: deal.placeLabel ?? 'Not specified',
                ),
                if (deal.pendingLabel != null)
                  _DealChangeRow(
                    label: 'Pending change',
                    value: deal.pendingLabel!,
                  ),
                const _DealChangeRow(label: 'Item payment', value: 'Offline'),
                if (offerMessage?.isNotEmpty == true)
                  _DealChangeRow(label: 'Offer message', value: offerMessage!),
              ],
            ),
          ),
          SizedBox(height: metrics.geometry(16)),
          if (onOpenMeeting != null || !hideUnavailableAction) BuyerPrimaryButton(
            key: const ValueKey('approved-real-deal-open-meeting'),
            label:
                deal.actionLabel ??
                (deal.meetingId == null
                    ? 'Arrange meeting'
                    : viewerIsSeller
                    ? 'Review meeting details'
                    : 'Open meeting details'),
            onPressed: onOpenMeeting,
            onLongPress: onMeetingOptions,
          ),
          if (onOpenMeeting == null && !hideUnavailableAction) ...[
            SizedBox(height: metrics.geometry(6)),
            Text(
              'Meeting details are currently unavailable.',
              key: const ValueKey('approved-real-deal-meeting-unavailable'),
              textAlign: TextAlign.center,
              style: _text(context, size: 10.5, color: _muted),
            ),
          ],
          if (onViewOriginalRequest != null) ...[
            SizedBox(height: metrics.geometry(8)),
            BuyerSecondaryButton(
              key: const ValueKey('approved-real-deal-original-request'),
              label: 'View original request',
              onPressed: onViewOriginalRequest,
            ),
          ],
          SizedBox(height: metrics.geometry(12)),
          Text(
            deal.completed
                ? 'This purchase is complete. Item payment was handled offline.'
                : 'Inspect the item before paying the seller offline.',
            style: _text(context, size: 10.5, color: _muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ApprovedConversationDealsSheet extends StatelessWidget {
  const _ApprovedConversationDealsSheet({
    this.offer,
    required this.secondDealAdded,
    required this.onClose,
    required this.onOpenActiveDeal,
  });

  final LocalOfferRecord? offer;
  final bool secondDealAdded;
  final VoidCallback onClose;
  final VoidCallback onOpenActiveDeal;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return _ApprovedChatSheetFrame(
      key: const Key('approved-conversation-deals-sheet'),
      title: 'Deals in this conversation',
      subtitle:
          'Choose an active deal or review an earlier deal without leaving this chat.',
      icon: Icons.receipt_long_outlined,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConversationDealGroup(
            title: 'Active',
            count: secondDealAdded ? 2 : 1,
            children: [
              _ConversationDealRow(
                asset: 'chat-ipad.png',
                title: offer?.requestTitle ?? 'iPad Air 5th Gen 64GB',
                price: offer?.price ?? r'$650',
                status: 'Meeting set',
                onTap: onOpenActiveDeal,
              ),
              if (secondDealAdded)
                _ConversationDealRow(
                  asset: 'chat-tv.png',
                  title: 'Samsung 65” QLED 4K TV',
                  price: r'$480',
                  status: 'Offer accepted',
                  onTap: onOpenActiveDeal,
                ),
            ],
          ),
          SizedBox(height: metrics.geometry(12)),
          const _ConversationDealGroup(
            title: 'Previous',
            count: 2,
            children: [
              _ConversationDealRow(
                icon: Icons.laptop_mac_outlined,
                title: 'MacBook Air M2',
                price: r'$720',
                status: 'Completed',
              ),
              _ConversationDealRow(
                icon: Icons.sports_esports_outlined,
                title: 'Game console bundle',
                price: r'$310',
                status: 'Cancelled',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationDealGroup extends StatelessWidget {
  const _ConversationDealGroup({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;

  /// Null hides the count chip: the count is unknown rather than zero.
  final int? count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: _text(
                context,
                size: 12.5,
                weight: FontWeight.w900,
                color: _navy,
              ),
            ),
            if (count != null) ...[
              SizedBox(width: metrics.geometry(6)),
              Container(
                padding: metrics.geometryInsets(
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                ),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(context, _lavender),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: _text(
                    context,
                    size: 9.5,
                    weight: FontWeight.w800,
                    color: _blue,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: metrics.geometry(7)),
        Container(
          decoration: BoxDecoration(
            color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
            border: Border.all(color: HocalistPalette.border(context, _line)),
            borderRadius: BorderRadius.circular(metrics.geometry(14)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  const Divider(height: 1, indent: 64, color: _line),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ConversationDealRow extends StatelessWidget {
  const _ConversationDealRow({
    required this.title,
    required this.price,
    required this.status,
    this.asset,
    this.icon,
    this.onTap,
    super.key,
  }) : assert(asset != null || icon != null);

  final String title;
  final String price;
  final String status;
  final String? asset;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    final statusColor = status == 'Cancelled'
        ? const Color(0xffc62828)
        : status == 'Completed'
        ? const Color(0xff14883f)
        : _blue;
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Semantics(
          button: onTap != null,
          label: '$title, $price, $status',
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: metrics.geometryInsets(const EdgeInsets.all(10)),
              child: Row(
                children: [
                  Container(
                    width: metrics.artSize(44),
                    height: metrics.artSize(48),
                    padding: metrics.geometryInsets(const EdgeInsets.all(4)),
                    decoration: BoxDecoration(
                      color: HocalistPalette.surface(context, _lavender),
                      borderRadius: BorderRadius.circular(metrics.geometry(9)),
                    ),
                    child: asset != null
                        ? _asset(asset!, fit: BoxFit.contain)
                        : BuyerGlyphIcon(
                            icon: icon!,
                            slotSize: metrics.artSize(25),
                            glyphSize: metrics.artSize(25),
                            color: HocalistPalette.text(context, _blue),
                          ),
                  ),
                  SizedBox(width: metrics.geometry(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _text(
                            context,
                            size: 12,
                            weight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        SizedBox(height: metrics.geometry(3)),
                        Text(
                          price,
                          style: _text(
                            context,
                            size: 11,
                            weight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: metrics.geometry(8)),
                  Text(
                    status,
                    style: _text(
                      context,
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  if (onTap != null) ...[
                    SizedBox(width: metrics.geometry(3)),
                    BuyerGlyphIcon(
                      icon: Icons.chevron_right_rounded,
                      slotSize: 20,
                      glyphSize: 20,
                      color: HocalistPalette.text(context, _blue),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedDealDetailsSheet extends StatefulWidget {
  const _ApprovedDealDetailsSheet({
    this.offer,
    required this.viewerIsSeller,
    required this.meetingConfirmed,
    required this.offerRevisionPending,
    required this.onClose,
    required this.onAccept,
    required this.onRequestChange,
  });

  final LocalOfferRecord? offer;
  final bool viewerIsSeller;
  final bool meetingConfirmed;
  final bool offerRevisionPending;
  final VoidCallback onClose;
  final VoidCallback onAccept;
  final VoidCallback onRequestChange;

  @override
  State<_ApprovedDealDetailsSheet> createState() =>
      _ApprovedDealDetailsSheetState();
}

class _ApprovedDealDetailsSheetState extends State<_ApprovedDealDetailsSheet> {
  bool _showMeetingDetails = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return _ApprovedChatSheetFrame(
      key: const ValueKey('approved-active-deal-sheet'),
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: metrics.artSize(76),
                height: metrics.artSize(88),
                padding: metrics.geometryInsets(const EdgeInsets.all(6)),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    const Color(0xfff8f8ff),
                  ),
                  borderRadius: BorderRadius.circular(metrics.geometry(14)),
                  border: Border.all(
                    color: HocalistPalette.border(context, _line),
                  ),
                ),
                child: Image.asset(
                  '$_assetRoot/chat-ipad.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              SizedBox(width: metrics.geometry(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.offer?.requestTitle ?? 'iPad Air 5th Gen 64GB',
                      style: _text(
                        context,
                        size: 17,
                        weight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(5)),
                    Text(
                      widget.offer?.price ?? r'$650',
                      style: _text(
                        context,
                        size: 24,
                        weight: FontWeight.w900,
                        color: _blue,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(6)),
                    Row(
                      children: [
                        BuyerAssetIcon(
                          asset: '$_assetRoot/chat-deal-shield.png',
                          slotSize: metrics.artSize(19),
                        ),
                        SizedBox(width: metrics.geometry(5)),
                        Expanded(
                          child: Text(
                            'Deal protection by Hocalist',
                            style: _text(
                              context,
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.geometry(18)),
          Container(
            padding: metrics.geometryInsets(const EdgeInsets.all(12)),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
              borderRadius: BorderRadius.circular(metrics.geometry(14)),
              border: Border.all(color: HocalistPalette.border(context, _line)),
            ),
            child: widget.viewerIsSeller
                ? const _SellerDealFacts()
                : const _BuyerDealFacts(),
          ),
          if (widget.viewerIsSeller) ...[
            SizedBox(height: metrics.geometry(14)),
            const _SellerTransactionNotice(),
          ],
          if (widget.offerRevisionPending) ...[
            SizedBox(height: metrics.geometry(12)),
            const _OfferUpdatedNotice(),
          ],
          if (_showMeetingDetails) ...[
            SizedBox(height: metrics.geometry(12)),
            Container(
              key: const ValueKey('approved-inline-meeting-review'),
              padding: metrics.geometryInsets(const EdgeInsets.all(13)),
              decoration: BoxDecoration(
                color: HocalistPalette.surface(context, _lavender),
                borderRadius: BorderRadius.circular(metrics.geometry(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meeting details',
                    style: _text(
                      context,
                      size: 13,
                      weight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                  SizedBox(height: metrics.geometry(8)),
                  _DealChangeRow(
                    label: 'Seller',
                    value: widget.offer?.sellerName ?? 'Northside Tech',
                  ),
                  _DealChangeRow(
                    label: 'Location',
                    value: widget.offer?.location ?? 'Yonkers, NY',
                  ),
                  _DealChangeRow(
                    label: 'Time',
                    value: widget.offer == null
                        ? 'Today • 5:00 PM'
                        : '${widget.offer!.meetingDate} • ${widget.offer!.meetingTime}',
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: metrics.geometry(18)),
          if (widget.viewerIsSeller ||
              widget.offerRevisionPending ||
              !widget.meetingConfirmed)
            SizedBox(
              height: metrics.geometry(50),
              child: FilledButton(
                key: widget.viewerIsSeller
                    ? const Key('seller-modify-offer')
                    : const Key('buyer-accept-updated-offer'),
                onPressed: widget.onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: HocalistPalette.surface(context, _blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(metrics.geometry(14)),
                  ),
                ),
                child: Text(
                  widget.viewerIsSeller
                      ? 'Modify Offer'
                      : widget.offerRevisionPending
                      ? 'Accept updated terms'
                      : 'Accept To Meet',
                  style: _text(
                    context,
                    size: 13,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: metrics.geometry(50),
              child: OutlinedButton(
                key: const ValueKey('approved-review-meeting-inline'),
                onPressed: () =>
                    setState(() => _showMeetingDetails = !_showMeetingDetails),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HocalistPalette.text(context, _blue),
                  side: BorderSide(
                    color: HocalistPalette.border(context, _blue),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(metrics.geometry(14)),
                  ),
                ),
                child: Text(
                  _showMeetingDetails
                      ? 'Hide meeting details'
                      : 'Review meeting details',
                ),
              ),
            ),
          if (!widget.viewerIsSeller && widget.offerRevisionPending) ...[
            SizedBox(height: metrics.geometry(8)),
            TextButton(
              onPressed: widget.onRequestChange,
              child: const Text('Request different terms'),
            ),
          ],
          if (_showMeetingDetails) ...[
            SizedBox(height: metrics.geometry(12)),
            Text(
              'Inspect the item before paying the seller offline.',
              key: const ValueKey('deal-safety-caution'),
              style: _text(context, size: 10.5, color: _muted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedOfferEditorSheet extends StatelessWidget {
  const _ApprovedOfferEditorSheet({
    required this.priceController,
    required this.locationController,
    required this.timeController,
    required this.onClose,
    required this.onSave,
  });

  final TextEditingController priceController;
  final TextEditingController locationController;
  final TextEditingController timeController;
  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return _ApprovedChatSheetFrame(
      key: const ValueKey('approved-revise-offer-sheet'),
      title: 'Revise offer',
      subtitle: 'The buyer will see a clear summary of every change.',
      icon: Icons.edit_note_rounded,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedSheetField(
            key: const Key('seller-revised-offer-price'),
            controller: priceController,
            label: 'Updated price',
            asset: 'chat-price.png',
            prefixText: '\$',
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: metrics.geometry(12)),
          _ApprovedSheetField(
            controller: locationController,
            label: 'Pickup location',
            asset: 'chat-location.png',
          ),
          SizedBox(height: metrics.geometry(12)),
          _ApprovedSheetField(
            controller: timeController,
            label: 'Meeting time',
            asset: 'chat-time.png',
          ),
          SizedBox(height: metrics.geometry(18)),
          SellerPrimaryButton(
            key: const Key('seller-save-revised-offer'),
            label: 'Send updated offer',
            onPressed: onSave,
            fontSize: 14,
          ),
        ],
      ),
    );
  }
}

class _ApprovedChatSheetFrame extends StatelessWidget {
  const _ApprovedChatSheetFrame({
    required this.child,
    required this.onClose,
    this.title,
    this.subtitle,
    this.icon,
    this.iconColor = _blue,
    this.iconSurface = _lavender,
    super.key,
  });

  final Widget child;
  final VoidCallback onClose;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final Color iconSurface;

  @override
  Widget build(BuildContext context) {
    return BuyerModalSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: HocalistPalette.text(context, iconColor),
      iconSurface: iconSurface,
      closeKey: const ValueKey('approved-chat-sheet-close'),
      onClose: onClose,
      child: child,
    );
  }
}

class _ApprovedMenuAction extends StatelessWidget {
  const _ApprovedMenuAction({
    required this.title,
    required this.onTap,
    this.asset,
    this.icon,
    this.subtitle,
    this.foregroundColor = _navy,
  }) : assert(asset != null || icon != null);

  final String title;
  final VoidCallback? onTap;
  final String? asset;
  final IconData? icon;
  final String? subtitle;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    final iconSize = metrics.artSize(20);
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.geometry(6)),
      child: Material(
        color: HocalistPalette.surface(context, const Color(0xfffbfcff)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(13)),
          side: BorderSide(color: HocalistPalette.border(context, _line)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: metrics.geometry(48)),
            child: Padding(
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: metrics.geometry(28),
                    height: metrics.geometry(28),
                    child: Center(
                      child: asset != null
                          ? BuyerAssetIcon(
                              asset: '$_assetRoot/$asset',
                              slotSize: iconSize,
                            )
                          : BuyerGlyphIcon(
                              icon: icon!,
                              slotSize: iconSize,
                              glyphSize: iconSize,
                              color: HocalistPalette.text(
                                context,
                                foregroundColor,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: metrics.geometry(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: _text(
                            context,
                            size: 12,
                            weight: FontWeight.w700,
                            color: foregroundColor,
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: metrics.geometry(2)),
                          Text(
                            subtitle!,
                            style: _text(context, size: 9.5, color: _muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: metrics.geometry(8)),
                  BuyerGlyphIcon(
                    icon: Icons.chevron_right_rounded,
                    slotSize: metrics.geometry(20),
                    glyphSize: metrics.geometry(20),
                    color: HocalistPalette.text(
                      context,
                      foregroundColor == _navy ? _blue : foregroundColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedSearchConversationSheet extends StatefulWidget {
  const _ApprovedSearchConversationSheet({
    required this.onClose,
    required this.onMessage,
    this.messages,
    this.search,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onMessage;
  final List<String>? messages;

  /// Server-side paged search. Null keeps the loaded-message filter.
  final Future<PageSlice<ChatSearchHit>> Function(String query, String? cursor)?
  search;

  @override
  State<_ApprovedSearchConversationSheet> createState() =>
      _ApprovedSearchConversationSheetState();
}

class _ApprovedSearchConversationSheetState
    extends State<_ApprovedSearchConversationSheet> {
  final _controller = TextEditingController();
  String _query = '';
  bool _hasSearched = false;

  bool _serverSearching = false;
  String? _serverError;
  String? _serverCursor;
  List<ChatSearchHit> _serverResults = const [];
  String _serverQuery = '';

  static const _messages = [
    'Hi! The iPad is in perfect condition like we discussed.',
    'Looks good! I’m ready to move forward 👍',
    'Great! I’m at the Yonkers location. See you at 5:00 PM today.',
    'Sounds good. I’ll have the iPad charged and ready for you to check.',
    'Awesome, thanks! Talk to you soon.',
  ];

  List<String> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return (widget.messages ?? _messages)
        .where((message) => message.toLowerCase().contains(query))
        .toList();
  }

  bool get _usesServerSearch => widget.search != null;

  Future<void> _runServerSearch({required bool reset}) async {
    final search = widget.search;
    if (search == null || _serverSearching) return;
    final query = _query.trim();
    if (query.length < 2) {
      widget.onMessage('Enter at least 2 characters to search.');
      return;
    }
    setState(() {
      _serverSearching = true;
      _serverError = null;
      _hasSearched = true;
      if (reset) {
        _serverResults = const [];
        _serverCursor = null;
        _serverQuery = query;
      }
    });
    try {
      final page = await search(query, reset ? null : _serverCursor);
      if (!mounted) return;
      setState(() {
        _serverResults = reset
            ? page.items
            : [..._serverResults, ...page.items];
        _serverCursor = page.nextCursor;
        _serverSearching = false;
      });
    } catch (error) {
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _serverSearching = false;
        _serverError = error is ChatSafetyException
            ? error.message
            : 'Search is unavailable right now. Try again.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return _ApprovedChatSheetFrame(
      key: const ValueKey('approved-search-conversation-sheet'),
      title: 'Search conversation',
      subtitle: _usesServerSearch
          ? 'Search your messages on this conversation.'
          : widget.messages == null
          ? 'Find a message without losing your place in the deal.'
          : 'Search the messages currently loaded in this conversation.',
      icon: Icons.search_rounded,
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('approved-conversation-search-field'),
            controller: _controller,
            autofocus: true,
            onChanged: (value) => setState(() {
              _query = value;
              _hasSearched = false;
            }),
            decoration: buyerInputDecoration(
              context,
              hintText: 'Search messages',
              prefixIcon: Center(
                widthFactor: 1,
                child: BuyerGlyphIcon(
                  icon: Icons.search_rounded,
                  slotSize: BuyerIconTokens.control,
                  glyphSize: BuyerIconTokens.control,
                  color: HocalistPalette.text(context, _blue),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          BuyerPrimaryButton(
            label: 'Search messages',
            onPressed: () {
              FocusScope.of(context).unfocus();
              if (_query.trim().isEmpty) {
                widget.onMessage('Enter a word or phrase to search.');
                return;
              }
              if (_usesServerSearch) {
                unawaited(_runServerSearch(reset: true));
                return;
              }
              setState(() => _hasSearched = true);
            },
          ),
          if (_usesServerSearch) ...[
            if (_serverSearching) ...[
              const SizedBox(height: 14),
              const Center(
                key: Key('approvedConversationSearchLoading'),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: HocalistLoadingIndicator(strokeWidth: 2.4),
                ),
              ),
            ] else if (_serverError != null) ...[
              const SizedBox(height: 12),
              Text(
                _serverError!,
                key: const Key('approvedConversationSearchError'),
                textAlign: TextAlign.center,
                style: BuyerTypography.style(
                  context, metrics, BuyerTextRole.secondaryBody,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 6),
              BuyerTextAction(
                key: const Key('approvedConversationSearchRetry'),
                onPressed: () => unawaited(_runServerSearch(reset: true)),
                label: 'Try again',
              ),
            ] else if (_hasSearched &&
                _serverResults.isEmpty &&
                _serverQuery.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'No messages found',
                key: const Key('approvedConversationSearchEmpty'),
                style: BuyerTypography.style(context, metrics, BuyerTextRole.cardTitle, color: _muted),
              ),
            ] else ...[
              if (_serverResults.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${_serverResults.length} ${_serverResults.length == 1 ? 'message' : 'messages'} found',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: HocalistPalette.text(context, _blue),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final hit in _serverResults) ...[
                  _ServerSearchResultCard(hit: hit),
                  const SizedBox(height: 8),
                ],
              ],
              if (_serverCursor != null)
                BuyerTextAction(
                  key: const Key('approvedConversationSearchMore'),
                  onPressed: _serverSearching
                      ? null
                      : () => unawaited(_runServerSearch(reset: false)),
                  label: 'Load more results',
                ),
            ],
          ] else if (_hasSearched) ...[
            const SizedBox(height: 12),
            Text(
              _matches.isEmpty
                  ? 'No messages found'
                  : '${_matches.length} ${_matches.length == 1 ? 'message' : 'messages'} found',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: HocalistPalette.text(
                  context,
                  _matches.isEmpty ? _muted : _blue,
                ),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final message in _matches) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    BuyerUiTokens.softSurface,
                  ),
                  border: Border.all(
                    color: HocalistPalette.border(
                      context,
                      BuyerUiTokens.border,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HocalistPalette.text(context, _navy),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// One server-side search hit with honest conversation context.
class _ServerSearchResultCard extends StatelessWidget {
  const _ServerSearchResultCard({required this.hit});

  final ChatSearchHit hit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
        border: Border.all(
          color: HocalistPalette.border(context, BuyerUiTokens.border),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hit.senderDisplayName ?? 'Sender unavailable',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: HocalistPalette.text(context, _muted),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hit.message.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: HocalistPalette.text(context, _navy),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest block banner for the active conversation. It never reveals a block
/// reason to the blocked member and only offers Unblock to the blocker.
class _BlockedConversationNotice extends StatelessWidget {
  const _BlockedConversationNotice({required this.blockedByMe, this.onUnblock});

  final bool blockedByMe;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('approvedChatBlockedNotice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xffffeeee)),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xffffcdd2)),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            blockedByMe
                ? 'You blocked this person'
                : 'Messaging is unavailable',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: HocalistPalette.text(context, const Color(0xffc62828)),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            blockedByMe
                ? 'They can’t send new messages or start calls. Your deal and history stay unchanged.'
                : 'You can’t send messages here right now. Your deal records are unchanged.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: HocalistPalette.text(context, _navy),
            ),
          ),
          if (onUnblock != null)
            TextButton(
              key: const Key('approvedChatUnblockAction'),
              onPressed: onUnblock,
              child: const Text('Unblock'),
            ),
        ],
      ),
    );
  }
}

class _BuyerDealFacts extends StatelessWidget {
  const _BuyerDealFacts();

  @override
  Widget build(BuildContext context) {
    const location = _ApprovedDealFact(
      asset: 'chat-location.png',
      label: 'Pickup location',
      value: 'Yonkers, NY',
    );
    const time = _ApprovedDealFact(
      asset: 'chat-time.png',
      label: 'Meet time',
      value: 'Today • 5:00 PM',
    );
    const earnings = _ApprovedDealFact(
      asset: 'detail-star.png',
      label: 'EST. Earn',
      value: '\$1.40',
      valueColor: Color(0xff159447),
    );
    const pin = _ApprovedDealFact(
      asset: 'detail-pin.png',
      label: 'Your PIN',
      value: '15230',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final useTwoRows = constraints.maxWidth < 300 || textScale > 1.3;
        if (useTwoRows) {
          return const Column(
            children: [
              _ApprovedDealFactRow(children: [location, time]),
              SizedBox(height: 14),
              _ApprovedDealFactRow(children: [earnings, pin]),
            ],
          );
        }
        return const _ApprovedDealFactRow(
          children: [location, time, earnings, pin],
        );
      },
    );
  }
}

class _SellerDealFacts extends StatelessWidget {
  const _SellerDealFacts();

  @override
  Widget build(BuildContext context) {
    return const _ApprovedDealFactRow(
      children: [
        _ApprovedDealFact(
          asset: 'chat-location.png',
          label: 'Pickup location',
          value: 'Yonkers, NY',
        ),
        _ApprovedDealFact(
          asset: 'chat-time.png',
          label: 'Meet time',
          value: 'Today • 5:00 PM',
        ),
      ],
    );
  }
}

class _ApprovedDealFactRow extends StatelessWidget {
  const _ApprovedDealFactRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rowChildren = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        rowChildren.add(
          Container(
            width: 1,
            height: 54,
            color: HocalistPalette.surface(context, _line),
          ),
        );
      }
      rowChildren.add(Expanded(child: children[index]));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rowChildren,
    );
  }
}

class _SellerTransactionNotice extends StatelessWidget {
  const _SellerTransactionNotice();

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Container(
      key: const ValueKey('seller-after-transaction-notice'),
      padding: metrics.geometryInsets(const EdgeInsets.all(14)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfffff5e7)),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerGlyphIcon(
            icon: Icons.notifications_none_rounded,
            slotSize: metrics.artSize(28),
            glyphSize: metrics.artSize(28),
            color: HocalistPalette.text(context, const Color(0xfff2a51a)),
          ),
          SizedBox(width: metrics.geometry(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'After the transaction',
                  style: _text(
                    context,
                    size: 12,
                    weight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                SizedBox(height: metrics.geometry(3)),
                Text(
                  'Go to Meets and submit the buyer’s PIN to honor their rewards.',
                  style: _text(context, size: 10.5, color: _navy, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedDealFact extends StatelessWidget {
  const _ApprovedDealFact({
    required this.asset,
    required this.label,
    required this.value,
    this.valueColor = _navy,
  });

  final String asset;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BuyerAssetIcon(
              asset: '$_assetRoot/$asset',
              slotSize: metrics.artSize(19),
            ),
            SizedBox(width: metrics.geometry(4)),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: _text(context, size: 8.5, color: _muted),
              ),
            ),
          ],
        ),
        SizedBox(height: metrics.geometry(7)),
        Text(
          value,
          textAlign: TextAlign.center,
          style: _text(
            context,
            size: 10.5,
            weight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ApprovedSheetField extends StatelessWidget {
  const _ApprovedSheetField({
    required this.controller,
    required this.label,
    required this.asset,
    this.prefixText,
    this.keyboardType,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String asset;
  final String? prefixText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuyerFieldLabel(label),
        SizedBox(height: metrics.spacing(5)),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: buyerInputDecoration(
            context,
            prefixText: prefixText,
            prefixIcon: Padding(
              padding: metrics.geometryInsets(const EdgeInsets.all(12)),
              child: BuyerAssetIcon(
                asset: '$_assetRoot/$asset',
                slotSize: metrics.artSize(24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DealChangeRow extends StatelessWidget {
  const _DealChangeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: HocalistPalette.text(context, _muted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferUpdatedNotice extends StatelessWidget {
  const _OfferUpdatedNotice();

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Container(
      key: const Key('buyer-offer-updated-notice'),
      padding: metrics.geometryInsets(const EdgeInsets.all(12)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfffff7e8)),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xffffd58d)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BuyerGlyphIcon(
                icon: Icons.update,
                slotSize: BuyerIconTokens.control,
                glyphSize: BuyerIconTokens.control,
                color: HocalistPalette.text(context, Color(0xff9b5b00)),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The seller updated this offer. Review the price and meeting details before accepting.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.geometry(10)),
          Container(
            padding: metrics.geometryInsets(
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(
                context,
                Colors.white.withValues(alpha: .72),
              ),
              borderRadius: BorderRadius.circular(metrics.geometry(9)),
            ),
            child: const Column(
              children: [
                _DealRevisionRow(
                  label: 'Price',
                  previous: r'$620',
                  updated: r'$650',
                ),
                Divider(height: 1, color: Color(0xffffe2ad)),
                _DealRevisionRow(
                  label: 'Meet time',
                  previous: 'Today • 4:30 PM',
                  updated: 'Today • 5:00 PM',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DealRevisionRow extends StatelessWidget {
  const _DealRevisionRow({
    required this.label,
    required this.previous,
    required this.updated,
  });

  final String label;
  final String previous;
  final String updated;

  @override
  Widget build(BuildContext context) {
    final metrics = _chatMetrics(context);
    return Padding(
      padding: metrics.geometryInsets(const EdgeInsets.symmetric(vertical: 7)),
      child: Row(
        children: [
          SizedBox(
            width: metrics.geometry(62),
            child: Text(label, style: _text(context, size: 10, color: _muted)),
          ),
          Expanded(
            child: Text(
              previous,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _text(
                context,
                size: 10,
                color: _muted,
              ).copyWith(decoration: TextDecoration.lineThrough),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: BuyerGlyphIcon(
              icon: Icons.arrow_forward_rounded,
              slotSize: 15,
              glyphSize: 15,
              color: HocalistPalette.text(context, Color(0xff9b5b00)),
            ),
          ),
          Expanded(
            child: Text(
              updated,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: _text(
                context,
                size: 10,
                weight: FontWeight.w900,
                color: const Color(0xff9b5b00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestUpdatedNotice extends StatelessWidget {
  const _RequestUpdatedNotice({
    required this.onContinue,
    required this.onWithdraw,
  });

  final VoidCallback onContinue;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('seller-request-updated-notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfffff7e8)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xffffd58d)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BuyerGlyphIcon(
                icon: Icons.edit_notifications_outlined,
                slotSize: BuyerIconTokens.control,
                glyphSize: BuyerIconTokens.control,
                color: HocalistPalette.text(context, Color(0xff9b5b00)),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Request updated',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'The buyer changed the requested price. Review the update and choose whether to continue.',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('seller-withdraw-updated-request'),
                  onPressed: onWithdraw,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                  ),
                  child: Text(
                    'Withdraw & restore credit',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: _text(
                      context,
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: _navy,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('seller-continue-updated-request'),
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: _text(
                      context,
                      size: 10.5,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Retained for the legacy offer-detail state while active-deal chat is rolled
// out across both roles.
// ignore: unused_element
class _ChatProductCard extends StatelessWidget {
  const _ChatProductCard();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: _Surface(
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: _asset(
                  'chat-ipad.png',
                  width: compact ? 48 : 58,
                  height: compact ? 58 : 70,
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'iPad Air 5th Gen 64GB',
                      style: _text(
                        context,
                        size: compact ? 12 : 15,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\$650',
                      style: _text(
                        context,
                        size: compact ? 16 : 19,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _asset(
                          'chat-deal-shield.png',
                          width: compact ? 15 : 18,
                          height: compact ? 15 : 18,
                        ),
                        SizedBox(width: compact ? 4 : 6),
                        Expanded(
                          child: Text(
                            'Deal details recorded by Hocalist; item payment stays offline.',
                            style: _text(
                              context,
                              size: compact ? 7 : 9,
                              weight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _FinalOfferCard extends StatelessWidget {
  const _FinalOfferCard({
    required this.expanded,
    required this.onToggle,
    required this.onRequestChange,
    required this.onChangeLocation,
  });
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRequestChange;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: _Surface(
          padding: EdgeInsets.all(compact ? 7 : 10),
          child: Column(
            children: [
              InkWell(
                key: const Key('approved-toggle-final-offer'),
                onTap: onToggle,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = _usesAccessibilityReflow(context);
                    final tight = constraints.maxWidth < 300;
                    final title = Row(
                      children: [
                        _asset(
                          'chat-final-offer.png',
                          width: tight ? 28 : 34,
                          height: tight ? 28 : 34,
                        ),
                        SizedBox(width: tight ? 5 : 7),
                        Expanded(
                          child: Text(
                            'Seller\'s Final Offer',
                            style: _text(
                              context,
                              size: tight ? 12 : 15,
                              weight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    );
                    final detail = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          expanded
                              ? 'Tap to close details'
                              : 'Tap to view details',
                          style: _text(
                            context,
                            size: tight ? 7 : 9,
                            weight: FontWeight.w500,
                            color: _muted,
                          ),
                        ),
                        SizedBox(width: tight ? 3 : 5),
                        RotatedBox(
                          quarterTurns: expanded ? 2 : 0,
                          child: _asset(
                            'chat-chevron-down.png',
                            width: tight ? 15 : 19,
                            height: tight ? 15 : 19,
                          ),
                        ),
                      ],
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title,
                          Align(
                            alignment: Alignment.centerRight,
                            child: detail,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: title),
                        SizedBox(width: tight ? 5 : 8),
                        detail,
                      ],
                    );
                  },
                ),
              ),
              if (expanded) ...[
                const Divider(height: 12, color: _line),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = _usesAccessibilityReflow(context);
                    final compact = constraints.maxWidth < 300;
                    const facts = [
                      _ChatOfferFact(
                        asset: 'chat-price.png',
                        title: 'Price',
                        body: '\$650',
                      ),
                      _ChatOfferFact(
                        asset: 'chat-location.png',
                        title: 'Pickup Location',
                        body: 'Yonkers, NY',
                      ),
                      _ChatOfferFact(
                        asset: 'chat-time.png',
                        title: 'Meet Time',
                        body: 'Today - 5:00 PM',
                      ),
                      _ChatOfferFact(
                        asset: 'chat-reward.png',
                        title: 'Close Deal To Earn',
                        body: '\$1.40',
                        bodyColor: _green,
                      ),
                    ];
                    if (stacked) {
                      return Column(
                        children: [
                          for (final fact in facts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: fact,
                            ),
                        ],
                      );
                    }
                    return GridView.count(
                      crossAxisCount: 2,
                      childAspectRatio: compact ? 5.2 : 4.8,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 6,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: facts,
                    );
                  },
                ),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = _usesAccessibilityReflow(context);
                    final compact = constraints.maxWidth < 300;
                    final request = OutlinedButton(
                      key: const Key('approved-request-change'),
                      onPressed: onRequestChange,
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, compact ? 38 : 44),
                        side: BorderSide(
                          color: HocalistPalette.border(context, _line),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Request Change',
                        style: _text(
                          context,
                          size: compact ? 9 : 11,
                          weight: FontWeight.w800,
                        ),
                      ),
                    );
                    final location = FilledButton(
                      key: const Key('approved-change-location'),
                      onPressed: onChangeLocation,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(0, compact ? 38 : 44),
                        backgroundColor: HocalistPalette.surface(
                          context,
                          _navy,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Change Location',
                        style: _text(
                          context,
                          size: compact ? 9 : 11,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    );
                    if (stacked) {
                      return Column(
                        children: [
                          SizedBox(width: double.infinity, child: request),
                          const SizedBox(height: 6),
                          SizedBox(width: double.infinity, child: location),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: request),
                        SizedBox(width: compact ? 5 : 8),
                        Expanded(child: location),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatOfferFact extends StatelessWidget {
  const _ChatOfferFact({
    required this.asset,
    required this.title,
    required this.body,
    this.bodyColor = _navy,
  });
  final String asset;
  final String title;
  final String body;
  final Color bodyColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 145;
        final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1;
        return Row(
          children: [
            _asset(asset, width: compact ? 28 : 34, height: compact ? 28 : 34),
            SizedBox(width: compact ? 4 : 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: _text(
                      context,
                      size: compact ? 7 : 9,
                      weight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  SizedBox(height: compact || enlargedText ? 1 : 2),
                  Text(
                    body,
                    style: _text(
                      context,
                      size: compact ? 9 : 11,
                      weight: FontWeight.w900,
                      color: bodyColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xffd8d9e5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Today',
            style: _text(
              context,
              size: compact ? 8 : 10,
              weight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xffd8d9e5))),
      ],
    );
  }
}

class _IncomingMessage extends StatelessWidget {
  const _IncomingMessage({
    required this.text,
    required this.time,
    this.contactInitials,
    this.prototypeStatus = true,
    this.attachmentMediaIds = const <String>[],
    super.key,
  });
  final String text;
  final String time;
  final String? contactInitials;
  final bool prototypeStatus;
  final List<String> attachmentMediaIds;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            if (contactInitials == null)
              ClipOval(
                child: _asset(
                  'john-avatar.png',
                  width: compact ? 29 : 34,
                  height: compact ? 29 : 34,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: compact ? 29 : 34,
                height: compact ? 29 : 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(context, _lavender),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  contactInitials!,
                  style: _text(
                    context,
                    size: compact ? 8 : 10,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
            if (prototypeStatus)
              Positioned(
                right: -1,
                bottom: 0,
                child: Container(
                  key: const Key('prototype-message-presence'),
                  width: compact ? 8 : 10,
                  height: compact ? 8 : 10,
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(
                      context,
                      const Color(0xff12b759),
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: HocalistPalette.border(context, Colors.white),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(width: compact ? 4 : 6),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: EdgeInsets.fromLTRB(
              compact ? 9 : 11,
              compact ? 9 : 12,
              compact ? 8 : 10,
              compact ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, Colors.white),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10101054),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (attachmentMediaIds.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in attachmentMediaIds)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: PrivateRemoteImage(
                              key: ValueKey('incoming-attachment-$id'),
                              id: id,
                              size: 128,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (text.trim().isNotEmpty) const SizedBox(height: 6),
                ],
                if (text.trim().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text,
                      style: _text(
                        context,
                        size: compact ? 9 : 11,
                        weight: FontWeight.w500,
                        color: const Color(0xff111325),
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: _text(
                    context,
                    size: compact ? 7 : 8,
                    weight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OutgoingMessage extends StatelessWidget {
  const _OutgoingMessage({
    required this.text,
    required this.time,
    this.attachmentMediaIds = const <String>[],
    this.isRead = false,
    super.key,
  });
  final String text;
  final String time;
  final List<String> attachmentMediaIds;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: EdgeInsets.fromLTRB(compact ? 10 : 12, 8, compact ? 8 : 10, 5),
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, _navy),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (attachmentMediaIds.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final id in attachmentMediaIds)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PrivateRemoteImage(
                          key: ValueKey('outgoing-attachment-$id'),
                          id: id,
                          size: 128,
                        ),
                      ),
                  ],
                ),
              ),
              if (text.trim().isNotEmpty) const SizedBox(height: 6),
            ],
            if (text.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: _text(
                    context,
                    size: compact ? 9 : 11,
                    weight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: _text(
                    context,
                    size: compact ? 7 : 8,
                    weight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 5),
                Semantics(
                  label: isRead ? 'Read' : 'Sent',
                  child: Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: compact ? 14 : 17,
                    color: isRead ? const Color(0xFF9FF5DA) : Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ChatSafetyNotice extends StatelessWidget {
  const _ChatSafetyNotice({required this.onLearnMore});
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, const Color(0xfff4f1ff)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _usesAccessibilityReflow(context);
          final copy = Row(
            children: [
              _asset('chat-safety.png', width: 30, height: 30),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Always be safe, meet in public crowded places with the person you expect.',
                  style: _text(
                    context,
                    size: 9,
                    weight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          );
          final link = TextButton(
            key: const Key('approved-safety-learn-more'),
            onPressed: onLearnMore,
            style: TextButton.styleFrom(
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(
              'Learn more',
              style: _text(
                context,
                size: 9,
                weight: FontWeight.w800,
                color: _blue,
              ),
            ),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                Align(alignment: Alignment.centerRight, child: link),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              link,
            ],
          );
        },
      ),
    );
  }
}

@immutable
class _ApprovedChatAttachment {
  const _ApprovedChatAttachment({required this.label, required this.isImage});

  final String label;
  final bool isImage;
}

class _ApprovedAttachmentPickerSheet extends StatelessWidget {
  const _ApprovedAttachmentPickerSheet({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _ApprovedChatSheetFrame(
      key: const Key('approved-attachment-picker-sheet'),
      title: 'Add an attachment',
      subtitle: 'Choose what you want to share in this conversation.',
      icon: Icons.attach_file_rounded,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovedMenuAction(
            icon: Icons.photo_camera_outlined,
            title: 'Take a photo',
            subtitle: 'Use the camera for an item or meetup photo.',
            onTap: () => Navigator.pop(
              context,
              const _ApprovedChatAttachment(
                label: 'iPad-condition-photo.jpg',
                isImage: true,
              ),
            ),
          ),
          _ApprovedMenuAction(
            icon: Icons.photo_library_outlined,
            title: 'Choose from library',
            subtitle: 'Select an existing photo or short video.',
            onTap: () => Navigator.pop(
              context,
              const _ApprovedChatAttachment(
                label: 'iPad-product-photo.jpg',
                isImage: true,
              ),
            ),
          ),
          _ApprovedMenuAction(
            icon: Icons.description_outlined,
            title: 'Attach a document',
            subtitle: 'Share a receipt, specification, or related file.',
            onTap: () => Navigator.pop(
              context,
              const _ApprovedChatAttachment(
                label: 'iPad-item-details.pdf',
                isImage: false,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Device permissions and storage upload connect when platform services are enabled.',
            style: _text(context, size: 10, color: _muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ApprovedPendingAttachment extends StatelessWidget {
  const _ApprovedPendingAttachment({
    required this.label,
    required this.isImage,
    required this.onRemove,
  });

  final String label;
  final bool isImage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('approved-pending-attachment'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        border: Border.all(color: HocalistPalette.border(context, _line)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, Colors.white),
              borderRadius: BorderRadius.circular(9),
            ),
            child: isImage
                ? Image.asset(
                    'assets/approved_offers_chat/chat-ipad.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                  )
                : BuyerGlyphIcon(
                    icon: Icons.description_outlined,
                    slotSize: 28,
                    glyphSize: 24,
                    color: HocalistPalette.text(context, _blue),
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    context,
                    size: 11,
                    weight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ready to send',
                  style: _text(context, size: 9.5, color: _green),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('approved-remove-pending-attachment'),
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 19),
          ),
        ],
      ),
    );
  }
}

class _ApprovedPendingRemoteAttachment extends StatelessWidget {
  const _ApprovedPendingRemoteAttachment({
    required this.mediaId,
    required this.busy,
    this.onRetry,
    this.onDiscard,
  });

  final String mediaId;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('approved-pending-remote-attachment'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, _lavender),
        border: Border.all(color: HocalistPalette.border(context, _line)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: PrivateRemoteImage(
                  key: ValueKey('pending-attachment-$mediaId'),
                  id: mediaId,
                  size: 44,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photo not confirmed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        size: 11,
                        weight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Retry sends the same upload; it never uploads again.',
                      style: _text(context, size: 9, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  key: const Key('approved-chat-attachment-retry'),
                  label: busy ? 'Retrying…' : 'Retry photo',
                  onPressed: busy ? null : onRetry,
                  height: 36,
                  backgroundColor: HocalistPalette.surface(context, _blue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  key: const Key('approved-chat-attachment-discard'),
                  onPressed: busy ? null : onDiscard,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    foregroundColor: HocalistPalette.text(context, _muted),
                  ),
                  child: const Text('Discard photo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.onAttach,
    required this.onSend,
    this.enabled = true,
    this.hintText = 'Type a message...',
  });
  final TextEditingController controller;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final bool enabled;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Row(
      children: [
        IconButton(
          key: const Key('approved-chat-attach'),
          tooltip: 'Attach',
          onPressed: enabled ? onAttach : null,
          iconSize: compact ? 38 : 44,
          padding: EdgeInsets.zero,
          icon: _asset(
            'chat-plus.png',
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
          ),
        ),
        SizedBox(width: compact ? 4 : 6),
        Expanded(
          child: TextField(
            key: const Key('approved-chat-message'),
            controller: controller,
            enabled: enabled,
            minLines: 1,
            maxLines: 4,
            style: _text(
              context,
              size: compact ? 9 : 11,
              weight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              isDense: false,
              constraints: BoxConstraints(
                minHeight: compact
                    ? HocalistInputTokens.compactMinimumHeight
                    : HocalistInputTokens.minimumHeight,
              ),
              hintText: hintText,
              hintStyle: _text(
                context,
                size: compact ? 9 : 11,
                weight: FontWeight.w500,
                color: const Color(0xff8c90a9),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: compact
                    ? HocalistInputTokens.compactHorizontalPadding
                    : HocalistInputTokens.horizontalPadding,
                vertical: compact
                    ? HocalistInputTokens.compactVerticalPadding
                    : HocalistInputTokens.verticalPadding,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: BorderSide(
                  color: HocalistPalette.border(context, _line),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: BorderSide(
                  color: HocalistPalette.border(context, _line),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 3 : 5),
        IconButton(
          key: const Key('approved-chat-send'),
          tooltip: 'Send message',
          onPressed: enabled ? onSend : null,
          icon: _asset(
            'chat-send.png',
            width: compact ? 26 : 31,
            height: compact ? 26 : 31,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.height = 48,
    this.backgroundColor = _blue,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width <= 320 &&
        !_usesAccessibilityReflow(context);
    final effectiveHeight = compact ? height.clamp(0, 38).toDouble() : height;
    return BuyerPrimaryButton(
      label: label,
      onPressed: onPressed,
      compact: effectiveHeight <= 40,
      fontSize: effectiveHeight <= 38 ? 10 : 13,
      colors: [backgroundColor, backgroundColor],
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials, required this.size});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.black),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: _text(
          context,
          size: size * 0.38,
          weight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.color = Colors.white,
    super.key,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, color),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HocalistPalette.border(context, _line)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0c111354),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EnquiryContextPanel extends StatelessWidget {
  const _EnquiryContextPanel({required this.enquiries,required this.selectedId,required this.onSelect});
  final List<ChatEnquiry> enquiries;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('approved-enquiry-contexts'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: HocalistPalette.surface(context,Colors.white),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color:HocalistPalette.text(context,_blue).withValues(alpha:.18)),
    ),
    child: Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[

      for(final enquiry in enquiries)
        TextButton(
          key: ValueKey('enquiry-${enquiry.id}'),
          onPressed:onSelect==null?null:()=>onSelect!(enquiry.id),
          style:TextButton.styleFrom(
            minimumSize:const Size(44,48),alignment:Alignment.centerLeft,
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:10),
            backgroundColor:selectedId==enquiry.id?HocalistPalette.text(context,_blue).withValues(alpha:.08):null,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
          ),
          child:Row(children:[
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(enquiry.originLabel,style:_text(context,size:11,weight:FontWeight.w700,color:_blue)),
              Text(enquiry.label,style:_text(context,size:13,weight:FontWeight.w800)),
            ])),
            if(selectedId==enquiry.id) const Icon(Icons.check_rounded,size:20),
          ]),
        ),

    ]),
  );
}
