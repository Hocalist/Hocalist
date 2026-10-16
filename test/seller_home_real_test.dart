import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';

const realLead = SellerLeadView(
  requestId: 'request-1',
  requestRevision: 1,
  name: 'Buyer',
  initials: 'B',
  city: 'Yonkers, NY',
  distance: '—',
  request: 'Used laptop',
  description: 'A working laptop',
  budget: r'$300 - $500',
  match: 0,
  purchases: 0,
  lastPurchase: '—',
  meeting: 'Public place',
  avatarColor: Colors.white,
  initialColor: Colors.blue,
);

Future<void> pumpHome(
  WidgetTester tester, {
  List<SellerLeadView> leads = const [realLead],
  bool loading = false,
  String? error,
  VoidCallback? onRetry,
  VoidCallback? onOfferHistory,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ApprovedSellerHomePage(
          onLeads: () {},
          onBrowseRequests: () {},
          onOfferHistory: onOfferHistory,
          sellerName: 'Northside Tech',
          realLeads: leads,
          leadsLoading: loading,
          leadsError: error,
          onRefreshLeads: onRetry,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real seller profile never fills an unavailable email with demo data',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: ApprovedSellerEditProfilePage(
            name: 'Northside Tech',
            onNameChanged: (_) {},
            onBack: () {},
            onDone: () {},
            contactEditor: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('northside.tech@example.com'), findsNothing);
    },
  );

  testWidgets('real seller More shows only the supplied account email', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedSellerMorePage(
          sellerName: 'Northside Tech',
          sellerEmail: 'seller@example.com',
          onProfile: () {},
          onEditProfile: () {},
          onSettings: () {},
          onNotifications: () {},
          onAccessibility: () {},
          onSafety: () {},
          onHelp: () {},
          onLogout: () {},
        ),
      ),
    );
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('northside.tech@example.com'), findsNothing);
  });

  testWidgets('seller edit profile keeps the placeholder photo without an id', (
    tester,
  ) async {
    SellerProfilePhotoAction? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerEditProfilePage(
            name: 'Northside Tech',
            onNameChanged: (_) {},
            onBack: () {},
            onDone: () {},
            onProfilePhotoAction: (value) => action = value,
            contactEditor: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sellerEditProfilePhotoAction')), findsOneWidget);
    expect(find.text('N'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerEditProfileChangePhoto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove current photo'));
    await tester.pumpAndSettle();
    expect(action, SellerProfilePhotoAction.remove);
  });

  testWidgets('real seller home displays only sourced lead facts', (
    tester,
  ) async {
    var historyOpens = 0;
    await pumpHome(tester, onOfferHistory: () => historyOpens++);
    expect(find.text('Welcome, Northside Tech'), findsOneWidget);
    expect(find.text('Used laptop'), findsOneWidget);
    expect(find.text('Yonkers, NY'), findsOneWidget);
    expect(find.text(r'$300 - $500'), findsOneWidget);
    expect(find.text('56'), findsNothing);
    expect(find.text('12'), findsNothing);
    expect(find.textContaining('Alex'), findsNothing);
    expect(find.text('Pressure Washing'), findsNothing);
    expect(find.text('This month'), findsNothing);
    expect(find.byKey(const Key('sellerAccountHealth')), findsOneWidget);
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.text('Recommended leads for you'), findsOneWidget);
    expect(
      find.byKey(const Key('sellerHomeRecommendedEmpty')),
      findsOneWidget,
    );
    await tester.tap(find.text('View offers'));
    expect(historyOpens, 1);
  });

  testWidgets('real seller home shows retry instead of sample leads', (
    tester,
  ) async {
    var retries = 0;
    await pumpHome(
      tester,
      leads: const [],
      error: 'Could not load requests.',
      onRetry: () => retries++,
    );
    expect(find.text('Could not load requests.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(find.text('PS5 Console'), findsNothing);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('real seller home fits $width at scale $scale', (
        tester,
      ) async {
        await pumpHome(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
