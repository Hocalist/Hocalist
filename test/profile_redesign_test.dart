import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/main.dart' show BuyerEditProfileMenu, BuyerProfilePhotoEditor;
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/profiles/profile_ui.dart';
import 'package:hocalist/features/profiles/profile_pages.dart';
import 'package:hocalist/domain/phase2/reviews.dart';

void main() {
  Future<void> pump(
    WidgetTester t,
    Widget page, {
    double width = 390,
    double scale = 1,
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: page),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Widget seller({bool available = true}) => SellerPublicProfileView(
    name: 'Example seller',
    onBack: () {},
    load: () async => {
      'available': available,
      'display_name': 'Example seller',
      'area_label': 'Chicago',
      'radius_miles': 15,
      'locations': [
        {'name': 'Downtown store', 'address': 'Test business address'},
      ],
      'categories': ['Electronics'],
      'badges': ['Email verified'],
      'about': 'Helpful local service',
    },
    listings: const Text('Real store listings'),
    reputation: PublicSellerReputation(
      sellerProfileId: 'seller',
      ratingSum: 5,
      ratingCount: 1,
      completedDeals: 2,
      reviews: [
        PublicReviewExcerpt(
          id: 'review',
          rating: 5,
          reviewerLabel: 'Hocalist buyer',
          body: 'Great seller',
          createdAt: DateTime.utc(2026),
        ),
      ],
    ),
  );
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets(
        'public seller fits $width/$scale and shows locations inline',
        (t) async {
          await pump(t, seller(), width: width, scale: scale);
          expect(find.text('Test business address'), findsOneWidget);
          expect(find.text('Chicago · Within 15 miles'), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right), findsNothing);
          expect(find.text('Real store listings'), findsOneWidget);
          expect(find.text('Great seller'), findsOneWidget);
          expect(find.text('Phone verified'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('unavailable seller does not leak profile cards or listings', (
    t,
  ) async {
    await pump(t, seller(available: false));
    expect(find.text('Real store listings'), findsNothing);
    expect(find.text('Test business address'), findsNothing);
    expect(find.text('Great seller'), findsNothing);
  });
  testWidgets('small profile edits use a closable popup', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showProfileEditor(
                c,
                'Edit name',
                const Text('Editor content'),
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();
    expect(find.text('Editor content'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Editor content'), findsNothing);
  });
  for (final sellerMode in [true, false]) {
    testWidgets(
      'private ${sellerMode ? 'seller' : 'buyer'} profile has correct actions',
      (t) async {
        int edits = 0, visibility = 0, photos = 0;
        await pump(
          t,
          ProfileOverviewPage(
            menuBuilder: (edit, visibility, categories) => sellerMode ? SellerEditProfileMenu(onDetails: edit, onVisibility: visibility, onCategories: categories) : BuyerEditProfileMenu(onDetails: edit, onVisibility: visibility),
            photoEditor: sellerMode
                ? SellerProfilePhotoEditor(sellerName: 'Test user', onProfilePhotoAction: (_) => photos++)
                : BuyerProfilePhotoEditor(onProfilePhotoAction: (_) => photos++),
            seller: sellerMode,
            name: 'Test user',
            onBack: () {},
            onPreview: () {},
            onEdit: () => edits++,
            onAddress: () {},
            onSavedPlaces: () {},
            onVisibility: () => visibility++,
            onVerification: () {},
            onSettings: () {},
            onActivity: () {},
          ),
        );
        for (final label in ['Preview public profile', 'Home address', 'Locations & service area',
          'Saved places', 'Account settings', 'My requests', 'Plan & payments', 'Meeting preference', 'Verification']) {
          expect(find.text(label), findsNothing);
        }
        await t.tap(find.text(sellerMode ? 'Business profile' : 'Profile details'));
        expect(edits, 1);
        expect(find.text('Edit Profile'), findsOneWidget);
        expect(find.text('Change profile picture'), findsOneWidget);
        expect(find.text('Add photo'), findsNothing);
        final photo = find.byKey(Key(sellerMode ? 'sellerEditProfileChangePhoto' : 'buyerEditProfileChangePhoto'));
        await t.ensureVisible(photo);
        await t.tap(photo);
        await t.pumpAndSettle();
        expect(find.text('Take a photo'), findsOneWidget);
        expect(find.text('Choose from photo library'), findsOneWidget);
        expect(find.text('Remove current photo'), findsOneWidget);
        await t.tap(find.byKey(Key(sellerMode ? 'sellerPhotoChooseGallery' : 'buyerPhotoChooseGallery')));
        await t.pumpAndSettle();
        expect(photos, 1);
        expect(find.text('Choose from photo library'), findsNothing);
        final visibilityLabel = sellerMode ? 'Contact & visibility' : 'Profile visibility';
        await t.ensureVisible(find.text(visibilityLabel));
        await t.tap(find.text(visibilityLabel));
        expect(visibility, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
}



