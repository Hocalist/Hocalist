import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets('settings accessibility row cannot absorb page title or tabs', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerSettingsPage(
              darkMode: false,
              textSizeLabel: 'Medium',
              onBack: () {},
              onEditProfile: () {},
              onThemeChanged: (_) {},
              onAccessibility: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    final row = tester.getSemantics(find.text('Accessibility'));
    expect(row.label, contains('Accessibility'));
    expect(row.label, isNot(contains('Account Settings')));
    expect(row.label, isNot(contains('Security')));
    semantics.dispose();
  });
  for (final seller in [false, true]) {
    testWidgets(
      '${seller ? 'Seller' : 'Buyer'} status and progress do not absorb page actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  seller
                      ? const SellerStatusChip(label: 'Pending')
                      : const BuyerStatusChip(label: 'Pending'),
                  seller
                      ? const SellerProgressStrip()
                      : const BuyerProgressStrip(),
                  TextButton(
                    key: const Key('reload-action'),
                    onPressed: () {},
                    child: const Text('Reload'),
                  ),
                ],
              ),
            ),
          ),
        );
        final chip = tester.getSemantics(
          find.byType(seller ? SellerStatusChip : BuyerStatusChip),
        );
        expect(chip.label, 'Pending');
        expect(
          tester.getSemantics(find.byKey(const Key('reload-action'))).label,
          'Reload',
        );
        expect(find.bySemanticsLabel('Loading'), findsOneWidget);
        semantics.dispose();
      },
    );
  }
}
