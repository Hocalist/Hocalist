import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/buyer_bottom_navigation.dart';
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

  void viewport(WidgetTester t) {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('fresh signup is blank and role remount retains every field', (
    t,
  ) async {
    viewport(t);
    await t.pumpWidget(const HocalistApp());
    await t.pumpAndSettle();
    await tap(
      t,
      find.bySemanticsLabel(
        'I am buying. Get paid to buy and get the best offers. Post a request.',
      ),
    );
    expect(find.text('Maya Chen'), findsNothing);
    const fields = {
      'name': 'New Buyer',
      'email': 'buyer@example.invalid',
      'phone': '+14155550123',
      'password': 'test-pass-123',
      'confirm-password': 'test-pass-123',
    };
    for (final entry in fields.entries) {
      await t.enterText(
        find.byKey(ValueKey('approved-account-${entry.key}-field')),
        entry.value,
      );
    }
    await tap(t, find.text('I am selling'));
    for (final entry in fields.entries) {
      final field = find.descendant(
        of: find.byKey(ValueKey('approved-account-${entry.key}-field')),
        matching: find.byType(EditableText),
      );
      expect(t.widget<EditableText>(field).controller.text, entry.value);
    }
    await tap(t, find.text('I am buying'));
    expect(
      t
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('approved-account-email-field')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'buyer@example.invalid',
    );
  });
  testWidgets(
    'benefits dismissal enters dashboard and empty back stack stays home',
    (t) async {
      viewport(t);
      await t.pumpWidget(const HocalistApp());
      await t.pumpAndSettle();
      await tap(
        t,
        find.bySemanticsLabel(
          'I am buying. Get paid to buy and get the best offers. Post a request.',
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('approved-account-name-field')),
        'New Buyer',
      );
      await tap(t, find.text('Create account'));
      await tap(t, find.byTooltip('Close'));
      expect(find.byType(ApprovedBuyerHomePage), findsOneWidget);
      final dynamic state = t.state(find.byType(HocalistPrototype));
      state.back();
      await t.pumpAndSettle();
      expect(find.byType(ApprovedBuyerHomePage), findsOneWidget);
    },
  );
  testWidgets(
    'shared login exposes recovery and unsupported providers give feedback',
    (t) async {
      viewport(t);
      var recovered = false;
      await t.pumpWidget(
        MaterialApp(
          home: ApprovedAccountCreationPage(
            role: ApprovedAccountRole.buyer,
            name: '',
            onNameChanged: (_) {},
            onRoleChanged: (_) {},
            onSignup: () {},
            onLogin: () {},
            onForgotPassword: () => recovered = true,
          ),
        ),
      );
      await tap(
        t,
        find.byKey(const ValueKey('approved-account-google-action')),
      );
      expect(
        find.textContaining('Google sign-in is unavailable'),
        findsOneWidget,
      );
      await tap(t, find.text('Log in'));
      await tap(
        t,
        find.byKey(const ValueKey('approved-account-forgot-password')),
      );
      expect(recovered, isTrue);
    },
  );
  testWidgets(
    'post-meetup instruction uses service title and no invented reward',
    (t) async {
      viewport(t);
      final nav = ApprovedBuyerNavigation(
        onHome: () {},
        onHocatrends: () {},
        onOffers: () {},
        onChats: () {},
        onMore: () {},
      );
      await t.pumpWidget(
        MaterialApp(
          home: ApprovedBuyerAfterMeetupPage(
            requestTitle: 'Garden maintenance',
            onBack: () {},
            navigation: nav,
            onReview: () {},
            onDealIssue: () {},
            onReport: () {},
          ),
        ),
      );
      expect(find.textContaining('check Garden maintenance'), findsOneWidget);
      expect(find.textContaining('inspect the iPad'), findsNothing);
      expect(find.textContaining('your \$1.40 reward'), findsNothing);
    },
  );
  testWidgets(
    'upcoming meetings View all opens meetings rather than activity',
    (t) async {
      viewport(t);
      var meetings = 0, activity = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Nunito'),
          home: ApprovedBuyerHomePage(
            name: '',
            requestTitle: 'Request',
            requestPosted: false,
            onCreate: () {},
            onRequestDetails: () {},
            onOffers: () {},
            onRecentActivity: () => activity++,
            onWallet: () {},
            onMeetingDetails: () => meetings++,
          ),
        ),
      );
      final row = find
          .ancestor(
            of: find.text('Upcoming meetings'),
            matching: find.byType(Row),
          )
          .first;
      await tap(t, find.descendant(of: row, matching: find.byType(TextButton)));
      expect(meetings, 1);
      expect(activity, 0);
    },
  );
}
