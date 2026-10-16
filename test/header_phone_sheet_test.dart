import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final role in UserRole.values) {
    testWidgets('$role secondary routes retain one brand header', (t) async {
      t.view.physicalSize = const Size(390, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const HocalistApp());
      await t.pumpAndSettle();
      final dynamic state = t.state(find.byType(HocalistPrototype));
      for (final page in [
        role == UserRole.seller
            ? AppPage.sellerSettings
            : AppPage.buyerSettings,
        AppPage.editProfile,
        AppPage.accountSecurity,
        AppPage.accountLifecycle,
        AppPage.accessibility,
      ]) {
        state.completeAuthentication(role, page);
        await t.pumpAndSettle();
        expect(
          find.byType(HocalistGlobalHeader),
          findsOneWidget,
          reason: page.name,
        );
        expect(t.takeException(), isNull, reason: page.name);
      }
    });
  }
  testWidgets('phone sheet cancels without losing email draft', (t) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedAccountCreationPage(
            role: ApprovedAccountRole.buyer,
            name: '',
            onNameChanged: (_) {},
            onRoleChanged: (_) {},
            onSignup: () {},
            onLogin: () {},
            onPhoneRequestCode: (_, {required signup}) async {},
            onPhoneConfirmCode: (_, _) async {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'kept@example.invalid',
    );
    final action = find.byKey(const ValueKey('approved-account-phone-action'));
    await t.ensureVisible(action);
    await t.tap(action);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    final cancel = find.byKey(const ValueKey('approved-account-phone-cancel'));
    await t.ensureVisible(cancel);
    await t.tap(cancel);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('kept@example.invalid'), findsOneWidget);
  });
}
