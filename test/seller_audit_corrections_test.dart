import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/seller_bottom_navigation.dart';
import 'package:hocalist/features/support/support_cases_page.dart';
import 'package:hocalist/data/phase2/support/support_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'phase2/marketplace/support/marketplace_fakes.dart';
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

  void size(WidgetTester t) {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('prototype deals metric opens offer history', (t) async {
    size(t);
    var leads = 0, offers = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Nunito'),
        home: ApprovedSellerHomePage(
          onLeads: () => leads++,
          onBrowseRequests: () {},
          onOfferHistory: () => offers++,
        ),
      ),
    );
    await tap(t, find.text('View offers'));
    expect(offers, 1);
    expect(leads, 0);
  });
  testWidgets(
    'seller nested pages keep their navigation context and setup uses editor',
    (t) async {
      size(t);
      await t.pumpWidget(const HocalistApp());
      await t.pumpAndSettle();
      final dynamic state = t.state(find.byType(HocalistPrototype));
      state.completeAuthentication(UserRole.seller, AppPage.sellerProfileSetup);
      await t.pumpAndSettle();
      expect(find.byType(ApprovedSellerEditProfilePage), findsOneWidget);
      expect(
        t
            .widget<SellerBottomNavigation>(find.byType(SellerBottomNavigation))
            .selected,
        SellerNavDestination.more,
      );
      await tap(t, find.byKey(const Key('sellerSaveProfile')));
      expect(find.byType(ApprovedSellerHomePage), findsOneWidget);
      for (final page in [
        AppPage.sellerOfferHistory,
        AppPage.sellerOfferDetail,
        AppPage.sellerVerification,
      ]) {
        state.resetTo(page);
        await t.pumpAndSettle();
        expect(
          t
              .widget<SellerBottomNavigation>(
                find.byType(SellerBottomNavigation),
              )
              .selected,
          page == AppPage.sellerVerification
              ? SellerNavDestination.more
              : SellerNavDestination.home,
        );
      }
    },
  );
  testWidgets('general help and safety entry points are separate', (t) async {
    size(t);
    var general = 0, safety = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Nunito'),
        home: ApprovedSellerHelpSupportPage(
          onBack: () {},
          onSafety: () {},
          onContactSupport: () => general++,
          onReportSafety: () => safety++,
        ),
      ),
    );
    await tap(t, find.text('Ask for help'));
    expect(general, 1);
    expect(safety, 0);
    await tap(t, find.text('Report a safety concern'));
    expect(safety, 1);
  });
  testWidgets('general support submits a real general case, not safety', (
    t,
  ) async {
    size(t);
    final transport = FakeMarketplaceTransport();
    String? reason;
    transport.handler = (call) {
      if (call.function == 'support_reasons') {
        return const MarketplaceTransportData({
          'items': [
            {'code': 'general', 'label': 'General support'},
            {'code': 'safety', 'label': 'Unsafe interaction'},
          ],
        });
      }
      if (call.function == 'support_command') {
        reason = (call.params['p_input'] as Map)['reason_code'] as String;
        return const MarketplaceTransportData({
          'id': '10000000-0000-4000-8000-000000000001',
          'status': 'open',
          'revision': 1,
        });
      }
      return const MarketplaceTransportData({'items': [], 'next_cursor': null});
    };
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportCasesPage(
            adapter: SupportAdapter(
              transport: transport,
              session: FakeMarketplaceSession('seller-test'),
            ),
            onBack: () {},
            generalHelp: true,
            initialReasonCode: 'general',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Help & support'), findsOneWidget);
    expect(find.text('General support'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'A general account question.');
    await tap(t, find.text('Send question'));
    expect(reason, 'general');
  });
  testWidgets(
    'low and high bid shortcuts prefill distinct editable budget prices',
    (t) async {
      size(t);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Nunito'),
          home: const ApprovedSellerLeadsPage(),
        ),
      );
      await t.pumpAndSettle();
      String price() => t
          .widget<TextField>(find.byKey(const Key('sellerOfferPrice')))
          .controller!
          .text;
      await tap(t, find.text('Send Low Bid').first);
      final low = price();
      await tap(t, find.byKey(const Key('sellerSendOfferCancel')));
      await tap(t, find.text('Send High Bid').first);
      final high = price();
      expect(double.parse(low), lessThan(double.parse(high)));
      expect(
        find.byKey(const Key('sellerSendOfferBottomSheet')),
        findsOneWidget,
      );
    },
  );
}
