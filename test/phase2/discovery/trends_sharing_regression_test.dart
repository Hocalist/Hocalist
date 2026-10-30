import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/discovery/discovery_backends.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';
import 'package:hocalist/features/discovery/buyer_profile_visibility_editor.dart';

class ConsentFake implements BuyerConsentBackend {
  BuyerPublicProfileConsent saved = const BuyerPublicProfileConsent();
  int writes = 0;
  @override
  Future<BuyerPublicProfileConsent> loadConsent() async => saved;
  @override
  Future<BuyerPublicProfileConsent> setConsent({
    required BuyerPublicProfileConsent consent,
    required String operationKey,
  }) async {
    writes++;
    return saved = consent;
  }

  @override
  Future<PublicBuyerProfile> loadPublicProfile(String profileId) async =>
      const PublicBuyerProfile(available: false);
}

void main() {
  testWidgets('trend search keeps the selected category identifier', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ApprovedHocatrendsPage(
      accent: Colors.blue, realMode: true,
      trends: HocatrendsProjection(items: const [
        HocatrendsTopic(rank: 1, categoryId: 'home-services', label: 'Home services', openRequests: 2, competingSellers: 1, confirmedPurchases: 0, participatingBuyers: 2, percent: 100, competition: 'New', activityCopy: '2 open requests'),
      ]), onSeeSellers: () {}, onSeeSellersForTopic: (id) => opened = id,
    )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-hocatrends-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'services');
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('See Sellers'));
    await tester.tap(find.text('See Sellers'));
    expect(opened, 'home-services');
  });
  testWidgets('signed-in trends never substitute preview rankings on load or failure', (tester) async {
    Widget page({bool loading = false, String? error}) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ApprovedHocatrendsPage(
      accent: Colors.blue, realMode: true, trendsLoading: loading, trendsError: error, onSeeSellers: () {},
    ))));
    await tester.pumpWidget(page(loading: true));
    await tester.pump();
    expect(find.byKey(const Key('approvedTrendsLoading')), findsOneWidget);
    expect(find.textContaining('iPad Air'), findsNothing);
    await tester.pumpWidget(page(error: 'Could not load trends'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load trends'), findsOneWidget);
    expect(find.textContaining('iPad Air'), findsNothing);
  });
  testWidgets(
    'real trend results use the selected category and actual sellers',
    (tester) async {
      HocatrendsSellerView? opened;
      const seller = HocatrendsSellerView(
        sellerProfileId: 'seller-a',
        displayName: 'Test store',
      );
      Widget page(List<HocatrendsSellerView> items) => MaterialApp(
        home: Scaffold(
          body: ApprovedHocatrendsPickedSellersPage(
            realMode: true,
            topicLabel: 'Home services',
            realResults: HocatrendsSellerResults(topicId: 'home', items: items),
            onBack: () {},
            onChatSeller: () {},
            onChatSellerView: (value) => opened = value,
          ),
        ),
      );
      await tester.pumpWidget(page([]));
      await tester.pumpAndSettle();
      expect(find.text('Home services'), findsOneWidget);
      expect(find.text('0 matching sellers'), findsOneWidget);
      expect(find.textContaining('iPad Air'), findsNothing);
      expect(find.textContaining('23 sellers'), findsNothing);
      await tester.pumpWidget(page([seller]));
      await tester.pumpAndSettle();
      expect(find.text('1 matching seller'), findsOneWidget);
    expect(find.text('Ask seller for details'), findsNothing);
      await tester.tap(find.text('Chat Seller'));
      expect(opened, same(seller));
    },
  );

  testWidgets('sharing choices save only the selected fields and restore', (
    tester,
  ) async {
    final backend = ConsentFake();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BuyerProfileVisibilityEditor(backend: backend),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Display name'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.ensureVisible(find.text('Save visibility'));
    await tester.tap(find.text('Save visibility'));
    await tester.pumpAndSettle();
    expect(backend.writes, 1);
    expect(backend.saved.isPublic, isTrue);
    expect(backend.saved.showArea, isTrue);
    expect(backend.saved.showDisplayName, isFalse);
    expect(backend.saved.showCategories, isFalse);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('sharing fits width $width scale $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final backend = ConsentFake()
          ..saved = const BuyerPublicProfileConsent(isPublic: true);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BuyerProfileVisibilityEditor(backend: backend),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save visibility'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
