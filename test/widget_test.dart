import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hocalist/features/approved/buyer_deal_card.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';

import 'test_fonts.dart';

ImageProvider _assetProvider(ImageProvider provider) => provider is ResizeImage ? provider.imageProvider : provider;

void main() {
  setUpAll(loadHocalistTestFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const analytics = MethodChannel('hocalist/marketplace_analytics');
    messenger.setMockMethodCallHandler(analytics, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(analytics, null));
  });

  void useTallMobileViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void useAccessibleTextViewport(WidgetTester tester) {
    useTallMobileViewport(tester);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
  }

  void useBossPhoneTextViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
  }

  Future<void> tapVisible(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
    await tester.ensureVisible(finder.last);
    await tester.pumpAndSettle();
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  Future<void> revealInApprovedScroll(
    WidgetTester tester,
    Finder target,
    Key scrollKey,
  ) async {
    final scrollable = find
        .descendant(
          of: find.byKey(scrollKey),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      target,
      280,
      scrollable: scrollable,
      maxScrolls: 20,
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final rect = tester.getRect(target);
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final lowerLimit = viewportHeight - 110;
    if (rect.bottom > lowerLimit) {
      await tester.drag(
        find.byKey(scrollKey),
        Offset(0, -(rect.bottom - lowerLimit)),
      );
      await tester.pumpAndSettle();
    } else if (rect.top < 20) {
      await tester.drag(find.byKey(scrollKey), Offset(0, 20 - rect.top));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapHomeRole(WidgetTester tester, int index) async {
    await tester.pumpAndSettle();
    final labels = [
      'I am buying. Post a request and compare offers from sellers.',
      'I am selling. Browse buyer requests and send offers.',
    ];
    final card = find.bySemanticsLabel(labels[index]);
    expect(card, findsOneWidget);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    if (index == 0) {
      await tester.enterText(
        find.byKey(const ValueKey('approved-account-name-field')),
        'Maya Chen',
      );
    }
  }

  Future<void> completeSellerSignup(WidgetTester tester) async {
    await tapHomeRole(tester, 1);
    await tapVisible(tester, 'Create account');
    final continueButton = find.byKey(const Key('sellerTutorialContinue'));
    await tester.scrollUntilVisible(
      continueButton,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerTutorialScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Save profile');
  }

  Future<void> finishBuyerOnboarding(WidgetTester tester) async {
    await tapVisible(tester, 'Jump to dashboard');
  }

  Future<void> postBuyerRequest(WidgetTester tester) async {
    await tapVisible(tester, 'Post a new request');
    await tapVisible(tester, 'Continue');
    await tapVisible(tester, 'Post request');
    expect(find.byType(ApprovedRequestPostedDialog), findsOneWidget);
    await tapVisible(tester, 'Back to dashboard');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> openBuyerDashboard(WidgetTester tester) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    await postBuyerRequest(tester);
    expect(find.textContaining('Maya'), findsOneWidget);
  }

  Future<void> openRequestEditor(WidgetTester tester) async {
    final options = find.byKey(const ValueKey('approved-active-request-card')).first;
    await tester.ensureVisible(options);
    await tester.pumpAndSettle();
    await tester.longPress(options);
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Edit request');
  }

  Future<void> openSampleOfferChat(WidgetTester tester) async {
    final sellerCard = find.byWidgetPredicate(
      (widget) =>
          widget is BuyerDealCard && widget.sellerName == 'Northside Tech',
    );
    final chatButton = find.descendant(
      of: sellerCard,
      matching: find.widgetWithText(BuyerPrimaryButton, 'Chat with seller'),
    );
    await revealInApprovedScroll(
      tester,
      chatButton,
      const Key('approved-offers-scroll'),
    );
    await tester.tap(chatButton);
    await tester.pumpAndSettle();
  }

  testWidgets('approved home renders supplied logo and interactive FAQ', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.byType(ApprovedNoAccountHomePage), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'I am buying. Post a request and compare offers from sellers.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'I am selling. Browse buyer requests and send offers.',
      ),
      findsOneWidget,
    );
    expect(find.text('See How Hocalist Works'), findsOneWidget);
    expect(find.text('Frequently Asked Questions'), findsOneWidget);
    expect(find.text('Create Free Account'), findsOneWidget);
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            _assetProvider(widget.image) is AssetImage &&
            (_assetProvider(widget.image) as AssetImage).assetName ==
                'assets/brand/hocalist-wordmark.png',
      ),
    );
    expect(_assetProvider(image.image), isA<AssetImage>());
    expect(
      (_assetProvider(image.image) as AssetImage).assetName,
      'assets/brand/hocalist-wordmark.png',
    );
    expect(
      find.text(
        'Hocalist is a reverse marketplace where buyers post what they need and sellers compete for the opportunity to earn your business.',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, 'Does Hocalist sell the items I buy?');
    expect(
      find.text(
        'No. Buyers choose sellers and arrange the item handoff directly after selection.',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, 'Does Hocalist sell the items I buy?');
    expect(
      find.text(
        'No. Buyers choose sellers and arrange the item handoff directly after selection.',
      ),
      findsNothing,
    );
    await tapVisible(tester, 'View all');
    expect(
      find.text(
        'Sellers can target real buyers who are actively looking instead of spending broadly on ads.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('logged-out Hocatrends nav opens approved redesign', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('approved-public-nav-hocatrends')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ApprovedNoAccountBottomNavigation>(
            find.byType(ApprovedNoAccountBottomNavigation),
          )
          .selectedIndex,
      1,
    );
    expect(find.byType(ApprovedPublicHocatrendsPage), findsOneWidget);
    expect(find.byType(ApprovedHocatrendsPage), findsOneWidget);
    expect(find.text('Hocatrends preview is coming soon.'), findsNothing);
    expect(
      find.byKey(const ValueKey('approved-bottom-navigation')),
      findsOneWidget,
    );
    expect(find.text('Winners'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Offers'), findsNothing);
    expect(find.text('Chats'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logged-out Hocatrends see sellers opens buyer account access', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('approved-public-nav-hocatrends')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('See Sellers').first);
    await tester.tap(find.text('See Sellers').first);
    await tester.pumpAndSettle();

    final accountPage = find.byType(ApprovedAccountCreationPage);
    expect(accountPage, findsOneWidget);
    expect(
      tester.widget<ApprovedAccountCreationPage>(accountPage).role,
      ApprovedAccountRole.buyer,
    );
    expect(find.text('iPad Air Sellers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hocatrends category cards tolerate common phone widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[344, 360, 390, 430]) {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          theme: HocalistTheme.light,
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ApprovedHocatrendsPage(
                  accent: HocalistTheme.actionBlue,
                  onSeeSellers: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Trending Products & Services'),
        findsOneWidget,
      );
      expect(find.text('How it works'), findsOneWidget);
      expect(find.text('Pressure Washing'), findsOneWidget);
      expect(find.text('Living Room Furniture'), findsOneWidget);
      expect(find.text('See Sellers'), findsNWidgets(5));
      if (width == 390) {
        final hero = tester.getRect(
          find.byKey(const ValueKey('approved-saving-opportunities-hero')),
        );
        final copy = tester.getRect(
          find.byKey(const ValueKey('approved-saving-opportunities-copy')),
        );
        final art = tester.getRect(
          find.byKey(const ValueKey('approved-saving-opportunities-art')),
        );
        final opportunities = tester.widget<Text>(find.text('Opportunities'));

        expect(hero.height, closeTo(104, 1));
        expect(copy.left, closeTo(hero.left, 1));
        expect(copy.center.dx, lessThan(art.center.dx));
        expect(art.right, closeTo(hero.right + 4, 1));
        expect(art.center.dy, closeTo(hero.center.dy, 3));
        expect(opportunities.style?.color, BuyerUiTokens.trendsAction);
        expect(
          find.text(
            'Discover products and services\n'
            'from Pro and Elite sellers.',
          ),
          findsOneWidget,
        );
      }
      final error = tester.takeException();
      if (error is FlutterError) {
        debugPrint('Hocatrends overflow diagnostics for width $width');
        debugPrint(error.toStringDeep());
        for (final diagnostic in error.diagnostics) {
          debugPrint(diagnostic.toStringDeep());
        }
      }
      expect(error, isNull, reason: 'width: $width');
    }
  });

  testWidgets('Hocatrends see sellers opens responsive seller list', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    await tapVisible(tester, 'Hocatrends');
    await tester.ensureVisible(find.text('See Sellers').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('See Sellers').first);
    await tester.pumpAndSettle();

    expect(find.text('iPad Air Sellers'), findsOneWidget);
    expect(find.text('23 sellers are offering deals'), findsOneWidget);
    expect(find.text('Northside Tech'), findsOneWidget);
    expect(find.text('Chat Seller'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home create account opens the approved account screen', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tapVisible(tester, 'Create Free Account');

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('I am buying'), findsOneWidget);
    expect(find.text('How will you use Hocalist?'), findsNothing);
  });

  testWidgets(
    'signed-in buyer dashboard renders the supplied Hocalist wordmark',
    (tester) async {
      useTallMobileViewport(tester);
      await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      await tapHomeRole(tester, 0);
      await tapVisible(tester, 'Create account');
      await finishBuyerOnboarding(tester);

      expect(find.textContaining('Maya'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              _assetProvider(widget.image) is AssetImage &&
              (_assetProvider(widget.image) as AssetImage).assetName ==
                  'assets/brand/hocalist-wordmark.png',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Total rewards earned'), findsOneWidget);
      expect(find.textContaining('Sample estimates'), findsOneWidget);
    },
  );

  testWidgets('account screen switches role and login mode in place', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tapHomeRole(tester, 0);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('I am buying'), findsOneWidget);
    expect(find.bySemanticsLabel('Upload profile image'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    for (final asset in [
      'assets/approved_onboarding_home/social-google.png',
      'assets/approved_onboarding_home/social-apple.png',
      'assets/approved_onboarding_home/social-facebook.png',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              _assetProvider(widget.image) is AssetImage &&
              (_assetProvider(widget.image) as AssetImage).assetName == asset,
        ),
        findsOneWidget,
      );
    }

    await tapVisible(tester, 'I am selling');
    expect(find.bySemanticsLabel('Upload profile image'), findsOneWidget);
    expect(find.text('Store or seller name'), findsOneWidget);
    expect(find.text('I am selling'), findsOneWidget);

    await tapVisible(tester, 'Log in');
    expect(find.text('Log in to your account'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Store or seller name'), findsNothing);

    await tapVisible(tester, 'Log in');
    expect(find.text('Seller mode'), findsOneWidget);
    expect(find.text('Find more buyers'), findsOneWidget);
  });

  testWidgets('buyer signup opens benefit onboarding before dashboard', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');

    expect(find.textContaining('Welcome,'), findsOneWidget);
    expect(find.text('As a buyer, you will:'), findsOneWidget);
    expect(find.text('Earn rewards on eligible purchases'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mileage logic for less driving'),
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Jump to dashboard'), findsOneWidget);

    await tapVisible(tester, 'Jump to dashboard');
    expect(find.textContaining('Maya'), findsOneWidget);
    expect(find.text('My active request'), findsNothing);
  });

  test('navy owns primary, actions, focus, and selected navigation', () {
    const navy = Color(0xff00036c);
    expect(HocalistTheme.primary, navy);
    expect(HocalistTheme.light.colorScheme.primary, navy);
    expect(HocalistTheme.dark.colorScheme.primary, navy);
    expect(
      HocalistTheme.light.inputDecorationTheme.focusedBorder,
      isA<OutlineInputBorder>().having(
        (border) => border.borderSide.color,
        'focus color',
        navy,
      ),
    );
    expect(HocalistTheme.buyer, navy);
    expect(HocalistTheme.seller, navy);
    expect(HocalistTheme.darkBuyer, const Color(0xffbec2ff));
    expect(HocalistTheme.darkSeller, const Color(0xffbec2ff));
    expect(HocalistTheme.roleSurface, const Color(0xffeeedff));
  });

  test('global input theme preserves vertical breathing room', () {
    for (final theme in <ThemeData>[HocalistTheme.light, HocalistTheme.dark]) {
      final input = theme.inputDecorationTheme;
      expect(input.isDense, isFalse);
      expect(input.constraints?.minHeight, 48);
      final padding = input.contentPadding! as EdgeInsets;
      expect(padding.top, 12);
      expect(padding.bottom, 12);
    }
  });

  testWidgets('primary actions keep the brand gradient with the seller accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(
            label: 'Seller action',
            icon: Icons.storefront_outlined,
            color: HocalistTheme.seller,
            onPressed: () {},
          ),
        ),
      ),
    );
    final surface = find.descendant(
      of: find.byType(BuyerPrimaryButton),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient != null,
      ),
    );
    final decoration =
        tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;
    expect(decoration.gradient!.colors, [
      BuyerUiTokens.action,
      BuyerUiTokens.requestAction,
    ]);
  });

  testWidgets('buyer can move through signup and deal flow', (tester) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        'I am buying. Post a request and compare offers from sellers.',
      ),
      findsOneWidget,
    );

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);

    expect(find.textContaining('Maya'), findsOneWidget);

    await tapVisible(tester, 'Post a new request');
    await tapVisible(tester, 'Continue');
    await tapVisible(tester, 'Post request');
    expect(find.byType(ApprovedRequestPostedDialog), findsOneWidget);
    await tapVisible(tester, 'Back to dashboard');
    await openRequestEditor(tester);
    await tapVisible(tester, '32 offers');
    await openSampleOfferChat(tester);

    expect(find.text('John D.'), findsOneWidget);
    expect(find.byKey(const Key('active-deal-ipad')), findsOneWidget);
    expect(find.text('Deal chat opened.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('active-deal-ipad')));
    await tester.pumpAndSettle();
    expect(find.text('Accept To Meet'), findsOneWidget);
    await tapVisible(tester, 'Accept To Meet');
    await tester.pumpAndSettle();
    expect(find.text('Upcoming meetings'), findsOneWidget);
    expect(find.text('On schedule'), findsWidgets);
  });

  testWidgets('buyer home request options open request details', (
    tester,
  ) async {
    await openBuyerDashboard(tester);

    await openRequestEditor(tester);

    expect(find.text('Request details'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(
      find.text('Review and edit your request information.'),
      findsOneWidget,
    );
    expect(find.text('Edit your request'), findsOneWidget);

    await tapVisible(tester, '32 offers');

    expect(find.text('Offers received'), findsOneWidget);
  });

  testWidgets('buyer home meeting and offers navigation open correct pages', (
    tester,
  ) async {
    await openBuyerDashboard(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('approved-active-request-card')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approved-active-request-card')).first);
    await tester.pumpAndSettle();

    expect(find.text('Offers received'), findsOneWidget);
    expect(find.text('Request details'), findsNothing);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Maya'), findsOneWidget);

    await tester.tap(find.text('Offers').last);
    await tester.pumpAndSettle();

    expect(find.text('Offers received'), findsOneWidget);
    expect(find.text('Request details'), findsNothing);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    final upcomingMeeting = find.text('iPad Air 5, 256GB').last;
    await tester.ensureVisible(upcomingMeeting);
    await tester.pumpAndSettle();
    await tester.tap(upcomingMeeting);
    await tester.pumpAndSettle();

    expect(find.text('Meeting details'), findsOneWidget);
    expect(find.text('Offers received'), findsNothing);
  });

  testWidgets('request details exposes editable controls and safe feedback', (
    tester,
  ) async {
    await openBuyerDashboard(tester);
    await openRequestEditor(tester);

    expect(find.byKey(const Key('request-title-field')), findsOneWidget);
    expect(find.byKey(const Key('request-description-field')), findsOneWidget);
    expect(find.text('Condition'), findsOneWidget);
    expect(find.text('Budget (optional)'), findsOneWidget);
    expect(find.byTooltip('Edit Condition'), findsOneWidget);
    expect(find.byKey(const ValueKey('approved-request-budget-min')), findsOneWidget);
    expect(find.byKey(const ValueKey('approved-request-budget-max')), findsOneWidget);
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('Willing to receive higher offers?'), findsOneWidget);
    expect(find.text('Current estimated rewards'), findsOneWidget);
    expect(find.text('32 offers'), findsOneWidget);

    final saveButton = find.byKey(const Key('save-request-changes'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -2200));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Updating changes the terms sellers see'),
      findsOneWidget,
    );
    await tester.tap(find.text('Update request'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Updating changes the terms sellers see'),
      findsNothing,
    );
    expect(find.textContaining('will be notified'), findsNothing);

    final deleteButton = find.byKey(const Key('delete-request'));
    await tester.drag(find.byType(ListView).first, const Offset(0, 2200));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete this request?'), findsOneWidget);
    await tapVisible(tester, 'Cancel');
    expect(find.text('Delete this request?'), findsNothing);
  });

  testWidgets('offers dashboard supports filtering and opens seller chat', (
    tester,
  ) async {
    await openBuyerDashboard(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('approved-active-request-card')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approved-active-request-card')).first);
    await tester.pumpAndSettle();

    expect(find.text('Sample reward estimate'), findsOneWidget);
    expect(find.text('From 2 sample sellers'), findsOneWidget);
    expect(find.text(r'$0.40'), findsOneWidget);
    expect(find.byTooltip('How offer rewards work'), findsOneWidget);
    expect(find.text('Northside Tech'), findsOneWidget);

    await tapVisible(tester, 'Filter');
    expect(
      find.byKey(const Key('approved-offers-filter-sheet')),
      findsOneWidget,
    );
    await tapVisible(tester, 'Apply filters');
    expect(find.text('Offer filters opened.'), findsOneWidget);

    await openSampleOfferChat(tester);
    await tester.pumpAndSettle();
    expect(find.text('John D.'), findsOneWidget);
    expect(find.text('Deal chat opened.'), findsOneWidget);
  });

  testWidgets('request details renders without tablet layout exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    await postBuyerRequest(tester);
    await openRequestEditor(tester);

    expect(find.text('Request details'), findsOneWidget);
    expect(find.text('Condition'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buyer offer and chat tolerate larger system text', (
    tester,
  ) async {
    useAccessibleTextViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    await tapVisible(tester, 'Hocatrends');

    expect(
      find.text('Browse seller listings'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tapVisible(tester, 'Home');
    await tapVisible(tester, 'Post a new request');
    await tapVisible(tester, 'Continue');
    await tapVisible(tester, 'Post request');
    expect(find.byType(ApprovedRequestPostedDialog), findsOneWidget);
    await tapVisible(tester, 'Back to dashboard');
    await openRequestEditor(tester);
    await tapVisible(tester, '32 offers');

    await openSampleOfferChat(tester);

    expect(find.text('John D.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('active-deal-ipad')));
    await tester.pumpAndSettle();
    expect(find.text('Accept To Meet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request details tolerate larger system text', (tester) async {
    useAccessibleTextViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    await postBuyerRequest(tester);
    await openRequestEditor(tester);

    expect(find.text('Request details'), findsOneWidget);
    expect(find.text('Edit your request'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(find.text('Current estimated rewards'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav and seller chat tolerate boss phone text scale', (
    tester,
  ) async {
    useBossPhoneTextViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Hocatrends'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    expect(tester.takeException(), isNull, reason: 'buyer dashboard');
    await tapVisible(tester, 'Post a new request');
    expect(tester.takeException(), isNull, reason: 'request editor');
    await tapVisible(tester, 'Continue');
    expect(tester.takeException(), isNull, reason: 'request review');
    await tapVisible(tester, 'Post request');
    expect(tester.takeException(), isNull, reason: 'posted dashboard');
    expect(find.byType(ApprovedRequestPostedDialog), findsOneWidget);
    await tapVisible(tester, 'Back to dashboard');
    await openRequestEditor(tester);
    expect(tester.takeException(), isNull, reason: 'request details');
    await tapVisible(tester, '32 offers');
    expect(tester.takeException(), isNull, reason: 'offers received');

    await openSampleOfferChat(tester);
    expect(find.text('Chats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller can move from signup to marketplace', (tester) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    await completeSellerSignup(tester);
    expect(find.text('Seller mode'), findsOneWidget);

    await tapVisible(tester, 'Browse requests');

    expect(find.text('Find Customers'), findsOneWidget);
    expect(find.text('Looking for iPad Air (5th gen)'), findsOneWidget);
    expect(find.byKey(const Key('sellerLeadsSearch')), findsOneWidget);
  });

  testWidgets('buyer chats tab opens inbox before individual chat', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);

    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsWidgets);
    expect(find.byTooltip('Back'), findsNothing);
    expect(
      find.byKey(const ValueKey('buyer-top-level-header-logo')),
      findsOneWidget,
    );
    expect(find.text('Northside Tech'), findsOneWidget);
    expect(find.text('Loop Resale'), findsOneWidget);
    expect(find.text('Selected seller'), findsNothing);

    await tapVisible(tester, 'Northside Tech');
    await tester.tap(find.byKey(const Key('active-deal-ipad')));
    await tester.pumpAndSettle();
    expect(find.text('Accept To Meet'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('buyer chat action buttons open supporting UI popups', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);
    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Northside Tech');

    await tester.tap(find.byTooltip('Call seller'));
    await tester.pumpAndSettle();
    expect(
      find.text('Open an eligible conversation before calling.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    expect(find.text('Report seller'), findsOneWidget);
    expect(find.text('Search conversation'), findsOneWidget);
    expect(find.text('Mute chat messages'), findsOneWidget);
  });

  testWidgets('welcome journey and marketplace cards adapt for tablet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final buyerCard = find.bySemanticsLabel(
      'I am buying. Post a request and compare offers from sellers.',
    );
    expect(buyerCard, findsOneWidget);
    final homeCardSize = tester.getSize(buyerCard);
    expect(homeCardSize.width, greaterThan(600));
    expect(homeCardSize.width, lessThanOrEqualTo(920));
    expect(homeCardSize.height, lessThan(540));
    expect(
      homeCardSize.width / homeCardSize.height,
      moreOrLessEquals(1.71, epsilon: 0.02),
    );

    await completeSellerSignup(tester);
    await tapVisible(tester, 'Browse requests');

    expect(find.text('Find Customers'), findsOneWidget);
    expect(find.byKey(const Key('sellerLeadsSearch')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buyer support exposes notifications safety reports and states', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('More'), findsWidgets);
    expect(
      find.byKey(const ValueKey('buyer-top-level-header-logo')),
      findsOneWidget,
    );
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('maya.chen@example.com'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Account Settings'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Safety Guide'), findsOneWidget);
    expect(find.text('Help & feedback'), findsOneWidget);
    expect(find.text('Quick controls'), findsNothing);
    expect(find.text('Offer alerts'), findsNothing);
    expect(find.text('Chat reminders'), findsNothing);
    expect(find.text('Safety tips'), findsNothing);
    expect(find.text('Report user or deal'), findsNothing);
    expect(find.text('Safety first'), findsNothing);
    expect(find.text('Log out'), findsOneWidget);

    await tapVisible(tester, 'Edit profile');
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Seller categories'), findsNothing);
    expect(find.text('Preferred request categories'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Notifications');
    expect(find.text('Notification Preferences'), findsOneWidget);
    expect(find.text('Offers'), findsWidgets);
    expect(find.text('Messages & chats'), findsOneWidget);
    expect(find.text('Meetings & deal updates'), findsOneWidget);
    expect(find.text('Account & safety alerts'), findsOneWidget);
    expect(find.text('Notification center ready'), findsNothing);
    final offersPreference = find.ancestor(
      of: find.text('Offers'),
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(
      find.descendant(of: offersPreference, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    final notificationPreferences = await SharedPreferences.getInstance();
    expect(
      notificationPreferences.getBool('hocalist.buyer.notifications.offers'),
      isFalse,
    );

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Saved');
    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.text('Saved request: compact espresso machine'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Safety Guide');
    expect(find.text('Meet in public'), findsOneWidget);
    expect(find.text('Protect private information'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Help & feedback');
    expect(find.text('Get help or send feedback'), findsOneWidget);
    expect(find.text('Report a problem or unsafe interaction'), findsOneWidget);
    await tapVisible(tester, 'Report a problem or unsafe interaction');
    expect(find.text('Report a Problem'), findsOneWidget);
    expect(find.text('Save report'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Log out');
    expect(find.text('See How Hocalist Works'), findsOneWidget);
  });

  testWidgets('buyer can review designed account settings', (tester) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    await tapHomeRole(tester, 0);
    await tapVisible(tester, 'Create account');
    await finishBuyerOnboarding(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Account Settings');

    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Personal information'), findsNothing);
    expect(find.byKey(const ValueKey('section-tab-Security')), findsOneWidget);
    expect(find.text('Password & security'), findsOneWidget);
    expect(find.text('ACCOUNT MANAGEMENT'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-tab-Privacy')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('section-tab-Preferences')));
    await tester.pumpAndSettle();
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Account removal needs backend'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Log out'), findsNothing);

    await tapVisible(tester, 'Accessibility');
    expect(find.text('Customize Hocalist to fit your needs'), findsOneWidget);
    expect(find.text('1. Choose your text size'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accessibility-back')));
    await tester.pumpAndSettle();
    expect(find.text('Account Settings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('section-tab-Preferences')));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Accessibility');

    await tester.tap(find.byKey(const Key('text-size-extraLarge')));
    await tester.pumpAndSettle();
    expect(find.text('Accessibility preferences applied.'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('show-accessibility-preview')),
      220,
      scrollable: find.descendant(
        of: find.byKey(const Key('accessibility-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 12,
    );
    await tester.ensureVisible(
      find.byKey(const Key('show-accessibility-preview')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('show-accessibility-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Example request card'), findsOneWidget);

    await tapVisible(tester, 'Apply changes');
    expect(find.text('Accessibility preferences applied.'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('hocalist.accessibility.textSize'),
      'extraLarge',
    );
    expect(
      preferences.getString('hocalist.accessibility.fontStyle'),
      'standard',
    );
    expect(
      preferences.getString('hocalist.accessibility.buttonStyle'),
      'rounded',
    );
  });

  testWidgets('seller settings expose seller-specific Phase 1 controls', (
    tester,
  ) async {
    useTallMobileViewport(tester);
    await tester.pumpWidget(const HocalistApp());
    await tester.pumpAndSettle();

    await completeSellerSignup(tester);
    await tester.tap(find.byKey(const Key('sellerNavMore')));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Account settings');

    expect(find.text('Account Settings'), findsOneWidget);
    expect(find.text('Seller information'), findsNothing);
    expect(find.byKey(const ValueKey('section-tab-Security')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('section-tab-Preferences')));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
  });
}
