import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_marketplace_repository.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/input_foundation.dart';
import '../../theme/seller_ui_foundation.dart' show SellerPrimaryButton;
import 'approved_replica_metrics.dart';
import 'buyer_bottom_navigation.dart';

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

@immutable
class ApprovedConversationEntry {
  const ApprovedConversationEntry({
    required this.isOutgoing,
    required this.time,
    this.text = '',
    this.attachmentLabel,
    this.attachmentIsImage = false,
  });

  final bool isOutgoing;
  final String time;
  final String text;
  final String? attachmentLabel;
  final bool attachmentIsImage;

  String get displayText {
    final attachment = attachmentLabel;
    if (attachment == null) return text;
    final prefix = attachmentIsImage ? 'Photo' : 'Attachment';
    if (text.isEmpty) return '$prefix: $attachment';
    return '$prefix: $attachment\n$text';
  }
}

/// Approved offers-received replica. It owns the page header, scroll surface,
/// offer actions, and buyer bottom navigation so integration does not depend on
/// private widgets in the existing app shell.
class ApprovedOffersReceivedPage extends StatefulWidget {
  const ApprovedOffersReceivedPage({
    required this.onBack,
    required this.onNotifications,
    required this.onViewOffer,
    required this.onChat,
    required this.onFilter,
    required this.navigation,
    this.latestOffer,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onViewOffer;
  final VoidCallback onChat;
  final VoidCallback onFilter;
  final ApprovedBuyerNavigation navigation;
  final LocalOfferRecord? latestOffer;

  @override
  State<ApprovedOffersReceivedPage> createState() =>
      _ApprovedOffersReceivedPageState();
}

class _ApprovedOffersReceivedPageState
    extends State<ApprovedOffersReceivedPage> {
  String _sort = 'Best match';
  bool _underFourHundredOnly = false;

  Future<void> _showFilters() async {
    var draft = _underFourHundredOnly;
    final applied = await showModalBottomSheet<bool>(
      context: context,
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
                color: Colors.transparent,
                child: CheckboxListTile(
                  key: const Key('approved-offers-under-400-filter'),
                  contentPadding: EdgeInsets.zero,
                  value: draft,
                  onChanged: (value) =>
                      setSheetState(() => draft = value ?? false),
                  activeColor: _offersBlue,
                  title: const Text(r'Offers under $400'),
                  subtitle: const Text(
                    'Show offers within the lower end of the budget.',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              BuyerPrimaryButton(
                key: const Key('approved-offers-apply-filter'),
                label: 'Apply filters',
                onPressed: () => Navigator.pop(sheetContext, true),
                colors: const [_offersBlue, _offersBlue],
              ),
              TextButton(
                key: const Key('approved-offers-clear-filter'),
                onPressed: () {
                  draft = false;
                  Navigator.pop(sheetContext, true);
                },
                child: const Text('Clear filters'),
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
    final offers = _underFourHundredOnly
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
              _ApprovedGlobalHeader(onNotifications: widget.onNotifications),
              const SizedBox(height: 6),
              const _OffersHero(),
              const SizedBox(height: 8),
              const _OffersRewardsCard(),
              const SizedBox(height: 10),
              _OffersToolbar(
                value: _sort,
                onChanged: (value) => setState(() => _sort = value),
                onFilter: _showFilters,
                filtersActive: _underFourHundredOnly,
              ),
              const SizedBox(height: 8),
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
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onSelectSeller;
  final VoidCallback onViewProfile;
  final ApprovedBuyerNavigation navigation;
  final LocalOfferRecord? latestOffer;

  @override
  Widget build(BuildContext context) {
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
              _OfferSellerSummary(offer: latestOffer),
              const SizedBox(height: 8),
              const _OfferRewardWindow(),
              const SizedBox(height: 8),
              _OfferDescription(offer: latestOffer),
              const SizedBox(height: 6),
              const _OfferPinNotice(),
              const SizedBox(height: 6),
              _AboutSeller(onViewProfile: onViewProfile),
              const SizedBox(height: 6),
              const _OfferOfflineNotice(),
              const SizedBox(height: 6),
              _SelectSellerPanel(onSelect: onSelectSeller),
            ],
          ),
        ),
      ],
    );
  }
}

/// Buyer route wrapper for the shared approved conversation experience.
class ApprovedBuyerChatPage extends StatelessWidget {
  const ApprovedBuyerChatPage({
    required this.onBack,
    required this.onPrimary,
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
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPrimary;
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
      ),
    );
  }
}

/// Role-aware conversation body shared by Buyer and Seller route shells.
class ApprovedConversationBody extends StatefulWidget {
  const ApprovedConversationBody({
    required this.onBack,
    required this.onPrimary,
    required this.onCall,
    required this.onMore,
    required this.onRequestChange,
    required this.onChangeLocation,
    required this.onAttach,
    required this.onSend,
    required this.onLearnMore,
    this.primaryLabel = 'Accept to meet',
    this.contactName = 'John D.',
    this.contactRoleLabel = 'Verified Seller',
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
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPrimary;
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

  @override
  State<ApprovedConversationBody> createState() =>
      _ApprovedConversationBodyState();
}

class _ApprovedConversationBodyState extends State<ApprovedConversationBody> {
  final _controller = TextEditingController();
  bool _messagesMuted = false;
  bool _secondDealAdded = false;
  String? _pendingAttachment;
  bool _pendingAttachmentIsImage = false;
  late final List<ApprovedConversationEntry> _sentEntries;

  @override
  void initState() {
    super.initState();
    _sentEntries = List<ApprovedConversationEntry>.of(widget.sentEntries);
  }

  @override
  void didUpdateWidget(covariant ApprovedConversationBody oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _send() {
    final text = _controller.text.trim();
    final attachment = _pendingAttachment;
    if (text.isEmpty && attachment == null) return;
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
              if (widget.viewerIsSeller)
                _ApprovedMenuAction(
                  asset: 'detail-description.png',
                  title: 'View original request',
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
                icon: _messagesMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                title: _messagesMuted
                    ? 'Unmute chat messages'
                    : 'Mute chat messages',
                subtitle: 'Critical deal and safety alerts stay on.',
                onTap: () {
                  setState(() => _messagesMuted = !_messagesMuted);
                  Navigator.pop(sheetContext);
                  _message(
                    _messagesMuted
                        ? 'Chat messages muted.'
                        : 'Chat messages unmuted.',
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ApprovedSearchConversationSheet(
        onClose: () => Navigator.pop(sheetContext),
        onMessage: _message,
      ),
    );
  }

  Future<void> _showAttachmentPicker() async {
    final attachment = await showModalBottomSheet<_ApprovedChatAttachment>(
      context: context,
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
    await showModalBottomSheet<void>(
      context: context,
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
  }

  Future<void> _showOfferEditor() async {
    final priceController = TextEditingController(text: '650');
    final locationController = TextEditingController(text: 'Yonkers, NY');
    final timeController = TextEditingController(text: 'Today • 5:00 PM');
    final revised = await showModalBottomSheet<bool>(
      context: context,
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
    await showModalBottomSheet<void>(
      context: context,
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

  Future<void> _showConversationDeals() async {
    await showModalBottomSheet<void>(
      context: context,
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
    final content = IconButtonTheme(
      data: const IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
        ),
      ),
      child: CustomScrollView(
        key: const Key('approved-chat-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            sliver: SliverList.list(
              children: [
                _ChatHeader(
                  onBack: widget.onBack,
                  onCall: widget.onCall,
                  onMore: _showConversationMenu,
                  contactName: widget.contactName,
                  contactRoleLabel: widget.contactRoleLabel,
                  contactInitials: widget.contactInitials,
                ),
                if (widget.viewerIsSeller && widget.requestChangePending) ...[
                  const SizedBox(height: 10),
                  _RequestUpdatedNotice(
                    onContinue: widget.onContinueWithRequest ?? () {},
                    onWithdraw: widget.onWithdrawFromRequest ?? () {},
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Active Deals (${_secondDealAdded ? 2 : 1})',
                        style: _text(
                          context,
                          size: 15,
                          weight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('approved-manage-conversation-deals'),
                      onPressed: _showConversationDeals,
                      style: TextButton.styleFrom(
                        foregroundColor: _blue,
                        minimumSize: const Size(44, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      icon: const BuyerGlyphIcon(
                        icon: Icons.tune_rounded,
                        slotSize: 18,
                        glyphSize: 18,
                        color: _blue,
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
                const SizedBox(height: 6),
                _ActiveDealsPanel(
                  offer: widget.offer,
                  viewerIsSeller: widget.viewerIsSeller,
                  meetingConfirmed: widget.meetingConfirmed,
                  offerRevisionPending: widget.offerRevisionPending,
                  secondDealAdded: _secondDealAdded,
                  onOpenDeal: _showDealDetails,
                  onLongPressDeal: _showDealDetails,
                  onAddDeal: () {
                    setState(() => _secondDealAdded = true);
                    _message('A second deal was added to this conversation.');
                  },
                ),
                const SizedBox(height: 12),
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
                    _OutgoingMessage(text: entry.displayText, time: entry.time)
                  else
                    _IncomingMessage(
                      text: entry.displayText,
                      time: entry.time,
                      contactInitials: widget.contactInitials,
                    ),
                ],
                const SizedBox(height: 8),
                if (_pendingAttachment != null) ...[
                  _ApprovedPendingAttachment(
                    label: _pendingAttachment!,
                    isImage: _pendingAttachmentIsImage,
                    onRemove: () => setState(() => _pendingAttachment = null),
                  ),
                  const SizedBox(height: 7),
                ],
                _MessageComposer(
                  controller: _controller,
                  onAttach: _showAttachmentPicker,
                  onSend: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (ApprovedReplicaScope.maybeOf(context) != null) return content;

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = ApprovedReplicaMetrics.resolve(
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
          availableWidth: availableWidth,
          textScaler: media.textScaler,
        );

        if (metrics.usesScaledReplicaCanvas) {
          final canvasSize = Size(
            ApprovedReplicaMetrics.referenceCanvasWidth,
            availableHeight / metrics.geometryScale,
          );
          final canvasMetrics = ApprovedReplicaMetrics.resolve(
            availableWidth: ApprovedReplicaMetrics.referenceCanvasWidth,
            textScaler: media.textScaler,
          );
          return ColoredBox(
            color: Colors.white,
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
                      child: _buildScaffold(media, canvasMetrics, canvasSize),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final canvasSize = Size(metrics.contentMaxWidth, availableHeight);
        return ColoredBox(
          color: Colors.white,
          child: Center(
            child: SizedBox.fromSize(
              key: const Key('approved-replica-viewport'),
              size: canvasSize,
              child: _buildScaffold(media, metrics, canvasSize),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScaffold(
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
            backgroundColor: Colors.white,
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
    color: color,
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

class _ApprovedGlobalHeader extends StatelessWidget {
  const _ApprovedGlobalHeader({required this.onNotifications});

  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context).scale(1);
        final stacked = scaler > 1.3;
        final compact = constraints.maxWidth < 320;
        final logo = Semantics(
          image: true,
          label: 'Hocalist Reverse Marketplace',
          child: Image.asset(
            'assets/brand/hocalist-wordmark.png',
            width: compact ? 64 : (constraints.maxWidth < 350 ? 84 : 92),
            height: compact ? 38 : 48,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        );
        final mode = Container(
          height: compact ? 30 : 36,
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
          decoration: BoxDecoration(
            color: _lavender,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _asset(
                'header-buyer.png',
                width: compact ? 17 : 21,
                height: compact ? 17 : 21,
              ),
              SizedBox(width: compact ? 4 : 5),
              Text(
                'Buyer mode',
                style: _text(
                  context,
                  size: compact ? 9 : 12,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
        final notification = IconButton(
          key: const Key('approved-notifications'),
          tooltip: 'Notifications',
          onPressed: onNotifications,
          icon: _asset(
            'header-bell.png',
            width: compact ? 21 : 28,
            height: compact ? 21 : 28,
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [logo, const Spacer(), notification]),
              Align(alignment: Alignment.centerRight, child: mode),
            ],
          );
        }
        return SizedBox(
          height: compact ? 42 : 56,
          child: Row(
            children: [
              logo,
              const Spacer(),
              mode,
              const SizedBox(width: 4),
              notification,
            ],
          ),
        );
      },
    );
  }
}

class _OffersHero extends StatelessWidget {
  const _OffersHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 330;
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

class _OffersRewardsCard extends StatelessWidget {
  const _OffersRewardsCard();

  @override
  Widget build(BuildContext context) {
    return _Surface(
      color: const Color(0xfffaf9ff),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _usesAccessibilityReflow(context);
          final tight = constraints.maxWidth < 300;
          final gift = Container(
            width: tight ? 54 : 70,
            height: tight ? 54 : 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _line),
            ),
            padding: EdgeInsets.all(tight ? 6 : 8),
            child: _asset('rewards-gift.png', fit: BoxFit.contain),
          );
          final total = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Est. Rewards',
                style: _text(
                  context,
                  size: tight ? 9 : 12,
                  weight: FontWeight.w800,
                ),
              ),
              Text(
                '\$0.40',
                style: _text(
                  context,
                  size: tight ? 24 : 31,
                  weight: FontWeight.w900,
                  color: _offersBlue,
                ),
              ),
              Text(
                'From 2 sellers',
                style: _text(context, size: tight ? 8 : 10, color: _muted),
              ),
            ],
          );
          final explanation = Text(
            'Rewards are earned after you confirm your purchase with your unique request PIN.',
            style: _text(
              context,
              size: tight ? 8 : 10,
              weight: FontWeight.w500,
              color: _muted,
              height: 1.45,
            ),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    gift,
                    const SizedBox(width: 10),
                    Expanded(child: total),
                  ],
                ),
                const SizedBox(height: 10),
                explanation,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              gift,
              SizedBox(width: tight ? 6 : 9),
              Expanded(flex: 4, child: total),
              SizedBox(width: tight ? 5 : 9),
              Container(
                width: 1,
                height: tight ? 54 : 72,
                color: const Color(0xffdedff0),
              ),
              SizedBox(width: tight ? 5 : 9),
              Expanded(flex: 6, child: explanation),
            ],
          );
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
  });
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;
  final bool filtersActive;

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
              child: DropdownButtonFormField<String>(
                key: const Key('approved-offers-sort'),
                initialValue: value,
                isExpanded: true,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                menuMaxHeight: 240,
                icon: _asset(
                  'offers-sort-down.png',
                  width: compact ? 13 : 16,
                  height: compact ? 13 : 16,
                ),
                decoration: InputDecoration(
                  isDense: false,
                  constraints: BoxConstraints(
                    minHeight: compact
                        ? HocalistInputTokens.compactMinimumHeight
                        : HocalistInputTokens.minimumHeight,
                  ),
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: compact
                        ? HocalistInputTokens.compactHorizontalPadding
                        : HocalistInputTokens.horizontalPadding,
                    vertical: compact
                        ? HocalistInputTokens.compactVerticalPadding
                        : HocalistInputTokens.verticalPadding,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _line),
                  ),
                ),
                style: _text(
                  context,
                  size: compact ? 9 : 11,
                  weight: FontWeight.w800,
                ),
                items: const ['Best match', 'Lowest price', 'Closest']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
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
                side: const BorderSide(color: _line),
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

class _ApprovedOfferCard extends StatelessWidget {
  const _ApprovedOfferCard({
    required this.seller,
    required this.initials,
    required this.reviews,
    required this.status,
    required this.statusColor,
    required this.price,
    required this.description,
    required this.firstFactAsset,
    required this.firstFactTitle,
    required this.firstFactBody,
    required this.distance,
    required this.availability,
    required this.onDetails,
    this.topMatch = false,
  });

  final String seller;
  final String initials;
  final String reviews;
  final String status;
  final Color statusColor;
  final String price;
  final String description;
  final String firstFactAsset;
  final String firstFactTitle;
  final String firstFactBody;
  final String distance;
  final String availability;
  final VoidCallback onDetails;
  final bool topMatch;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      key: Key('approved-offer-card-$initials'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topMatch)
            Container(
              padding: const EdgeInsets.fromLTRB(4, 0, 7, 0),
              decoration: const BoxDecoration(
                color: Color(0xffe5f5eb),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _asset('offers-top-match.png', width: 11, height: 11),
                  const SizedBox(width: 3),
                  Text(
                    'Top match',
                    style: _text(
                      context,
                      size: 8,
                      weight: FontWeight.w800,
                      color: _green,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              children: [
                _OfferCardHeader(
                  seller: seller,
                  initials: initials,
                  reviews: reviews,
                  status: status,
                  statusColor: statusColor,
                ),
                const SizedBox(height: 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 300;
                    final priceCard = Container(
                      constraints: BoxConstraints(
                        minWidth: compact ? 80 : 112,
                        minHeight: compact ? 52 : 76,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 7 : 10,
                        vertical: compact ? 6 : 9,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xfff8f7ff),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          BuyerGlyphIcon(
                            icon: Icons.sell_outlined,
                            slotSize: compact ? 17 : 23,
                            glyphSize: compact ? 17 : 23,
                            color: _offersBlue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            price,
                            style: _text(
                              context,
                              size: compact ? 18 : 24,
                              weight: FontWeight.w900,
                              color: _offersBlue,
                            ),
                          ),
                        ],
                      ),
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _asset(
                            'offer-thumbnail.png',
                            width: compact ? 38 : 50,
                            height: compact ? 25 : 33,
                            fit: BoxFit.cover,
                          ),
                        ),
                        SizedBox(width: compact ? 5 : 7),
                        Expanded(
                          child: Text(
                            description,
                            style: _text(
                              context,
                              size: compact ? 8 : 10,
                              weight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 5 : 8),
                        priceCard,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = !_usesAccessibilityReflow(context);
                    final facts = [
                      _OfferFact(
                        asset: firstFactAsset,
                        title: firstFactTitle,
                        body: firstFactBody,
                      ),
                      _OfferFact(
                        asset: 'offers-location.png',
                        title: distance,
                        body: 'from you',
                      ),
                      _OfferFact(
                        asset: 'offers-clock.png',
                        title: 'Available',
                        body: availability,
                      ),
                    ];
                    if (!columns) {
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
                          if (i < facts.length - 1) const SizedBox(width: 5),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = _usesAccessibilityReflow(context);
                    final compact = constraints.maxWidth < 300;
                    final details = _PrimaryButton(
                      key: Key('approved-view-offer-$initials'),
                      label: 'View offer details',
                      onPressed: onDetails,
                      height: compact ? 30 : 44,
                      backgroundColor: _offersBlue,
                    );
                    if (stacked) {
                      return SizedBox(width: double.infinity, child: details);
                    }
                    return SizedBox(width: double.infinity, child: details);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCardHeader extends StatelessWidget {
  const _OfferCardHeader({
    required this.seller,
    required this.initials,
    required this.reviews,
    required this.status,
    required this.statusColor,
  });
  final String seller;
  final String initials;
  final String reviews;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 300;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InitialsAvatar(initials: initials, size: tight ? 28 : 36),
            SizedBox(width: tight ? 5 : 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          seller,
                          style: _text(
                            context,
                            size: tight ? 11 : 14,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _asset(
                        'detail-verified.png',
                        width: tight ? 13 : 16,
                        height: tight ? 13 : 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _asset(
                        'detail-star.png',
                        width: tight ? 10 : 13,
                        height: tight ? 10 : 13,
                      ),
                      Text(
                        reviews,
                        style: _text(
                          context,
                          size: tight ? 7 : 9,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '•  $status',
                        style: _text(
                          context,
                          size: tight ? 7 : 9,
                          weight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        return identity;
      },
    );
  }
}

class _OfferFact extends StatelessWidget {
  const _OfferFact({
    required this.asset,
    required this.title,
    required this.body,
  });
  final String asset;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 95;
        return Row(
          children: [
            _asset(asset, width: compact ? 17 : 26, height: compact ? 17 : 26),
            SizedBox(width: compact ? 3 : 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    style: _text(
                      context,
                      size: compact ? 7 : 9,
                      weight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 2),
                  Text(
                    body,
                    maxLines: 3,
                    style: _text(
                      context,
                      size: compact ? 6 : 8,
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

class _SecurePrivateNotice extends StatelessWidget {
  const _SecurePrivateNotice();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      key: const Key('approved-secure-private-notice'),
      padding: EdgeInsets.all(compact ? 5 : 9),
      decoration: BoxDecoration(
        color: const Color(0xfff1faf5),
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
        Row(
          children: [
            IconButton(
              key: const Key('approved-offer-back'),
              tooltip: 'Back',
              onPressed: onBack,
              icon: _asset('detail-back.png', width: 24, height: 24),
            ),
            Expanded(
              child: Center(
                child: Image.asset(
                  'assets/brand/hocalist-wordmark.png',
                  width: 84,
                  height: 48,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'Hocalist Reverse Marketplace',
                ),
              ),
            ),
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _lavender,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _asset('header-buyer.png', width: 19, height: 19),
                  const SizedBox(width: 5),
                  Text(
                    'Buyer mode',
                    style: _text(
                      context,
                      size: 10,
                      weight: FontWeight.w800,
                      color: _blue,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: onNotifications,
              icon: _asset('header-bell.png', width: 25, height: 25),
            ),
          ],
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
  const _OfferSellerSummary({this.offer});

  final LocalOfferRecord? offer;

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
                            const SizedBox(width: 5),
                            _asset(
                              'detail-verified.png',
                              width: compact ? 14 : 17,
                              height: compact ? 14 : 17,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
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
                  final facts = const [
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
  const _OfferRewardWindow();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      padding: EdgeInsets.all(compact ? 6 : 9),
      decoration: BoxDecoration(
        color: const Color(0xfffff8eb),
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
                      'You have 7 days left',
                      style: _text(
                        context,
                        size: compact ? 11 : 14,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Buy from any seller within 7 days to get your rewards.',
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
          final reward = Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 11,
              vertical: compact ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: const Color(0xffffedc8),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              children: [
                Text(
                  'Est. rewards',
                  style: _text(
                    context,
                    size: compact ? 7 : 9,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$12.40',
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
  const _OfferDescription({this.offer});

  final LocalOfferRecord? offer;

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
        color: const Color(0xfff8f7ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffecebfa)),
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
  const _OfferPinNotice();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xfff5f1ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffdfd8ff)),
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
                      'Seller PIN for your rewards',
                      style: _text(
                        context,
                        size: compact ? 8 : 10,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'When you meet the seller, show them your confirmation PIN to complete the transaction. If the PIN isn\'t verified, you won\'t receive your rewards. Your PIN expires 24 hours after accepting your seller\'s offer.',
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
              color: const Color(0xffe8e0ff),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '15230',
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
  const _AboutSeller({required this.onViewProfile});
  final VoidCallback onViewProfile;

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
                      'Local seller with 230+ successful deals. Usually responds in a few hours.',
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
              backgroundColor: _lavender,
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
  const _OfferOfflineNotice();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Container(
      padding: EdgeInsets.all(compact ? 3 : 7),
      decoration: BoxDecoration(
        color: const Color(0xfff6f4ff),
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
                  'Chat opens only after you select this seller.',
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
  const _SelectSellerPanel({required this.onSelect});
  final VoidCallback onSelect;

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
                  label: 'Select this seller',
                  onPressed: onSelect,
                  height: compact ? 32 : 44,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 1 : 2),
          Text(
            'Selecting this seller will share your contact information.',
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
  });
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onMore;
  final String contactName;
  final String contactRoleLabel;
  final String? contactInitials;

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
            decoration: const BoxDecoration(
              color: _lavender,
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
        Positioned(
          right: -1,
          bottom: 0,
          child: Container(
            width: compact ? 9 : 11,
            height: compact ? 9 : 11,
            decoration: BoxDecoration(
              color: const Color(0xff12b759),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
    final badge = Container(
      key: const Key('approved-chat-role-badge'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 6,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: _lavender,
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
      tooltip: 'Call seller',
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
              'Active now',
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        onLongPress: viewerIsSeller ? onLongPress : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 118 : 134),
          padding: EdgeInsets.all(compact ? 7 : 9),
          decoration: BoxDecoration(
            border: Border.all(color: _blue, width: 1.2),
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
                      color: const Color(0xfff8f8ff),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: asset == null
                        ? BuyerGlyphIcon(
                            icon: Icons.tv_outlined,
                            slotSize: compact ? 22 : 28,
                            glyphSize: compact ? 22 : 28,
                            color: _blue,
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: status == 'Offer updated'
                      ? const Color(0xfffff4df)
                      : _lavender,
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
                    color: _blue,
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
    );
  }
}

class _NewDealCard extends StatelessWidget {
  const _NewDealCard({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: const Key('active-deal-new'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 134),
          decoration: BoxDecoration(
            border: Border.all(color: _line, style: BorderStyle.solid),
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
  final int count;
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
            SizedBox(width: metrics.geometry(6)),
            Container(
              padding: metrics.geometryInsets(
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              ),
              decoration: BoxDecoration(
                color: _lavender,
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
        ),
        SizedBox(height: metrics.geometry(7)),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xfffbfcff),
            border: Border.all(color: _line),
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
    return Semantics(
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
                  color: _lavender,
                  borderRadius: BorderRadius.circular(metrics.geometry(9)),
                ),
                child: asset != null
                    ? _asset(asset!, fit: BoxFit.contain)
                    : BuyerGlyphIcon(
                        icon: icon!,
                        slotSize: metrics.artSize(25),
                        glyphSize: metrics.artSize(25),
                        color: _blue,
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
                const BuyerGlyphIcon(
                  icon: Icons.chevron_right_rounded,
                  slotSize: 20,
                  glyphSize: 20,
                  color: _blue,
                ),
              ],
            ],
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
                  color: const Color(0xfff8f8ff),
                  borderRadius: BorderRadius.circular(metrics.geometry(14)),
                  border: Border.all(color: _line),
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
              color: const Color(0xfffbfcff),
              borderRadius: BorderRadius.circular(metrics.geometry(14)),
              border: Border.all(color: _line),
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
                color: _lavender,
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
                  SizedBox(height: metrics.geometry(5)),
                  Text(
                    'Inspect the item before paying the seller offline.',
                    style: _text(
                      context,
                      size: 10.5,
                      color: _muted,
                      height: 1.35,
                    ),
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
                  backgroundColor: _blue,
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
                  foregroundColor: _blue,
                  side: const BorderSide(color: _blue),
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
      iconColor: iconColor,
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
  final VoidCallback onTap;
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
        color: const Color(0xfffbfcff),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(13)),
          side: const BorderSide(color: _line),
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
                              color: foregroundColor,
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
                    color: foregroundColor == _navy ? _blue : foregroundColor,
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
  });

  final VoidCallback onClose;
  final ValueChanged<String> onMessage;

  @override
  State<_ApprovedSearchConversationSheet> createState() =>
      _ApprovedSearchConversationSheetState();
}

class _ApprovedSearchConversationSheetState
    extends State<_ApprovedSearchConversationSheet> {
  final _controller = TextEditingController();
  String _query = '';
  bool _hasSearched = false;

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
    return _messages
        .where((message) => message.toLowerCase().contains(query))
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ApprovedChatSheetFrame(
      key: const ValueKey('approved-search-conversation-sheet'),
      title: 'Search conversation',
      subtitle: 'Find a message without losing your place in the deal.',
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
              prefixIcon: const Center(
                widthFactor: 1,
                child: BuyerGlyphIcon(
                  icon: Icons.search_rounded,
                  slotSize: BuyerIconTokens.control,
                  glyphSize: BuyerIconTokens.control,
                  color: _blue,
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
              setState(() => _hasSearched = true);
            },
          ),
          if (_hasSearched) ...[
            const SizedBox(height: 12),
            Text(
              _matches.isEmpty
                  ? 'No messages found'
                  : '${_matches.length} ${_matches.length == 1 ? 'message' : 'messages'} found',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: _matches.isEmpty ? _muted : _blue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final message in _matches) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BuyerUiTokens.softSurface,
                  border: Border.all(color: BuyerUiTokens.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _navy,
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
        rowChildren.add(Container(width: 1, height: 54, color: _line));
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
        color: const Color(0xfffff5e7),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuyerGlyphIcon(
            icon: Icons.notifications_none_rounded,
            slotSize: metrics.artSize(28),
            glyphSize: metrics.artSize(28),
            color: const Color(0xfff2a51a),
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
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: _muted)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
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
        color: const Color(0xfffff7e8),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        border: Border.all(color: const Color(0xffffd58d)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BuyerGlyphIcon(
                icon: Icons.update,
                slotSize: BuyerIconTokens.control,
                glyphSize: BuyerIconTokens.control,
                color: Color(0xff9b5b00),
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
              color: Colors.white.withValues(alpha: .72),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: BuyerGlyphIcon(
              icon: Icons.arrow_forward_rounded,
              slotSize: 15,
              glyphSize: 15,
              color: Color(0xff9b5b00),
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
        color: const Color(0xfffff7e8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffffd58d)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              BuyerGlyphIcon(
                icon: Icons.edit_notifications_outlined,
                slotSize: BuyerIconTokens.control,
                glyphSize: BuyerIconTokens.control,
                color: Color(0xff9b5b00),
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
    return _Surface(
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
    return _Surface(
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
                      expanded ? 'Tap to close details' : 'Tap to view details',
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
                      Align(alignment: Alignment.centerRight, child: detail),
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
                    side: const BorderSide(color: _line),
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
                    backgroundColor: _navy,
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
    super.key,
  });
  final String text;
  final String time;
  final String? contactInitials;

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
                decoration: const BoxDecoration(
                  color: _lavender,
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
            Positioned(
              right: -1,
              bottom: 0,
              child: Container(
                width: compact ? 8 : 10,
                height: compact ? 8 : 10,
                decoration: BoxDecoration(
                  color: const Color(0xff12b759),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
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
              color: Colors.white,
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
  const _OutgoingMessage({required this.text, required this.time, super.key});
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: EdgeInsets.fromLTRB(compact ? 10 : 12, 8, compact ? 8 : 10, 5),
        decoration: const BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                _asset(
                  'chat-checks.png',
                  width: compact ? 16 : 19,
                  height: compact ? 12 : 14,
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
        color: const Color(0xfff4f1ff),
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
        color: _lavender,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: isImage
                ? Image.asset(
                    'assets/approved_offers_chat/chat-ipad.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                  )
                : const BuyerGlyphIcon(
                    icon: Icons.description_outlined,
                    slotSize: 28,
                    glyphSize: 24,
                    color: _blue,
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

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.onAttach,
    required this.onSend,
  });
  final TextEditingController controller;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 320;
    return Row(
      children: [
        IconButton(
          key: const Key('approved-chat-attach'),
          tooltip: 'Attach',
          onPressed: onAttach,
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
              hintText: 'Type a message...',
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
                borderSide: const BorderSide(color: _line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(color: _line),
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 3 : 5),
        IconButton(
          key: const Key('approved-chat-send'),
          tooltip: 'Send message',
          onPressed: onSend,
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
  final VoidCallback onPressed;
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
      decoration: const BoxDecoration(
        color: Colors.black,
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
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
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
