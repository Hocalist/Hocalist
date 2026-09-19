import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/local_marketplace_repository.dart';
import 'features/approved/offers_chat_pages.dart';
import 'features/approved/onboarding_home_pages.dart';
import 'features/approved/approved_replica_metrics.dart';
import 'features/approved/request_flow_pages.dart';
import 'features/approved/trends_notifications_pages.dart';
import 'features/seller/approved_seller_home_page.dart';
import 'features/seller/approved_seller_leads_page.dart';
import 'features/seller/approved_seller_meets_page.dart';
import 'features/seller/approved_seller_chats_page.dart';
import 'features/seller/approved_seller_account_pages.dart';
import 'features/seller/approved_seller_more_page.dart';
import 'features/seller/approved_seller_tutorial_page.dart';
import 'features/seller/seller_app_shell.dart';
import 'features/seller/seller_bottom_navigation.dart';
import 'theme/accessibility_visuals.dart';
import 'theme/buyer_ui_foundation.dart';
import 'theme/input_foundation.dart';
import 'theme/role_asset_bundle.dart';

export 'theme/accessibility_visuals.dart';

part 'components/ui_components.dart';
part 'features/accessibility/accessibility_page.dart';
part 'features/accessibility/accessibility_preferences.dart';
part 'features/screens.dart';
part 'theme/hocalist_theme.dart';

void main() {
  runApp(const HocalistApp());
}

class HocalistApp extends StatelessWidget {
  const HocalistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const HocalistPrototype();
  }
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
  sellerSignup,
  sellerTutorial,
  sellerProfileSetup,
  sellerVerification,
  sellerDashboard,
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

class HocalistPrototype extends StatefulWidget {
  const HocalistPrototype({super.key});

  @override
  State<HocalistPrototype> createState() => _HocalistPrototypeState();
}

class _HocalistPrototypeState extends State<HocalistPrototype> {
  static const _storage = _LocalSessionStore();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final LocalMarketplaceRepository _marketplace = LocalMarketplaceRepository();

  UserRole role = UserRole.buyer;
  bool authenticated = false;
  AppPage page = AppPage.welcome;
  final history = <AppPage>[];

  String buyerName = 'Maya Chen';
  String sellerName = 'Northside Tech';
  String requestTitle = 'iPad Air, 5th gen or newer';
  String requestBudget = '\$350 - \$480';
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
  bool get showGlobalBack =>
      signedIn && history.isNotEmpty && !_isBottomNavPage(page);
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
        AppPage.buyerRequestDetail,
        AppPage.offersReceived,
        AppPage.buyerOfferDetail,
        AppPage.buyerChat,
        AppPage.buyerConfirmation,
        AppPage.dealRecovery,
        AppPage.buyerReview,
        AppPage.buyerWallet,
        AppPage.sellerDashboard,
        AppPage.marketplace,
        AppPage.sellerMeets,
        AppPage.sellerChat,
        AppPage.sellerMore,
        AppPage.sellerConversation,
      }.contains(page);
  bool get _suppressesGlobalHeader =>
      {
        AppPage.hocatrendsSellers,
        AppPage.recentActivity,
        AppPage.sellerProfile,
        AppPage.sellerProfileSetup,
        AppPage.sellerVerification,
        AppPage.sellerOfferHistory,
        AppPage.sellerOfferDetail,
        AppPage.sellerOriginalRequest,
        AppPage.buyerPublicProfile,
        AppPage.sellerBilling,
        AppPage.sellerPaymentMethod,
        AppPage.sellerSettings,
        AppPage.sellerNotifications,
        AppPage.sellerNotificationPreferences,
        AppPage.safetyGuide,
        AppPage.helpSupport,
        AppPage.editProfile,
      }.contains(page) ||
      (role == UserRole.buyer &&
          {
            AppPage.buyerNotificationPreferences,
            AppPage.savedItems,
            AppPage.safetyGuide,
            AppPage.reportIssue,
            AppPage.helpSupport,
            AppPage.supportReviewStatus,
            AppPage.sellerPublicProfile,
            AppPage.withdrawal,
            AppPage.buyerSettings,
          }.contains(page));

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
    onLeads: () => resetTo(AppPage.marketplace),
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
    _NavItem('Leads', Icons.person_outline, AppPage.marketplace),
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
    _restoreSession();
  }

  @override
  void dispose() {
    _marketplace.dispose();
    super.dispose();
  }

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

  Future<void> _saveSession() {
    return _storage.save(
      _LocalSessionData(
        role: role,
        authenticated: authenticated,
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
      history.add(page);
      page = destination;
    });
    _saveSession();
  }

  void commit({
    required AppPage next,
    required String message,
    VoidCallback? update,
    bool resetHistory = false,
  }) {
    final destination = _upgradedDestination(next);
    setState(() {
      update?.call();
      if (resetHistory) {
        history.clear();
      } else {
        history.add(page);
      }
      page = destination;
    });
    _saveSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showMessage(message);
    });
  }

  void resetTo(AppPage next) {
    final destination = _upgradedDestination(next);
    setState(() {
      history.clear();
      page = destination;
    });
    _saveSession();
  }

  void completeAuthentication(UserRole nextRole, AppPage nextPage) {
    final destination = _upgradedDestination(nextPage, forRole: nextRole);
    setState(() {
      role = nextRole;
      authenticated = true;
      history.clear();
      page = destination;
    });
    _saveSession();
  }

  AppPage _upgradedDestination(AppPage requested, {UserRole? forRole}) {
    return upgradedDestinationFor(requested, forRole ?? role);
  }

  void logout() {
    setState(() {
      authenticated = false;
      history.clear();
      page = AppPage.welcome;
    });
    _saveSession();
  }

  void submitBuyerRequest() {
    setState(() {
      requestPosted = true;
      history.clear();
      page = AppPage.buyerDashboard;
    });
    _saveSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showMessage('Request posted. You are back home.');
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
    if (history.isEmpty) return;
    setState(() => page = history.removeLast());
    _saveSession();
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
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final phoneScale = media.textScaler.scale(1);
        final selectedScale = accessibilityPreferences.textSize.scale;
        final effectiveScale = phoneScale > 1
            ? math.max(phoneScale, selectedScale)
            : selectedScale;
        final clampedScale = effectiveScale.clamp(0.9, 1.6).toDouble();
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(clampedScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(
        body: _usesIntegratedPageChrome
            ? AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(page), child: currentPage()),
              )
            : SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: page == AppPage.accessibility
                      ? KeyedSubtree(key: ValueKey(page), child: currentPage())
                      : AppFrame(
                          key: ValueKey(page),
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
                            child: currentPage(),
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

  Widget currentPage() {
    switch (page) {
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
          name: buyerName,
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
          onClose: () => resetTo(AppPage.welcome),
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
        return ApprovedBuyerHomePage(
          name: buyerName,
          requestTitle: requestTitle,
          requestPosted: requestPosted,
          onCreate: () => go(AppPage.createRequest),
          onRequestDetails: () => go(AppPage.buyerRequestDetail),
          onOffers: () => go(AppPage.offersReceived),
          onRecentActivity: () => go(AppPage.recentActivity),
          onWallet: () => go(AppPage.buyerRewardsDetail),
          meetingConfirmed: meetingConfirmed,
          onMeetingDetails: () => go(AppPage.meetingDetails),
          onNotifications: () => go(AppPage.notifications),
          onHome: () => resetTo(AppPage.buyerDashboard),
          onTrends: () => resetTo(AppPage.hocatrends),
          onOffersTab: () => resetTo(AppPage.offersReceived),
          onChats: () => resetTo(AppPage.buyerChats),
          onMore: () => resetTo(AppPage.buyerSupport),
        );
      case AppPage.recentActivity:
        return ApprovedBuyerNotificationsPage(onBack: back);
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
          onSeeSellers: () => go(AppPage.hocatrendsSellers),
        );
      case AppPage.hocatrendsSellers:
        return ApprovedHocatrendsPickedSellersPage(
          onBack: back,
          onChatSeller: () => go(AppPage.buyerChat),
          onNotifications: () => go(AppPage.notifications),
        );
      case AppPage.createRequest:
        return ApprovedRequestFlowPage(
          accent: accent,
          requestTitle: requestTitle,
          budget: requestBudget,
          onTitleChanged: updateRequestTitle,
          onBudgetChanged: updateRequestBudget,
          onBack: back,
          onNotifications: () => go(AppPage.notifications),
          onSubmit: submitBuyerRequest,
          includeAppChrome: true,
          onHome: () => resetTo(AppPage.buyerDashboard),
          onHocatrends: () => resetTo(AppPage.hocatrends),
          onOffers: () => resetTo(AppPage.offersReceived),
          onChats: () => resetTo(AppPage.buyerChats),
          onMore: () => resetTo(AppPage.buyerSupport),
        );
      case AppPage.requestSuccess:
        return ResultPage(
          accent: accent,
          icon: Icons.check_circle_outline,
          title: 'Request posted',
          body:
              'Sellers nearby can now send offers. You can review the request or wait for new offer alerts.',
          primaryLabel: 'View request',
          onPrimary: () => go(AppPage.buyerRequestDetail),
          secondaryLabel: 'Back to dashboard',
          onSecondary: () => resetTo(AppPage.buyerDashboard),
        );
      case AppPage.buyerRequestDetail:
        return ApprovedBuyerRequestDetailsPage(
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
        );
      case AppPage.offersReceived:
        return ApprovedOffersReceivedPage(
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
          onFilter: () => showMessage('Offer filters opened.'),
          navigation: _approvedBuyerNavigation,
          latestOffer: _marketplace.latestOffer,
        );
      case AppPage.buyerOfferDetail:
        return ApprovedViewOfferPage(
          onBack: back,
          onNotifications: () => go(AppPage.notifications),
          onSelectSeller: () => commit(
            next: AppPage.buyerChat,
            message: 'Seller selected. Chatroom opened.',
            update: () {
              offerSelected = true;
              _marketplace.updateOfferStatus(LocalOfferStatus.selected);
            },
          ),
          onViewProfile: () => go(AppPage.sellerPublicProfile),
          navigation: _approvedBuyerNavigation,
          latestOffer: _marketplace.latestOffer,
        );
      case AppPage.sellerPublicProfile:
        return ApprovedSellerPublicProfilePage(
          onBack: back,
          onSelect: () => commit(
            next: AppPage.buyerChat,
            message: 'Seller selected. Chatroom opened.',
            update: () {
              offerSelected = true;
              _marketplace.updateOfferStatus(LocalOfferStatus.selected);
            },
          ),
        );
      case AppPage.buyerPublicProfile:
        return ApprovedBuyerPublicProfilePage(onBack: back);
      case AppPage.buyerChats:
        return BuyerChatsPage(
          onBack: back,
          onOpenChat: () => go(AppPage.buyerChat),
          onOffers: () => go(AppPage.offersReceived),
          latestOffer: _marketplace.latestOffer,
          latestMessagePreview: _latestConversationPreview,
        );
      case AppPage.buyerChat:
        return ApprovedBuyerChatPage(
          onBack: back,
          onPrimary: () => commit(
            next: AppPage.buyerDashboard,
            message: 'Meeting confirmed and added to Upcoming meetings.',
            update: () {
              offerSelected = true;
              meetingConfirmed = true;
              _marketplace.updateOfferStatus(LocalOfferStatus.meetingConfirmed);
            },
          ),
          primaryLabel: 'Accept to meet',
          onCall: () => showMessage('Calling is available after confirmation.'),
          onMore: () => go(AppPage.reportIssue),
          onRequestChange: () => showMessage('Request change opened.'),
          onChangeLocation: () => go(AppPage.meetingDetails),
          onAttach: () => showMessage('Attachment ready to send.'),
          onSend: (message) {
            if (message.isNotEmpty) showMessage('Message sent.');
          },
          onLearnMore: () => go(AppPage.safetyGuide),
          onViewProfile: () => go(AppPage.sellerPublicProfile),
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
              _marketplace.updateOfferStatus(LocalOfferStatus.meetingConfirmed);
            },
          ),
          offer: _marketplace.latestOffer,
          sentEntries: _conversationEntriesFor(viewerIsSeller: false),
          onEntrySent: (entry) =>
              _storeConversationEntry(entry, senderIsSeller: false),
        );
      case AppPage.finalizeDeal:
        return FinalizeDealPage(
          accent: accent,
          price: offerPrice,
          onContinue: () => go(AppPage.meetingDetails),
        );
      case AppPage.meetingDetails:
        final meetingDetails = ApprovedMeetingDetailsPage(
          onBack: back,
          onConfirm: () => commit(
            next: AppPage.buyerConfirmation,
            message: 'Meeting details saved for both sides.',
            update: () => meetingConfirmed = true,
          ),
        );
        return role == UserRole.seller
            ? RoleAssetVariant(
                sourceRoot: 'assets/approved_onboarding_home',
                variantRoot: 'assets/approved_seller/onboarding_home',
                child: meetingDetails,
              )
            : meetingDetails;
      case AppPage.buyerConfirmation:
        return ApprovedBuyerAfterMeetupPage(
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
        return ApprovedBuyerDealRecoveryPage(
          onBack: back,
          navigation: _approvedBuyerNavigation,
          onReopen: () => commit(
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
        );
      case AppPage.buyerReview:
        return ApprovedBuyerReviewPage(
          onBack: back,
          navigation: _approvedBuyerNavigation,
          onFinish: () => resetTo(AppPage.buyerWallet),
        );
      case AppPage.buyerWallet:
        return ApprovedBuyerDealHistoryPage(
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
          onSupport: () {
            setState(() => dealSupportReviewRequested = true);
            _saveSession();
            showMessage('Support review request saved.');
          },
        );
      case AppPage.buyerRewardsDetail:
        return ApprovedBuyerRewardsDetailPage(
          onBack: back,
          onDealHistory: () => go(AppPage.buyerWallet),
          onWithdraw: () => go(AppPage.withdrawal),
        );
      case AppPage.withdrawal:
        return ApprovedBuyerWithdrawalPage(
          onBack: back,
          onComplete: () {
            setState(() => withdrawalRequested = true);
            _saveSession();
            showMessage('Withdrawal request saved for payout processing.');
          },
        );
      case AppPage.supportReviewStatus:
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
          email: 'maya.chen@example.com',
          onNotifications: () => go(AppPage.buyerNotificationPreferences),
          onRewards: () => go(AppPage.buyerRewardsDetail),
          onSaved: () => go(AppPage.savedItems),
          onSafety: () => go(AppPage.safetyGuide),
          onReport: () => go(AppPage.reportIssue),
          onHelp: () => go(AppPage.helpSupport),
          onEditProfile: () => go(AppPage.editProfile),
          onSettings: () => go(AppPage.buyerSettings),
          onLogout: logout,
          onProfilePhotoAction: (action) => showMessage(switch (action) {
            BuyerProfilePhotoAction.camera => 'Camera opened.',
            BuyerProfilePhotoAction.gallery => 'Photo library opened.',
            BuyerProfilePhotoAction.remove => 'Profile picture removed.',
          }),
        );
      case AppPage.notifications:
        return ApprovedBuyerNotificationsPage(
          onBack: back,
          title: 'Notifications',
        );
      case AppPage.buyerNotificationPreferences:
        return BuyerNotificationPreferencesPage(accent: accent);
      case AppPage.savedItems:
        return SavedItemsPage(accent: accent);
      case AppPage.safetyGuide:
        if (role == UserRole.seller) {
          return ApprovedSellerSafetyGuidePage(
            onBack: back,
            onHelp: () => go(AppPage.helpSupport),
          );
        }
        return SafetyGuidePage(accent: accent);
      case AppPage.reportIssue:
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
          );
        }
        return HelpSupportPage(
          accent: accent,
          onReport: () => go(AppPage.reportIssue),
          onContactSupport: () => go(AppPage.supportReviewStatus),
        );
      case AppPage.buyerSettings:
        return BuyerSettingsPage(
          darkMode: darkMode,
          textSize: textSize,
          onEditProfile: () => go(AppPage.editProfile),
          onThemeChanged: updateThemeMode,
          onAccessibility: () => go(AppPage.accessibility),
        );
      case AppPage.sellerSettings:
        return ApprovedSellerSettingsPage(
          darkMode: darkMode,
          textSizeLabel: textSize.label,
          onBack: back,
          onEditProfile: () => go(AppPage.editProfile),
          onThemeChanged: updateThemeMode,
          onAccessibility: () => go(AppPage.accessibility),
        );
      case AppPage.accessibility:
        return AccessibilityPage(
          appliedPreferences: accessibilityPreferences,
          onApply: applyAccessibilityPreferences,
          onBack: back,
        );
      case AppPage.editProfile:
        if (role == UserRole.seller) {
          return ApprovedSellerEditProfilePage(
            name: sellerName,
            onNameChanged: updateSellerName,
            onBack: back,
            onDone: () => resetTo(AppPage.sellerProfile),
          );
        }
        return BuyerProfileEditPage(
          name: buyerName,
          onNameChanged: updateBuyerName,
          onDone: () => resetTo(AppPage.buyerSettings),
          onProfilePhotoAction: (action) => showMessage(switch (action) {
            BuyerProfilePhotoAction.camera => 'Camera opened.',
            BuyerProfilePhotoAction.gallery => 'Photo library opened.',
            BuyerProfilePhotoAction.remove => 'Profile picture removed.',
          }),
        );
      case AppPage.sellerSignup:
        return RoleAssetVariant(
          sourceRoot: 'assets/approved_onboarding_home',
          variantRoot: 'assets/approved_seller/onboarding_home',
          child: ApprovedAccountCreationPage(
            role: ApprovedAccountRole.seller,
            name: sellerName,
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
          onContinue: () =>
              completeAuthentication(UserRole.seller, AppPage.sellerDashboard),
          onClose: () =>
              completeAuthentication(UserRole.seller, AppPage.sellerDashboard),
        );
      case AppPage.sellerProfileSetup:
        return ApprovedSellerProfileSetupPage(
          onBack: () => resetTo(AppPage.sellerTutorial),
          onContinue: () => go(AppPage.sellerVerification),
        );
      case AppPage.sellerVerification:
        return ApprovedSellerVerificationPage(
          onBack: back,
          onFinish: () => resetTo(AppPage.sellerDashboard),
        );
      case AppPage.sellerDashboard:
        return _sellerShell(
          selected: SellerNavDestination.home,
          child: ApprovedSellerHomePage(
            onLeads: () => resetTo(AppPage.marketplace),
            onBrowseRequests: () => resetTo(AppPage.marketplace),
          ),
        );
      case AppPage.marketplace:
        return _sellerShell(
          selected: SellerNavDestination.leads,
          child: ApprovedSellerLeadsPage(
            sellerName: sellerName,
            onOfferSubmitted: _submitSellerOffer,
          ),
        );
      case AppPage.sellerMeets:
        return _sellerShell(
          selected: SellerNavDestination.meets,
          child: ApprovedSellerMeetsPage(
            onOpenChat: () => go(AppPage.sellerConversation),
            dealCompleted: dealCompleted,
            onPinVerified: () {
              setState(() {
                dealCompleted = true;
                dealFailed = false;
                _marketplace.updateOfferStatus(LocalOfferStatus.completed);
              });
              _saveSession();
            },
          ),
        );
      case AppPage.sellerChat:
        return _sellerShell(
          selected: SellerNavDestination.chats,
          child: ApprovedSellerChatsPage(
            onOpenConversation: () => go(AppPage.sellerConversation),
            latestOffer: _marketplace.latestOffer,
            latestMessagePreview: _latestConversationPreview,
          ),
        );
      case AppPage.sellerMore:
        return _sellerShell(
          selected: SellerNavDestination.more,
          child: ApprovedSellerMorePage(
            sellerName: sellerName,
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
        return ApprovedSellerOfferHistoryPage(
          onBack: back,
          sellerOfferSent: sellerOfferSent,
          offerSelected: offerSelected,
          onOpen: () => go(AppPage.sellerOfferDetail),
          latestOffer: _marketplace.latestOffer,
        );
      case AppPage.sellerOfferDetail:
        return ApprovedSellerOfferDetailPage(
          onBack: back,
          onChat: () => go(AppPage.sellerConversation),
          latestOffer: _marketplace.latestOffer,
        );
      case AppPage.sellerOriginalRequest:
        return ApprovedSellerOriginalRequestPage(
          onBack: back,
          onReturnToChat: () => resetTo(AppPage.sellerConversation),
        );
      case AppPage.sellerConversation:
        return _sellerShell(
          selected: SellerNavDestination.chats,
          showHeader: false,
          child: RoleAssetVariant(
            sourceRoot: 'assets/approved_offers_chat',
            variantRoot: 'assets/approved_seller/chat',
            child: ApprovedConversationBody(
              key: const Key('sellerConversationCurrent'),
              onBack: back,
              onPrimary: () => showMessage(
                'Review and update this deal from the active-deal sheet.',
              ),
              onCall: () => showMessage(
                'Calling is available after meeting confirmation.',
              ),
              onMore: () => go(AppPage.reportIssue),
              onRequestChange: () => showMessage('Request change opened.'),
              onChangeLocation: () => go(AppPage.meetingDetails),
              onAttach: () => showMessage('Attachment ready to send.'),
              onSend: (message) {
                if (message.isNotEmpty) showMessage('Message sent.');
              },
              onLearnMore: () => go(AppPage.safetyGuide),
              onViewProfile: () => go(AppPage.buyerPublicProfile),
              onViewOriginalRequest: () => go(AppPage.sellerOriginalRequest),
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
              contactName: buyerName,
              contactRoleLabel: 'Verified Buyer',
              contactInitials: 'MC',
              incomingMessage:
                  'Looks good! I\'m ready to move forward. Does Saturday still work?',
              outgoingMessage:
                  'Yes, the iPad is in perfect condition like we discussed.',
            ),
          ),
        );
      case AppPage.sellerBilling:
        return ApprovedSellerBillingPage(
          onBack: back,
          onPayment: () => go(AppPage.sellerPaymentMethod),
        );
      case AppPage.sellerPaymentMethod:
        return ApprovedSellerPaymentMethodPage(
          onBack: back,
          onDone: () => resetTo(AppPage.sellerBilling),
        );
      case AppPage.sellerNotifications:
        return ApprovedSellerNotificationsPage(
          onBack: back,
          onPreferences: () => go(AppPage.sellerNotificationPreferences),
        );
      case AppPage.sellerNotificationPreferences:
        return ApprovedSellerNotificationPreferencesPage(onBack: back);
      case AppPage.sellerProfile:
        return ApprovedSellerProfilePage(
          sellerName: sellerName,
          onBack: back,
          onEditProfile: () => go(AppPage.editProfile),
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
    if ({
      AppPage.marketplace,
      AppPage.sellerRequestDetail,
      AppPage.sendOffer,
    }.contains(target)) {
      return SellerNavDestination.leads;
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
    super.key,
  });

  final Widget child;
  final bool compactBottom;
  final bool buyerTopLevel;
  final Widget? header;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) {
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
