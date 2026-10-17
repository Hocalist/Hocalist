import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/phase2/chat/chat_live_updates.dart';
import 'data/phase2/chat/chat_session.dart';
import 'components/hocalist_page_transition.dart';
import 'components/hocalist_motion.dart';
import 'components/hocalist_section_tabs.dart';
import 'components/hocalist_reload_link.dart';
import 'components/notification_indicator.dart';
import 'components/notification_preference_edits.dart';
import 'theme/adaptive_palette.dart';
import 'dart:math' as math;
import 'data/phase2/marketplace/marketplace_saved_backend.dart';
import 'data/phase2/marketplace/saved_item_reference.dart';
import 'features/saved/saved_item_button.dart';
import 'features/saved/public_seller_listings.dart';
import 'features/account/profile_details_editor.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/phase2/maps/meeting_directions.dart';
import 'data/phase2/avatars/profile_avatar_backend.dart';
import 'features/media/private_remote_image.dart';
import 'data/phase2/support/support_adapter.dart';
import 'data/phase2/support/support_composition.dart';
import 'features/support/support_cases_page.dart';
import 'data/phase2/outcomes/sale_composition.dart';
import 'features/meetings/sale_confirmation_panel.dart';
import 'features/meetings/meeting_proposal_location.dart';
import 'data/phase2/media/image_gateway.dart';
import 'features/calls/hocalist_call_page.dart';
import 'features/calls/call_invitation_listener.dart';
import 'features/commercial/credit_wallet_panel.dart';
import 'domain/phase2/commercial/commercial.dart';
import 'features/commercial/buyer_rewards_panel.dart';
import 'features/commercial/withdrawal_panel.dart';
import 'data/phase2/commercial/commercial_wallet_backend.dart';
import 'data/phase2/commercial/withdrawal_backend.dart';
import 'data/phase2/trust/trust_backend.dart';
import 'data/phase2/accounts/account_lifecycle_backend.dart';
import 'data/phase2/accounts/profile_categories_backend.dart';
import 'features/account/account_lifecycle_page.dart';
import 'features/account/account_security_page.dart';
import 'features/account/seller_category_editor.dart';
import 'features/account/verification_review_panel.dart';
import 'features/media/photo_bytes.dart';
import 'features/media/photo_camera_page.dart';
import 'features/approved/meeting_directions_page.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'data/local_marketplace_repository.dart';
import 'data/phase2/discovery/discovery_adapter.dart';
import 'data/phase2/discovery/discovery_backends.dart';
import 'data/phase2/discovery/discovery_composition.dart';
import 'features/discovery/buyer_public_profile_page.dart';
import 'features/discovery/buyer_profile_visibility_editor.dart';
import 'data/phase2/maps/device_location.dart';
import 'data/phase2/maps/places_composition.dart';
import 'data/phase2/maps/places_repository.dart';
import 'data/phase2/marketplace/marketplace_composition.dart';
import 'data/phase2/marketplace/marketplace_leads_backend.dart';
import 'data/phase2/reviews/review_backend.dart';
import 'data/phase2/reviews/review_composition.dart';
import 'data/phase2/meetings/meeting_composition.dart';
import 'data/phase2/meetings/meeting_adapter.dart';
import 'data/phase2/meetings/meeting_codecs.dart';
import 'domain/phase2/schedule.dart';
import 'domain/phase2/account_completion.dart';
import 'features/seller/approved_seller_reschedule_dialog.dart';
import 'data/phase2/notifications/notification_composition.dart';
import 'data/phase2/chat/chat_safety_coordinator.dart';
import 'data/phase2/chat/chat_inbox_search.dart';
import 'data/phase2/providers/hocalist_push_service.dart';
import 'domain/phase2/communication_completion.dart';
import 'domain/phase2/conversations.dart';
import 'data/phase2/providers/hocalist_client_config.dart';
import 'data/phase2/providers/provider_runtime.dart' show hocalistLocalWebTest;
import 'domain/phase2/common.dart';
import 'domain/phase2/discovery.dart';
import 'domain/phase2/money.dart';
import 'domain/phase2/offers.dart';
import 'domain/phase2/notifications.dart';
import 'domain/phase2/notification_destination.dart';
import 'domain/phase2/profiles.dart' show HocalistRole, NotificationPreferences;
import 'domain/phase2/requests.dart';
import 'domain/phase2/reviews.dart';
import 'features/account/hocalist_account_controller.dart';
import 'features/account/private_contact_editor.dart';
import 'features/account/push_service_scope.dart';
import 'features/account/device_push_settings.dart';
import 'data/phase2/notifications/push_inbox_router.dart';
import 'data/phase2/notifications/notification_codecs.dart';
import 'features/account/real_account_gate.dart';
import 'features/approved/offers_chat_pages.dart';
import 'features/discovery/reopen_flow_coordinator.dart';
import 'features/approved/onboarding_home_pages.dart';
import 'features/approved/approved_replica_metrics.dart';
import 'features/approved/hocalist_map_surface.dart';
import 'features/approved/place_capture_sheet.dart';
import 'features/approved/request_flow_pages.dart';
import 'features/approved/trends_notifications_pages.dart';
import 'features/chat/conversation_deal_groups.dart';
import 'features/chat/conversation_profile_identity.dart';
import 'features/seller/approved_seller_home_page.dart';
import 'features/seller/approved_seller_leads_page.dart';
import 'features/seller/approved_seller_meets_page.dart';
import 'features/seller/approved_seller_chats_page.dart';
import 'features/seller/approved_seller_account_pages.dart';
import 'features/seller/approved_seller_more_page.dart';
import 'features/seller/approved_seller_store_page.dart';
import 'features/seller/seller_offer_revision_editor.dart';
import 'features/seller/approved_seller_tutorial_page.dart';
import 'features/seller/seller_app_shell.dart';
import 'features/seller/seller_bottom_navigation.dart';
import 'theme/accessibility_visuals.dart';
import 'theme/buyer_ui_foundation.dart';
import 'theme/seller_ui_foundation.dart' show SellerUiColors;
import 'theme/input_foundation.dart';
import 'theme/role_asset_bundle.dart';

export 'theme/accessibility_visuals.dart';

part 'components/ui_components.dart';
part 'features/accessibility/accessibility_page.dart';
part 'features/accessibility/accessibility_preferences.dart';
part 'features/screens.dart';
part 'theme/hocalist_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeMapsSdk();
  registerHocalistPushBackgroundHandler();
  runApp(const HocalistApp());
}

class HocalistApp extends StatelessWidget {
  const HocalistApp({this.config, this.connectionsInitializer, super.key});

  /// Explicit configuration override. Production resolves the public client
  /// configuration from the build environment.
  final HocalistClientConfig? config;

  /// Test seam for the real-mode initialization path.
  final HocalistConnectionsInitializer? connectionsInitializer;

  @override
  Widget build(BuildContext context) {
    final resolved = config ?? HocalistClientConfig.fromEnvironment;
    if (!resolved.isConfigured) {
      // Explicit prototype mode: no public key was supplied at build time.
      return const HocalistPrototype();
    }
    return HocalistRealProviderBootstrap(
      publishableKey: resolved.publishableKey,
      initialize: connectionsInitializer,
      shellBuilder: _hocalistRealModeShell,
      trustBackend: createConfiguredTrustBackend(),
      // Keyed by identity so a replacement identity can never reuse the
      // previous account's navigation, forms or marketplace state.
      activeBuilder: (context, controller) => HocalistPrototype(
        key: ValueKey('real-account-${controller.userId ?? 'signed-in'}'),
        accountSession: controller,
      ),
    );
  }
}

/// Application shell for every real-mode state that is not the active app
/// (loading, initialization failure, signed-out, confirmation, onboarding,
/// pending, restricted, failure). The active subtree brings the same theme
/// and accessibility scaling from the prototype shell, so MaterialApps are
/// never nested.
Widget _hocalistRealModeShell(Widget child) {
  const preferences = AccessibilityPreferences.defaults;
  return MaterialApp(
    title: 'Hocalist',
    debugShowCheckedModeBanner: false,
    theme: HocalistTheme.lightFor(preferences),
    darkTheme: HocalistTheme.darkFor(preferences),
    themeMode: ThemeMode.light,
    builder: (context, appChild) =>
        _hocalistTextScale(context, appChild, preferences),
    home: child,
  );
}

/// Shared accessibility text scaling used by both app shells.
Widget _hocalistTextScale(
  BuildContext context,
  Widget? child,
  AccessibilityPreferences preferences,
) {
  final media = MediaQuery.of(context);
  final phoneScale = media.textScaler.scale(1);
  final selectedScale = preferences.textSize.scale;
  final effectiveScale = phoneScale > 1
      ? math.max(phoneScale, selectedScale)
      : selectedScale;
  final clampedScale = effectiveScale.clamp(0.9, 1.6).toDouble();
  return MediaQuery(
    data: media.copyWith(textScaler: TextScaler.linear(clampedScale)),
    child: child ?? const SizedBox.shrink(),
  );
}

enum UserRole { buyer, seller }

enum AppTextSize {
  small('Small', 0.9),
  medium('Medium', 1.0),
  large('Large', 1.15),
  extraLarge('Extra Large', 1.3);

  const AppTextSize(this.label, this.scale);

  final String label;
  final double scale;
}

enum AppPage {
  welcome,
  chooseRole,
  buyerSignup,
  buyerBenefits,
  buyerProfile,
  buyerDashboard,
  hocatrends,
  hocatrendsSellers,
  recentActivity,
  createRequest,
  requestSuccess,
  buyerRequestDetail,
  offersReceived,
  buyerOfferDetail,
  sellerPublicProfile,
  buyerPublicProfile,
  buyerChats,
  buyerChat,
  finalizeDeal,
  meetingDetails,
  buyerConfirmation,
  dealRecovery,
  buyerReview,
  buyerWallet,
  buyerRewardsDetail,
  withdrawal,
  supportReviewStatus,
  buyerSupport,
  notifications,
  buyerNotificationPreferences,
  savedItems,
  safetyGuide,
  reportIssue,
  helpSupport,
  buyerSettings,
  accessibility,
  editProfile,
  accountSecurity,
  accountLifecycle,
  sellerSignup,
  sellerTutorial,
  sellerProfileSetup,
  sellerVerification,
  sellerDashboard,
  sellerStore,
  marketplace,
  sellerMeets,
  sellerRequestDetail,
  sendOffer,
  offerSuccess,
  sellerOfferHistory,
  sellerOfferDetail,
  sellerOriginalRequest,
  sellerChat,
  sellerConversation,
  sellerBilling,
  sellerPaymentMethod,
  sellerNotifications,
  sellerNotificationPreferences,
  sellerProfile,
  sellerMore,
  sellerSettings,
}

@visibleForTesting
AppPage upgradedDestinationFor(AppPage requested, UserRole role) {
  return switch (requested) {
    AppPage.buyerProfile => AppPage.buyerSettings,
    AppPage.requestSuccess => AppPage.buyerDashboard,
    AppPage.finalizeDeal =>
      role == UserRole.seller ? AppPage.sellerConversation : AppPage.buyerChat,
    AppPage.sellerRequestDetail || AppPage.sendOffer => AppPage.marketplace,
    AppPage.offerSuccess => AppPage.sellerOfferHistory,
    _ => requested,
  };
}

/// Participant-meeting page size used by [LocalMarketplaceRepository] for the
/// chat's conversation-deal scan (it calls `loadMeetings(limit: 50)`).
@visibleForTesting
const int conversationDealsMeetingPageSize = 50;

/// Safety cap for the conversation-deal scan. The chat refresh walks every
/// returned page so no matching deal is dropped, and stops after this many
/// pages (1,000 meetings at the 50-per-page limit); a doubly long history
/// reports truncation instead of silently missing deals.
@visibleForTesting
const int conversationDealsMaxPages = 20;

/// Refreshes the participant meetings and paginates every page (up to
/// [maxPages]) so all meetings for [conversationId] are collected, not only
/// the first page that contains a match.
@visibleForTesting
Future<({List<MeetingView> matches, int pagesScanned, bool truncated})>
collectConversationMeetings(
  LocalMarketplaceRepository marketplace, {
  required String conversationId,
  int maxPages = conversationDealsMaxPages,
}) async {
  await marketplace.refreshMeetings();
  var pagesScanned = 1;
  while (marketplace.meetingsError == null &&
      marketplace.meetingsHasMore &&
      pagesScanned < maxPages) {
    await marketplace.loadMoreMeetings();
    pagesScanned += 1;
  }
  final truncated =
      marketplace.meetingsError == null &&
      marketplace.meetingsHasMore &&
      pagesScanned >= maxPages;
  return (
    matches: marketplace.meetings
        .where((meeting) => meeting.conversationId == conversationId)
        .toList(growable: false),
    pagesScanned: pagesScanned,
    truncated: truncated,
  );
}

class _CurrentChatSession implements ChatSession {
  _CurrentChatSession(this.readIdentity);
  final String? Function() readIdentity;
  @override
  String? get currentUserId => readIdentity();
}

class HocalistPrototype extends StatefulWidget {
  const HocalistPrototype({this.accountSession, super.key});

  /// Real account session in real-provider mode; null keeps the explicit
  /// local prototype used by the demo tests.
  final HocalistAccountController? accountSession;

  @override
  State<HocalistPrototype> createState() => _HocalistPrototypeState();
}

class _HocalistPrototypeState extends State<HocalistPrototype>
    with WidgetsBindingObserver {
  Timer? _chatRefreshTimer;
  ChatLiveUpdates? _chatLiveUpdates;
  String? _chatLiveConversation;
  StreamSubscription<String>? _chatInboxSignals;
  Timer? _chatInboxSignalTimer;

  void _stopChatLiveUpdates() {
    final previous = _chatLiveUpdates;
    _chatLiveUpdates = null;
    _chatLiveConversation = null;
    unawaited(_chatInboxSignals?.cancel());
    _chatInboxSignals = null;
    _chatInboxSignalTimer?.cancel();
    if (previous != null) unawaited(previous.dispose());
  }

  void _syncChatLiveConversation() {
    final live = _chatLiveUpdates;
    final conversation = _marketplace.activeConversationId;
    if (live == null || conversation == _chatLiveConversation) return;
    _chatLiveConversation = conversation;
    if (conversation == null) {
      live.stop();
      return;
    }
    final repository = _marketplace;
    live.watch(
      conversationId: conversation,
      refetch: (fence) async {
        if (!mounted || !fence.isActive || repository != _marketplace) return;
        await repository.pollChatMessages();
      },
    );
  }

  void _configureChatRefresh() {
    _chatRefreshTimer?.cancel();
    _stopChatLiveUpdates();
    if (widget.accountSession == null ||
        !_marketplace.isChatBacked ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    if (const bool.fromEnvironment('HOCALIST_CHAT_REALTIME')) {
      final repository = _marketplace;
      final identity = widget.accountSession?.userId;
      final source = SupabaseChatChangeSource(
        Supabase.instance.client,
        enabled: true,
      );
      final live = ChatLiveUpdates(
        source: source,
        session: _CurrentChatSession(() => widget.accountSession?.userId),
      );
      _chatLiveUpdates = live;
      _chatInboxSignals = source.conversationChanges.listen((_) {
        _chatInboxSignalTimer?.cancel();
        _chatInboxSignalTimer = Timer(const Duration(milliseconds: 250), () {
          if (!mounted ||
              _chatLiveUpdates != live ||
              repository != _marketplace ||
              identity != widget.accountSession?.userId ||
              widget.accountSession?.phase != AccountAccessPhase.active) {
            return;
          }
          unawaited(repository.refreshChatInbox());
        });
      });
      _syncChatLiveConversation();
      unawaited(source.start());
    }
    _chatRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted ||
          widget.accountSession?.phase != AccountAccessPhase.active) {
        return;
      }
      if (page == AppPage.buyerChat || page == AppPage.sellerConversation) {
        unawaited(_marketplace.pollChatMessages());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _configureChatRefresh();
    if (state == AppLifecycleState.resumed &&
        (page == AppPage.buyerChat || page == AppPage.sellerConversation)) {
      unawaited(_marketplace.pollChatMessages());
    }
  }

  SupportAdapter? _supportAdapter;
  String? _supportConversationId;
  Widget _realSupportPage() => SupportCasesPage(
    key: ValueKey(
      'support-${page.name}-${_supportConversationId ?? 'general'}',
    ),
    initialReasonCode: page == AppPage.reportIssue ? 'safety' : 'general',
    generalHelp: page != AppPage.reportIssue,
    adapter: _supportAdapter ??= createSupportAdapter(),
    onBack: back,
    conversationId: page == AppPage.reportIssue ? _supportConversationId : null,
  );
  static const _storage = _LocalSessionStore();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final appNavigatorKey = GlobalKey<NavigatorState>();
  bool _callOpen = false;
  late LocalMarketplaceRepository _marketplace;
  Phase2DiscoveryBackend? _discoveryBackend;
  Phase2ReviewBackend? _reviewBackend;
  String? _reviewRequestId;
  SaleDetailView? _reviewPurchase;
  RecommendedLeadsView? _recommendedLeads;
  bool _recommendedLeadsLoading = false;
  String? _recommendedLeadsError;
  SellerAccountHealthView? _accountHealth;
  bool _accountHealthLoading = false;
  String? _accountHealthError;
  Set<String>? _confirmedMeetingIds;
  HocatrendsProjection? _hocatrends;
  bool _hocatrendsLoading = false;
  String? _hocatrendsError;
  HocatrendsSellerResults? _topicSellerResults;
  bool _topicSellersLoading = false;
  String? _topicSellersError;
  String? _selectedTopicId;
  PublicSellerReputation? _sellerReputation;
  bool _sellerReputationLoading = false;
  String? _sellerReputationError;
  String? _sellerReputationFor;
  int _sellerReputationGeneration = 0;
  bool _sellerProfileFromConversation = false;
  int _navigationEpoch = 0;
  late final ReopenFlowCoordinator _reopenFlow;
  SellerDiscoveryOrigin? _discoveryOrigin;
  bool _discoveryOriginLoading = false;

  UserRole role = UserRole.buyer;
  bool authenticated = false;
  AppPage page = AppPage.welcome;
  final history = <AppPage>[];

  String buyerName = '';
  final ApprovedAccountDraft _signupDraft = ApprovedAccountDraft();
  String sellerName = 'Northside Tech';
  String requestTitle = 'iPad Air, 5th gen or newer';
  String requestBudget = '\$350 - \$480';
  String _newRequestTitle = '';
  String _newRequestBudget = '';
  String offerPrice = '\$420';
  bool requestPosted = false;
  bool sellerOfferSent = false;
  bool offerSelected = false;
  bool meetingConfirmed = false;
  bool offerRevisionPending = false;
  bool requestChangePending = false;
  bool dealFailed = false;
  bool requestReopened = false;
  bool dealCompleted = false;
  bool withdrawalRequested = false;
  bool dealSupportReviewRequested = false;
  bool reportSubmitted = false;
  bool darkMode = false;
  AccessibilityPreferences accessibilityPreferences =
      AccessibilityPreferences.defaults;
  bool restoredSession = false;

  /// Authoritative request created or opened in real mode. Null keeps the
  /// prototype request flow.
  MarketplaceRequest? _activeRequest;

  /// Real-mode buyer offer state.
  BuyerOfferView? _selectedBuyerOffer;
  bool _offerSelectionBusy = false;
  String? _offerSelectionError;
  bool _offerSelectionUncertain = false;
  String? _offerSelectionKey;
  String? _offerSelectionOfferId;

  /// Real-mode final purchase designation state.
  bool _purchaseSelectionBusy = false;
  String? _purchaseSelectionError;
  String? _purchaseSelectionKey;
  String? _purchaseSelectionOfferId;

  /// Real-mode chat state for the active conversation.
  bool _chatSending = false;
  String? _chatSendError;

  /// Authoritative active deals for the open conversation. Null means the
  /// projection has not loaded; an empty list is a real "no deals" answer.
  List<ApprovedDealView>? _conversationDeals;
  List<ApprovedDealView>? _previousConversationDeals;
  int _conversationDealsGeneration = 0;
  bool _conversationDealsLoading = false;
  bool _conversationDealsTruncated = false;
  String? _conversationDealsError;
  String? _conversationDealsFor;

  /// Authoritative counterpart of the open conversation, when the server
  /// projected a public profile id for the other participant.
  ({String name, String? profileId})? _chatCounterpart;

  ({String name, String? profileId})? get _currentChatCounterpart {
    final id = _marketplace.activeConversationId;
    final summary = _marketplace.chatInbox
        .where((row) => row.conversation.id == id)
        .firstOrNull;
    return summary == null
        ? null
        : (
            name: summary.counterpartDisplayName,
            profileId: summary.counterpartProfileId,
          );
  }

  String? get _activeConversationName {
    if (!_marketplace.isChatBacked) return null;
    final id = _marketplace.activeConversationId;
    for (final item in _marketplace.chatInbox) {
      if (item.conversation.id == id) return item.counterpartDisplayName;
    }
    return null;
  }

  /// Real-mode profile avatar state. The backend is null until the reviewed
  /// avatar migration is deployed and its feature flag is enabled.
  ProfileAvatarBackend? _profileAvatarBackend;
  String? _profileAvatarMediaId;
  bool _profileAvatarBusy = false;
  final Map<String, ({String key, String? mediaId, int revision})>
  _profileAvatarIntents =
      <String, ({String key, String? mediaId, int revision})>{};

  /// Seller category summary for the read-only profile page. Loaded lazily
  /// only when the reviewed category backend is configured.
  SellerCategorySelection? _sellerCategorySelection;
  bool _sellerCategoriesRequested = false;

  Future<void> _reloadSellerCategories() async {
    final backend = createConfiguredProfileCategoriesBackend();
    _sellerCategoriesRequested = true;
    if (backend == null) return;
    try {
      final selection = await backend.loadSellerCategories();
      if (mounted) setState(() => _sellerCategorySelection = selection);
    } catch (_) {
      // Keep the previous summary; the editor renders its own error state.
    }
  }

  void _reloadSellerCategoriesAfterEdit() {
    _sellerCategoriesRequested = true;
    unawaited(_reloadSellerCategories());
  }

  /// Real-mode seller offer state.
  SellerOfferView? _selectedSellerOffer;
  bool _withdrawBusy = false;
  String? _withdrawError;
  String? _withdrawKey;
  String? _withdrawOfferId;

  /// Places boundary for place capture. Null keeps manual entry only.
  PlacesRepository? _placesRepository;

  AppTextSize get textSize => accessibilityPreferences.textSize;

  Color get roleAccent => role == UserRole.buyer
      ? darkMode
            ? HocalistTheme.darkBuyer
            : HocalistTheme.buyer
      : darkMode
      ? HocalistTheme.darkSeller
      : HocalistTheme.seller;
  Color get accent =>
      darkMode ? HocalistTheme.darkPrimary : HocalistTheme.primary;
  bool get publicHocatrends => page == AppPage.hocatrends && !authenticated;
  bool get signedIn => authenticated;
  bool get showGlobalBack => signedIn && !_isBottomNavPage(page);
  bool get _usesIntegratedPageChrome =>
      (page == AppPage.hocatrends && !authenticated) ||
      {
        AppPage.welcome,
        AppPage.buyerSignup,
        AppPage.sellerSignup,
        AppPage.sellerTutorial,
        AppPage.buyerBenefits,
        AppPage.buyerDashboard,
        AppPage.createRequest,
        AppPage.requestSuccess,
        AppPage.buyerRequestDetail,
        AppPage.offersReceived,
        AppPage.buyerOfferDetail,
        AppPage.buyerChat,
        AppPage.buyerConfirmation,
        AppPage.dealRecovery,
        AppPage.buyerReview,
        AppPage.buyerWallet,
        AppPage.sellerDashboard,
        AppPage.sellerStore,
        AppPage.marketplace,
        AppPage.sellerMeets,
        AppPage.sellerChat,
        AppPage.sellerMore,
        AppPage.sellerConversation,
        AppPage.accountSecurity,
        AppPage.accountLifecycle,
      }.contains(page);
  bool get _suppressesGlobalHeader => false;

  ApprovedBuyerNavigation get _approvedBuyerNavigation =>
      ApprovedBuyerNavigation(
        onHome: () => resetTo(AppPage.buyerDashboard),
        onHocatrends: () => resetTo(AppPage.hocatrends),
        onOffers: () => resetTo(AppPage.offersReceived),
        onChats: () => resetTo(AppPage.buyerChats),
        onMore: () => resetTo(AppPage.buyerSupport),
      );

  SellerNavigationCallbacks get _sellerNavigation => SellerNavigationCallbacks(
    onHome: () => resetTo(AppPage.sellerDashboard),
    onStore: () => resetTo(AppPage.sellerStore),
    onMeets: () => resetTo(AppPage.sellerMeets),
    onChats: () => resetTo(AppPage.sellerChat),
    onMore: () => resetTo(AppPage.sellerMore),
  );

  List<_NavItem> get _buyerBottomNavItems => const [
    _NavItem(
      'Home',
      Icons.home_outlined,
      AppPage.buyerDashboard,
      selectedIcon: Icons.home,
      asset: 'assets/buyer_nav/buyer-nav-home.png',
    ),
    _NavItem(
      'Hocatrends',
      Icons.local_fire_department,
      AppPage.hocatrends,
      asset: 'assets/buyer_nav/buyer-nav-hocatrends.png',
    ),
    _NavItem(
      'Offers',
      Icons.sell_outlined,
      AppPage.offersReceived,
      asset: 'assets/buyer_nav/buyer-nav-offers.png',
    ),
    _NavItem(
      'Chats',
      Icons.chat_bubble_outline,
      AppPage.buyerChats,
      asset: 'assets/buyer_nav/buyer-nav-chats.png',
    ),
    _NavItem(
      'More',
      Icons.menu,
      AppPage.buyerSupport,
      asset: 'assets/buyer_nav/buyer-nav-more.png',
    ),
  ];

  List<_NavItem> get _sellerBottomNavItems => const [
    _NavItem('Home', Icons.home_outlined, AppPage.sellerDashboard),
    _NavItem('Store', Icons.storefront_outlined, AppPage.sellerStore),
    _NavItem('Meets', Icons.handshake_outlined, AppPage.sellerMeets),
    _NavItem('Chats', Icons.chat_bubble_outline, AppPage.sellerChat),
    _NavItem('More', Icons.menu, AppPage.sellerMore),
  ];

  bool _isBottomNavPage(AppPage target) {
    final items = role == UserRole.buyer
        ? _buyerBottomNavItems
        : _sellerBottomNavItems;
    return items.any((item) => item.page == target);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = widget.accountSession;
    _placesRepository = createConfiguredPlacesRepository();
    _profileAvatarBackend = createConfiguredProfileAvatarBackend();
    _marketplace = LocalMarketplaceRepository(
      storeBackend: _createStoreBackend(session),
      leadsBackend: _createLeadsBackend(session),
      offersBackend: _createOffersBackend(session),
      requestsBackend: _createRequestsBackend(session),
      buyerOffersBackend: _createBuyerOffersBackend(session),
      chatBackend: _createChatBackend(session),
      sellerOffersBackend: _createSellerOffersBackend(session),
      notificationsBackend: _createNotificationsBackend(session),
      meetingsBackend: _createMeetingsBackend(session),
    );
    _configureChatRefresh();
    _reopenFlow = ReopenFlowCoordinator(
      reopen: ({required requestId, required expectedRevision}) =>
          _marketplace.reopenBuyerRequest(
            requestId: requestId,
            expectedRevision: expectedRevision,
          ),
      sessionUserId: () => widget.accountSession?.userId,
      destinationEpoch: () => _navigationEpoch,
      selectedRequestId: () => _activeRequest?.id,
      discardServerIntent: () => _marketplace.discardReopenIntent(),
    );
    _discoveryBackend = createConfiguredDiscoveryBackend();
    _reviewBackend = createConfiguredReviewBackend();
    if (_discoveryBackend != null) {
      unawaited(_refreshRecommendedLeads());
      unawaited(_refreshHocatrends());
      unawaited(_refreshDiscoveryOrigin());
    }
    _refreshAccountHealth();
    _chatSafety = createConfiguredChatSafetyCoordinator();
    _marketplace.addListener(_onMarketplaceChanged);
    if (_marketplace.isStoreBacked) {
      unawaited(_marketplace.refreshStore());
    }
    if (_marketplace.isLeadsBacked) {
      unawaited(_marketplace.refreshSellerLeads());
    }
    if (_marketplace.isOffersBacked) {
      unawaited(_marketplace.refreshOfferTimezones());
    }
    if (_marketplace.isRequestsBacked) {
      unawaited(_marketplace.refreshBuyerRequests());
      unawaited(_marketplace.refreshRequestCategories());
    }
    if (_marketplace.isNotificationsBacked) {
      unawaited(_marketplace.refreshNotifications());
      unawaited(_marketplace.refreshNotificationPreferences());
    }
    if (_marketplace.isMeetingsBacked) {
      unawaited(_marketplace.refreshMeetings());
    }
    if (session != null) {
      session.addListener(_onAccountSessionChanged);
      _adoptAccountSession(session, initial: true);
      _restoreDevicePreferences();
      if (role == UserRole.buyer && kCommercialReadsEnabled) {
        unawaited(_refreshConfirmedBuyerMeetings());
      }
    } else {
      _restoreSession();
    }
  }

  PushInboxRouter? _pushRouter;
  StreamSubscription<PushInboxSignal>? _pushSubscription;

  Future<void> _refreshRecommendedLeads() async {
    final backend = _discoveryBackend;
    if (backend == null) return;
    setState(() {
      _recommendedLeadsLoading = true;
      _recommendedLeadsError = null;
    });
    try {
      final view = await backend.loadRecommendedLeads();
      if (mounted) setState(() => _recommendedLeads = view);
    } on StoreBackendException catch (error) {
      if (mounted) setState(() => _recommendedLeadsError = error.message);
    } finally {
      if (mounted) setState(() => _recommendedLeadsLoading = false);
    }
  }

  Future<void> _refreshAccountHealth() async {
    final trust = createConfiguredTrustBackend(
      enabled: kTrustReviewEnabled || hocalistLocalWebTest,
    );
    if (trust == null) return;
    final userId = widget.accountSession?.userId;
    setState(() {
      _accountHealthLoading = true;
      _accountHealthError = null;
    });
    try {
      final status = await trust.loadStatus();
      if (!mounted || widget.accountSession?.userId != userId) return;
      setState(() {
        _accountHealth = SellerAccountHealthView(
          emailVerified: status.emailVerified,
          phoneVerified: status.phoneVerified,
          reviewStatus: status.reviewStatus,
          restrictions: status.restrictions
              .map(
                (row) => SellerHealthRestriction(
                  id: row.id,
                  scope: row.scope,
                  reason: row.reason,
                  appealId: row.appealId,
                  appealStatus: row.appealStatus,
                ),
              )
              .toList(growable: false),
        );
      });
    } on TrustUnavailableException catch (error) {
      if (mounted && widget.accountSession?.userId == userId) {
        setState(() => _accountHealthError = error.message);
      }
    } finally {
      if (mounted && widget.accountSession?.userId == userId) {
        setState(() => _accountHealthLoading = false);
      }
    }
  }

  Future<void> _refreshHocatrends() async {
    final backend = _discoveryBackend;
    if (backend == null) return;
    setState(() {
      _hocatrendsLoading = true;
      _hocatrendsError = null;
    });
    try {
      final projection = await backend.loadTrends();
      if (mounted) setState(() => _hocatrends = projection);
    } on StoreBackendException catch (error) {
      if (mounted) setState(() => _hocatrendsError = error.message);
    } finally {
      if (mounted) setState(() => _hocatrendsLoading = false);
    }
  }

  Future<void> _refreshConfirmedMeetings() async {
    if (role != UserRole.seller) return;
    final backend =
        _discoveryBackend ??
        createConfiguredDiscoveryBackend(enabled: kCommercialReadsEnabled);
    if (backend == null) return;
    try {
      final ids = await backend.loadConfirmedMeetingIds();
      if (mounted) setState(() => _confirmedMeetingIds = ids);
    } on StoreBackendException {
      // A missing outcome projection keeps the completed tab honestly empty.
    }
  }

  Future<void> _refreshConfirmedBuyerMeetings() async {
    final session = widget.accountSession;
    if (role != UserRole.buyer || session == null || !kCommercialReadsEnabled) {
      return;
    }
    final backend = createConfiguredCommercialWalletBackend();
    if (backend == null) return;
    final userId = session.userId;
    setState(() {
      _buyerCompletionLoading = true;
      _buyerCompletionError = null;
    });
    try {
      final confirmed = <String>{};
      DateTime? beforeTime;
      String? beforeId;
      // Exhaust the authorized 25-row pages before labelling a meeting
      // upcoming. A partial read could show a completed purchase here again.
      for (var page = 0; page < 20; page++) {
        final rows = await backend.loadSaleHistory(
          beforeTime: beforeTime,
          beforeId: beforeId,
        );
        if (!mounted || widget.accountSession?.userId != userId) return;
        for (final row in rows) {
          final detail = await backend.loadSaleDetail(row.id);
          if (!mounted || widget.accountSession?.userId != userId) return;
          confirmed.add(detail.meetingId);
        }
        if (rows.length < 25) {
          setState(() {
            _confirmedPurchaseMeetings.addAll(confirmed);
            _buyerCompletionLoading = false;
          });
          return;
        }
        beforeTime = rows.last.confirmedAt;
        beforeId = rows.last.id;
      }
      throw StateError('Purchase history exceeded the bounded read.');
    } catch (_) {
      if (mounted && widget.accountSession?.userId == userId) {
        setState(() {
          _buyerCompletionLoading = false;
          _buyerCompletionError = 'Could not verify completed meetings. Retry.';
        });
      }
    }
  }

  Future<void> _refreshDiscoveryOrigin() async {
    final backend = _discoveryBackend;
    if (backend == null) return;
    setState(() => _discoveryOriginLoading = true);
    try {
      final origin = await backend.loadOrigin();
      if (mounted) setState(() => _discoveryOrigin = origin);
    } on StoreBackendException {
      // The editor stays available and will surface its own save errors.
    } finally {
      if (mounted) setState(() => _discoveryOriginLoading = false);
    }
  }

  Future<void> _openTopicSellers(String topicId) async {
    final backend = _discoveryBackend;
    setState(() {
      _selectedTopicId = topicId;
      _topicSellerResults = null;
      _topicSellersError = null;
    });
    go(AppPage.hocatrendsSellers);
    if (backend == null) return;
    setState(() => _topicSellersLoading = true);
    try {
      final results = await backend.loadTopicSellers(topicId);
      if (mounted) setState(() => _topicSellerResults = results);
    } on StoreBackendException catch (error) {
      if (mounted) setState(() => _topicSellersError = error.message);
    } finally {
      if (mounted) setState(() => _topicSellersLoading = false);
    }
  }

  Future<void> _loadSellerReputation(String sellerProfileId) async {
    final backend = _reviewBackend;
    if (backend == null) return;
    final generation = ++_sellerReputationGeneration;
    final userId = widget.accountSession?.userId;
    bool current() =>
        mounted &&
        generation == _sellerReputationGeneration &&
        userId == widget.accountSession?.userId;
    setState(() {
      _sellerReputationFor = sellerProfileId;
      _sellerReputation = null;
      _sellerReputationError = null;
      _sellerReputationLoading = true;
    });
    try {
      final reputation = await backend.loadReputation(sellerProfileId);
      if (current()) setState(() => _sellerReputation = reputation);
    } on StoreBackendException catch (error) {
      if (current()) setState(() => _sellerReputationError = error.message);
    } finally {
      if (current()) setState(() => _sellerReputationLoading = false);
    }
  }

  Future<void> _reopenCurrentRequest() async {
    final request = _currentBuyerRequest;
    if (request == null) return;
    final outcome = await _reopenFlow.reopenRequest(
      requestId: request.id,
      expectedRevision: request.stamp.revision,
    );
    if (!mounted) return;
    // Only a confirmed, still-current result may adopt the record and navigate.
    // The page-feedback mapping keeps stale failures, replaced accounts and
    // current failures silent; failures render the coordinator's error state.
    if (reopenPageMayAdopt(outcome)) {
      final adopted = outcome as ReopenFlowAdopted;
      setState(() {
        _activeRequest = adopted.request;
        requestTitle = adopted.request.draft.title;
        requestBudget = _formatRequestBudget(adopted.request.draft);
        offerSelected = false;
        meetingConfirmed = false;
        dealFailed = true;
        requestReopened = true;
      });
      _saveSession();
      resetTo(AppPage.buyerRequestDetail);
    }
    final feedback = reopenPageFeedback(outcome);
    if (feedback != null) showMessage(feedback);
  }

  void _discardReopenIntent() {
    _reopenFlow.discard();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final push = PushServiceScope.read(context);
    if (_pushRouter != null || push == null) {
      return;
    }
    _pushRouter = PushInboxRouter(
      identity: () => widget.accountSession?.phase == AccountAccessPhase.active
          ? widget.accountSession?.userId
          : null,
      canOpen: _canOpenNotification,
      lookup: (id) async {
        final row = await push.fetchNotification(id);
        return row == null ? null : decodeNotificationItemJson(row, 'push');
      },
      refresh: () => _marketplace.refreshNotifications(),
      open: (item) async {
        await _openNotification(item);
        if (mounted) await _marketplace.markNotificationRead(item.id);
      },
      unavailable: () {
        if (mounted) {
          showMessage(
            'This notification is unavailable. Open your inbox to refresh.',
          );
        }
      },
    );
    _pushSubscription = push.signals.listen((signal) {
      unawaited(_pushRouter!.receive(signal));
    });
    // A cold-start tap that arrived before authentication is replayed now and
    // whenever the account session becomes active.
    unawaited(_pushRouter!.onAuthenticated());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(push.start().catchError((Object _) {}));
    });
  }

  /// Real Store backend when a configured Supabase seller session exists.
  /// Returns null in prototype mode or for a buyer identity.
  MarketplaceStoreBackend? _createStoreBackend(
    HocalistAccountController? session,
  ) {
    final userId = session?.userId;
    if (session == null ||
        userId == null ||
        session.selectedRole != HocalistRole.seller) {
      return null;
    }
    return createConfiguredMarketplaceStoreBackend(sellerUserId: userId);
  }

  /// Real leads backend for the same seller-session conditions.
  MarketplaceLeadsBackend? _createLeadsBackend(
    HocalistAccountController? session,
  ) {
    final userId = session?.userId;
    if (session == null ||
        userId == null ||
        session.selectedRole != HocalistRole.seller) {
      return null;
    }
    return createConfiguredMarketplaceLeadsBackend(sellerUserId: userId);
  }

  /// Real offers backend for the same seller-session conditions.
  MarketplaceOffersBackend? _createOffersBackend(
    HocalistAccountController? session,
  ) {
    if (session == null || session.selectedRole != HocalistRole.seller) {
      return null;
    }
    return createConfiguredMarketplaceOffersBackend();
  }

  /// Real requests backend when a configured buyer session exists.
  MarketplaceRequestsBackend? _createRequestsBackend(
    HocalistAccountController? session,
  ) {
    final userId = session?.userId;
    if (session == null ||
        userId == null ||
        session.selectedRole != HocalistRole.buyer) {
      return null;
    }
    return createConfiguredMarketplaceRequestsBackend(buyerUserId: userId);
  }

  /// Real buyer offers backend when a configured buyer session exists.
  MarketplaceBuyerOffersBackend? _createBuyerOffersBackend(
    HocalistAccountController? session,
  ) {
    if (session == null || session.selectedRole != HocalistRole.buyer) {
      return null;
    }
    return createConfiguredMarketplaceBuyerOffersBackend();
  }

  /// Real chat backend for any configured session with an identity.
  MarketplaceChatBackend? _createChatBackend(
    HocalistAccountController? session,
  ) {
    final userId = session?.userId;
    if (session == null || userId == null) return null;
    return createConfiguredMarketplaceChatBackend(userId: userId);
  }

  /// Chat block/unblock and server-side search for the active conversation.
  /// Null in prototype mode; the widgets keep their local behavior then.
  ChatSafetyCoordinator? _chatSafety;
  ConversationBlockState? _conversationBlockState;
  String? _conversationBlockConversationId;
  String? _conversationBlockLoadingFor;
  bool _blockWritePending = false;
  bool _conversationHadReadError = false;

  void _onMarketplaceChanged() {
    _syncChatLiveConversation();
    final active = _marketplace.activeConversationId;
    final readFailed = _marketplace.chatMessagesError != null;
    final readRecovered = _conversationHadReadError && !readFailed;
    _conversationHadReadError = readFailed;
    if (active != null &&
        (readFailed || readRecovered) &&
        active != _conversationBlockLoadingFor) {
      unawaited(_loadConversationBlockState(active));
    }
    if (active == _conversationBlockConversationId ||
        active == _conversationBlockLoadingFor) {
      return;
    }
    _conversationBlockState = null;
    _conversationBlockConversationId = active;
    if (active != null) unawaited(_loadConversationBlockState(active));
  }

  Future<void> _loadConversationBlockState(String conversationId) async {
    final safety = _chatSafety;
    if (safety == null) return;
    _conversationBlockLoadingFor = conversationId;
    try {
      final state = await safety.loadBlockState(conversationId);
      if (!mounted ||
          _chatSafety != safety ||
          _marketplace.activeConversationId != conversationId) {
        return;
      }
      setState(() {
        _conversationBlockState = state;
        _conversationBlockConversationId = conversationId;
      });
    } finally {
      if (_conversationBlockLoadingFor == conversationId) {
        _conversationBlockLoadingFor = null;
      }
    }
  }

  /// Loads the participant meetings for the open conversation and projects
  /// them onto the approved Active Deals cards. No deal is invented: a missing
  /// offer summary keeps an honest unavailable label, and an empty result is
  /// rendered as "no active deals".
  void _scheduleConversationDealsLoad({bool force = false}) {
    if (widget.accountSession == null || !_marketplace.isMeetingsBacked) return;
    final conversationId = _marketplace.activeConversationId;
    if (conversationId == null) return;
    if (!force && _conversationDealsFor == conversationId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadConversationDeals(force: force));
    });
  }

  Future<void> _loadConversationDeals({bool force = false}) async {
    if (!_marketplace.isMeetingsBacked) return;
    final conversationId = _marketplace.activeConversationId;
    if (conversationId == null) return;
    if (!force &&
        _conversationDealsFor == conversationId &&
        (_conversationDealsLoading || _conversationDeals != null)) {
      return;
    }
    final generation = ++_conversationDealsGeneration;
    setState(() {
      _conversationDealsFor = conversationId;
      _conversationDealsLoading = true;
      _conversationDealsTruncated = false;
      _conversationDealsError = null;
      _conversationDeals = null;
      _previousConversationDeals = null;
    });
    try {
      // Direct entry from an accepted offer or meeting may bypass the inbox.
      // Load the participant projection before exposing names/profile actions.
      await _marketplace.refreshChatInbox();
      if (!mounted ||
          generation != _conversationDealsGeneration ||
          _marketplace.activeConversationId != conversationId) {
        return;
      }
      final summary = _marketplace.chatInbox
          .where((row) => row.conversation.id == conversationId)
          .firstOrNull;
      if (summary != null) {
        setState(
          () => _chatCounterpart = (
            name: summary.counterpartDisplayName,
            profileId: summary.counterpartProfileId,
          ),
        );
      }
      final result = await collectConversationMeetings(
        _marketplace,
        conversationId: conversationId,
      );
      final selectedOffer =
          result.matches.isEmpty && _marketplace.meetingsError == null
          ? await _marketplace.loadActiveConversationOffer()
          : null;
      if (!mounted ||
          _conversationDealsFor != conversationId ||
          generation != _conversationDealsGeneration) {
        return;
      }
      Set<String>? completed;
      String? completionError;
      if (kCommercialReadsEnabled) {
        try {
          if (role == UserRole.buyer) {
            await _refreshConfirmedBuyerMeetings();
            if (_buyerCompletionError != null) {
              throw StateError('Completion read failed');
            }
            completed = Set.of(_confirmedPurchaseMeetings);
          } else {
            final backend =
                _discoveryBackend ??
                createConfiguredDiscoveryBackend(enabled: true);
            if (backend == null) {
              throw StateError('Completion read unavailable');
            }
            completed = await backend.loadConfirmedMeetingIds();
          }
        } catch (_) {
          completionError =
              'Purchase history could not be verified. These meeting records may include completed deals. Retry to refresh their status.';
        }
      }
      if (!mounted ||
          _conversationDealsFor != conversationId ||
          generation != _conversationDealsGeneration) {
        return;
      }
      final groups = ConversationDealGroups(result.matches, completed);
      setState(() {
        _conversationDealsError = _marketplace.meetingsError ?? completionError;
        _conversationDealsTruncated = result.truncated;
        _conversationDeals = groups.active
            .map((meeting) => _dealViewFor(meeting))
            .toList(growable: false);
        if (selectedOffer != null &&
            selectedOffer.status == OfferStatus.selected &&
            selectedOffer.conversationId == conversationId) {
          _conversationDeals = [
            ApprovedDealView.fromSelectedOffer(selectedOffer),
          ];
        }
        _previousConversationDeals = groups.previous
            ?.map(
              (meeting) => _dealViewFor(
                meeting,
                completed: completed!.contains(meeting.meetingId),
              ),
            )
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted &&
          _conversationDealsFor == conversationId &&
          generation == _conversationDealsGeneration) {
        setState(
          () => _conversationDealsError =
              'Could not verify conversation deals. Retry.',
        );
      }
    } finally {
      if (mounted &&
          _conversationDealsFor == conversationId &&
          generation == _conversationDealsGeneration) {
        setState(() => _conversationDealsLoading = false);
      }
    }
  }

  Future<void> _openConversationDeal(String id) async {
    final deal = _conversationDeals?.where((row) => row.id == id).firstOrNull;
    if (deal != null && deal.meetingId == null) {
      await _openConversationMeeting();
      return;
    }
    await _openMeetingById(id);
  }

  ApprovedDealView _dealViewFor(MeetingView meeting, {bool completed = false}) {
    final summary = meeting.offerSummary;
    final accepted = meeting.acceptedSchedule;
    final pending = meeting.pendingSchedule;
    final schedule = accepted ?? pending;
    final (statusLabel, statusTone) = completed
        ? ('PIN confirmed', BuyerNoticeTone.success)
        : meeting.isCancelled
        ? ('Cancelled', BuyerNoticeTone.error)
        : pending != null && accepted != null
        ? ('Reschedule proposed', BuyerNoticeTone.warning)
        : pending != null
        ? ('Meeting proposed', BuyerNoticeTone.brand)
        : accepted != null
        ? ('Meeting set', BuyerNoticeTone.success)
        : ('Offer accepted', BuyerNoticeTone.brand);
    return ApprovedDealView(
      meetingId: meeting.meetingId,
      title: summary?.title ?? 'Deal terms unavailable',
      priceLabel: summary?.priceLabel ?? 'Price unavailable',
      statusLabel: statusLabel,
      statusTone: statusTone,
      scheduleLabel: schedule == null
          ? null
          : '${schedule.date} ${schedule.startTime}',
      zoneLabel: schedule?.timezoneId,
      placeLabel: schedule?.placeLabel,
      pendingLabel: pending == null || pending == accepted
          ? null
          : 'New time proposed: ${pending.date} ${pending.startTime}',
      purchaseSelected: meeting.purchaseSelected,
    );
  }

  Future<bool> _setConversationBlocked(bool blocked) async {
    final safety = _chatSafety;
    final conversationId = _marketplace.activeConversationId;
    if (safety == null || conversationId == null || _blockWritePending) {
      return false;
    }
    _blockWritePending = true;
    try {
      final acknowledged = await safety.setBlocked(conversationId, blocked);
      if (!mounted ||
          _marketplace.activeConversationId != conversationId ||
          !acknowledged) {
        return acknowledged;
      }
      final state = await safety.loadBlockState(conversationId);
      if (!mounted || _marketplace.activeConversationId != conversationId) {
        return acknowledged;
      }
      setState(() {
        _conversationBlockState = state;
        _conversationBlockConversationId = conversationId;
      });
      return acknowledged;
    } finally {
      _blockWritePending = false;
    }
  }

  ConversationBlockState? get _activeBlockState =>
      _conversationBlockConversationId == _marketplace.activeConversationId
      ? _conversationBlockState
      : null;

  Future<PageSlice<ChatSearchHit>> _searchChatMessages(
    String query,
    String? cursor,
  ) async {
    final safety = _chatSafety;
    final conversationId = _marketplace.activeConversationId;
    if (safety == null || conversationId == null) {
      throw const ChatSafetyException(
        'unavailable',
        'Search is unavailable right now.',
      );
    }
    return safety.searchMessages(
      conversationId: conversationId,
      query: query,
      cursor: cursor,
    );
  }

  Future<PageSlice<ConversationSummary>> _searchChatConversations(
    String query,
  ) async {
    final safety = _chatSafety;
    if (safety == null) {
      throw const ChatSafetyException(
        'unavailable',
        'Search is unavailable right now.',
      );
    }
    return safety.searchConversations(query: query);
  }

  bool _canOpenNotification(NotificationInboxItem item) {
    if (widget.accountSession?.phase != AccountAccessPhase.active) return false;
    final destination = NotificationDestination.fromInbox(item);
    if (destination == null) return false;
    switch (destination.kind) {
      case NotificationDestinationKind.offer:
        return role == UserRole.seller
            ? _marketplace.isSellerOffersBacked
            : _marketplace.isBuyerOffersBacked;
      case NotificationDestinationKind.chat:
        return _marketplace.isChatBacked;
      case NotificationDestinationKind.meeting:
        return _marketplace.isMeetingsBacked;
      case NotificationDestinationKind.billing:
      case NotificationDestinationKind.account:
        return true;
    }
  }

  /// Real seller offers backend when a configured seller session exists.
  MarketplaceSellerOffersBackend? _createSellerOffersBackend(
    HocalistAccountController? session,
  ) {
    final userId = session?.userId;
    if (session == null ||
        userId == null ||
        session.selectedRole != HocalistRole.seller) {
      return null;
    }
    return createConfiguredMarketplaceSellerOffersBackend(sellerUserId: userId);
  }

  /// Real notification backend for any configured session with an identity.
  MarketplaceNotificationsBackend? _createNotificationsBackend(
    HocalistAccountController? session,
  ) {
    if (session?.userId == null) return null;
    return createConfiguredMarketplaceNotificationsBackend();
  }

  /// Real meetings backend for any configured session with an identity.
  MarketplaceMeetingsBackend? _createMeetingsBackend(
    HocalistAccountController? session,
  ) {
    if (session?.userId == null) return null;
    return createConfiguredMarketplaceMeetingsBackend();
  }

  /// Attaches the real marketplace backends when a session becomes a seller
  /// or buyer after the initial build (the app shell is keyed by identity, not
  /// role). Callers are already inside a state update, so this only swaps the
  /// repository.
  void _attachStoreBackendIfNeeded() {
    final session = widget.accountSession;
    final needsSeller =
        session?.selectedRole == HocalistRole.seller &&
        !(_marketplace.isStoreBacked &&
            _marketplace.isLeadsBacked &&
            _marketplace.isOffersBacked &&
            _marketplace.isSellerOffersBacked);
    final needsBuyer =
        session?.selectedRole == HocalistRole.buyer &&
        !(_marketplace.isRequestsBacked && _marketplace.isBuyerOffersBacked);
    final needsChat = session?.userId != null && !_marketplace.isChatBacked;
    if (!needsSeller && !needsBuyer && !needsChat) return;
    final storeBackend = needsSeller ? _createStoreBackend(session) : null;
    final leadsBackend = needsSeller ? _createLeadsBackend(session) : null;
    final offersBackend = needsSeller ? _createOffersBackend(session) : null;
    final requestsBackend = needsBuyer ? _createRequestsBackend(session) : null;
    final buyerOffersBackend = needsBuyer
        ? _createBuyerOffersBackend(session)
        : null;
    final chatBackend = needsChat ? _createChatBackend(session) : null;
    final sellerOffersBackend = needsSeller
        ? _createSellerOffersBackend(session)
        : null;
    final notificationsBackend = needsChat
        ? _createNotificationsBackend(session)
        : null;
    final meetingsBackend = needsChat ? _createMeetingsBackend(session) : null;
    if (storeBackend == null &&
        leadsBackend == null &&
        offersBackend == null &&
        requestsBackend == null &&
        buyerOffersBackend == null &&
        chatBackend == null &&
        sellerOffersBackend == null &&
        notificationsBackend == null &&
        meetingsBackend == null) {
      return;
    }
    final previous = _marketplace;
    previous.removeListener(_onMarketplaceChanged);
    _marketplace = LocalMarketplaceRepository(
      storeBackend: storeBackend,
      leadsBackend: leadsBackend,
      offersBackend: offersBackend,
      requestsBackend: requestsBackend,
      buyerOffersBackend: buyerOffersBackend,
      chatBackend: chatBackend,
      sellerOffersBackend: sellerOffersBackend,
      notificationsBackend: notificationsBackend,
      meetingsBackend: meetingsBackend,
    );
    _marketplace.addListener(_onMarketplaceChanged);
    _configureChatRefresh();
    if (storeBackend != null) unawaited(_marketplace.refreshStore());
    if (leadsBackend != null) unawaited(_marketplace.refreshSellerLeads());
    if (offersBackend != null) {
      unawaited(_marketplace.refreshOfferTimezones());
    }
    if (requestsBackend != null) {
      unawaited(_marketplace.refreshBuyerRequests());
      unawaited(_marketplace.refreshRequestCategories());
    }
    if (buyerOffersBackend != null) {
      final request = _currentBuyerRequest;
      if (request != null) {
        unawaited(_marketplace.refreshBuyerOffers(request.id));
      }
    }
    if (chatBackend != null) {
      unawaited(_marketplace.refreshChatInbox());
    }
    if (notificationsBackend != null) {
      unawaited(_marketplace.refreshNotifications());
      unawaited(_marketplace.refreshNotificationPreferences());
    }
    if (meetingsBackend != null) {
      unawaited(_marketplace.refreshMeetings());
    }
    if (sellerOffersBackend != null) {
      unawaited(_marketplace.refreshSellerOffers());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  @override
  void dispose() {
    _chatRefreshTimer?.cancel();
    _stopChatLiveUpdates();
    WidgetsBinding.instance.removeObserver(this);
    _pushRouter?.dispose();
    unawaited(_pushSubscription?.cancel());
    widget.accountSession?.removeListener(_onAccountSessionChanged);
    _reopenFlow.dispose();
    _marketplace.removeListener(_onMarketplaceChanged);
    _marketplace.dispose();
    super.dispose();
  }

  bool get _realAccountMode => widget.accountSession != null;

  void _onAccountSessionChanged() {
    final session = widget.accountSession;
    if (!mounted || session == null) return;
    if (session.phase != AccountAccessPhase.active) return;
    setState(() => _adoptAccountSession(session));
    final router = _pushRouter;
    if (router != null) unawaited(router.onAuthenticated());
  }

  void _adoptAccountSession(
    HocalistAccountController session, {
    bool initial = false,
  }) {
    final wasSeller = role == UserRole.seller;
    role = session.selectedRole == HocalistRole.seller
        ? UserRole.seller
        : UserRole.buyer;
    authenticated = true;
    if (!initial) {
      _attachStoreBackendIfNeeded();
    }
    if (initial) {
      // A freshly authorized real identity starts on its own dashboard, never
      // on the signed-out welcome page or a previous identity's screen.
      history.clear();
      page = role == UserRole.seller
          ? AppPage.sellerDashboard
          : AppPage.buyerDashboard;
    }
    final displayName = session.profile?.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      if (role == UserRole.buyer) {
        buyerName = displayName;
      } else {
        sellerName = displayName;
      }
    }
    if (role == UserRole.seller &&
        (initial || !wasSeller) &&
        (_discoveryBackend != null || kCommercialReadsEnabled)) {
      unawaited(_refreshConfirmedMeetings());
    }
    unawaited(_loadOwnAvatar());
  }

  /// Loads the selected membership's avatar reference for the photo editors.
  /// Display is best-effort: a failure keeps the approved placeholder and
  /// never blocks the rest of the account screen.
  Future<void> _loadOwnAvatar() async {
    final backend = _profileAvatarBackend;
    final profile = widget.accountSession?.profile;
    if (backend == null || profile == null) return;
    final membershipId = profile.membershipId;
    if (mounted && _profileAvatarMediaId != null) {
      setState(() => _profileAvatarMediaId = null);
    }
    try {
      final reference = await backend.loadMemberAvatar(membershipId);
      if (!mounted ||
          widget.accountSession?.profile?.membershipId != membershipId) {
        return;
      }
      setState(() => _profileAvatarMediaId = reference.imageMediaId);
    } on ProfileAvatarUnavailableException {
      // Keep the placeholder; the editor still works for other fields.
    }
  }

  Future<void> _changeBuyerProfileAvatar(BuyerProfilePhotoAction action) =>
      _changeProfileAvatar(
        role: 'buyer',
        remove: action == BuyerProfilePhotoAction.remove,
        camera: action == BuyerProfilePhotoAction.camera,
      );

  Future<void> _changeSellerProfileAvatar(SellerProfilePhotoAction action) =>
      _changeProfileAvatar(
        role: 'seller',
        remove: action == SellerProfilePhotoAction.remove,
        camera: action == SellerProfilePhotoAction.camera,
      );

  /// Picks or removes a profile photo. Without a deployed avatar backend the
  /// approved prototype acknowledgement (or the honest real-mode notice) is
  /// preserved unchanged.
  Future<void> _changeProfileAvatar({
    required String role,
    required bool remove,
    required bool camera,
  }) async {
    final backend = _profileAvatarBackend;
    final profile = widget.accountSession?.profile;
    final avatarUserId = widget.accountSession?.userId;
    bool currentAvatarSession() =>
        mounted &&
        identical(backend, _profileAvatarBackend) &&
        widget.accountSession?.userId == avatarUserId &&
        widget.accountSession?.profile?.membershipId == profile?.membershipId;
    if (backend == null || profile == null) {
      showMessage(
        _realAccountMode
            ? 'Profile photo changes are not available yet.'
            : remove
            ? 'Profile picture removed.'
            : camera
            ? 'Camera opened.'
            : 'Photo library opened.',
      );
      return;
    }
    if (_profileAvatarBusy) return;
    if (profile.role.name != role) {
      showMessage('Switch to this account role to change its photo.');
      return;
    }
    if (_profileAvatarIntents.containsKey(role)) {
      showMessage('Retry or discard the earlier photo change first.');
      return;
    }
    if (remove) {
      await _applyProfileAvatar(
        role: role,
        mediaId: null,
        expectedRevision: profile.stamp.revision,
      );
      return;
    }
    final upload = configuredImageUpload('profile');
    if (upload == null) {
      showMessage('Photo upload is unavailable. Try again later.');
      return;
    }
    final XFile? picked;
    try {
      if (camera && kIsWeb) {
        final bytes = await showDialog<Uint8List>(
          context: appNavigatorKey.currentContext!,
          builder: (_) =>
              PhotoCameraPage(seller: role == 'seller', autoStart: true),
        );
        picked = bytes == null
            ? null
            : XFile.fromData(
                bytes,
                mimeType: 'image/jpeg',
                name: 'profile.jpg',
              );
      } else {
        picked = await ImagePicker().pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
      }
    } catch (_) {
      showMessage('The photo picker is unavailable on this device.');
      return;
    }
    if (picked == null || !currentAvatarSession()) return;
    setState(() => _profileAvatarBusy = true);
    try {
      final bytes = preparePrivatePhoto(await picked.readAsBytes());
      if (!currentAvatarSession()) return;
      if (bytes.length > 4 * 1024 * 1024) {
        if (mounted) setState(() => _profileAvatarBusy = false);
        showMessage('Choose a photo smaller than 4 MB.');
        return;
      }
      final mediaId = await upload(bytes, newMediaUploadKey());
      if (!currentAvatarSession()) {
        if (mounted) setState(() => _profileAvatarBusy = false);
        return;
      }
      await _applyProfileAvatar(
        role: role,
        mediaId: mediaId,
        expectedRevision: profile.stamp.revision,
      );
    } catch (error) {
      if (mounted) setState(() => _profileAvatarBusy = false);
      showMessage(photoUploadFailureMessage(error));
    }
  }

  /// Applies one avatar intent at the carried revision. An uncertain outcome
  /// keeps the same role-scoped operation key so a retry replays the committed
  /// result; a new intent is blocked until the retained one is reconciled.
  Future<void> _applyProfileAvatar({
    required String role,
    required String? mediaId,
    required int expectedRevision,
  }) async {
    final backend = _profileAvatarBackend;
    if (backend == null) return;
    final pending = _profileAvatarIntents[role];
    final matchesPending =
        pending != null &&
        pending.mediaId == mediaId &&
        pending.revision == expectedRevision;
    final key = matchesPending
        ? pending.key
        : LocalMarketplaceRepository.newStoreOperationKey('avatar');
    setState(() {
      _profileAvatarIntents[role] = (
        key: key,
        mediaId: mediaId,
        revision: expectedRevision,
      );
      _profileAvatarBusy = true;
    });
    try {
      final reference = await backend.updateAvatar(
        role: role,
        operationKey: key,
        expectedRevision: expectedRevision,
        mediaId: mediaId,
      );
      if (!mounted) return;
      _profileAvatarIntents.remove(role);
      setState(() {
        _profileAvatarBusy = false;
        _profileAvatarMediaId = reference.imageMediaId;
      });
      showMessage(
        mediaId == null ? 'Profile picture removed.' : 'Profile photo updated.',
      );
      unawaited(widget.accountSession?.refresh() ?? Future<void>.value());
    } on ProfileAvatarConflictException {
      if (!mounted) return;
      _profileAvatarIntents.remove(role);
      setState(() => _profileAvatarBusy = false);
      showMessage(
        'Your profile changed on another device. Reloading the current values.',
      );
      unawaited(widget.accountSession?.refresh() ?? Future<void>.value());
    } on ProfileAvatarUnavailableException catch (error) {
      if (!mounted) return;
      if (!error.outcomeUncertain) _profileAvatarIntents.remove(role);
      setState(() => _profileAvatarBusy = false);
      showMessage(error.message);
    }
  }

  /// Replays the retained avatar intent for [role] without uploading again.
  Future<void> _retryProfileAvatar(String role) async {
    final intent = _profileAvatarIntents[role];
    if (intent == null || _profileAvatarBusy) return;
    await _applyProfileAvatar(
      role: role,
      mediaId: intent.mediaId,
      expectedRevision: intent.revision,
    );
  }

  void _discardProfileAvatar(String role) {
    if (_profileAvatarIntents.remove(role) == null) return;
    setState(() => _profileAvatarBusy = false);
    showMessage('Unconfirmed photo change discarded.');
  }

  /// Real mode restores only device-level preferences from local storage;
  /// identity always comes from the provider session.
  Future<void> _restoreDevicePreferences() async {
    final sessionUser = widget.accountSession?.userId;
    final sessionRole = role;
    final navigationEpoch = _navigationEpoch;
    final data = await _storage.load();
    if (!mounted || data == null) return;
    final prefs = await SharedPreferences.getInstance();
    final savedPage = prefs.getString(
      'hocalist.navigation.$sessionUser.${sessionRole.name}',
    );
    if (!mounted ||
        widget.accountSession?.userId != sessionUser ||
        role != sessionRole ||
        _navigationEpoch != navigationEpoch) {
      return;
    }
    setState(() {
      darkMode = data.darkMode;
      accessibilityPreferences = data.accessibilityPreferences;
      restoredSession = true;
      final destination = AppPage.values
          .where((p) => p.name == savedPage)
          .firstOrNull;
      if (destination != null &&
          _restorableAccountPages.contains(destination)) {
        page = destination;
      }
    });
    final destination = AppPage.values
        .where((p) => p.name == savedPage)
        .firstOrNull;
    if (destination != null && _restorableAccountPages.contains(destination)) {
      _refreshDestinationData(destination);
    }
    final rawContext = prefs.getString(
      'hocalist.navigation.$sessionUser.${sessionRole.name}.context',
    );
    if (destination == null ||
        rawContext == null ||
        _restorableAccountPages.contains(destination)) {
      return;
    }
    bool current() =>
        mounted &&
        widget.accountSession?.userId == sessionUser &&
        role == sessionRole &&
        _navigationEpoch == navigationEpoch;
    try {
      final context = jsonDecode(rawContext) as Map<String, dynamic>;
      if (context['page'] != savedPage) return;
      final conversationId = context['conversation'] as String?;
      final requestId = context['request'] as String?;
      final offerId = context['offer'] as String?;
      final meetingId = context['meeting'] as String?;
      if ({
            AppPage.buyerChat,
            AppPage.sellerConversation,
            AppPage.buyerPublicProfile,
            AppPage.sellerPublicProfile,
          }.contains(destination) &&
          conversationId != null &&
          !(destination == AppPage.sellerPublicProfile &&
              context['sellerProfileSource'] == 'offer')) {
        await _marketplace.openChatConversation(conversationId);
        if (!current() || _marketplace.chatMessagesError != null) return;
        await _marketplace.refreshChatInbox();
        if (!current()) return;
        final summary = _marketplace.chatInbox
            .where((row) => row.conversation.id == conversationId)
            .firstOrNull;
        if (summary != null) {
          final thread = ChatThreadView.fromSummary(
            summary,
            viewerUserId: sessionUser ?? '',
          );
          _chatCounterpart = (
            name: thread.counterpartName,
            profileId: thread.counterpartProfileId,
          );
        }
        setState(() {
          _sellerProfileFromConversation =
              destination == AppPage.sellerPublicProfile;
          page = destination;
        });
        unawaited(_loadConversationDeals(force: true));
      } else if ({
            AppPage.buyerRequestDetail,
            AppPage.offersReceived,
            AppPage.buyerOfferDetail,
            AppPage.sellerPublicProfile,
          }.contains(destination) &&
          requestId != null) {
        await _marketplace.refreshBuyerRequests();
        if (!current()) return;
        final request = _marketplace.buyerRequests
            .where((row) => row.id == requestId)
            .firstOrNull;
        if (request == null) return;
        if (offerId != null || destination == AppPage.offersReceived) {
          await _marketplace.refreshBuyerOffers(requestId);
          if (!current()) return;
        }
        final offer = _marketplace.buyerOffers
            .where((row) => row.id == offerId)
            .firstOrNull;
        if (offerId != null && offer == null) return;
        setState(() {
          _activeRequest = request;
          requestTitle = request.draft.title;
          requestBudget = _formatRequestBudget(request.draft);
          if (offer != null) {
            _selectedBuyerOffer = BuyerOfferView.fromOffer(offer);
          }
          page = destination;
        });
      } else if (destination == AppPage.meetingDetails) {
        if (meetingId == null && _marketplace.isMeetingsBacked) {
          await _marketplace.refreshMeetings();
          if (current()) {
            setState(() => page = destination);
            unawaited(_refreshConfirmedBuyerMeetings());
          }
        } else if (meetingId != null) {
          final meeting = await _marketplace.loadMeeting(meetingId);
          if (current() && meeting != null) setState(() => page = destination);
        }
      }
    } catch (_) {
      // Invalid/stale navigation never restores another identity or fixture data.
    }
  }

  static const _restorableAccountPages = {
    AppPage.buyerDashboard,
    AppPage.buyerChats,
    AppPage.buyerWallet,
    AppPage.buyerRewardsDetail,
    AppPage.editProfile,
    AppPage.buyerSettings,
    AppPage.sellerDashboard,
    AppPage.sellerStore,
    AppPage.sellerMeets,
    AppPage.sellerProfile,
    AppPage.sellerBilling,
    AppPage.sellerSettings,
    AppPage.sellerMore,
    AppPage.marketplace,
    AppPage.sellerChat,
    AppPage.sellerNotifications,
    AppPage.notifications,
    AppPage.savedItems,
    AppPage.helpSupport,
    AppPage.buyerSupport,
    AppPage.accountSecurity,
    AppPage.accountLifecycle,
    AppPage.hocatrends,
    AppPage.recentActivity,
    AppPage.sellerOfferHistory,
    AppPage.buyerNotificationPreferences,
    AppPage.sellerNotificationPreferences,
    AppPage.accessibility,
    AppPage.safetyGuide,
    AppPage.reportIssue,
    AppPage.withdrawal,
    AppPage.sellerPaymentMethod,
    AppPage.sellerVerification,
  };

  Future<void> _restoreSession() async {
    final data = await _storage.load();
    if (!mounted || data == null) return;
    setState(() {
      role = data.role;
      authenticated = data.authenticated;
      page = _upgradedDestination(data.page, forRole: data.role);
      buyerName = data.buyerName;
      sellerName = data.sellerName;
      requestTitle = data.requestTitle;
      requestBudget = data.requestBudget;
      offerPrice = data.offerPrice;
      requestPosted = data.requestPosted;
      sellerOfferSent = data.sellerOfferSent;
      offerSelected = data.offerSelected;
      meetingConfirmed = data.meetingConfirmed;
      dealFailed = data.dealFailed;
      requestReopened = data.requestReopened;
      dealCompleted = data.dealCompleted;
      withdrawalRequested = data.withdrawalRequested;
      dealSupportReviewRequested = data.dealSupportReviewRequested;
      reportSubmitted = data.reportSubmitted;
      darkMode = data.darkMode;
      accessibilityPreferences = data.accessibilityPreferences;
      _marketplace.restoreSnapshot(data.marketplaceSnapshot);
      restoredSession = true;
    });
  }

  Future<void> _saveSession() async {
    final userId = widget.accountSession?.userId;
    final savedRole = role;
    final savedPage = page;
    final savedContext = jsonEncode({
      'page': savedPage.name,
      'conversation': _marketplace.activeConversationId,
      'request': _activeRequest?.id,
      'offer': _selectedBuyerOffer?.offerId,
      'meeting': _marketplace.meetingDetail?.meetingId,
      'sellerProfileSource': _sellerProfileFromConversation
          ? 'conversation'
          : 'offer',
    });
    if (_realAccountMode && userId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'hocalist.navigation.$userId.${savedRole.name}',
        savedPage.name,
      );
      await prefs.setString(
        'hocalist.navigation.$userId.${savedRole.name}.context',
        savedContext,
      );
    }
    return _storage.save(
      _LocalSessionData(
        role: role,
        // Real identity never writes the prototype authenticated flag, so a
        // later prototype run cannot restore a simulated signed-in session.
        authenticated: _realAccountMode ? false : authenticated,
        page: page,
        buyerName: buyerName,
        sellerName: sellerName,
        requestTitle: requestTitle,
        requestBudget: requestBudget,
        offerPrice: offerPrice,
        requestPosted: requestPosted,
        sellerOfferSent: sellerOfferSent,
        offerSelected: offerSelected,
        meetingConfirmed: meetingConfirmed,
        dealFailed: dealFailed,
        requestReopened: requestReopened,
        dealCompleted: dealCompleted,
        withdrawalRequested: withdrawalRequested,
        dealSupportReviewRequested: dealSupportReviewRequested,
        reportSubmitted: reportSubmitted,
        darkMode: darkMode,
        accessibilityPreferences: accessibilityPreferences,
        marketplaceSnapshot: _marketplace.encodeSnapshot(),
      ),
    );
  }

  void showMessage(String message) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void updateThemeMode(bool value) {
    setState(() => darkMode = value);
    _saveSession();
    showMessage(value ? 'Dark mode enabled.' : 'Light mode enabled.');
  }

  void updateTextSize(AppTextSize value) {
    setState(() {
      accessibilityPreferences = accessibilityPreferences.copyWith(
        textSize: value,
      );
    });
    _saveSession();
    showMessage('Text size set to ${value.label}.');
  }

  void applyAccessibilityPreferences(AccessibilityPreferences value) {
    setState(() => accessibilityPreferences = value);
    _saveSession();
    showMessage('Accessibility preferences applied.');
  }

  void go(AppPage next) {
    final destination = _upgradedDestination(next);
    setState(() {
      _navigationEpoch += 1;
      if (destination == AppPage.createRequest &&
          page != AppPage.createRequest &&
          widget.accountSession != null) {
        _newRequestTitle = '';
        _newRequestBudget = '';
      }
      if (destination == AppPage.reportIssue) {
        _supportConversationId =
            _marketplace.isChatBacked &&
                (page == AppPage.buyerChat ||
                    page == AppPage.sellerConversation)
            ? _marketplace.activeConversationId
            : null;
      }
      history.add(page);
      page = destination;
    });
    _saveSession();
    _refreshDestinationData(destination);
  }

  void commit({
    required AppPage next,
    required String message,
    VoidCallback? update,
    bool resetHistory = false,
  }) {
    final destination = _upgradedDestination(next);
    setState(() {
      _navigationEpoch += 1;
      update?.call();
      if (resetHistory) {
        history.clear();
      } else {
        history.add(page);
      }
      page = destination;
    });
    _saveSession();
    _refreshDestinationData(destination);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showMessage(message);
    });
  }

  void resetTo(AppPage next) {
    final destination = _upgradedDestination(next);
    setState(() {
      _navigationEpoch += 1;
      history.clear();
      page = destination;
    });
    _saveSession();
    _refreshDestinationData(destination);
  }

  void completeAuthentication(UserRole nextRole, AppPage nextPage) {
    final destination = _upgradedDestination(nextPage, forRole: nextRole);
    setState(() {
      _navigationEpoch += 1;
      role = nextRole;
      authenticated = true;
      history.clear();
      page = destination;
    });
    _saveSession();
    _refreshDestinationData(destination);
  }

  /// Loads destination-owned real data after navigation. Runs after the frame
  /// so a repository notification never rebuilds a route mid-build.
  void _refreshDestinationData(AppPage destination) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((destination == AppPage.marketplace ||
              destination == AppPage.sellerDashboard) &&
          _marketplace.isLeadsBacked) {
        unawaited(_marketplace.refreshSellerLeads());
      }
      if (destination == AppPage.offersReceived ||
          destination == AppPage.buyerOfferDetail) {
        _refreshBuyerOffersIfNeeded();
      }
      if (destination == AppPage.buyerDashboard &&
          _marketplace.isRequestsBacked) {
        unawaited(_marketplace.refreshBuyerRequests());
      }
      if (destination == AppPage.buyerDashboard &&
          _marketplace.isNotificationsBacked) {
        unawaited(_marketplace.refreshNotifications());
      }
      if (destination == AppPage.buyerDashboard &&
          _marketplace.isMeetingsBacked) {
        unawaited(_marketplace.refreshMeetings());
        unawaited(_refreshConfirmedBuyerMeetings());
      }
      if (destination == AppPage.sellerDashboard && _realAccountMode) {
        unawaited(_refreshAccountHealth());
      }
      if (destination == AppPage.buyerChats ||
          destination == AppPage.sellerChat) {
        _refreshChatInboxIfNeeded();
      }
      if (destination == AppPage.buyerChat ||
          destination == AppPage.sellerConversation) {
        _refreshChatMessagesIfNeeded();
      }
      if (destination == AppPage.sellerOfferHistory ||
          destination == AppPage.sellerOfferDetail) {
        if (_marketplace.isSellerOffersBacked) {
          unawaited(_marketplace.refreshSellerOffers());
        }
      }
      if (destination == AppPage.notifications ||
          destination == AppPage.recentActivity ||
          destination == AppPage.sellerNotifications ||
          destination == AppPage.buyerNotificationPreferences ||
          destination == AppPage.sellerNotificationPreferences) {
        if (_marketplace.isNotificationsBacked) {
          unawaited(_marketplace.refreshNotifications());
          unawaited(_marketplace.refreshNotificationPreferences());
        }
      }
      if (destination == AppPage.meetingDetails ||
          destination == AppPage.sellerMeets) {
        if (_marketplace.isMeetingsBacked) {
          unawaited(_marketplace.refreshMeetings());
        }
        if (destination == AppPage.sellerMeets) {
          unawaited(_refreshConfirmedMeetings());
        }
      }
    });
  }

  bool _meetingBusy = false;
  final Set<String> _confirmedPurchaseMeetings = {};
  bool _buyerCompletionLoading = false;
  String? _buyerCompletionError;
  String? _meetingError;
  ({String key, bool accept})? _meetingResponseIntent;
  bool _meetingResponseUncertain = false;
  int? _meetingResponseRevision;
  String? _meetingCancelKey;
  int? _meetingCancelRevision;
  String? _meetingProposalKey;
  String? _meetingProposalConversation;
  MeetingScheduleInput? _meetingProposalInput;
  ({String conversationId, Offer offer})? _selectedMeetingOffer;
  int _notificationOpenGeneration = 0;

  Future<void> _openNotification(NotificationInboxItem item) async {
    final destination = NotificationDestination.fromInbox(item);
    if (destination == null) {
      showMessage(item.body.isEmpty ? item.title : item.body);
      return;
    }
    final generation = ++_notificationOpenGeneration;
    switch (destination.kind) {
      case NotificationDestinationKind.meeting:
        await _openMeetingById(
          destination.id,
          notificationGeneration: generation,
        );
      case NotificationDestinationKind.chat:
        if (!_marketplace.isChatBacked) return;
        await _marketplace.openChatConversation(destination.id);
        if (!mounted || generation != _notificationOpenGeneration) return;
        if (_marketplace.chatMessagesError != null) {
          showMessage(_marketplace.chatMessagesError!);
          return;
        }
        go(
          role == UserRole.seller
              ? AppPage.sellerConversation
              : AppPage.buyerChat,
        );
      case NotificationDestinationKind.offer:
        if (role == UserRole.seller) {
          if (!_marketplace.isSellerOffersBacked) {
            showMessage('Offer details are unavailable for this account.');
            return;
          }
          await _marketplace.refreshSellerOffers();
          if (!mounted || generation != _notificationOpenGeneration) return;
          final sellerOffer = _marketplace.sellerOffers
              .where((row) => row.id == destination.id)
              .firstOrNull;
          if (sellerOffer == null) {
            showMessage(
              _marketplace.sellerOffersError ??
                  'This offer is no longer available.',
            );
            return;
          }
          setState(() {
            _selectedSellerOffer = SellerOfferView.fromOffer(sellerOffer);
            _withdrawError = null;
          });
          go(AppPage.sellerOfferDetail);
          return;
        }
        if (!_marketplace.isBuyerOffersBacked) {
          showMessage('Switch to your buyer account to review this offer.');
          return;
        }
        await _marketplace.refreshBuyerRequests();
        if (!mounted || generation != _notificationOpenGeneration) return;
        final request = _marketplace.buyerRequests
            .where((row) => row.id == destination.requestId)
            .firstOrNull;
        if (request == null) {
          showMessage(
            'This request is unavailable. Refresh your requests and try again.',
          );
          return;
        }
        await _marketplace.refreshBuyerOffers(destination.requestId!);
        if (!mounted || generation != _notificationOpenGeneration) return;
        final offer = _marketplace.buyerOffers
            .where((row) => row.id == destination.id)
            .firstOrNull;
        if (_marketplace.buyerOffersError != null || offer == null) {
          showMessage(
            _marketplace.buyerOffersError ??
                'This offer is no longer available.',
          );
          return;
        }
        setState(() {
          _activeRequest = request;
          requestTitle = request.draft.title;
          _selectedBuyerOffer = BuyerOfferView.fromOffer(offer);
          _offerSelectionError = null;
          _offerSelectionKey = null;
          _offerSelectionOfferId = null;
          _offerSelectionUncertain = false;
        });
        go(AppPage.buyerOfferDetail);
      case NotificationDestinationKind.billing:
        go(
          role == UserRole.seller
              ? AppPage.sellerBilling
              : AppPage.buyerRewardsDetail,
        );
      case NotificationDestinationKind.account:
        go(
          role == UserRole.seller ? AppPage.sellerProfile : AppPage.editProfile,
        );
    }
  }

  Future<void> _openMeetingDirections([MeetingView? meeting]) async {
    final selectedMeeting = meeting ?? _marketplace.meetingDetail;
    final schedule = selectedMeeting?.acceptedSchedule;
    if (!hasConfirmedMeetingDestination(
      address: schedule?.placeAddress,
      label: schedule?.placeLabel,
      placeId: schedule?.placeId,
    )) {
      showMessage('No confirmed meeting address is available.');
      return;
    }
    if (selectedMeeting == null) return;
    await appNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => MeetingDirectionsPage(
          meetingId: selectedMeeting.meetingId,
          seller: role == UserRole.seller,
          destination: schedule?.placeAddress?.trim().isNotEmpty == true
              ? schedule!.placeAddress!
              : schedule!.placeLabel!,
        ),
      ),
    );
  }

  Future<void> _openMeetingChat(MeetingView meeting) async {
    final repository = _marketplace;
    final userId = widget.accountSession?.userId;
    final epoch = _navigationEpoch;
    if (!repository.isChatBacked) return;
    await repository.openChatConversation(meeting.conversationId);
    if (!mounted ||
        repository != _marketplace ||
        userId != widget.accountSession?.userId ||
        epoch != _navigationEpoch ||
        repository.activeConversationId != meeting.conversationId) {
      return;
    }
    if (repository.chatMessagesError != null) {
      showMessage(repository.chatMessagesError!);
      return;
    }
    setState(() {
      _chatCounterpart = null;
      _chatSendError = null;
    });
    go(
      role == UserRole.seller ? AppPage.sellerConversation : AppPage.buyerChat,
    );
  }

  Future<void> _openCall() async {
    final conversation = _marketplace.activeConversationId;
    if (!_marketplace.isChatBacked || conversation == null) {
      showMessage('Open an eligible conversation before calling.');
      return;
    }
    if (_callOpen) return;
    _callOpen = true;
    try {
      await appNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => HocalistCallPage(conversationId: conversation),
        ),
      );
    } finally {
      _callOpen = false;
    }
  }

  Future<void> _openConversationMeeting() async {
    if (!_marketplace.isMeetingsBacked) {
      go(AppPage.meetingDetails);
      return;
    }
    final conversationId = _marketplace.activeConversationId;
    if (conversationId == null || _meetingBusy) return;
    final proposalUserId = widget.accountSession?.userId;
    final proposalEpoch = _navigationEpoch;
    bool isCurrentProposal() =>
        mounted &&
        widget.accountSession?.userId == proposalUserId &&
        _navigationEpoch == proposalEpoch &&
        _marketplace.activeConversationId == conversationId;
    void abandonProposal() {
      if (mounted) setState(() => _meetingBusy = false);
    }

    setState(() => _meetingBusy = true);
    await _marketplace.refreshMeetings();
    if (!isCurrentProposal()) {
      abandonProposal();
      return;
    }
    while (_marketplace.meetingsError == null &&
        _marketplace.meetingsHasMore &&
        !_marketplace.meetings.any((m) => m.conversationId == conversationId)) {
      await _marketplace.loadMoreMeetings();
      if (!isCurrentProposal()) {
        abandonProposal();
        return;
      }
    }
    if (_marketplace.meetingsError != null) {
      setState(() => _meetingBusy = false);
      showMessage(_marketplace.meetingsError!);
      return;
    }
    final existing = _marketplace.meetings.where(
      (m) => m.conversationId == conversationId,
    );
    if (existing.isNotEmpty) {
      setState(() => _meetingBusy = false);
      await _openMeetingById(existing.first.meetingId);
      return;
    }
    final offers = _marketplace.buyerOffers.where(
      (o) => o.conversationId == conversationId,
    );
    var sourceOffer = _selectedMeetingOffer?.conversationId == conversationId
        ? _selectedMeetingOffer!.offer
        : offers.firstOrNull;
    if (sourceOffer == null && _marketplace.isChatBacked) {
      try {
        sourceOffer = await _marketplace.loadActiveConversationOffer();
      } on StoreBackendException catch (error) {
        if (!isCurrentProposal()) {
          abandonProposal();
          return;
        }
        setState(() => _meetingBusy = false);
        showMessage(error.message);
        return;
      }
      if (!isCurrentProposal()) {
        abandonProposal();
        return;
      }
    }
    if (_marketplace.activeConversationId != conversationId) {
      setState(() => _meetingBusy = false);
      return;
    }
    if (sourceOffer == null) {
      setState(() => _meetingBusy = false);
      showMessage(
        'Open the accepted offer to propose its meeting, or ask your counterpart to send a proposal.',
      );
      return;
    }
    final acceptedRevisionId = sourceOffer.acceptedRevisionId;
    final acceptedRevision = sourceOffer.revisions
        .where((revision) => revision.id == acceptedRevisionId)
        .firstOrNull;
    if (acceptedRevision == null) {
      setState(() => _meetingBusy = false);
      showMessage('Refresh the accepted offer before proposing a meeting.');
      return;
    }
    final terms = acceptedRevision.terms;
    if (_meetingProposalConversation != conversationId ||
        _meetingProposalKey == null) {
      final input = await prepareMeetingProposalLocation(
        schedule: terms.schedule,
        place: terms.place,
        isCurrent: isCurrentProposal,
        confirmPlace: (place) async {
          final selected = await _chooseOfferPlace(
            appNavigatorKey.currentState!.context,
          );
          if (selected == null) return null;
          return MeetingPlace(
            choice: place.choice,
            label: selected.name,
            address: selected.address,
            placeId: selected.placeId,
            latitude: selected.latitude,
            longitude: selected.longitude,
          );
        },
      );
      if (!isCurrentProposal() || input == null) {
        abandonProposal();
        return;
      }
      _meetingProposalConversation = conversationId;
      _meetingProposalKey = LocalMarketplaceRepository.newStoreOperationKey(
        'meeting-propose',
      );
      _meetingProposalInput = input;
    }
    final result = await _marketplace.proposeMeeting(
      conversationId: conversationId,
      operationKey: _meetingProposalKey!,
      input: _meetingProposalInput!,
    );
    if (!isCurrentProposal()) {
      abandonProposal();
      return;
    }
    setState(() => _meetingBusy = false);
    if (!result.outcomeUncertain) {
      _meetingProposalConversation = null;
      _meetingProposalKey = null;
      _meetingProposalInput = null;
    }
    if (result.isSuccess) {
      go(AppPage.meetingDetails);
    } else {
      showMessage(result.error ?? 'Could not propose meeting.');
    }
  }

  void _showMeetingList() {
    if (_marketplace.isMeetingsBacked) _marketplace.clearMeetingDetail();
    go(AppPage.meetingDetails);
  }

  Future<void> _openMeetingById(
    String id, {
    int? notificationGeneration,
  }) async {
    final loaded = await _marketplace.loadMeeting(id);
    if (!mounted) return;
    if (notificationGeneration != null &&
        notificationGeneration != _notificationOpenGeneration) {
      return;
    }
    if (loaded == null) {
      showMessage(_marketplace.meetingsError ?? 'This meeting is unavailable.');
      return;
    }
    setState(() {
      _meetingError = null;
      _meetingResponseIntent = null;
      _meetingResponseUncertain = false;
      _meetingResponseRevision = null;
      _meetingCancelKey = null;
      _meetingCancelRevision = null;
    });
    go(AppPage.meetingDetails);
  }

  Future<void> _rescheduleMeeting() async {
    final meeting = _marketplace.meetingDetail;
    final schedule = meeting?.acceptedSchedule;
    if (meeting == null || schedule == null || meeting.status != 'accepted') {
      return;
    }
    final dialogContext = appNavigatorKey.currentContext;
    if (dialogContext == null) return;
    await showDialog<bool>(
      context: dialogContext,
      animationStyle: HocalistMotion.dialogStyle(dialogContext),
      barrierDismissible: false,
      builder: (_) => ApprovedSellerRescheduleDialog(
        customerName: role == UserRole.seller ? 'buyer' : 'seller',
        currentDate: schedule.date.toString(),
        currentTime: schedule.startTime.toString(),
        initialDate: DateTime(
          schedule.date.year,
          schedule.date.month,
          schedule.date.day,
        ),
        initialTime: TimeOfDay(
          hour: schedule.startTime.hour,
          minute: schedule.startTime.minute,
        ),
        timezoneId: schedule.timezoneId,
        onSubmit: (date, time, occurrence, key) =>
            _marketplace.proposeMeetingReschedule(
              meetingId: meeting.meetingId,
              expectedRevision: meeting.revision,
              operationKey: key,
              input: MeetingScheduleInput(
                schedule: LocalSchedule(
                  date: LocalDate.fromDateTime(date),
                  startTime: LocalTime(hour: time.hour, minute: time.minute),
                  timezoneId: schedule.timezoneId,
                  occurrence: occurrence,
                ),
                placeChoice: schedule.placeChoice,
                placeLabel: schedule.placeLabel,
                placeAddress: schedule.placeAddress,
                placeId: schedule.placeId,
                latitude: schedule.latitude,
                longitude: schedule.longitude,
              ),
            ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Accepts or declines the newest pending schedule. The operation key is
  /// allocated once per intent and reused until the outcome is definite, so a
  /// retry after a lost response replays the committed result; a changed
  /// decision before a resolved outcome allocates a fresh key.
  Future<void> _respondToMeeting({required bool accept}) async {
    final meeting = _marketplace.meetingDetail;
    if (meeting == null || _meetingBusy) return;
    final pending = _meetingResponseIntent;
    if (_meetingResponseUncertain &&
        pending != null &&
        pending.accept != accept) {
      setState(
        () => _meetingError =
            'Retry the unconfirmed decision before changing it.',
      );
      return;
    }
    final key = (pending != null && pending.accept == accept)
        ? pending.key
        : LocalMarketplaceRepository.newStoreOperationKey('meeting-respond');
    _meetingResponseIntent = (key: key, accept: accept);
    if (!_meetingResponseUncertain) _meetingResponseRevision = meeting.revision;
    setState(() {
      _meetingBusy = true;
      _meetingError = null;
    });
    final result = await _marketplace.respondToMeeting(
      meetingId: meeting.meetingId,
      accept: accept,
      expectedRevision: _meetingResponseRevision!,
      operationKey: key,
    );
    if (!mounted) return;
    setState(() {
      _meetingBusy = false;
      if (result.isSuccess) {
        _meetingResponseIntent = null;
        _meetingResponseUncertain = false;
      } else {
        _meetingResponseUncertain = result.outcomeUncertain;
        if (!result.outcomeUncertain) _meetingResponseIntent = null;
        _meetingError = result.outcomeUncertain
            ? 'The change could not be confirmed. Retry to check it safely.'
            : result.error;
      }
    });
  }

  Future<void> _cancelMeeting() async {
    final meeting = _marketplace.meetingDetail;
    if (meeting == null || _meetingBusy) return;
    _meetingCancelKey ??= LocalMarketplaceRepository.newStoreOperationKey(
      'meeting-cancel',
    );
    _meetingCancelRevision ??= meeting.revision;
    setState(() {
      _meetingBusy = true;
      _meetingError = null;
    });
    final result = await _marketplace.cancelMeeting(
      meetingId: meeting.meetingId,
      expectedRevision: _meetingCancelRevision!,
      operationKey: _meetingCancelKey!,
    );
    if (!mounted) return;
    setState(() {
      _meetingBusy = false;
      if (!result.outcomeUncertain) {
        _meetingCancelKey = null;
        _meetingCancelRevision = null;
      }
      if (!result.isSuccess) {
        _meetingError = result.outcomeUncertain
            ? 'The change could not be confirmed. Retry to check it safely.'
            : result.error;
      }
    });
  }

  void _refreshChatInboxIfNeeded() {
    if (!_marketplace.isChatBacked) return;
    if (_marketplace.chatInboxLoading) return;
    unawaited(_marketplace.refreshChatInbox());
  }

  void _refreshChatMessagesIfNeeded() {
    if (!_marketplace.isChatBacked) return;
    if (_marketplace.activeConversationId == null) return;
    if (_marketplace.chatMessagesLoading) return;
    unawaited(_marketplace.refreshChatMessages());
  }

  /// Opens one inbox thread, loads its history and marks the newest
  /// counterpart message read.
  Future<void> _openChatThread(ChatThreadView thread) async {
    if (!_marketplace.isChatBacked) {
      go(
        role == UserRole.seller
            ? AppPage.sellerConversation
            : AppPage.buyerChat,
      );
      return;
    }
    setState(() {
      _chatSendError = null;
      _chatCounterpart = (
        name: thread.counterpartName,
        profileId: thread.counterpartProfileId,
      );
    });
    await _marketplace.openChatConversation(thread.conversationId);
    if (!mounted ||
        _marketplace.activeConversationId != thread.conversationId) {
      return;
    }
    if (_marketplace.chatMessagesError != null) {
      showMessage(_marketplace.chatMessagesError!);
      return;
    }
    final messages = _marketplace.chatMessages;
    final viewerId = widget.accountSession?.userId;
    if (messages.isNotEmpty && messages.last.senderUserId != viewerId) {
      unawaited(_marketplace.markChatRead(messages.last.id));
    }
    go(
      role == UserRole.seller ? AppPage.sellerConversation : AppPage.buyerChat,
    );
  }

  /// Opens the public seller profile for the open conversation's counterpart.
  /// Configured sessions use the server-projected profile id; a missing
  /// projection is reported honestly instead of fabricating a profile.
  Future<void> _openChatCounterpartProfile() async {
    if (!_marketplace.isChatBacked) {
      go(AppPage.sellerPublicProfile);
      return;
    }
    var profileId = _currentChatCounterpart?.profileId;
    if (profileId == null) {
      final conversationId = _marketplace.activeConversationId;
      final userId = widget.accountSession?.userId;
      final epoch = _navigationEpoch;
      await _marketplace.refreshChatInbox();
      if (!mounted ||
          _marketplace.activeConversationId != conversationId ||
          widget.accountSession?.userId != userId ||
          _navigationEpoch != epoch) {
        return;
      }
      profileId = _currentChatCounterpart?.profileId;
    }
    if (profileId == null || profileId.isEmpty) {
      showMessage(
        'Seller details could not be loaded. Refresh the conversation and try again.',
      );
      return;
    }
    _sellerProfileFromConversation = true;
    go(AppPage.sellerPublicProfile);
  }

  bool _openingSellerOfferChat = false;
  SellerLeadProjection? _conversationRequest;
  String? _conversationRequestError;
  bool _conversationRequestLoading = false;
  int _conversationRequestGeneration = 0;

  Future<void> _openConversationRequest() async {
    if (!_marketplace.isChatBacked) {
      go(AppPage.sellerOriginalRequest);
      return;
    }
    final repository = _marketplace;
    final backend = repository.chatBackend;
    final conversationId = repository.activeConversationId;
    final generation = ++_conversationRequestGeneration;
    setState(() {
      _conversationRequest = null;
      _conversationRequestError = null;
      _conversationRequestLoading = true;
    });
    if (page != AppPage.sellerOriginalRequest) {
      go(AppPage.sellerOriginalRequest);
    }
    try {
      final request =
          backend is MarketplaceChatRequestBackend && conversationId != null
          ? await (backend as MarketplaceChatRequestBackend)
                .loadConversationRequest(conversationId)
          : null;
      if (!mounted ||
          generation != _conversationRequestGeneration ||
          !identical(repository, _marketplace) ||
          repository.activeConversationId != conversationId) {
        return;
      }
      setState(() => _conversationRequest = request);
    } catch (_) {
      if (!mounted ||
          generation != _conversationRequestGeneration ||
          !identical(repository, _marketplace)) {
        return;
      }
      setState(
        () => _conversationRequestError =
            'This request could not be loaded. It may no longer be available.',
      );
    } finally {
      if (mounted &&
          generation == _conversationRequestGeneration &&
          identical(repository, _marketplace)) {
        setState(() => _conversationRequestLoading = false);
      }
    }
  }

  Future<void> _openSellerOfferChat() async {
    if (!_marketplace.isSellerOffersBacked) {
      go(AppPage.sellerConversation);
      return;
    }
    if (_openingSellerOfferChat) return;
    final offer = _selectedSellerOffer;
    final conversationId = offer?.conversationId;
    if (conversationId == null) {
      showMessage(
        'Chat becomes available when the buyer selects this offer. Refresh your offers to check its status.',
      );
      return;
    }
    _openingSellerOfferChat = true;
    try {
      await _marketplace.openChatConversation(conversationId);
      if (!mounted ||
          _selectedSellerOffer?.offerId != offer!.offerId ||
          _marketplace.activeConversationId != conversationId) {
        return;
      }
      if (_marketplace.chatMessagesError != null) {
        showMessage(_marketplace.chatMessagesError!);
        return;
      }
      setState(() => _chatSendError = null);
      go(AppPage.sellerConversation);
    } finally {
      _openingSellerOfferChat = false;
    }
  }

  String _chatTimeLabel(DateTime sentAt) {
    final local = sentAt.toLocal();
    final now = DateTime.now();
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

  /// Authoritative chat history mapped to the approved bubble entries.
  List<ApprovedConversationEntry>? _realConversationEntries() {
    if (!_marketplace.isChatBacked ||
        _marketplace.activeConversationId == null) {
      return null;
    }
    final viewerId = widget.accountSession?.userId;
    return _marketplace.chatMessages
        .map(
          (message) => ApprovedConversationEntry(
            isOutgoing: message.senderUserId == viewerId,
            time: _chatTimeLabel(message.sentAt),
            text: message.text,
            attachmentLabel: message.attachments.isEmpty
                ? null
                : message.attachments.length == 1
                ? message.attachments.first.fileName
                : '${message.attachments.length} photos',
            attachmentIsImage: message.attachments.isNotEmpty,
            attachmentMediaIds: message.attachments
                .map((attachment) => attachment.id)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  /// Picks one chat photo, uploads it to the authorized `chat` purpose and
  /// sends it through the attachment path. Only reachable while the repository
  /// reports `chatAttachmentsSupported`; the outcome message stays singular.
  Future<void> _pickAndSendChatAttachment() async {
    if (!_marketplace.chatAttachmentsSupported || _chatSending) return;
    if (_marketplace.hasUnconfirmedChatAttachment) {
      showMessage('Retry or discard the earlier photo first.');
      return;
    }
    final repository = _marketplace;
    final conversationId = repository.activeConversationId;
    final userId = widget.accountSession?.userId;
    if (conversationId == null || userId == null) return;
    final upload = configuredImageUpload('chat');
    if (upload == null) {
      showMessage('Photo upload is unavailable. Try again later.');
      return;
    }
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      showMessage('The photo picker is unavailable on this device.');
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _chatSending = true;
      _chatSendError = null;
    });
    try {
      final bytes = preparePrivatePhoto(await picked.readAsBytes());
      if (bytes.length > 4 * 1024 * 1024) {
        if (!mounted) return;
        setState(() => _chatSending = false);
        showMessage('Choose a photo smaller than 4 MB.');
        return;
      }
      final mediaId = await upload(bytes, newMediaUploadKey());
      if (!mounted) return;
      // The delayed upload must never land in another session or chat. A
      // switched session discards it; a switched conversation keeps it with the
      // original conversation for an explicit retry there.
      if (!identical(repository, _marketplace) ||
          widget.accountSession?.userId != userId) {
        setState(() => _chatSending = false);
        showMessage('Your session changed. The photo was not sent.');
        return;
      }
      final result = await repository.sendChatAttachment(
        text: '',
        mediaIds: [mediaId],
        expectedConversationId: conversationId,
      );
      if (!mounted) return;
      setState(() {
        _chatSending = false;
        if (!result.isSuccess &&
            repository.isActiveConversation(conversationId)) {
          _chatSendError = result.error ?? 'The photo could not be sent.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _chatSending = false);
      showMessage('The photo could not be uploaded. Try again.');
    }
  }

  /// Retries the retained attachment for the active conversation without
  /// uploading the image again.
  Future<void> _retryChatAttachment() async {
    if (_chatSending) return;
    final repository = _marketplace;
    final conversationId = repository.activeConversationId;
    if (conversationId == null) return;
    setState(() {
      _chatSending = true;
      _chatSendError = null;
    });
    final result = await repository.retryChatAttachment();
    if (!mounted) return;
    setState(() {
      _chatSending = false;
      if (!result.isSuccess &&
          repository.isActiveConversation(conversationId)) {
        _chatSendError = result.error ?? 'The photo could not be sent.';
      }
    });
  }

  void _discardChatAttachment() {
    _marketplace.discardChatAttachment();
    if (mounted) setState(() {});
  }

  Future<bool> _sendChatMessage(String text) async {
    if (!_marketplace.isChatBacked) {
      if (text.isNotEmpty) showMessage('Message sent.');
      return true;
    }
    if (_chatSending) return false;
    final conversationId = _marketplace.activeConversationId;
    setState(() {
      _chatSending = true;
      _chatSendError = null;
    });
    final result = await _marketplace.sendChatMessage(text);
    if (!mounted) return false;
    setState(() {
      _chatSending = false;
      if (!result.isSuccess &&
          conversationId == _marketplace.activeConversationId) {
        _chatSendError = result.error ?? 'The message could not be sent.';
      }
    });
    return result.isSuccess &&
        conversationId == _marketplace.activeConversationId;
  }

  Future<void> _toggleChatMute(bool muted) async {
    if (!_marketplace.isChatBacked) return;
    final applied = await _marketplace.setChatMuted(muted);
    if (!mounted) return;
    showMessage(
      applied
          ? (muted ? 'Chat messages muted.' : 'Chat messages unmuted.')
          : 'Mute could not be saved. Try again.',
    );
  }

  void _refreshBuyerOffersIfNeeded() {
    final request = _currentBuyerRequest;
    if (request == null || !_marketplace.isBuyerOffersBacked) return;
    if (_marketplace.buyerOffersRequestId == request.id &&
        !_marketplace.buyerOffersLoading) {
      return;
    }
    unawaited(_marketplace.refreshBuyerOffers(request.id));
  }

  SellerOfferView _sellerOfferView(Offer offer) {
    String? title;
    for (final lead in _marketplace.sellerLeads) {
      if (lead.requestId == offer.requestId) {
        title = lead.title;
        break;
      }
    }
    return SellerOfferView.fromOffer(offer, requestTitle: title);
  }

  /// Withdraws the offer shown on the seller offer detail screen. A changed
  /// offer intent allocates a new key; an uncertain outcome keeps it.
  Future<void> _withdrawSelectedSellerOffer() async {
    final view = _selectedSellerOffer;
    if (view == null || !_marketplace.isSellerOffersBacked) return;
    if (_withdrawBusy) return;
    if (!view.isWithdrawable) {
      setState(() => _withdrawError = 'This offer can no longer be withdrawn.');
      return;
    }
    if (_withdrawOfferId != view.offerId) {
      _withdrawOfferId = view.offerId;
      _withdrawKey = LocalMarketplaceRepository.newStoreOperationKey(
        'offer-withdraw',
      );
    }
    setState(() {
      _withdrawBusy = true;
      _withdrawError = null;
    });
    final result = await _marketplace.withdrawSellerOffer(
      offerId: view.offerId,
      expectedOfferRevision: view.offerRevision,
      operationKey: _withdrawKey!,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      _withdrawKey = null;
      _withdrawOfferId = null;
      setState(() {
        _withdrawBusy = false;
        _selectedSellerOffer = SellerOfferView.fromOffer(
          result.offer!,
          requestTitle: view.requestTitle,
        );
      });
      showMessage('Offer withdrawn.');
      return;
    }
    setState(() {
      _withdrawBusy = false;
      _withdrawError = result.error;
      if (!result.outcomeUncertain) {
        _withdrawKey = null;
        _withdrawOfferId = null;
      }
    });
  }

  Future<void> _editSelectedSellerOffer() async {
    final selected = _selectedSellerOffer;
    if (selected == null || !selected.isWithdrawable) return;
    final matching = _marketplace.sellerOffers.where(
      (offer) => offer.id == selected.offerId,
    );
    if (matching.isEmpty) {
      showMessage('Refresh your offers before editing this one.');
      return;
    }
    final offer = matching.first;
    final changed = await showModalBottomSheet<Offer>(
      context: context,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SellerOfferRevisionEditor(
        offer: offer,
        onSave: (terms, key) => _marketplace.reviseSellerOffer(
          offerId: offer.id,
          expectedOfferRevision: offer.stamp.revision,
          terms: terms,
          operationKey: key,
        ),
      ),
    );
    if (!mounted ||
        changed == null ||
        _selectedSellerOffer?.offerId != changed.id) {
      return;
    }
    setState(
      () => _selectedSellerOffer = SellerOfferView.fromOffer(
        changed,
        requestTitle: selected.requestTitle,
      ),
    );
    showMessage('Updated offer sent to the buyer.');
  }

  /// Selects the offer shown on the buyer offer detail screen. A changed offer
  /// intent allocates a new operation key; an uncertain outcome keeps the
  /// original key until it is reconciled.
  Future<void> _selectSelectedOffer() async {
    final view = _selectedBuyerOffer;
    if (view == null || !_marketplace.isBuyerOffersBacked) {
      commit(
        next: AppPage.buyerChat,
        message: 'Seller selected. Chatroom opened.',
        update: () {
          offerSelected = true;
          _marketplace.updateOfferStatus(LocalOfferStatus.selected);
        },
      );
      return;
    }
    if (_offerSelectionBusy) return;
    if (!view.isSelectable) {
      setState(
        () => _offerSelectionError = 'This offer can no longer be selected.',
      );
      return;
    }
    if (_offerSelectionOfferId != view.offerId) {
      _offerSelectionOfferId = view.offerId;
      _offerSelectionKey = LocalMarketplaceRepository.newStoreOperationKey(
        'offer-select',
      );
      _offerSelectionUncertain = false;
    }
    setState(() {
      _offerSelectionBusy = true;
      _offerSelectionError = null;
    });
    final result = await _marketplace.selectBuyerOffer(
      offerId: view.offerId,
      revisionId: view.revisionId,
      expectedOfferRevision: view.offerRevision,
      operationKey: _offerSelectionKey!,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      final selected = result.offer!;
      final conversationId = result.conversationId ?? selected.conversationId;
      if (conversationId != null) {
        _selectedMeetingOffer = (
          conversationId: conversationId,
          offer: selected,
        );
      }
      if (conversationId != null && _marketplace.isChatBacked) {
        await _marketplace.openChatConversation(conversationId);
        if (!mounted) return;
      }
      _offerSelectionKey = null;
      _offerSelectionOfferId = null;
      _offerSelectionUncertain = false;
      setState(() {
        _offerSelectionBusy = false;
        _selectedBuyerOffer = BuyerOfferView.fromOffer(selected);
        offerSelected = true;
      });
      _saveSession();
      commit(
        next: AppPage.buyerChat,
        message: 'Seller selected. Chatroom opened.',
        update: () {},
      );
      return;
    }
    setState(() {
      _offerSelectionBusy = false;
      _offerSelectionError = result.error;
      _offerSelectionUncertain = result.outcomeUncertain;
      if (!result.outcomeUncertain) {
        _offerSelectionKey = null;
        _offerSelectionOfferId = null;
      }
    });
  }

  /// Buyer identifies the accepted seller they purchased from. Only that
  /// seller can complete the request PIN; the server owns the one-purchase
  /// rule. A changed intent uses a new key; an uncertain outcome keeps the
  /// original key until it is reconciled.
  Future<void> _chooseSelectedPurchaseSeller() async {
    final view = _selectedBuyerOffer;
    if (view == null || !_marketplace.isBuyerOffersBacked) return;
    if (_purchaseSelectionBusy) return;
    if (_purchaseSelectionOfferId != view.offerId) {
      _purchaseSelectionOfferId = view.offerId;
      _purchaseSelectionKey = LocalMarketplaceRepository.newStoreOperationKey(
        'purchase-select',
      );
    }
    setState(() {
      _purchaseSelectionBusy = true;
      _purchaseSelectionError = null;
    });
    final result = await _marketplace.selectBuyerPurchaseSeller(
      offerId: view.offerId,
      expectedOfferRevision: view.offerRevision,
      operationKey: _purchaseSelectionKey!,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      _purchaseSelectionKey = null;
      _purchaseSelectionOfferId = null;
      setState(() {
        _purchaseSelectionBusy = false;
        _selectedBuyerOffer = BuyerOfferView.fromOffer(result.offer!);
      });
      showMessage('You chose this seller for the final purchase.');
      return;
    }
    setState(() {
      _purchaseSelectionBusy = false;
      _purchaseSelectionError = result.error;
      if (!result.outcomeUncertain) {
        _purchaseSelectionKey = null;
        _purchaseSelectionOfferId = null;
      }
    });
  }

  AppPage _upgradedDestination(AppPage requested, {UserRole? forRole}) {
    return upgradedDestinationFor(requested, forRole ?? role);
  }

  Future<void> logout() async {
    final session = widget.accountSession;
    if (session != null) {
      try {
        await session.logout();
      } on AccountActionException catch (error) {
        if (mounted) showMessage(error.message);
      }
      // The real account gate owns navigation after sign-out.
      return;
    }
    setState(() {
      authenticated = false;
      history.clear();
      page = AppPage.welcome;
    });
    _saveSession();
  }

  /// Persists the edited display name through the real account command when a
  /// session is attached; prototype mode keeps the local value only.
  Future<bool> _saveProfileName(String value, {required bool seller}) async {
    final session = widget.accountSession;
    if (session == null) return true;
    try {
      await session.updateDisplayName(value);
      if (mounted) showMessage('Profile name saved.');
      return true;
    } on AccountActionException catch (error) {
      if (mounted) {
        showMessage(error.message);
        setState(() => _adoptAccountSession(session));
      }
      return false;
    }
  }

  void submitBuyerRequest() {
    setState(() {
      requestPosted = true;
      history.clear();
      page = AppPage.buyerRequestDetail;
    });
    _saveSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRequestPostedDialog();
    });
  }

  void _showRequestPostedDialog() {
    final dialogContext = appNavigatorKey.currentContext;
    if (dialogContext == null || !mounted) return;
    showDialog<void>(
      context: dialogContext,
      animationStyle: HocalistMotion.dialogStyle(dialogContext),
      builder: (popupContext) => ApprovedRequestPostedDialog(
        onViewRequest: () => Navigator.of(popupContext).pop(),
        onHome: () {
          Navigator.of(popupContext).pop();
          resetTo(AppPage.buyerDashboard);
        },
      ),
    );
  }

  /// Opens the place-capture sheet for a real offer and maps the confirmed
  /// place to the offer form's place value. Manual entry stays available when
  /// Places is unconfigured or fails.
  Future<SellerOfferPlace?> _chooseOfferPlace(BuildContext context) async {
    final result = await showPlaceCaptureSheet(
      context: context,
      places: _placesRepository,
      mapBuilder: _placesRepository == null || !mapSdkAvailable
          ? null
          : buildGoogleMapSurface,
      locationReader: readForegroundLocation,
    );
    if (result == null) return null;
    return SellerOfferPlace(
      name: result.label,
      address: result.address,
      placeId: result.placeId,
      latitude: result.latitude,
      longitude: result.longitude,
    );
  }

  Future<RequestLocation?> _chooseRequestLocation(
    BuildContext requestContext, {
    RequestLocation? initial,
  }) async {
    final address = initial?.address;
    final addressText = address == null
        ? ''
        : [
                address.line1,
                address.line2,
                address.city,
                address.state,
                address.postalCode,
                address.country,
              ]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .join(', ');
    final result = await showPlaceCaptureSheet(
      context: requestContext,
      initial: addressText.isEmpty
          ? null
          : PlaceCaptureResult(
              label: 'Saved request location',
              address: addressText,
              latitude: initial?.coordinates?.latitude,
              longitude: initial?.coordinates?.longitude,
              source: PlaceCaptureSource.manual,
            ),
      places: _placesRepository,
      mapBuilder: _placesRepository == null || !mapSdkAvailable
          ? null
          : buildGoogleMapSurface,
      locationReader: readForegroundLocation,
    );
    if (result == null || result.address.trim().isEmpty) return null;
    return RequestLocation.custom(
      address: result.postalAddress ?? PostalAddress(line1: result.address),
      coordinates: result.hasCoordinates
          ? RequestCoordinates(
              latitude: result.latitude!,
              longitude: result.longitude!,
            )
          : null,
    );
  }

  /// Opens one real request from the dashboard list by its identity.
  void _openBuyerRequest(BuyerRequestView view) {
    for (final request in _marketplace.buyerRequests) {
      if (request.id == view.requestId) {
        setState(() {
          _activeRequest = request;
          requestTitle = request.draft.title;
          requestBudget = _formatRequestBudget(request.draft);
        });
        _saveSession();
        break;
      }
    }
    go(AppPage.buyerRequestDetail);
  }

  /// Opens the offers route scoped to the tapped request card. The tapped
  /// identity is adopted before navigation, prior offer selection is cleared,
  /// and the next frame refreshes that request's offers only.
  void _openBuyerRequestOffers(BuyerRequestView view) {
    for (final request in _marketplace.buyerRequests) {
      if (request.id == view.requestId) {
        setState(() {
          _activeRequest = request;
          _selectedBuyerOffer = null;
          _offerSelectionError = null;
          _offerSelectionUncertain = false;
          requestTitle = request.draft.title;
          requestBudget = _formatRequestBudget(request.draft);
        });
        _saveSession();
        break;
      }
    }
    go(AppPage.offersReceived);
  }

  /// The authoritative request shown by the detail route in real mode.
  MarketplaceRequest? get _currentBuyerRequest {
    if (!_marketplace.isRequestsBacked) return null;
    final active = _activeRequest;
    if (active != null) return active;
    final requests = _marketplace.buyerRequests;
    return requests.isEmpty ? null : requests.first;
  }

  /// Buyer home address from the account contacts, when loaded.
  PostalAddress? get _buyerHomeAddress {
    final contact = widget.accountSession?.contact?.contact;
    if (contact == null) return null;
    final address = PostalAddress(
      line1: contact.addressLine1,
      line2: contact.addressLine2,
      city: contact.city,
      state: contact.region,
      postalCode: contact.postalCode,
      country: contact.countryCode,
    );
    return address.isEmpty ? null : address;
  }

  String _formatRequestBudget(RequestDraft draft) {
    final range = draft.budget;
    if (range.isEmpty) return '';
    String amount(Money money) {
      final units = money.minorUnits / 100;
      return units.truncateToDouble() == units
          ? units.toStringAsFixed(0)
          : units.toStringAsFixed(2);
    }

    final minimum = range.minimum;
    final maximum = range.maximum;
    if (minimum != null && maximum != null) {
      return '\$${amount(minimum)} - \$${amount(maximum)}';
    }
    if (minimum != null) return 'From \$${amount(minimum)}';
    return 'Up to \$${amount(maximum!)}';
  }

  /// Adopts the server-created request: the approved screens show its real
  /// values and the detail route opens on the new record.
  void _adoptCreatedRequest(MarketplaceRequest request) {
    setState(() {
      _navigationEpoch += 1;
      _activeRequest = request;
      requestTitle = request.draft.title;
      requestBudget = _formatRequestBudget(request.draft);
      requestPosted = true;
      history.clear();
      page = AppPage.buyerRequestDetail;
    });
    _saveSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRequestPostedDialog();
    });
  }

  void _submitSellerOffer(LocalOfferRecord offer) {
    setState(() {
      _marketplace.submitOffer(offer);
      sellerOfferSent = true;
      offerPrice = offer.price;
      requestTitle = offer.requestTitle;
      buyerName = offer.buyerName;
    });
    _saveSession();
  }

  List<ApprovedConversationEntry> _conversationEntriesFor({
    required bool viewerIsSeller,
  }) {
    return _marketplace.conversationEntries
        .map(
          (entry) => ApprovedConversationEntry(
            isOutgoing: entry.senderIsSeller == viewerIsSeller,
            time: entry.sentAtLabel,
            text: entry.text,
            attachmentLabel: entry.attachmentLabel,
            attachmentIsImage: entry.attachmentIsImage,
          ),
        )
        .toList(growable: false);
  }

  void _storeConversationEntry(
    ApprovedConversationEntry entry, {
    required bool senderIsSeller,
  }) {
    _marketplace.addConversationEntry(
      senderIsSeller: senderIsSeller,
      text: entry.text,
      attachmentLabel: entry.attachmentLabel,
      attachmentIsImage: entry.attachmentIsImage,
    );
    _saveSession();
  }

  String? get _latestConversationPreview {
    if (_marketplace.conversationEntries.isEmpty) return null;
    final entry = _marketplace.conversationEntries.last;
    if (entry.text.isNotEmpty) return entry.text;
    final attachment = entry.attachmentLabel;
    if (attachment == null) return null;
    return entry.attachmentIsImage ? 'Photo: $attachment' : 'File: $attachment';
  }

  void back() {
    if (history.isEmpty) {
      if (signedIn) {
        resetTo(
          role == UserRole.seller
              ? AppPage.sellerDashboard
              : AppPage.buyerDashboard,
        );
      }
      return;
    }
    setState(() {
      _navigationEpoch += 1;
      page = history.removeLast();
    });
    _saveSession();
    _refreshDestinationData(page);
  }

  void updateBuyerName(String value) {
    setState(() => buyerName = value);
    _saveSession();
  }

  void updateSellerName(String value) {
    setState(() => sellerName = value);
    _saveSession();
  }

  void updateRequestTitle(String value) {
    setState(() => requestTitle = value);
    _saveSession();
  }

  void updateRequestBudget(String value) {
    setState(() => requestBudget = value);
    _saveSession();
  }

  void updateOfferPrice(String value) {
    setState(() => offerPrice = value);
    _saveSession();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hocalist',
      debugShowCheckedModeBanner: false,
      theme: HocalistTheme.lightFor(accessibilityPreferences),
      darkTheme: HocalistTheme.darkFor(accessibilityPreferences),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      scaffoldMessengerKey: messengerKey,
      navigatorKey: appNavigatorKey,
      builder: (context, child) {
        final scaled = AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) => NotificationIndicatorScope(
            unreadCount: _marketplace.isNotificationsBacked
                ? _marketplace.notificationsUnreadCount
                : null,
            child: _hocalistTextScale(context, child, accessibilityPreferences),
          ),
        );
        if (widget.accountSession == null) return scaled;
        return CallInvitationListener(
          child: scaled,
          canOpen: () => !_callOpen,
          onIncoming: (id, conversation) async {
            if (_callOpen) return;
            _callOpen = true;
            try {
              await appNavigatorKey.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => HocalistCallPage(
                    conversationId: conversation,
                    incomingId: id,
                  ),
                ),
              );
            } finally {
              _callOpen = false;
            }
          },
        );
      },
      home: Scaffold(
        body: _usesIntegratedPageChrome
            ? HocalistPageTransition(
                child:
                    {
                      AppPage.accountSecurity,
                      AppPage.accountLifecycle,
                      AppPage.buyerWallet,
                    }.contains(page)
                    ? SafeArea(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                              child: HocalistGlobalHeader(
                                role: role,
                                accent: roleAccent,
                                showSavedIndicator: restoredSession,
                                onNotifications: () => go(
                                  role == UserRole.seller
                                      ? AppPage.sellerNotifications
                                      : AppPage.notifications,
                                ),
                              ),
                            ),
                            Expanded(
                              child: KeyedSubtree(
                                key: ValueKey(page),
                                child: currentPage(),
                              ),
                            ),
                          ],
                        ),
                      )
                    : KeyedSubtree(key: ValueKey(page), child: currentPage()),
              )
            : SafeArea(
                child: HocalistPageTransition(
                  child: page == AppPage.accessibility
                      ? Column(
                          children: [
                            if (signedIn)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  8,
                                ),
                                child: HocalistGlobalHeader(
                                  role: role,
                                  accent: roleAccent,
                                  onNotifications: () => go(
                                    role == UserRole.seller
                                        ? AppPage.sellerNotifications
                                        : AppPage.notifications,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: KeyedSubtree(
                                key: ValueKey(page),
                                child: currentPage(),
                              ),
                            ),
                          ],
                        )
                      : AppFrame(
                          key: ValueKey(page),
                          childOwnsScroll:
                              page == AppPage.meetingDetails &&
                              _marketplace.isMeetingsBacked &&
                              _marketplace.meetingDetail == null,
                          scrollKey: PageStorageKey<String>(
                            'app-frame-${page.name}',
                          ),
                          compactBottom: page == AppPage.buyerDashboard,
                          buyerTopLevel:
                              role == UserRole.buyer &&
                              {
                                AppPage.hocatrends,
                                AppPage.buyerChats,
                                AppPage.buyerSupport,
                              }.contains(page),
                          header: signedIn && !_suppressesGlobalHeader
                              ? Builder(
                                  builder: (context) {
                                    return HocalistGlobalHeader(
                                      role: role,
                                      accent: roleAccent,
                                      showSavedIndicator: restoredSession,
                                      onNotifications: () => go(
                                        role == UserRole.seller
                                            ? AppPage.sellerNotifications
                                            : AppPage.notifications,
                                      ),
                                    );
                                  },
                                )
                              : null,
                          child: _TitleBackScope(
                            onBack: showGlobalBack ? back : null,
                            child: HocalistTabPersistenceScope(
                              namespace:
                                  '${widget.accountSession?.userId ?? 'prototype'}.${role.name}',
                              child: currentPage(),
                            ),
                          ),
                        ),
                ),
              ),
        bottomNavigationBar: signedIn
            ? _usesIntegratedPageChrome
                  ? null
                  : bottomNav()
            : null,
      ),
    );
  }

  Widget currentPage() => currentPageFor(page);

  @visibleForTesting
  Widget currentPageFor(AppPage requested) {
    switch (requested) {
      case AppPage.welcome:
        return ApprovedNoAccountHomePage(
          onStart: () {
            role = UserRole.buyer;
            go(AppPage.buyerSignup);
          },
          onBuyer: () {
            role = UserRole.buyer;
            go(AppPage.buyerSignup);
          },
          onSeller: () {
            role = UserRole.seller;
            go(AppPage.sellerSignup);
          },
          onHome: () => resetTo(AppPage.welcome),
          onTrends: () => go(AppPage.hocatrends),
          onWinners: () => showMessage('Winners preview is coming soon.'),
          onSignup: () {
            role = UserRole.buyer;
            go(AppPage.buyerSignup);
          },
        );
      case AppPage.chooseRole:
        return ChooseRolePage(
          onBuyer: () {
            role = UserRole.buyer;
            go(AppPage.buyerSignup);
          },
          onSeller: () {
            role = UserRole.seller;
            go(AppPage.sellerSignup);
          },
        );
      case AppPage.buyerSignup:
        return ApprovedAccountCreationPage(
          role: ApprovedAccountRole.buyer,
          draft: _signupDraft,
          name: _signupDraft.name,
          onNameChanged: updateBuyerName,
          onRoleChanged: (nextRole) {
            setState(
              () => role = nextRole == ApprovedAccountRole.buyer
                  ? UserRole.buyer
                  : UserRole.seller,
            );
            resetTo(
              nextRole == ApprovedAccountRole.buyer
                  ? AppPage.buyerSignup
                  : AppPage.sellerSignup,
            );
          },
          onClose: () => resetTo(AppPage.welcome),
          onSignup: () => go(AppPage.buyerBenefits),
          onLogin: () =>
              completeAuthentication(UserRole.buyer, AppPage.buyerDashboard),
          onUploadProfile: () => showMessage('Profile image picker opened.'),
        );
      case AppPage.buyerBenefits:
        return ApprovedBuyerBenefitsPage(
          name: buyerName,
          onClose: () =>
              completeAuthentication(UserRole.buyer, AppPage.buyerDashboard),
          onFinish: () =>
              completeAuthentication(UserRole.buyer, AppPage.buyerDashboard),
        );
      case AppPage.buyerProfile:
        return FormStepPage(
          accent: accent,
          title: 'Set up buyer profile',
          subtitle: 'These details make local offers more relevant.',
          fields: const [
            MockFieldData('Primary city', 'Chicago, IL'),
            MockFieldData('Preferred pickup distance', 'Within 12 miles'),
            MockFieldData(
              'Notification preference',
              'Offer updates and meeting reminders',
            ),
          ],
          primaryLabel: 'Go to buyer dashboard',
          onPrimary: () => resetTo(AppPage.buyerDashboard),
        );
      case AppPage.buyerDashboard:
        return AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) => ApprovedBuyerHomePage(
            name: buyerName,
            requestTitle: requestTitle,
            requestPosted: requestPosted,
            onCreate: () => go(AppPage.createRequest),
            onRequestDetails: () => go(AppPage.buyerRequestDetail),
            onOffers: () => go(AppPage.offersReceived),
            onOpenOffers: _openBuyerRequestOffers,
            onRecentActivity: () => go(AppPage.recentActivity),
            onWallet: () => go(AppPage.buyerRewardsDetail),
            meetingConfirmed: meetingConfirmed,
            onMeetingDetails: _showMeetingList,
            onNotifications: () => go(AppPage.notifications),
            onHome: () => resetTo(AppPage.buyerDashboard),
            onTrends: () => resetTo(AppPage.hocatrends),
            onOffersTab: () => resetTo(AppPage.offersReceived),
            onChats: () => resetTo(AppPage.buyerChats),
            onMore: () => resetTo(AppPage.buyerSupport),
            realRequests: _marketplace.isRequestsBacked
                ? _marketplace.buyerRequests
                      .map(BuyerRequestView.fromRequest)
                      .toList(growable: false)
                : null,
            requestsLoading: _marketplace.buyerRequestsLoading,
            requestsError: _marketplace.buyerRequestsError,
            onRefreshRequests: () =>
                unawaited(_marketplace.refreshBuyerRequests()),
            onOpenRequest: _openBuyerRequest,
            realMeetings: _marketplace.isMeetingsBacked
                ? _marketplace.meetings
                      .where(
                        (meeting) => !_confirmedPurchaseMeetings.contains(
                          meeting.meetingId,
                        ),
                      )
                      .toList(growable: false)
                : null,
            meetingsLoading:
                _marketplace.meetingsLoading || _buyerCompletionLoading,
            meetingsError: _marketplace.meetingsError ?? _buyerCompletionError,
            onRefreshMeetings: () {
              unawaited(_marketplace.refreshMeetings());
              unawaited(_refreshConfirmedBuyerMeetings());
            },
            onOpenMeeting: (meeting) =>
                unawaited(_openMeetingById(meeting.meetingId)),
            realActivity: _marketplace.isNotificationsBacked
                ? _marketplace.notifications
                      .map(
                        (item) => ApprovedActivityView.fromNotification(item),
                      )
                      .toList(growable: false)
                : null,
            activityLoading: _marketplace.notificationsLoading,
            activityError: _marketplace.notificationsError,
            onRefreshActivity: () =>
                unawaited(_marketplace.refreshNotifications()),
            loadRealRewards: widget.accountSession == null
                ? null
                : loadBuyerRewards,
          ),
        );
      case AppPage.recentActivity:
        return ApprovedBuyerNotificationsPage(
          onBack: back,
          repository: _marketplace,
          onOpenNotification: _openNotification,
        );
      case AppPage.hocatrends:
        if (!authenticated) {
          return ApprovedPublicHocatrendsPage(
            accent: accent,
            onSeeSellers: () {
              setState(() => role = UserRole.buyer);
              go(AppPage.buyerSignup);
            },
            onHome: () => resetTo(AppPage.welcome),
            onHocatrends: () {},
            onWinners: () => showMessage('Winners preview is coming soon.'),
            onSignup: () {
              setState(() => role = UserRole.buyer);
              go(AppPage.buyerSignup);
            },
          );
        }
        return ApprovedHocatrendsPage(
          accent: accent,
          realMode: _realAccountMode,
          trends: _hocatrends,
          trendsLoading: _hocatrendsLoading,
          trendsError: _hocatrendsError,
          onRefreshTrends: _discoveryBackend == null
              ? null
              : () => unawaited(_refreshHocatrends()),
          onSeeSellersForTopic: _discoveryBackend == null
              ? null
              : (topicId) => unawaited(_openTopicSellers(topicId)),
          onSeeSellers: _realAccountMode
              ? () => showMessage(
                  'Seller results are not connected yet. Real trend ranking is pending.',
                )
              : () => go(AppPage.hocatrendsSellers),
        );
      case AppPage.hocatrendsSellers:
        return ApprovedHocatrendsPickedSellersPage(
          onBack: back,
          onChatSeller: () => go(AppPage.buyerChat),
          onNotifications: () => go(AppPage.notifications),
          realMode: _discoveryBackend != null,
          realResults: _topicSellerResults,
          resultsLoading: _topicSellersLoading,
          resultsError: _topicSellersError,
          onRetryResults: _selectedTopicId == null
              ? null
              : () => unawaited(_openTopicSellers(_selectedTopicId!)),
          onChatSellerView: (seller) async {
            final backend = _discoveryBackend;
            if (backend == null) return;
            try {
              final opened = await backend.openEnquiry(
                origin: DiscoveryEnquiryOrigin.hocatrendsEnquiry,
                subjectId: _selectedTopicId!,
                sellerProfileId: seller.sellerProfileId,
                operationKey: LocalMarketplaceRepository.newStoreOperationKey(
                  'enquiry',
                ),
              );
              await _marketplace.refreshChatInbox();
              await _marketplace.openChatConversation(opened.conversationId);
              if (mounted) go(AppPage.buyerChat);
            } on StoreBackendException catch (error) {
              if (mounted) showMessage(error.message);
            }
          },
        );
      case AppPage.createRequest:
        return ApprovedRequestFlowPage(
          accent: accent,
          requestTitle: widget.accountSession == null
              ? requestTitle
              : _newRequestTitle,
          budget: widget.accountSession == null
              ? requestBudget
              : _newRequestBudget,
          onTitleChanged: widget.accountSession == null
              ? updateRequestTitle
              : (value) => setState(() => _newRequestTitle = value),
          onBudgetChanged: widget.accountSession == null
              ? updateRequestBudget
              : (value) => setState(() => _newRequestBudget = value),
          onBack: back,
          onNotifications: () => go(AppPage.notifications),
          onSubmit: submitBuyerRequest,
          includeAppChrome: true,
          onHome: () => resetTo(AppPage.buyerDashboard),
          onHocatrends: () => resetTo(AppPage.hocatrends),
          onOffers: () => resetTo(AppPage.offersReceived),
          onChats: () => resetTo(AppPage.buyerChats),
          onMore: () => resetTo(AppPage.buyerSupport),
          onSubmitDraft: _marketplace.isRequestsBacked
              ? (draft, operationKey) => _marketplace.createBuyerRequest(
                  draft: draft,
                  operationKey: operationKey,
                )
              : null,
          onCreated: _adoptCreatedRequest,
          categories: _marketplace.requestCategories,
          categoriesLoading: _marketplace.requestCategoriesLoading,
          categoriesError: _marketplace.requestCategoriesError,
          onRefreshCategories: _marketplace.refreshRequestCategories,
          homeAddress: _buyerHomeAddress,
          onChooseLocation: _marketplace.isRequestsBacked
              ? _chooseRequestLocation
              : null,
        );
      case AppPage.requestSuccess:
        return ApprovedRequestSuccessPage(
          navigation: _approvedBuyerNavigation,
          onViewRequest: () => go(AppPage.buyerRequestDetail),
          onHome: () => resetTo(AppPage.buyerDashboard),
        );
      case AppPage.buyerRequestDetail:
        final activeRequest = _currentBuyerRequest;
        final bookmarkBackend = widget.accountSession?.userId == null
            ? null
            : createConfiguredSavedBackend(widget.accountSession!.userId!);
        final bookmarkReference = activeRequest == null
            ? null
            : SavedItemReference(id: activeRequest.id, type: 'request');
        return ApprovedBuyerRequestDetailsPage(
          bookmarkAction: bookmarkBackend == null || bookmarkReference == null
              ? null
              : SavedItemButton(
                  key: ValueKey('saved-${bookmarkReference.id}'),
                  read: () => bookmarkBackend.isSaved(bookmarkReference),
                  setSaved: (saved, key) =>
                      bookmarkBackend.setSaved(bookmarkReference, saved, key),
                ),
          accent: accent,
          requestTitle: requestTitle,
          budget: requestBudget,
          onBack: back,
          onNotifications: () => go(AppPage.notifications),
          onOffers: () => go(AppPage.offersReceived),
          onSaveRequest: () => setState(() => requestChangePending = true),
          includeAppChrome: true,
          onHome: () => resetTo(AppPage.buyerDashboard),
          onHocatrends: () => resetTo(AppPage.hocatrends),
          onChats: () => resetTo(AppPage.buyerChats),
          onMore: () => resetTo(AppPage.buyerSupport),
          request: activeRequest,
          onUpdateRequest: activeRequest == null
              ? null
              : (draft, operationKey) => _marketplace.updateBuyerRequest(
                  requestId: activeRequest.id,
                  expectedRevision: activeRequest.stamp.revision,
                  draft: draft,
                  operationKey: operationKey,
                ),
          onCloseRequest: activeRequest == null
              ? null
              : (operationKey) => _marketplace.closeBuyerRequest(
                  requestId: activeRequest.id,
                  expectedRevision: activeRequest.stamp.revision,
                  operationKey: operationKey,
                ),
          onChooseLocation: _marketplace.isRequestsBacked
              ? (context) => _chooseRequestLocation(
                  context,
                  initial: activeRequest?.draft.location,
                )
              : null,
          onUpdated: (updated) {
            setState(() {
              _activeRequest = updated;
              requestTitle = updated.draft.title;
              requestBudget = _formatRequestBudget(updated.draft);
            });
            _saveSession();
          },
        );
      case AppPage.offersReceived:
        return AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) => ApprovedOffersReceivedPage(
            onBack: back,
            onNotifications: () => go(AppPage.notifications),
            onViewOffer: () => go(AppPage.buyerOfferDetail),
            onChat: () => commit(
              next: AppPage.buyerChat,
              message: 'Seller selected. Chatroom opened.',
              update: () {
                offerSelected = true;
                _marketplace.updateOfferStatus(LocalOfferStatus.selected);
              },
            ),
            onFilter: _realAccountMode
                ? () {}
                : () => showMessage('Offer filters opened.'),
            navigation: _approvedBuyerNavigation,
            latestOffer: _marketplace.latestOffer,
            realOffers: _marketplace.isBuyerOffersBacked
                ? _marketplace.buyerOffers
                      .map(BuyerOfferView.fromOffer)
                      .toList(growable: false)
                : null,
            budgetMaximum: _currentBuyerRequest?.draft.budget.maximum == null
                ? null
                : _currentBuyerRequest!.draft.budget.maximum!.minorUnits / 100,
            requestClosed:
                _currentBuyerRequest != null &&
                _currentBuyerRequest!.status != RequestStatus.active,
            offersLoading: _marketplace.buyerOffersLoading,
            offersError: _marketplace.buyerOffersError,
            onRefreshOffers: _refreshBuyerOffersIfNeeded,
            onOpenOffer: (view) {
              setState(() {
                _selectedBuyerOffer = view;
                _offerSelectionError = null;
                _purchaseSelectionError = null;
                _purchaseSelectionKey = null;
                _purchaseSelectionOfferId = null;
              });
              go(AppPage.buyerOfferDetail);
            },
          ),
        );
      case AppPage.buyerOfferDetail:
        return ApprovedViewOfferPage(
          onBack: back,
          onNotifications: () => go(AppPage.notifications),
          onSelectSeller: _selectSelectedOffer,
          onViewProfile: () {
            _sellerProfileFromConversation = false;
            go(AppPage.sellerPublicProfile);
          },
          navigation: _approvedBuyerNavigation,
          latestOffer: _marketplace.latestOffer,
          realOffer: _marketplace.isBuyerOffersBacked
              ? _selectedBuyerOffer
              : null,
          requestTitle: _currentBuyerRequest?.draft.title ?? requestTitle,
          selectionBusy: _offerSelectionBusy,
          selectionError: _offerSelectionError,
          selectionUncertain: _offerSelectionUncertain,
          onChoosePurchaseSeller: _marketplace.isBuyerOffersBacked
              ? _chooseSelectedPurchaseSeller
              : null,
          purchaseBusy: _purchaseSelectionBusy,
          purchaseError: _purchaseSelectionError,
        );
      case AppPage.sellerPublicProfile:
        final chatCounterpart = _currentChatCounterpart;
        final selectedOffer = _selectedBuyerOffer;
        final identity = sellerProfileIdentity(
          fromConversation: _sellerProfileFromConversation,
          conversation: chatCounterpart,
          offer: selectedOffer == null
              ? null
              : (
                  profileId: selectedOffer.sellerProfileId,
                  name: selectedOffer.sellerName,
                ),
        );
        final sellerProfileId = identity.profileId;
        final fromChat = _sellerProfileFromConversation;
        final publicStore = widget.accountSession?.userId == null
            ? null
            : createConfiguredSavedBackend(widget.accountSession!.userId!);
        if (sellerProfileId != null &&
            _reviewBackend != null &&
            (_sellerReputationFor != sellerProfileId ||
                (_sellerReputation == null &&
                    !_sellerReputationLoading &&
                    _sellerReputationError == null))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_loadSellerReputation(sellerProfileId));
          });
        }
        return ApprovedSellerPublicProfilePage(
          onBack: back,
          realMode: _realAccountMode,
          realSellerName: identity.name,
          subtitle: fromChat
              ? 'Seller details from this conversation.'
              : 'Seller details from the selected offer.',
          publishedListings: publicStore != null && sellerProfileId != null
              ? PublicSellerListings(
                  key: ValueKey('public-store-$sellerProfileId'),
                  repository: publicStore.adapter,
                  sellerProfileId: sellerProfileId,
                )
              : null,
          reputation: _sellerReputationFor == sellerProfileId
              ? _sellerReputation
              : null,
          reputationLoading:
              _reviewBackend != null &&
              (_sellerReputationFor != sellerProfileId ||
                  _sellerReputationLoading),
          reputationError: _sellerReputationFor == sellerProfileId
              ? _sellerReputationError
              : null,
          selectionBusy: !fromChat && _offerSelectionBusy,
          selectionError: fromChat ? null : _offerSelectionError,
          onSelect: fromChat
              ? null
              : _realAccountMode
              ? _selectSelectedOffer
              : () => commit(
                  next: AppPage.buyerChat,
                  message: 'Seller selected. Chatroom opened.',
                  update: () {
                    offerSelected = true;
                    _marketplace.updateOfferStatus(LocalOfferStatus.selected);
                  },
                ),
        );
      case AppPage.buyerPublicProfile:
        if (_realAccountMode) {
          final profileId = _chatCounterpart?.profileId;
          return BuyerPublicProfilePage(
            key: ValueKey('buyer-public-$profileId'),
            onBack: back,
            load: () async {
              final backend = _discoveryBackend;
              if (profileId == null || backend == null) {
                return const PublicBuyerProfile(available: false);
              }
              return backend.loadPublicProfile(profileId);
            },
          );
        }
        return ApprovedBuyerPublicProfilePage(onBack: back);
      case AppPage.buyerChats:
        return AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) => BuyerChatsPage(
            onBack: back,
            onOpenChat: () => go(AppPage.buyerChat),
            onOffers: () => go(AppPage.offersReceived),
            latestOffer: _marketplace.latestOffer,
            latestMessagePreview: _latestConversationPreview,
            realThreads: _marketplace.isChatBacked
                ? _marketplace.chatInbox
                      .map(
                        (summary) => ChatThreadView.fromSummary(
                          summary,
                          viewerUserId: widget.accountSession?.userId ?? '',
                        ),
                      )
                      .toList(growable: false)
                : null,
            threadsLoading: _marketplace.chatInboxLoading,
            threadsError: _marketplace.chatInboxError,
            onRefreshThreads: _refreshChatInboxIfNeeded,
            onOpenThread: _openChatThread,
            onSearchConversations: _marketplace.isChatBacked
                ? _searchChatConversations
                : null,
          ),
        );
      case AppPage.buyerChat:
        _scheduleConversationDealsLoad();
        return AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) => ApprovedBuyerChatPage(
            realContactName: _activeConversationName,
            key: ValueKey(
              'buyer-chat-${_marketplace.activeConversationId ?? 'prototype'}',
            ),
            realDeals: _conversationDeals,
            previousDeals: _previousConversationDeals,
            realDealsLoading: _conversationDealsLoading,
            realDealsError: _conversationDealsError,
            realDealsTruncated: _conversationDealsTruncated,
            onRefreshRealDeals: _marketplace.isMeetingsBacked
                ? () => unawaited(_loadConversationDeals(force: true))
                : null,
            onOpenRealDeal: _marketplace.isMeetingsBacked
                ? (meetingId) => unawaited(_openConversationDeal(meetingId))
                : null,
            onBack: back,
            onPrimary: _marketplace.isMeetingsBacked
                ? _openConversationMeeting
                : () => commit(
                    next: AppPage.buyerDashboard,
                    message:
                        'Meeting confirmed and added to Upcoming meetings.',
                    update: () {
                      offerSelected = true;
                      meetingConfirmed = true;
                      _marketplace.updateOfferStatus(
                        LocalOfferStatus.meetingConfirmed,
                      );
                    },
                  ),
            primaryLabel: 'Accept to meet',
            onCall: _openCall,
            onMore: () => go(AppPage.reportIssue),
            onRequestChange: () => showMessage('Request change opened.'),
            onChangeLocation: _openConversationMeeting,
            onAttach: _marketplace.chatAttachmentsSupported
                ? () => unawaited(_pickAndSendChatAttachment())
                : () => showMessage(
                    'Attachments are not connected yet. Text messages still send.',
                  ),
            attachmentsEnabled: _marketplace.chatAttachmentsSupported,
            pendingAttachmentMediaId:
                _marketplace.pendingChatAttachment?.mediaIds.isNotEmpty == true
                ? _marketplace.pendingChatAttachment!.mediaIds.first
                : null,
            attachmentRetryBusy: _chatSending,
            onRetryAttachment: () => unawaited(_retryChatAttachment()),
            onDiscardAttachment: _discardChatAttachment,
            onSend: _sendChatMessage,
            onSubmitMessage: _marketplace.isChatBacked
                ? _sendChatMessage
                : null,
            initialDraft: _marketplace.unconfirmedChatText,
            onLearnMore: () => go(AppPage.safetyGuide),
            onViewProfile: _openChatCounterpartProfile,
            navigation: _approvedBuyerNavigation,
            meetingConfirmed: meetingConfirmed,
            offerRevisionPending: offerRevisionPending,
            onOfferRevisionAccepted: () => commit(
              next: AppPage.buyerDashboard,
              message:
                  'Updated offer accepted. Meeting added to Upcoming meetings.',
              update: () {
                offerRevisionPending = false;
                meetingConfirmed = true;
                _marketplace.updateOfferStatus(
                  LocalOfferStatus.meetingConfirmed,
                );
              },
            ),
            offer: _marketplace.latestOffer,
            sentEntries: _conversationEntriesFor(viewerIsSeller: false),
            onEntrySent: (entry) =>
                _storeConversationEntry(entry, senderIsSeller: false),
            realEntries: _realConversationEntries(),
            messagesLoading: _marketplace.chatMessagesLoading,
            messagesError: _marketplace.chatMessagesError,
            onRefreshMessages: _refreshChatMessagesIfNeeded,
            onLoadOlder: _marketplace.chatHasOlder
                ? _marketplace.loadOlderChatMessages
                : null,
            olderLoading: _marketplace.chatOlderLoading,
            olderError: _marketplace.chatOlderError,
            sending: _chatSending,
            sendError: _chatSendError,
            muted: _marketplace.isChatBacked ? _marketplace.chatMuted : null,
            onMuteChanged: _marketplace.isChatBacked ? _toggleChatMute : null,
            blockState: _activeBlockState,
            blockWritePending: _blockWritePending,
            onBlockChanged: _marketplace.isChatBacked
                ? _setConversationBlocked
                : null,
            onSearchMessages: _marketplace.isChatBacked
                ? _searchChatMessages
                : null,
          ),
        );
      case AppPage.finalizeDeal:
        // Alias to the role conversation: the legacy ScreenBlock page is not a
        // reachable destination and the accepted deal opens in chat.
        return currentPageFor(_upgradedDestination(AppPage.finalizeDeal));
      case AppPage.meetingDetails:
        if (_marketplace.isMeetingsBacked &&
            _marketplace.meetingDetail == null) {
          if (role == UserRole.seller) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Meetings'),
                leading: BackButton(onPressed: back),
              ),
              body: AnimatedBuilder(
                animation: _marketplace,
                builder: (context, _) => ApprovedSellerMeetsPage(
                  onOpenChat: () {},
                  meetings: _marketplace.meetings,
                  hasMore: _marketplace.meetingsHasMore,
                  onLoadMore: _marketplace.loadMoreMeetings,
                  loading: _marketplace.meetingsLoading,
                  error: _marketplace.meetingsError,
                  onRefresh: () => _marketplace.refreshMeetings(),
                  onOpenMeeting: (meeting) =>
                      _openMeetingById(meeting.meetingId),
                ),
              ),
            );
          }
          return AnimatedBuilder(
            animation: _marketplace,
            builder: (context, _) => ApprovedBuyerMeetingsPage(
              onBack: back,
              meetings: _marketplace.meetings
                  .where(
                    (meeting) =>
                        !_confirmedPurchaseMeetings.contains(meeting.meetingId),
                  )
                  .toList(growable: false),
              loading: _marketplace.meetingsLoading || _buyerCompletionLoading,
              error: _marketplace.meetingsError ?? _buyerCompletionError,
              onRefresh: () {
                unawaited(_marketplace.refreshMeetings());
                unawaited(_refreshConfirmedBuyerMeetings());
              },
              onOpenMeeting: (meeting) =>
                  unawaited(_openMeetingById(meeting.meetingId)),
            ),
          );
        }
        final confirmationMeetingId = _marketplace.meetingDetail?.meetingId;
        return AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) {
            final meetingDetails = ApprovedMeetingDetailsPage(
              purchaseConfirmed: _confirmedPurchaseMeetings.contains(
                _marketplace.meetingDetail?.meetingId,
              ),
              saleConfirmation:
                  _marketplace.isMeetingsBacked &&
                      _marketplace.meetingDetail != null
                  ? SaleConfirmationPanel(
                      key: ValueKey(
                        'sale-${_marketplace.meetingDetail!.meetingId}-${_marketplace.meetingDetail!.revision}',
                      ),
                      adapter: createSaleConfirmationAdapter(),
                      meetingId: _marketplace.meetingDetail!.meetingId,
                      onRefreshMeeting: () async {
                        final id = confirmationMeetingId;
                        if (id == null ||
                            _marketplace.meetingDetail?.meetingId != id) {
                          return;
                        }
                        await _marketplace.loadMeeting(id);
                      },
                      isBuyer: role == UserRole.buyer,
                      purchaseSelected:
                          _marketplace.meetingDetail!.purchaseSelected,
                      meetingAccepted:
                          _marketplace.meetingDetail!.hasAcceptedSchedule &&
                          !_marketplace.meetingDetail!.isCancelled,
                      onPurchaseConfirmed: () {
                        final id = confirmationMeetingId;
                        if (mounted &&
                            id != null &&
                            !_confirmedPurchaseMeetings.contains(id)) {
                          setState(() => _confirmedPurchaseMeetings.add(id));
                          if (role == UserRole.seller) {
                            unawaited(_refreshConfirmedMeetings());
                          } else {
                            unawaited(_refreshConfirmedBuyerMeetings());
                          }
                        }
                      },
                    )
                  : null,
              onBack: back,
              onConfirm:
                  _marketplace.isMeetingsBacked &&
                      _marketplace.meetingDetail != null
                  ? () => _respondToMeeting(accept: true)
                  : () => commit(
                      next: AppPage.buyerConfirmation,
                      message: 'Meeting details saved for both sides.',
                      update: () => meetingConfirmed = true,
                    ),
              meeting: _marketplace.meetingDetail,
              viewerUserId: widget.accountSession?.userId,
              onDirections: _marketplace.isMeetingsBacked
                  ? _openMeetingDirections
                  : null,
              onReschedule: _marketplace.isMeetingsBacked
                  ? _rescheduleMeeting
                  : null,
              busy: _meetingBusy,
              error: _meetingError,
              onDecline: _marketplace.isMeetingsBacked
                  ? () => _respondToMeeting(accept: false)
                  : null,
              onCancel: _marketplace.isMeetingsBacked ? _cancelMeeting : null,
            );
            return role == UserRole.seller
                ? RoleAssetVariant(
                    sourceRoot: 'assets/approved_onboarding_home',
                    variantRoot: 'assets/approved_seller/onboarding_home',
                    child: meetingDetails,
                  )
                : meetingDetails;
          },
        );
      case AppPage.buyerConfirmation:
        return ApprovedBuyerAfterMeetupPage(
          requestTitle: requestTitle,
          onBack: back,
          navigation: _approvedBuyerNavigation,
          onReview: () => commit(
            next: AppPage.buyerReview,
            message: 'Deal marked completed. Review is ready.',
            update: () {
              dealCompleted = true;
              dealFailed = false;
            },
          ),
          onDealIssue: () => go(AppPage.dealRecovery),
          onReport: () => go(AppPage.reportIssue),
        );
      case AppPage.dealRecovery:
        return AnimatedBuilder(
          animation: _reopenFlow,
          builder: (context, _) => ApprovedBuyerDealRecoveryPage(
            onBack: back,
            navigation: _approvedBuyerNavigation,
            actionBusy: _reopenFlow.busy,
            actionError: _reopenFlow.error,
            actionUncertain: _reopenFlow.uncertain,
            onDiscard: _marketplace.isRequestsBacked
                ? _discardReopenIntent
                : null,
            onReopen: _marketplace.isRequestsBacked
                ? () => unawaited(_reopenCurrentRequest())
                : () => commit(
                    next: AppPage.buyerRequestDetail,
                    message: 'Request reopened. Backup offers are available.',
                    update: () {
                      offerSelected = false;
                      meetingConfirmed = false;
                      dealFailed = true;
                      requestReopened = true;
                    },
                  ),
            onBackup: () => commit(
              next: AppPage.offersReceived,
              message: 'Backup offers restored for comparison.',
              update: () {
                offerSelected = false;
                meetingConfirmed = false;
                dealFailed = true;
                requestReopened = true;
              },
            ),
            onReport: () => go(AppPage.reportIssue),
          ),
        );
      case AppPage.buyerReview:
        return ApprovedBuyerReviewPage(
          onBack: back,
          navigation: _approvedBuyerNavigation,
          onFinish: () => resetTo(AppPage.buyerWallet),
          backend: _reviewBackend,
          requestId: _reviewRequestId ?? _currentBuyerRequest?.id,
          purchase: _reviewPurchase,
          sellerName: _reviewRequestId == null
              ? _selectedBuyerOffer?.sellerName
              : null,
        );
      case AppPage.buyerWallet:
        final historyBackend = widget.accountSession != null
            ? createConfiguredCommercialWalletBackend()
            : null;
        return ApprovedBuyerDealHistoryPage(
          realContent: widget.accountSession != null
              ? ApprovedBuyerDealHistoryRealSections(
                  load: historyBackend?.loadSaleHistory,
                  loadDetail: historyBackend?.loadSaleDetail,
                  loadSummary: historyBackend is CommercialDealSummaryBackend
                      ? (historyBackend as CommercialDealSummaryBackend)
                            .loadDealSummary
                      : null,
                  onReview: _reviewBackend == null
                      ? null
                      : (detail) {
                          _reviewRequestId = detail.requestId;
                          _reviewPurchase = detail;
                          go(AppPage.buyerReview);
                        },
                  supportReviewRequested: dealSupportReviewRequested,
                  onSupport: () => go(AppPage.reportIssue),
                )
              : null,
          onBack: history.isEmpty
              ? () => resetTo(AppPage.buyerDashboard)
              : back,
          navigation: _approvedBuyerNavigation,
          dealCompleted: dealCompleted,
          dealFailed: dealFailed,
          requestReopened: requestReopened,
          supportReviewRequested: dealSupportReviewRequested,
          requestTitle: requestTitle,
          sellerName: sellerName,
          offerPrice: offerPrice,
          onSupport: widget.accountSession != null
              ? () => go(AppPage.reportIssue)
              : () {
                  setState(() => dealSupportReviewRequested = true);
                  _saveSession();
                  showMessage('Support review request saved.');
                },
        );
      case AppPage.buyerRewardsDetail:
        final rewardsBackend = widget.accountSession != null
            ? createConfiguredCommercialWalletBackend()
            : null;
        final rewardsWithdrawalBackend = widget.accountSession != null
            ? createConfiguredWithdrawalStatusLoader()
            : null;
        return ApprovedBuyerRewardsDetailPage(
          realContent: widget.accountSession != null
              ? ApprovedBuyerRewardsRealSections(
                  load: rewardsBackend?.loadRewardWallet,
                  loadWithdrawals: rewardsWithdrawalBackend,
                  onWithdraw: () => go(AppPage.withdrawal),
                  onDealHistory: () => go(AppPage.buyerWallet),
                )
              : null,
          onBack: back,
          onDealHistory: () => go(AppPage.buyerWallet),
          onWithdraw: () => go(AppPage.withdrawal),
        );
      case AppPage.withdrawal:
        if (widget.accountSession != null) {
          final withdrawalBackend = createConfiguredWithdrawalBackend();
          final rewardsBackend = createConfiguredCommercialWalletBackend();
          return ApprovedBuyerRewardsDetailPage(
            onBack: back,
            onDealHistory: () => go(AppPage.buyerWallet),
            realContent: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ApprovedBuyerRewardsRealSections(
                  load: rewardsBackend?.loadRewardWallet,
                  loadWithdrawals: createConfiguredWithdrawalStatusLoader(),
                  onDealHistory: () => go(AppPage.buyerWallet),
                ),
                if (withdrawalBackend != null) ...[
                  const SizedBox(height: 12),
                  WithdrawalPanel(
                    load: withdrawalBackend.loadStatus,
                    submit: (amountMinor, operationKey) =>
                        withdrawalBackend.requestWithdrawal(
                          amountMinor: amountMinor,
                          operationKey: operationKey,
                        ),
                  ),
                ],
              ],
            ),
          );
        }
        return ApprovedBuyerWithdrawalPage(
          onBack: back,
          onComplete: () {
            setState(() => withdrawalRequested = true);
            _saveSession();
            showMessage('Withdrawal request saved for payout processing.');
          },
        );
      case AppPage.supportReviewStatus:
        if (widget.accountSession != null) return _realSupportPage();
        return BuyerSupportStatusPage(
          accent: accent,
          actionLabel: history.isEmpty
              ? 'View Buyer deal history'
              : 'Back to Help & Support',
          onAction: history.isEmpty ? () => go(AppPage.buyerWallet) : back,
        );
      case AppPage.buyerSupport:
        return SupportPage(
          accent: accent,
          name: buyerName,
          avatarMediaId: _profileAvatarMediaId,
          email: _realAccountMode
              ? (widget.accountSession?.email ?? 'Signed in')
              : 'maya.chen@example.com',
          onNotifications: () => go(AppPage.buyerNotificationPreferences),
          onRewards: () => go(AppPage.buyerRewardsDetail),
          onSaved: () => go(AppPage.savedItems),
          onSafety: () => go(AppPage.safetyGuide),
          onReport: () => go(AppPage.reportIssue),
          onHelp: () => go(AppPage.helpSupport),
          onEditProfile: () => go(AppPage.editProfile),
          onSettings: () => go(AppPage.buyerSettings),
          onLogout: logout,
          onProfilePhotoAction: _changeBuyerProfileAvatar,
        );
      case AppPage.notifications:
        return ApprovedBuyerNotificationsPage(
          onBack: back,
          title: 'Notifications',
          repository: _marketplace,
          onOpenNotification: _openNotification,
        );
      case AppPage.buyerNotificationPreferences:
        return BuyerNotificationPreferencesPage(
          accent: accent,
          repository: _marketplace,
        );
      case AppPage.savedItems:
        final savedBackend = widget.accountSession?.userId == null
            ? null
            : createConfiguredSavedBackend(widget.accountSession!.userId!);
        return SavedItemsPage(
          accent: accent,
          realMode: widget.accountSession != null,
          load: savedBackend?.load,
          remove: savedBackend == null
              ? null
              : (reference, key) =>
                    savedBackend.setSaved(reference, false, key),
        );
      case AppPage.safetyGuide:
        if (role == UserRole.seller) {
          return ApprovedSellerSafetyGuidePage(
            onBack: back,
            onHelp: () => go(AppPage.helpSupport),
          );
        }
        return SafetyGuidePage(accent: accent);
      case AppPage.reportIssue:
        if (widget.accountSession != null) return _realSupportPage();
        return ReportIssuePage(
          accent: accent,
          submitted: reportSubmitted,
          onSubmit: () => commit(
            next: AppPage.reportIssue,
            message: 'Report saved in this device session.',
            update: () => reportSubmitted = true,
            resetHistory: true,
          ),
        );
      case AppPage.helpSupport:
        if (role == UserRole.seller) {
          return ApprovedSellerHelpSupportPage(
            onBack: back,
            onSafety: () => go(AppPage.safetyGuide),
            onContactSupport: _realAccountMode
                ? () => go(AppPage.supportReviewStatus)
                : null,
            onReportSafety: _realAccountMode
                ? () => go(AppPage.reportIssue)
                : null,
          );
        }
        return HelpSupportPage(
          accent: accent,
          connected: _realAccountMode,
          onReport: () => go(AppPage.reportIssue),
          onContactSupport: () => go(AppPage.supportReviewStatus),
        );
      case AppPage.buyerSettings:
        return BuyerSettingsPage(
          onBack: back,
          darkMode: darkMode,
          textSize: textSize,
          onEditProfile: () => go(AppPage.editProfile),
          onThemeChanged: updateThemeMode,
          onAccessibility: () => go(AppPage.accessibility),
          onSecurity: widget.accountSession == null
              ? null
              : () => go(AppPage.accountSecurity),
          securityContent: widget.accountSession == null
              ? null
              : AccountSecurityPage(
                  controller: widget.accountSession!,
                  onBack: back,
                  embedded: true,
                ),
          securityStatus: widget.accountSession == null ? null : 'Available',
          pendingEmailChange: widget.accountSession?.pendingEmailChange,
          onAccountLifecycle: widget.accountSession == null
              ? null
              : () => go(AppPage.accountLifecycle),
        );
      case AppPage.sellerSettings:
        return ApprovedSellerSettingsPage(
          darkMode: darkMode,
          textSizeLabel: textSize.label,
          onBack: back,
          onEditProfile: () => go(AppPage.editProfile),
          onThemeChanged: updateThemeMode,
          onAccessibility: () => go(AppPage.accessibility),
          onSecurity: widget.accountSession == null
              ? null
              : () => go(AppPage.accountSecurity),
          securityContent: widget.accountSession == null
              ? null
              : AccountSecurityPage(
                  controller: widget.accountSession!,
                  onBack: back,
                  embedded: true,
                ),
          securityStatus: widget.accountSession == null ? null : 'Available',
          pendingEmailChange: widget.accountSession?.pendingEmailChange,
          onAccountLifecycle: widget.accountSession == null
              ? null
              : () => go(AppPage.accountLifecycle),
        );
      case AppPage.accountSecurity:
        final securitySession = widget.accountSession;
        if (securitySession == null) {
          return BuyerStateNotice(
            icon: Icons.lock_outline,
            title: 'Sign in to manage security',
            body: 'Password and email settings require an active account.',
            actionLabel: 'Back',
            onAction: back,
          );
        }
        return AccountSecurityPage(controller: securitySession, onBack: back);
      case AppPage.accountLifecycle:
        final lifecycleSession = widget.accountSession;
        final lifecycleUserId = lifecycleSession?.userId;
        return AccountLifecyclePage(
          seller: role == UserRole.seller,
          backend: createConfiguredAccountLifecycleBackend(),
          email: lifecycleSession?.email,
          reauthenticate: lifecycleSession?.reauthenticate,
          isSessionCurrent: lifecycleSession == null || lifecycleUserId == null
              ? null
              : () => lifecycleSession.userId == lifecycleUserId,
          onBack: back,
        );
      case AppPage.accessibility:
        return AccessibilityPage(
          seller: role == UserRole.seller,
          appliedPreferences: accessibilityPreferences,
          onApply: applyAccessibilityPreferences,
          onBack: back,
        );
      case AppPage.sellerProfileSetup:
      case AppPage.editProfile:
        final account = widget.accountSession;
        final categoryBackend = createConfiguredProfileCategoriesBackend();
        final contactEditor = account == null
            ? null
            : PrivateContactEditor(
                readCurrent: () => account.contact,
                onSave: (command) => account.updateContact((_) => command),
              );
        if (role == UserRole.seller) {
          return ApprovedSellerEditProfilePage(
            name: sellerName,
            onNameChanged: updateSellerName,
            onBack: back,
            email: widget.accountSession?.email,
            serviceAreaLabel: widget.accountSession?.profile?.areaLabel,
            profileNote: widget.accountSession?.profile?.profileNote,
            avatarMediaId: _profileAvatarMediaId,
            avatarPending: _profileAvatarIntents.containsKey('seller'),
            onRetryAvatar: () => unawaited(_retryProfileAvatar('seller')),
            onDiscardAvatar: () => _discardProfileAvatar('seller'),
            onProfilePhotoAction: _changeSellerProfileAvatar,
            profileDetailsEditor: account == null
                ? null
                : ProfileDetailsEditor(
                    readCurrent: () => account.profile,
                    onSave: account.updateProfileDetails,
                    readDisplayName: () => sellerName,
                    onSaved: () => showMessage('Profile saved.'),
                  ),
            contactEditor: account == null
                ? null
                : PrivateContactEditor(
                    seller: true,
                    readCurrent: () => account.contact,
                    onSave: (command) => account.updateContact((_) => command),
                  ),
            categoryEditor: categoryBackend == null
                ? null
                : SellerCategoryEditor(
                    load: categoryBackend.loadSellerCategories,
                    save: (revision, ids) =>
                        categoryBackend.updateSellerCategories(
                          expectedRevision: revision,
                          categoryIds: ids,
                          operationKey:
                              LocalMarketplaceRepository.newStoreOperationKey(
                                'seller-categories',
                              ),
                        ),
                    onSaved: _reloadSellerCategoriesAfterEdit,
                  ),
            onDone: () async {
              if (!await _saveProfileName(sellerName, seller: true)) return;
              if (mounted) {
                resetTo(
                  page == AppPage.sellerProfileSetup
                      ? AppPage.sellerDashboard
                      : AppPage.sellerProfile,
                );
              }
            },
          );
        }
        return BuyerProfileEditPage(
          realEmail: account?.email,
          contactEditor: contactEditor,
          profileDetailsEditor: account == null
              ? null
              : ProfileDetailsEditor(
                  readCurrent: () => account.profile,
                  readDisplayName: () => buyerName,
                  onSave: account.updateProfileDetails,
                  onSaved: () => showMessage('Profile saved.'),
                ),
          visibilityEditor: _discoveryBackend == null
              ? null
              : BuyerProfileVisibilityEditor(
                  key: ValueKey('buyer-visibility-${account?.userId}'),
                  backend: _discoveryBackend!,
                ),
          name: buyerName,
          avatarMediaId: _profileAvatarMediaId,
          avatarPending: _profileAvatarIntents.containsKey('buyer'),
          onRetryAvatar: () => unawaited(_retryProfileAvatar('buyer')),
          onDiscardAvatar: () => _discardProfileAvatar('buyer'),
          onNameChanged: updateBuyerName,
          onDone: () async {
            if (!await _saveProfileName(buyerName, seller: false)) return;
            if (mounted) resetTo(AppPage.buyerSettings);
          },
          onProfilePhotoAction: _changeBuyerProfileAvatar,
        );
      case AppPage.sellerSignup:
        return RoleAssetVariant(
          sourceRoot: 'assets/approved_onboarding_home',
          variantRoot: 'assets/approved_seller/onboarding_home',
          child: ApprovedAccountCreationPage(
            role: ApprovedAccountRole.seller,
            draft: _signupDraft,
            name: _signupDraft.name,
            onNameChanged: updateSellerName,
            onRoleChanged: (nextRole) {
              setState(
                () => role = nextRole == ApprovedAccountRole.buyer
                    ? UserRole.buyer
                    : UserRole.seller,
              );
              resetTo(
                nextRole == ApprovedAccountRole.buyer
                    ? AppPage.buyerSignup
                    : AppPage.sellerSignup,
              );
            },
            onClose: () => resetTo(AppPage.welcome),
            onSignup: () => go(AppPage.sellerTutorial),
            onLogin: () => completeAuthentication(
              UserRole.seller,
              AppPage.sellerDashboard,
            ),
            onUploadProfile: () => showMessage('Profile image picker opened.'),
          ),
        );
      case AppPage.sellerTutorial:
        return ApprovedSellerTutorialPage(
          onContinue: () => completeAuthentication(
            UserRole.seller,
            AppPage.sellerProfileSetup,
          ),
          onClose: () =>
              completeAuthentication(UserRole.seller, AppPage.sellerDashboard),
        );
      case AppPage.sellerVerification:
        final trustBackend = createConfiguredTrustBackend();
        return ApprovedSellerVerificationPage(
          onBack: back,
          onFinish: () => resetTo(AppPage.sellerDashboard),
          identityStatus: trustBackend == null
              ? null
              : switch (_accountHealth?.reviewStatus) {
                  'approved' => 'Review approved',
                  'pending' => 'Under review',
                  'rejected' => 'Review not approved',
                  'not_submitted' => 'Not submitted',
                  _ => 'Checking status…',
                },
          phoneStatus: trustBackend == null
              ? null
              : _accountHealth == null
              ? 'Checking status…'
              : _accountHealth!.phoneVerified
              ? 'Verified'
              : 'Not verified',
          areaStatus: trustBackend == null
              ? null
              : (widget.accountSession?.profile?.areaLabel?.trim().isNotEmpty ??
                    false)
              ? 'Area saved'
              : 'No area saved',
          reviewSection: trustBackend == null
              ? null
              : VerificationReviewPanel(
                  load: trustBackend.loadStatus,
                  onStatusChanged: () => unawaited(_refreshAccountHealth()),
                  submit: (kind, note, operationKey) =>
                      trustBackend.submitVerification(
                        kind: kind,
                        note: note,
                        operationKey: operationKey,
                      ),
                  appeal: (restrictionId, body, operationKey) =>
                      trustBackend.submitAppeal(
                        restrictionId: restrictionId,
                        body: body,
                        operationKey: operationKey,
                      ),
                  evidenceUpload: configuredImageUpload('review'),
                  attachEvidence: (id, media, key) =>
                      trustBackend.attachReviewEvidence(
                        submissionId: id,
                        mediaIds: media,
                        operationKey: key,
                      ),
                  detachEvidence: (id, media, key) =>
                      trustBackend.detachReviewEvidence(
                        submissionId: id,
                        mediaId: media,
                        operationKey: key,
                      ),
                ),
        );
      case AppPage.sellerDashboard:
        return _sellerShell(
          selected: SellerNavDestination.home,
          child: AnimatedBuilder(
            animation: _marketplace,
            builder: (context, _) => ApprovedSellerHomePage(
              onLeads: () => resetTo(AppPage.marketplace),
              onBrowseRequests: () => resetTo(AppPage.marketplace),
              onOfferHistory: () => go(AppPage.sellerOfferHistory),
              sellerName: sellerName,
              realLeads: _marketplace.isLeadsBacked
                  ? _marketplace.sellerLeads
                        .map(SellerLeadView.fromProjection)
                        .toList(growable: false)
                  : null,
              leadsLoading: _marketplace.sellerLeadsLoading,
              leadsError: _marketplace.sellerLeadsError,
              onRefreshLeads: _marketplace.refreshSellerLeads,
              offersCount: _marketplace.isSellerOffersBacked
                  ? _marketplace.sellerOffers.length
                  : null,
              offersLoading: _marketplace.sellerOffersLoading,
              offersError: _marketplace.sellerOffersError,
              onRefreshOffers: _marketplace.isSellerOffersBacked
                  ? () => unawaited(_marketplace.refreshSellerOffers())
                  : null,
              recommendedLeads: _recommendedLeads,
              recommendedLoading: _recommendedLeadsLoading,
              recommendedError: _recommendedLeadsError,
              onRefreshRecommended: _discoveryBackend == null
                  ? null
                  : () => unawaited(_refreshRecommendedLeads()),
              accountHealth: _accountHealth,
              accountHealthLoading: _accountHealthLoading,
              accountHealthError: _accountHealthError,
              onRefreshAccountHealth: () => unawaited(_refreshAccountHealth()),
              onOpenVerification: kTrustReviewEnabled
                  ? () => go(AppPage.sellerVerification)
                  : null,
              onAppealRestriction: kTrustReviewEnabled
                  ? (_) => go(AppPage.sellerVerification)
                  : null,
            ),
          ),
        );
      case AppPage.sellerStore:
        return _sellerShell(
          selected: SellerNavDestination.store,
          child: ApprovedSellerStorePage(
            repository: _marketplace,
            sellerName: sellerName,
            sellerProfileId: widget.accountSession?.profile?.membershipId,
            onStoreSettings: () => go(AppPage.sellerProfile),
          ),
        );
      case AppPage.marketplace:
        return _sellerShell(
          selected: SellerNavDestination.home,
          child: AnimatedBuilder(
            animation: _marketplace,
            builder: (context, _) => ApprovedSellerLeadsPage(
              sellerName: sellerName,
              onOfferSubmitted: _submitSellerOffer,
              onValidateLead: _marketplace.isOffersBacked
                  ? (lead) async {
                      final client = Supabase.instance.client;
                      final identity = client.auth.currentUser?.id;
                      if (identity == null || lead.requestId == null) {
                        return null;
                      }
                      final result = await createMarketplaceDataAdapter(
                        client: client,
                      ).fetchSellerRequest(lead.requestId!);
                      if (!mounted ||
                          page != AppPage.marketplace ||
                          identity != client.auth.currentUser?.id) {
                        return null;
                      }
                      final fresh = result.valueOrNull;
                      if (fresh == null ||
                          fresh.discoveryOpen == false ||
                          (fresh.acceptanceExpiresAt != null &&
                              !fresh.acceptanceExpiresAt!.isAfter(
                                DateTime.now().toUtc(),
                              ))) {
                        return null;
                      }
                      return SellerLeadView.fromProjection(fresh);
                    }
                  : null,
              leads: _marketplace.isLeadsBacked
                  ? _marketplace.sellerLeads
                        .map(SellerLeadView.fromProjection)
                        .toList(growable: false)
                  : null,
              leadsLoading: _marketplace.sellerLeadsLoading,
              leadsError: _marketplace.sellerLeadsError,
              onRefreshLeads: _marketplace.refreshSellerLeads,
              categories: _marketplace.storeCategories,
              categoriesLoading: _marketplace.leadCategoriesLoading,
              categoriesError: _marketplace.leadCategoriesError,
              onRefreshCategories: _marketplace.isStoreBacked
                  ? () => unawaited(_marketplace.refreshLeadCategories())
                  : null,
              offerTimezones: _marketplace.offerTimezones,
              uploadImage: _marketplace.isOffersBacked
                  ? configuredImageUpload('offer')
                  : null,
              onSubmitOffer: _marketplace.isOffersBacked
                  ? (lead, terms, operationKey) =>
                        _marketplace.submitOfferForRequest(
                          requestId: lead.requestId!,
                          terms: terms,
                          operationKey: operationKey,
                        )
                  : null,
              onChooseSpecificLocation: _marketplace.isOffersBacked
                  ? _chooseOfferPlace
                  : null,
              leadPaging:
                  _marketplace.leadsBackend is MarketplacePagedLeadsBackend
                  ? _marketplace.leadsBackend as MarketplacePagedLeadsBackend
                  : null,
              discoveryOrigin: _discoveryOrigin,
              discoveryOriginLoading: _discoveryOriginLoading,
              onSaveDiscoveryOrigin: _discoveryBackend == null
                  ? null
                  : (input, operationKey) => _discoveryBackend!.setOrigin(
                      input: input,
                      operationKey: operationKey,
                    ),
              onDiscoveryOriginSaved: (saved) {
                setState(() => _discoveryOrigin = saved);
                unawaited(_refreshRecommendedLeads());
              },
            ),
          ),
        );
      case AppPage.sellerMeets:
        return _sellerShell(
          selected: SellerNavDestination.meets,
          child: AnimatedBuilder(
            animation: _marketplace,
            builder: (context, _) => ApprovedSellerMeetsPage(
              meetings: _marketplace.isMeetingsBacked
                  ? _marketplace.meetings
                  : null,
              loading: _marketplace.meetingsLoading,
              hasMore: _marketplace.meetingsHasMore,
              onLoadMore: _marketplace.loadMoreMeetings,
              error: _marketplace.meetingsError,
              onRefresh: () async {
                await Future.wait([
                  _marketplace.refreshMeetings(),
                  _refreshConfirmedMeetings(),
                ]);
              },
              onOpenMeeting: (meeting) => _openMeetingById(meeting.meetingId),
              onMessageMeeting: (meeting) =>
                  unawaited(_openMeetingChat(meeting)),
              onDirectionsMeeting: (meeting) =>
                  unawaited(_openMeetingDirections(meeting)),
              onOpenChat: () => go(AppPage.sellerConversation),
              dealCompleted: dealCompleted,
              completedMeetingIds: _confirmedMeetingIds,
              onPinVerified: () {
                setState(() {
                  dealCompleted = true;
                  dealFailed = false;
                  _marketplace.updateOfferStatus(LocalOfferStatus.completed);
                });
                _saveSession();
              },
            ),
          ),
        );
      case AppPage.sellerChat:
        return _sellerShell(
          selected: SellerNavDestination.chats,
          child: AnimatedBuilder(
            animation: _marketplace,
            builder: (context, _) => ApprovedSellerChatsPage(
              onOpenConversation: () => go(AppPage.sellerConversation),
              latestOffer: _marketplace.latestOffer,
              latestMessagePreview: _latestConversationPreview,
              realThreads: _marketplace.isChatBacked
                  ? _marketplace.chatInbox
                        .map(
                          (summary) => ChatThreadView.fromSummary(
                            summary,
                            viewerUserId: widget.accountSession?.userId ?? '',
                          ),
                        )
                        .toList(growable: false)
                  : null,
              threadsLoading: _marketplace.chatInboxLoading,
              threadsError: _marketplace.chatInboxError,
              onRefreshThreads: _refreshChatInboxIfNeeded,
              onOpenThread: _openChatThread,
              onSearchConversations: _marketplace.isChatBacked
                  ? _searchChatConversations
                  : null,
            ),
          ),
        );
      case AppPage.sellerMore:
        return _sellerShell(
          selected: SellerNavDestination.more,
          child: ApprovedSellerMorePage(
            sellerName: sellerName,
            avatarMediaId: _profileAvatarMediaId,
            sellerEmail: widget.accountSession == null
                ? 'northside.tech@example.com'
                : (widget.accountSession?.email ?? ''),
            onProfile: () => go(AppPage.sellerProfile),
            onEditProfile: () => go(AppPage.editProfile),
            onSettings: () => go(AppPage.sellerSettings),
            onNotifications: () => go(AppPage.sellerNotificationPreferences),
            onAccessibility: () => go(AppPage.accessibility),
            onSafety: () => go(AppPage.safetyGuide),
            onHelp: () => go(AppPage.helpSupport),
            onOfferHistory: () => go(AppPage.sellerOfferHistory),
            onBilling: () => go(AppPage.sellerBilling),
            onLogout: logout,
          ),
        );
      case AppPage.sellerRequestDetail:
        return SellerRequestDetailPage(
          accent: accent,
          onOffer: () => go(AppPage.sendOffer),
        );
      case AppPage.sendOffer:
        return SendOfferPage(
          accent: accent,
          price: offerPrice,
          onPriceChanged: updateOfferPrice,
          onSubmit: () => commit(
            next: AppPage.offerSuccess,
            message: 'Offer saved on this device.',
            update: () => sellerOfferSent = true,
          ),
        );
      case AppPage.offerSuccess:
        return ResultPage(
          accent: accent,
          icon: Icons.outgoing_mail,
          title: 'Offer sent',
          body:
              'The buyer can now compare your offer and choose whether to open chat.',
          primaryLabel: 'View offer',
          onPrimary: () => go(AppPage.sellerOfferDetail),
          secondaryLabel: 'Offer history',
          onSecondary: () => resetTo(AppPage.sellerOfferHistory),
        );
      case AppPage.sellerOfferHistory:
        return AnimatedBuilder(
          animation: _marketplace,
          builder: (context, _) => ApprovedSellerOfferHistoryPage(
            onBack: back,
            sellerOfferSent: sellerOfferSent,
            offerSelected: offerSelected,
            onOpen: () => go(AppPage.sellerOfferDetail),
            latestOffer: _marketplace.latestOffer,
            realOffers: _marketplace.isSellerOffersBacked
                ? _marketplace.sellerOffers
                      .map(_sellerOfferView)
                      .toList(growable: false)
                : null,
            offersLoading: _marketplace.sellerOffersLoading,
            offersError: _marketplace.sellerOffersError,
            onRefreshOffers: () =>
                unawaited(_marketplace.refreshSellerOffers()),
            onOpenOffer: (view) {
              setState(() {
                _selectedSellerOffer = view;
                _withdrawError = null;
              });
              go(AppPage.sellerOfferDetail);
            },
          ),
        );
      case AppPage.sellerOfferDetail:
        return ApprovedSellerOfferDetailPage(
          onBack: back,
          onChat: _openSellerOfferChat,
          latestOffer: _marketplace.latestOffer,
          realOffer: _marketplace.isSellerOffersBacked
              ? _selectedSellerOffer
              : null,
          withdrawBusy: _withdrawBusy,
          withdrawError: _withdrawError,
          onWithdraw: _marketplace.isSellerOffersBacked
              ? _withdrawSelectedSellerOffer
              : null,
          onEdit: _marketplace.isSellerOffersBacked
              ? _editSelectedSellerOffer
              : null,
        );
      case AppPage.sellerOriginalRequest:
        return ApprovedSellerOriginalRequestPage(
          onBack: back,
          onReturnToChat: () => resetTo(AppPage.sellerConversation),
          realMode: _marketplace.isChatBacked,
          request: _conversationRequest,
          loading: _conversationRequestLoading,
          error: _conversationRequestError,
          onRetry: _openConversationRequest,
        );
      case AppPage.sellerConversation:
        _scheduleConversationDealsLoad();
        return _sellerShell(
          selected: SellerNavDestination.chats,
          showHeader: false,
          child: RoleAssetVariant(
            sourceRoot: 'assets/approved_offers_chat',
            variantRoot: 'assets/approved_seller/chat',
            child: AnimatedBuilder(
              animation: _marketplace,
              builder: (context, _) => ApprovedConversationBody(
                realContactName: _activeConversationName,
                key: _marketplace.isChatBacked
                    ? ValueKey(
                        'seller-chat-${_marketplace.activeConversationId}',
                      )
                    : const Key('sellerConversationCurrent'),
                realDeals: _conversationDeals,
                previousDeals: _previousConversationDeals,
                realDealsLoading: _conversationDealsLoading,
                realDealsError: _conversationDealsError,
                realDealsTruncated: _conversationDealsTruncated,
                onRefreshRealDeals: _marketplace.isMeetingsBacked
                    ? () => unawaited(_loadConversationDeals(force: true))
                    : null,
                onOpenRealDeal: _marketplace.isMeetingsBacked
                    ? (meetingId) => unawaited(_openConversationDeal(meetingId))
                    : null,
                onBack: back,
                onPrimary: _marketplace.isMeetingsBacked
                    ? _openConversationMeeting
                    : () => showMessage(
                        'Review and update this deal from the active-deal sheet.',
                      ),
                onCall: _openCall,
                onMore: () => go(AppPage.reportIssue),
                onRequestChange: () => showMessage('Request change opened.'),
                onChangeLocation: _openConversationMeeting,
                onAttach: _marketplace.chatAttachmentsSupported
                    ? () => unawaited(_pickAndSendChatAttachment())
                    : () => showMessage(
                        'Attachments are not connected yet. Text messages still send.',
                      ),
                attachmentsEnabled: _marketplace.chatAttachmentsSupported,
                pendingAttachmentMediaId:
                    _marketplace.pendingChatAttachment?.mediaIds.isNotEmpty ==
                        true
                    ? _marketplace.pendingChatAttachment!.mediaIds.first
                    : null,
                attachmentRetryBusy: _chatSending,
                onRetryAttachment: () => unawaited(_retryChatAttachment()),
                onDiscardAttachment: _discardChatAttachment,
                onSend: _sendChatMessage,
                onSubmitMessage: _marketplace.isChatBacked
                    ? _sendChatMessage
                    : null,
                initialDraft: _marketplace.unconfirmedChatText,
                onLearnMore: () => go(AppPage.safetyGuide),
                onViewProfile: () => go(AppPage.buyerPublicProfile),
                onViewOriginalRequest: _openConversationRequest,
                primaryLabel: 'Review deal details',
                viewerIsSeller: true,
                meetingConfirmed: meetingConfirmed,
                offerRevisionPending: offerRevisionPending,
                onOfferRevised: () => commit(
                  next: AppPage.sellerConversation,
                  message: 'Updated offer sent. The buyer has been notified.',
                  update: () => offerRevisionPending = true,
                ),
                requestChangePending: requestChangePending,
                onContinueWithRequest: () =>
                    setState(() => requestChangePending = false),
                onWithdrawFromRequest: () => commit(
                  next: AppPage.sellerChat,
                  message:
                      'Seller withdrew. Targeting credit restoration is pending database connection.',
                  update: () => requestChangePending = false,
                ),
                offer: _marketplace.latestOffer,
                sentEntries: _conversationEntriesFor(viewerIsSeller: true),
                onEntrySent: (entry) =>
                    _storeConversationEntry(entry, senderIsSeller: true),
                realEntries: _realConversationEntries(),
                messagesLoading: _marketplace.chatMessagesLoading,
                messagesError: _marketplace.chatMessagesError,
                onRefreshMessages: _refreshChatMessagesIfNeeded,
                onLoadOlder: _marketplace.chatHasOlder
                    ? _marketplace.loadOlderChatMessages
                    : null,
                olderLoading: _marketplace.chatOlderLoading,
                olderError: _marketplace.chatOlderError,
                sending: _chatSending,
                sendError: _chatSendError,
                muted: _marketplace.isChatBacked
                    ? _marketplace.chatMuted
                    : null,
                onMuteChanged: _marketplace.isChatBacked
                    ? _toggleChatMute
                    : null,
                blockState: _activeBlockState,
                blockWritePending: _blockWritePending,
                onBlockChanged: _marketplace.isChatBacked
                    ? _setConversationBlocked
                    : null,
                onSearchMessages: _marketplace.isChatBacked
                    ? _searchChatMessages
                    : null,
              ),
            ),
          ),
        );
      case AppPage.sellerBilling:
        return ApprovedSellerBillingPage(
          realContent: widget.accountSession != null
              ? const CreditWalletPanel()
              : null,
          onBack: back,
          onPayment: () => go(AppPage.sellerPaymentMethod),
        );
      case AppPage.sellerPaymentMethod:
        return ApprovedSellerPaymentMethodPage(
          onBack: back,
          realMode: widget.accountSession != null,
          onDone: () => resetTo(AppPage.sellerBilling),
        );
      case AppPage.sellerNotifications:
        return ApprovedSellerNotificationsPage(
          onBack: back,
          onPreferences: () => go(AppPage.sellerNotificationPreferences),
          repository: _marketplace,
          onOpenNotification: _openNotification,
        );
      case AppPage.sellerNotificationPreferences:
        return ApprovedSellerNotificationPreferencesPage(
          onBack: back,
          repository: _marketplace,
        );
      case AppPage.sellerProfile:
        if (_realAccountMode && !_sellerCategoriesRequested) {
          unawaited(_reloadSellerCategories());
        }
        final sellerCategories = _sellerCategorySelection;
        return ApprovedSellerProfilePage(
          sellerName: sellerName,
          onBack: back,
          onEditProfile: () => go(AppPage.editProfile),
          showPrototypeTrustDetails: !_realAccountMode,
          serviceAreaLabel: widget.accountSession?.profile?.areaLabel,
          categoryLabels: sellerCategories?.selected
              .map((option) => option.label)
              .toList(growable: false),
          retiredCategoryCount: sellerCategories?.retiredSelected.length ?? 0,
        );
    }
  }

  Widget bottomNav() {
    final items = role == UserRole.buyer
        ? _buyerBottomNavItems
        : _sellerBottomNavItems;
    final selected = role == UserRole.buyer
        ? _buyerSelectedNavIndex(page, items)
        : items.indexWhere((item) => item.page == page);

    if (role == UserRole.buyer) {
      final selectedIndex = selected < 0 ? 0 : selected;
      return BuyerBottomNavigation(
        navigationKey: const ValueKey('global-buyer-bottom-navigation'),
        contentKey: const ValueKey('global-buyer-bottom-navigation-content'),
        selected: ApprovedBuyerNavSelection.values[selectedIndex],
        callbacks: _approvedBuyerNavigation,
        accentColor: BuyerUiTokens.action,
      );
    }

    return SellerBottomNavigation(
      navigationKey: const ValueKey('global-seller-bottom-navigation'),
      selected: _sellerSelectedNavigation(page),
      callbacks: _sellerNavigation,
    );
  }

  Widget _sellerShell({
    required SellerNavDestination selected,
    required Widget child,
    bool showHeader = true,
  }) {
    return SellerAppShell(
      selected: selected,
      navigation: _sellerNavigation,
      onNotifications: () => go(AppPage.sellerNotifications),
      showHeader: showHeader,
      child: child,
    );
  }

  SellerNavDestination? _sellerSelectedNavigation(AppPage target) {
    if (target == AppPage.sellerDashboard) {
      return SellerNavDestination.home;
    }
    if ({AppPage.sellerStore}.contains(target)) {
      return SellerNavDestination.store;
    }
    if ({
      AppPage.marketplace,
      AppPage.sellerRequestDetail,
      AppPage.sellerOfferHistory,
      AppPage.sellerOfferDetail,
      AppPage.sendOffer,
    }.contains(target)) {
      return SellerNavDestination.home;
    }
    if (target == AppPage.sellerMeets) {
      return SellerNavDestination.meets;
    }
    if ({
      AppPage.sellerChat,
      AppPage.sellerConversation,
      AppPage.finalizeDeal,
      AppPage.meetingDetails,
      AppPage.sellerOriginalRequest,
      AppPage.buyerPublicProfile,
    }.contains(target)) {
      return SellerNavDestination.chats;
    }
    if ({
      AppPage.sellerMore,
      AppPage.sellerProfileSetup,
      AppPage.sellerVerification,
      AppPage.sellerProfile,
      AppPage.sellerSettings,
      AppPage.sellerBilling,
      AppPage.sellerPaymentMethod,
      AppPage.sellerNotifications,
      AppPage.sellerNotificationPreferences,
      AppPage.accessibility,
      AppPage.editProfile,
      AppPage.safetyGuide,
      AppPage.reportIssue,
      AppPage.helpSupport,
      AppPage.supportReviewStatus,
    }.contains(target)) {
      return SellerNavDestination.more;
    }
    return null;
  }

  int _buyerSelectedNavIndex(AppPage page, List<_NavItem> items) {
    if ({
      AppPage.createRequest,
      AppPage.recentActivity,
      AppPage.buyerRewardsDetail,
      AppPage.meetingDetails,
    }.contains(page)) {
      return 0;
    }
    if (page == AppPage.hocatrendsSellers) {
      return items.indexWhere((item) => item.page == AppPage.hocatrends);
    }
    if ({
      AppPage.buyerOfferDetail,
      AppPage.sellerPublicProfile,
      AppPage.buyerChat,
      AppPage.finalizeDeal,
      AppPage.buyerConfirmation,
      AppPage.dealRecovery,
    }.contains(page)) {
      return items.indexWhere((item) => item.page == AppPage.buyerChats);
    }
    if ({
      AppPage.buyerSupport,
      AppPage.buyerSettings,
      AppPage.accessibility,
      AppPage.editProfile,
      AppPage.buyerWallet,
      AppPage.withdrawal,
      AppPage.supportReviewStatus,
      AppPage.notifications,
      AppPage.buyerNotificationPreferences,
      AppPage.savedItems,
      AppPage.safetyGuide,
      AppPage.reportIssue,
      AppPage.helpSupport,
    }.contains(page)) {
      return items.indexWhere((item) => item.page == AppPage.buyerSupport);
    }
    return items.indexWhere((item) => item.page == page);
  }
}

class _LocalSessionData {
  const _LocalSessionData({
    required this.role,
    required this.authenticated,
    required this.page,
    required this.buyerName,
    required this.sellerName,
    required this.requestTitle,
    required this.requestBudget,
    required this.offerPrice,
    required this.requestPosted,
    required this.sellerOfferSent,
    required this.offerSelected,
    required this.meetingConfirmed,
    required this.dealFailed,
    required this.requestReopened,
    required this.dealCompleted,
    required this.withdrawalRequested,
    required this.dealSupportReviewRequested,
    required this.reportSubmitted,
    required this.darkMode,
    required this.accessibilityPreferences,
    required this.marketplaceSnapshot,
  });

  final UserRole role;
  final bool authenticated;
  final AppPage page;
  final String buyerName;
  final String sellerName;
  final String requestTitle;
  final String requestBudget;
  final String offerPrice;
  final bool requestPosted;
  final bool sellerOfferSent;
  final bool offerSelected;
  final bool meetingConfirmed;
  final bool dealFailed;
  final bool requestReopened;
  final bool dealCompleted;
  final bool withdrawalRequested;
  final bool dealSupportReviewRequested;
  final bool reportSubmitted;
  final bool darkMode;
  final AccessibilityPreferences accessibilityPreferences;
  final String marketplaceSnapshot;
}

class _LocalSessionStore {
  const _LocalSessionStore();

  static const _hasSession = 'hocalist.hasSession';
  static const _authenticated = 'hocalist.authenticated';
  static const _role = 'hocalist.role';
  static const _page = 'hocalist.page';
  static const _buyerName = 'hocalist.buyerName';
  static const _sellerName = 'hocalist.sellerName';
  static const _requestTitle = 'hocalist.requestTitle';
  static const _requestBudget = 'hocalist.requestBudget';
  static const _offerPrice = 'hocalist.offerPrice';
  static const _requestPosted = 'hocalist.requestPosted';
  static const _sellerOfferSent = 'hocalist.sellerOfferSent';
  static const _offerSelected = 'hocalist.offerSelected';
  static const _meetingConfirmed = 'hocalist.meetingConfirmed';
  static const _dealFailed = 'hocalist.dealFailed';
  static const _requestReopened = 'hocalist.requestReopened';
  static const _dealCompleted = 'hocalist.dealCompleted';
  static const _withdrawalRequested = 'hocalist.withdrawalRequested';
  static const _dealSupportReviewRequested =
      'hocalist.dealSupportReviewRequested';
  static const _reportSubmitted = 'hocalist.reportSubmitted';
  static const _darkMode = 'hocalist.darkMode';
  static const _textSize = 'hocalist.textSize';
  static const _accessibilityVersion = 'hocalist.accessibility.version';
  static const _accessibilityTextSize = 'hocalist.accessibility.textSize';
  static const _accessibilityFontStyle = 'hocalist.accessibility.fontStyle';
  static const _accessibilityButtonStyle = 'hocalist.accessibility.buttonStyle';
  static const _marketplaceSnapshot = 'hocalist.marketplace.snapshot.v1';

  Future<_LocalSessionData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_hasSession) ?? false)) return null;
    final restoredPage = _parsePage(prefs.getString(_page));
    return _LocalSessionData(
      role: _parseRole(prefs.getString(_role)),
      authenticated:
          prefs.getBool(_authenticated) ??
          _legacyPageWasAuthenticated(restoredPage),
      page: restoredPage,
      buyerName: prefs.getString(_buyerName) ?? 'Maya Chen',
      sellerName: prefs.getString(_sellerName) ?? 'Northside Tech',
      requestTitle:
          prefs.getString(_requestTitle) ?? 'iPad Air, 5th gen or newer',
      requestBudget: prefs.getString(_requestBudget) ?? '\$350 - \$480',
      offerPrice: prefs.getString(_offerPrice) ?? '\$420',
      requestPosted: prefs.getBool(_requestPosted) ?? false,
      sellerOfferSent: prefs.getBool(_sellerOfferSent) ?? false,
      offerSelected: prefs.getBool(_offerSelected) ?? false,
      meetingConfirmed: prefs.getBool(_meetingConfirmed) ?? false,
      dealFailed: prefs.getBool(_dealFailed) ?? false,
      requestReopened: prefs.getBool(_requestReopened) ?? false,
      dealCompleted: prefs.getBool(_dealCompleted) ?? false,
      withdrawalRequested: prefs.getBool(_withdrawalRequested) ?? false,
      dealSupportReviewRequested:
          prefs.getBool(_dealSupportReviewRequested) ?? false,
      reportSubmitted: prefs.getBool(_reportSubmitted) ?? false,
      darkMode: prefs.getBool(_darkMode) ?? false,
      accessibilityPreferences: AccessibilityPreferences(
        textSize: _parseTextSize(
          prefs.getString(_accessibilityTextSize) ?? prefs.getString(_textSize),
        ),
        fontStyle: _parseFontStyle(prefs.getString(_accessibilityFontStyle)),
        buttonStyle: _parseButtonStyle(
          prefs.getString(_accessibilityButtonStyle),
        ),
      ),
      marketplaceSnapshot: prefs.getString(_marketplaceSnapshot) ?? '',
    );
  }

  Future<void> save(_LocalSessionData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSession, true);
    await prefs.setBool(_authenticated, data.authenticated);
    await prefs.setString(_role, data.role.name);
    await prefs.setString(_page, data.page.name);
    await prefs.setString(_buyerName, data.buyerName);
    await prefs.setString(_sellerName, data.sellerName);
    await prefs.setString(_requestTitle, data.requestTitle);
    await prefs.setString(_requestBudget, data.requestBudget);
    await prefs.setString(_offerPrice, data.offerPrice);
    await prefs.setBool(_requestPosted, data.requestPosted);
    await prefs.setBool(_sellerOfferSent, data.sellerOfferSent);
    await prefs.setBool(_offerSelected, data.offerSelected);
    await prefs.setBool(_meetingConfirmed, data.meetingConfirmed);
    await prefs.setBool(_dealFailed, data.dealFailed);
    await prefs.setBool(_requestReopened, data.requestReopened);
    await prefs.setBool(_dealCompleted, data.dealCompleted);
    await prefs.setBool(_withdrawalRequested, data.withdrawalRequested);
    await prefs.setBool(
      _dealSupportReviewRequested,
      data.dealSupportReviewRequested,
    );
    await prefs.setBool(_reportSubmitted, data.reportSubmitted);
    await prefs.setBool(_darkMode, data.darkMode);
    await prefs.setInt(_accessibilityVersion, 1);
    await prefs.setString(
      _accessibilityTextSize,
      data.accessibilityPreferences.textSize.name,
    );
    await prefs.setString(
      _accessibilityFontStyle,
      data.accessibilityPreferences.fontStyle.name,
    );
    await prefs.setString(
      _accessibilityButtonStyle,
      data.accessibilityPreferences.buttonStyle.name,
    );
    await prefs.setString(
      _textSize,
      data.accessibilityPreferences.textSize.name,
    );
    await prefs.setString(_marketplaceSnapshot, data.marketplaceSnapshot);
  }

  UserRole _parseRole(String? value) {
    return UserRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => UserRole.buyer,
    );
  }

  AppPage _parsePage(String? value) {
    return AppPage.values.firstWhere(
      (page) => page.name == value,
      orElse: () => AppPage.welcome,
    );
  }

  bool _legacyPageWasAuthenticated(AppPage page) {
    return !{
      AppPage.welcome,
      AppPage.chooseRole,
      AppPage.buyerSignup,
      AppPage.buyerBenefits,
      AppPage.sellerSignup,
      AppPage.sellerTutorial,
      AppPage.hocatrends,
    }.contains(page);
  }

  AppTextSize _parseTextSize(String? value) {
    return AppTextSize.values.firstWhere(
      (size) => size.name == value,
      orElse: () => AppTextSize.medium,
    );
  }

  AccessibilityFontStyle _parseFontStyle(String? value) {
    return AccessibilityFontStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => AccessibilityFontStyle.standard,
    );
  }

  AccessibilityButtonStyle _parseButtonStyle(String? value) {
    return AccessibilityButtonStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => AccessibilityButtonStyle.rounded,
    );
  }
}

class _NavItem {
  const _NavItem(
    this.label,
    this.icon,
    this.page, {
    this.selectedIcon,
    this.asset,
  });
  final String label;
  final IconData icon;
  final AppPage page;
  final IconData? selectedIcon;
  final String? asset;
}

class AppFrame extends StatelessWidget {
  const AppFrame({
    required this.child,
    this.compactBottom = false,
    this.buyerTopLevel = false,
    this.header,
    this.scrollKey,
    this.childOwnsScroll = false,
    super.key,
  });

  final Widget child;
  final bool compactBottom;
  final bool buyerTopLevel;
  final Widget? header;
  final Key? scrollKey;
  final bool childOwnsScroll;

  @override
  Widget build(BuildContext context) {
    if (childOwnsScroll) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[header!, const SizedBox(height: 18)],
            Expanded(child: child),
          ],
        ),
      );
    }
    if (buyerTopLevel) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final metrics = ApprovedReplicaMetrics.resolve(
            availableWidth: constraints.maxWidth,
            textScaler: MediaQuery.textScalerOf(context),
          );
          final horizontal = metrics.pageHorizontalPadding(18);
          return ApprovedReplicaScope(
            metrics: metrics,
            child: ListView(
              key: scrollKey ?? const ValueKey('buyer-top-level-page-scroll'),
              padding: EdgeInsets.fromLTRB(
                horizontal,
                metrics.spacing(8),
                horizontal,
                metrics.spacing(24),
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: metrics.innerContentMaxWidth(
                        referenceHorizontalInset: 18,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (header != null) ...[
                          header!,
                          SizedBox(height: metrics.spacing(6)),
                        ],
                        child,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return ListView(
      key: scrollKey,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 56),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 18)],
        child,
      ],
    );
  }
}

class WelcomePageFrame extends StatelessWidget {
  const WelcomePageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 86),
      children: [child],
    );
  }
}

class AuthPageFrame extends StatelessWidget {
  const AuthPageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [child],
    );
  }
}
