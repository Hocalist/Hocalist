import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Chats and More remain responsive across cleanup viewports', (
    tester,
  ) async {
    for (final width in <double>[320, 360, 390, 768]) {
      await _pumpBuyerTopLevel(
        tester,
        width: width,
        child: BuyerChatsPage(
          onBack: () {},
          onOpenChat: () {},
          onOffers: () {},
        ),
      );
      expect(find.text('Northside Tech'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Chats failed at $width.');

      await _pumpBuyerTopLevel(
        tester,
        width: width,
        child: SupportPage(
          accent: HocalistTheme.actionBlue,
          name: 'Maya Chen',
          email: 'maya.chen@example.com',
          onNotifications: () {},
          onSaved: () {},
          onSafety: () {},
          onReport: () {},
          onHelp: () {},
          onEditProfile: () {},
          onSettings: () {},
          onLogout: () {},
        ),
      );
      expect(find.text('Account Settings'), findsOneWidget);
      expect(find.text('Quick controls'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'More failed at $width.');
    }
  });

  testWidgets('Home CTA, Chats, and More reflow at 360px and 1.6x text', (
    tester,
  ) async {
    await _pumpStandalone(
      tester,
      width: 360,
      textScale: 1.6,
      child: ApprovedNoAccountHomePage(
        onStart: () {},
        onBuyer: () {},
        onSeller: () {},
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Ready to start earning?'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Create Free Account').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Home CTA at 1.6x.');

    await _pumpBuyerTopLevel(
      tester,
      width: 360,
      textScale: 1.6,
      child: BuyerChatsPage(onBack: () {}, onOpenChat: () {}, onOffers: () {}),
    );
    expect(find.text('Northside Tech'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Chats at 1.6x.');

    await _pumpBuyerTopLevel(
      tester,
      width: 360,
      textScale: 1.6,
      child: SupportPage(
        accent: HocalistTheme.actionBlue,
        name: 'Maya Chen',
        email: 'maya.chen@example.com',
        onNotifications: () {},
        onSaved: () {},
        onSafety: () {},
        onReport: () {},
        onHelp: () {},
        onEditProfile: () {},
        onSettings: () {},
        onLogout: () {},
      ),
    );
    expect(find.text('Help & Support'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'More at 1.6x.');
  });

  testWidgets('Buyer More destinations use responsive Buyer subpages', (
    tester,
  ) async {
    for (final width in <double>[320, 390, 768]) {
      for (final page in _buyerMoreDestinations()) {
        await _pumpSubpage(tester, width: width, child: page.widget);
        expect(find.text(page.proofText), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.proofText} failed at $width.',
        );
      }
    }
  });

  testWidgets('Buyer More destinations reflow at 360px and 1.6x text', (
    tester,
  ) async {
    for (final page in _buyerMoreDestinations()) {
      await _pumpSubpage(
        tester,
        width: 360,
        textScale: 1.6,
        child: page.widget,
      );
      expect(find.text(page.proofText), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: '${page.proofText} failed at 1.6x text.',
      );
    }
  });

  testWidgets('Buyer profile picture controls work in More and Edit Profile', (
    tester,
  ) async {
    BuyerProfilePhotoAction? selectedAction;
    await _pumpBuyerTopLevel(
      tester,
      width: 360,
      child: SupportPage(
        accent: HocalistTheme.actionBlue,
        name: 'Maya Chen',
        email: 'maya.chen@example.com',
        onNotifications: () {},
        onSaved: () {},
        onSafety: () {},
        onReport: () {},
        onHelp: () {},
        onEditProfile: () {},
        onSettings: () {},
        onLogout: () {},
        onProfilePhotoAction: (action) => selectedAction = action,
      ),
    );

    await tester.tap(find.byKey(const Key('buyerMoreProfilePhotoAction')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buyerPhotoTakePhoto')), findsOneWidget);
    expect(find.byKey(const Key('buyerPhotoChooseGallery')), findsOneWidget);
    expect(find.byKey(const Key('buyerPhotoRemove')), findsOneWidget);
    await tester.tap(find.byKey(const Key('buyerPhotoChooseGallery')));
    await tester.pumpAndSettle();
    expect(selectedAction, BuyerProfilePhotoAction.gallery);

    await _pumpSubpage(
      tester,
      width: 360,
      child: BuyerProfileEditPage(
        name: 'Maya Chen',
        onNameChanged: (_) {},
        onDone: () {},
      ),
    );
    expect(find.text('PROFILE PICTURE'), findsOneWidget);
    expect(
      find.byKey(const Key('buyerEditProfilePhotoAction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('buyerEditProfileChangePhoto')),
      findsOneWidget,
    );

    final firstInput = find.byType(TextFormField).first;
    final emailLabel = find.text('Email');
    final relatedFieldGap =
        tester.getTopLeft(emailLabel).dy - tester.getBottomLeft(firstInput).dy;
    expect(relatedFieldGap, inInclusiveRange(6, 10));
    expect(tester.takeException(), isNull);
  });
}

List<({String proofText, Widget widget})> _buyerMoreDestinations() => [
  (
    proofText: 'Password & security',
    widget: BuyerSettingsPage(
      darkMode: false,
      textSize: AppTextSize.medium,
      onEditProfile: () {},
      onThemeChanged: (_) {},
      onAccessibility: () {},
    ),
  ),
  (
    proofText: 'Meetings & deal updates',
    widget: BuyerNotificationPreferencesPage(accent: HocalistTheme.actionBlue),
  ),
  (
    proofText: 'Nothing saved yet',
    widget: SavedItemsPage(accent: HocalistTheme.actionBlue),
  ),
  (
    proofText: 'Protect private information',
    widget: SafetyGuidePage(accent: HocalistTheme.actionBlue),
  ),
  (
    proofText: 'Report a problem or unsafe interaction',
    widget: HelpSupportPage(
      accent: HocalistTheme.actionBlue,
      onReport: () {},
      onContactSupport: () {},
    ),
  ),
  (
    proofText: 'Save profile',
    widget: BuyerProfileEditPage(
      name: 'Maya Chen',
      onNameChanged: (_) {},
      onDone: () {},
    ),
  ),
];

Future<void> _pumpSubpage(
  WidgetTester tester, {
  required double width,
  required Widget child,
  double textScale = 1,
}) {
  return _pumpStandalone(
    tester,
    width: width,
    textScale: textScale,
    child: Scaffold(
      body: SafeArea(child: AppFrame(child: child)),
    ),
  );
}

Future<void> _pumpBuyerTopLevel(
  WidgetTester tester, {
  required double width,
  required Widget child,
  double textScale = 1,
}) {
  return _pumpStandalone(
    tester,
    width: width,
    textScale: textScale,
    child: Scaffold(
      body: SafeArea(
        child: AppFrame(
          buyerTopLevel: true,
          header: HocalistGlobalHeader(
            role: UserRole.buyer,
            accent: HocalistTheme.actionBlue,
            onNotifications: () {},
          ),
          child: child,
        ),
      ),
    ),
  );
}

Future<void> _pumpStandalone(
  WidgetTester tester, {
  required double width,
  required Widget child,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, width == 768 ? 1024 : 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: ObjectKey(child),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: HocalistTheme.appFontFamily,
        scaffoldBackgroundColor: HocalistTheme.background,
        colorScheme: ColorScheme.fromSeed(seedColor: HocalistTheme.primary),
      ),
      builder: (context, appChild) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: appChild ?? const SizedBox.shrink(),
        );
      },
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}
