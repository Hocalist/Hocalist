import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/commercial/credit_wallet_panel.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'phase2/commercial/support/commercial_payloads.dart';

void main() {
  testWidgets('Activity filters use authoritative target states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CreditWalletPanel(
              additionalSections: const {'Plans': []},
              load: () async => CreditWalletView.fromJson(
                creditWalletJson(
                  targets: [
                    targetJson(
                      id: 'reserved',
                      status: 'reserved',
                      charged: 0,
                      title: 'Reserved camera',
                    ),
                    targetJson(
                      id: 'charged',
                      status: 'initial_charged',
                      reserved: 0,
                      title: 'Charged camera',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('creditBatch-bt-1')), findsOneWidget);
    expect(find.byKey(const Key('creditWalletNoPacks')), findsOneWidget);
    expect(find.text('Refresh credits'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('section-tab-Activity')));
    await tester.pumpAndSettle();
    expect(find.text('Reserved camera'), findsOneWidget);
    expect(find.text('Charged camera'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reserved').last);
    await tester.pumpAndSettle();
    expect(find.text('Reserved camera'), findsOneWidget);
    expect(find.text('Charged camera'), findsNothing);
    await tester.tap(find.byTooltip('Filter activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charged').last);
    await tester.pumpAndSettle();
    expect(find.text('Reserved camera'), findsNothing);
    expect(find.text('Charged camera'), findsOneWidget);
  });
  testWidgets('real billing keeps credits separate from plans and payment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerBillingPage(
              onBack: () {},
              onPayment: () {},
              realContent: const Text('Authoritative ledger'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Authoritative ledger'), findsOneWidget);
    expect(find.text('Manage payment methods securely'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('section-tab-Plans')));
    await tester.pumpAndSettle();
    expect(find.text('Authoritative ledger'), findsNothing);
    expect(find.text('Manage payment methods securely'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('section-tab-Credits')));
    await tester.pumpAndSettle();
    expect(find.text('Authoritative ledger'), findsOneWidget);
  });

  testWidgets(
    'one wallet read feeds Credits and Recent targeting; payment is inline',
    (tester) async {
      var loads = 0;
      var oldPaymentRoute = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ApprovedSellerBillingPage(
                onBack: () {},
                onPayment: () => oldPaymentRoute++,
                realContent: CreditWalletPanel(
                  load: () async {
                    loads++;
                    return CreditWalletView.fromJson(creditWalletJson());
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('52.50 HC'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('creditWalletRefresh'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('creditWalletAvailable'))).dy,
        ),
      );
      expect(find.text('Sold camera'), findsNothing);
      expect(find.byKey(const Key('creditBatch-bt-1')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('creditDepositDetailsToggle')),
      );
      await tester.tap(find.byKey(const Key('creditDepositDetailsToggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('creditBatch-bt-1')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('section-tab-Activity')),
      );
      await tester.tap(find.byKey(const ValueKey('section-tab-Activity')));
      await tester.pumpAndSettle();
      expect(find.text('Sold camera'), findsOneWidget);
      expect(find.byKey(const Key('creditWalletAvailable')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('section-tab-Plans')));
      await tester.pumpAndSettle();
      expect(find.text('Manage payment method'), findsOneWidget);
      expect(find.byKey(const Key('creditWalletRefresh')), findsNothing);
      expect(oldPaymentRoute, 0);
      await tester.tap(find.byKey(const ValueKey('section-tab-Credits')));
      await tester.pumpAndSettle();
      expect(find.text('52.50 HC'), findsOneWidget);
      expect(loads, 1);
    },
  );

  testWidgets('Plans stays reachable if the credit read fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerBillingPage(
              onBack: () {},
              onPayment: () {},
              realContent: CreditWalletPanel(
                load: () async => throw StateError('offline'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-tab-Plans')));
    await tester.pumpAndSettle();
    expect(find.text('Manage payment method'), findsOneWidget);
    expect(find.textContaining('HC'), findsNothing);
  });

  testWidgets(
    'seller identity, categories and details are separate and drafts survive',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovedSellerEditProfilePage(
              name: 'Northside',
              email: 'seller@example.com',
              onNameChanged: (_) {},
              onBack: () {},
              onDone: () => saves++,
              categoryEditor: const Text('Connected category editor'),
              profileDetailsEditor: const Text('Connected service-area editor'),
              contactEditor: const Text('Private contact fields'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Updated store');
      expect(find.text('Connected category editor'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('section-tab-Categories')));
      await tester.pumpAndSettle();
      expect(find.text('Connected category editor'), findsOneWidget);
      expect(find.byKey(const Key('sellerSaveProfile')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('section-tab-Private contact')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private contact fields'), findsOneWidget);
      expect(find.text('Connected service-area editor'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('section-tab-Seller info')));
      await tester.pumpAndSettle();
      expect(find.text('Updated store'), findsOneWidget);
      expect(find.byKey(const Key('sellerSaveProfile')), findsNothing);
      expect(saves, 0);
    },
  );

  for (final seller in [false, true]) {
    testWidgets(
      '${seller ? 'Seller' : 'Buyer'} settings tabs preserve reachable actions',
      (tester) async {
        var edits = 0;
        final page = seller
            ? ApprovedSellerSettingsPage(
                contactEditor: const Text('Saved business address fields'),
                darkMode: false,
                textSizeLabel: 'Default',
                onBack: () {},
                onEditProfile: () => edits++,
                onThemeChanged: (_) {},
                onAccessibility: () {},
                onSecurity: () => edits++,
                onAccountLifecycle: () {},
              )
            : BuyerSettingsPage(
                contactEditor: const Text('Saved home address fields'),
                darkMode: false,
                textSize: AppTextSize.medium,
                onEditProfile: () => edits++,
                onThemeChanged: (_) {},
                onAccessibility: () {},
                onSecurity: () => edits++,
                onAccountLifecycle: () {},
              );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: page)),
          ),
        );
        await tester.pumpAndSettle();
        if (seller) {
          expect(find.byKey(const ValueKey('section-tab-Privacy')), findsNothing);
          expect(find.text('Public Seller visibility'), findsNothing);
          expect(find.text('Service-area privacy'), findsNothing);
          expect(find.text('Saved business address fields'), findsOneWidget);
          expect(find.text('Appearance'), findsOneWidget);
          expect(find.text('Account data & deletion'), findsOneWidget);
          await tester.tap(find.text('Password & security'));
          expect(edits, 1);
          return;
        }
        await tester.tap(find.byKey(const ValueKey('section-tab-Private contact')));
        await tester.pumpAndSettle();
        expect(find.text(seller ? 'Saved business address fields' : 'Saved home address fields'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('section-tab-Security')));
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsNothing);
        expect(find.text('Account data & deletion'), findsOneWidget);
        expect(
          find.text(seller ? 'Seller information' : 'Personal information'),
          findsNothing,
        );
        await tester.tap(find.text('Password & security'));
        expect(edits, 1);
        await tester.tap(find.byKey(const ValueKey('section-tab-Preferences')));
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Password & security'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('section-tab-Privacy')));
        await tester.pumpAndSettle();
        expect(find.text('Account data & deletion'), findsNothing);
        expect(
          find.text(
            seller ? 'Public Seller visibility' : 'Request & location privacy',
          ),
          findsOneWidget,
        );
        expect(find.text('Appearance'), findsNothing);
      },
    );
  }
}
