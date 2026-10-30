import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/account/account_security_page.dart';
import 'package:hocalist/features/account/account_lifecycle_page.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'phase2/account/account_test_fakes.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Nunito'),
        home: Scaffold(
          body:
              (child is BuyerSettingsPage ||
                  child is ApprovedSellerSettingsPage)
              ? SingleChildScrollView(child: child)
              : child,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final seller in [false, true]) {
    testWidgets(
      '${seller ? 'seller' : 'buyer'} settings keeps account management in Security and Back works',
      (t) async {
        var backed = false;
        final child = seller
            ? ApprovedSellerSettingsPage(
                darkMode: false,
                textSizeLabel: 'Medium',
                onBack: () => backed = true,
                onEditProfile: () {},
                onThemeChanged: (_) {},
                onAccessibility: () {},
                onAccountLifecycle: () {},
              )
            : BuyerSettingsPage(
                darkMode: false,
                textSize: AppTextSize.medium,
                onBack: () => backed = true,
                onEditProfile: () {},
                onThemeChanged: (_) {},
                onAccountLifecycle: () {},
              );
        await pump(t, child);
        expect(find.text('Account data & deletion'), findsOneWidget);
        if (seller) {
          expect(find.byKey(const ValueKey('section-tab-Privacy')), findsNothing);
          expect(find.text('Appearance'), findsOneWidget);
        } else {
          await tap(t, find.byKey(const ValueKey('section-tab-Privacy')));
          expect(find.text('Account data & deletion'), findsNothing);
        }
        await tap(t, find.byTooltip('Back'));
        expect(backed, isTrue);
      },
    );
    testWidgets(
      '${seller ? 'seller' : 'buyer'} security and lifecycle use their role actions/notices',
      (t) async {
        final auth = FakeAuthGateway();
        final controller = HocalistAccountController(
          auth: auth,
          accounts: FakeAccountRepository(),
          initialRole: seller ? HocalistRole.seller : HocalistRole.buyer,
        );
        addTearDown(controller.dispose);
        addTearDown(auth.dispose);
        await pump(
          t,
          AccountSecurityPage(controller: controller, onBack: () {}),
        );
        final action = find.byKey(const ValueKey('security-password-submit'));
        expect(
          find.descendant(
            of: action,
            matching: find.byType(
              seller ? SellerPrimaryButton : BuyerPrimaryButton,
            ),
          ),
          findsOneWidget,
        );
        await pump(t, AccountLifecyclePage(seller: seller, onBack: () {}));
        expect(
          find.byType(seller ? SellerStateNotice : BuyerStateNotice),
          findsWidgets,
        );
      },
    );
    testWidgets(
      '${seller ? 'seller' : 'buyer'} accessibility retains the correct role accent',
      (t) async {
        await pump(
          t,
          AccessibilityPage(
            seller: seller,
            appliedPreferences: AccessibilityPreferences.defaults,
            onApply: (_) {},
            onBack: () {},
          ),
        );
        final c = t.widget<Container>(
          find.byKey(const Key('button-preview-rounded')),
        );
        final decoration = c.decoration! as BoxDecoration;
        expect(
          (decoration.gradient! as LinearGradient).colors.first,
          seller ? SellerUiColors.primaryBright : const Color(0xff5215ff),
        );
      },
    );
  }
  testWidgets('seller settings removes duplicate profile and service-area links', (t) async {
    var opened = 0;
    await pump(
      t,
      ApprovedSellerSettingsPage(
        darkMode: false,
        textSizeLabel: 'Medium',
        onBack: () {},
        onEditProfile: () => opened++,
        onThemeChanged: (_) {},
        onAccessibility: () {},
      ),
    );
    expect(find.byKey(const ValueKey('section-tab-Privacy')), findsNothing);
    expect(find.text('Public Seller visibility'), findsNothing);
    expect(find.text('Service-area privacy'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);
    expect(opened, 0);
  });
  testWidgets(
    'selected settings tab reveals its full label on a narrow phone',
    (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Nunito'),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 1000),
                textScaler: TextScaler.linear(1.3),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: BuyerSettingsPage(
                    darkMode: false,
                    textSize: AppTextSize.medium,
                    onBack: () {},
                    onEditProfile: () {},
                    onThemeChanged: (_) {},
                    onAccountLifecycle: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final tab = find.byKey(const ValueKey('section-tab-Privacy'));
      await t.tap(tab);
      await t.pumpAndSettle();
      final strip = find
          .ancestor(
            of: tab,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            ),
          )
          .first;
      expect(
        t.getRect(tab).right,
        lessThanOrEqualTo(t.getRect(strip).right + 0.5),
      );
      expect(
        t.getRect(tab).left,
        greaterThanOrEqualTo(t.getRect(strip).left - 0.5),
      );
    },
  );
}
