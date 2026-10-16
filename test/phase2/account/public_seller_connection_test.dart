import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import '../../test_fonts.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import '../marketplace/support/marketplace_fakes.dart' show leadJson;

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets(
    'real request renders authoritative fields without prototype PIN',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ApprovedSellerOriginalRequestPage(
                onBack: () {},
                onReturnToChat: () {},
                realMode: true,
                request: decodeLeadJson({
                  ...leadJson(),
                  'title': 'Actual requested item',
                }, 'lead'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Actual requested item'), findsOneWidget);
      expect(find.textContaining('PIN'), findsNothing);
      expect(find.text('Latest request details shared by the buyer.'), findsOneWidget);
      expect(find.textContaining('USD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable real request offers retry without sample details', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerOriginalRequestPage(
              onBack: () {},
              onReturnToChat: () {},
              realMode: true,
              error: 'Request unavailable',
              onRetry: () => retries++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Request unavailable'), findsOneWidget);
    expect(find.textContaining('iPad'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
  testWidgets('seller help and safety report both reach connected support', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerHelpSupportPage(
              onBack: () {},
              onSafety: () {},
              onContactSupport: () {
                opened++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Ask for help'));
    await tester.tap(find.text('Ask for help'));
    await tester.pump();
    await tester.ensureVisible(find.text('Report a safety concern'));
    await tester.tap(find.text('Report a safety concern'));
    await tester.pump();
    expect(opened, 2);
    expect(find.text('Support UI is ready'), findsNothing);
    expect(
      find.text('Support request saved for ticket connection.'),
      findsNothing,
    );
  });
  testWidgets(
    'real seller surface never invents trust and selection calls the backend callback',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ApprovedSellerPublicProfilePage(
                onBack: () {},
                onSelect: () {
                  calls++;
                },
                realMode: true,
                realSellerName: 'Actual seller',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Actual seller'), findsOneWidget);
      expect(find.text('John D.'), findsNothing);
      expect(find.text('Verified seller • Active now'), findsNothing);
      expect(find.text('126'), findsNothing);
      await tester.tap(
        find.byKey(const Key('approved-public-profile-select-seller')),
      );
      expect(calls, 1);
    },
  );
  testWidgets('busy selection prevents another submit and preserves error', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerPublicProfilePage(
              onBack: () {},
              onSelect: () {
                calls++;
              },
              realMode: true,
              realSellerName: 'Actual seller',
              selectionBusy: true,
              selectionError: 'Offer changed. Refresh before selecting.',
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('approved-public-profile-select-seller')),
    );
    expect(calls, 0);
    expect(
      find.text('Offer changed. Refresh before selecting.'),
      findsOneWidget,
    );
  });
}
