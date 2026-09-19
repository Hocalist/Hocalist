import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/seller_app_shell.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';

Widget _foundationHarness({
  required Widget child,
  AccessibilityPreferences preferences = AccessibilityPreferences.defaults,
  double width = 390,
  double textScale = 1,
}) {
  final metrics = ApprovedReplicaMetrics.resolve(
    availableWidth: width,
    textScaler: TextScaler.linear(textScale),
  );
  return MaterialApp(
    theme: HocalistTheme.lightFor(preferences),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: ApprovedReplicaScope(metrics: metrics, child: child),
      ),
    ),
  );
}

BoxDecoration _firstDecoration(WidgetTester tester, Finder root) {
  final decorated = tester.widget<DecoratedBox>(
    find.descendant(of: root, matching: find.byType(DecoratedBox)).first,
  );
  return decorated.decoration as BoxDecoration;
}

void main() {
  testWidgets('default Buyer and Seller actions retain approved geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _foundationHarness(
        child: Column(
          children: [
            BuyerPrimaryButton(
              key: const Key('buyer-action'),
              label: 'Buyer action',
              onPressed: () {},
            ),
            SellerPrimaryButton(
              key: const Key('seller-action'),
              label: 'Seller action',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final buyer = find.byKey(const Key('buyer-action'));
    final seller = find.byKey(const Key('seller-action'));
    expect(tester.getSize(buyer).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(seller).height, greaterThanOrEqualTo(44));
    expect(
      _firstDecoration(tester, buyer).borderRadius,
      BorderRadius.circular(13),
    );
    expect(
      _firstDecoration(tester, seller).borderRadius,
      BorderRadius.circular(13),
    );
  });

  testWidgets('shared high-contrast preference reaches both role actions', (
    tester,
  ) async {
    const preferences = AccessibilityPreferences(
      textSize: AppTextSize.medium,
      fontStyle: AccessibilityFontStyle.standard,
      buttonStyle: AccessibilityButtonStyle.highContrast,
    );
    await tester.pumpWidget(
      _foundationHarness(
        preferences: preferences,
        child: Column(
          children: [
            BuyerPrimaryButton(
              key: const Key('buyer-action'),
              label: 'Buyer action',
              onPressed: () {},
            ),
            SellerPrimaryButton(
              key: const Key('seller-action'),
              label: 'Seller action',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    for (final key in const [Key('buyer-action'), Key('seller-action')]) {
      final decoration = _firstDecoration(tester, find.byKey(key));
      expect(decoration.borderRadius, BorderRadius.circular(3));
      expect(decoration.color, const Color(0xff2b11aa));
      expect(decoration.gradient, isNull);
    }
  });

  testWidgets('Seller role pill remains available during adaptive scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      _foundationHarness(
        width: 320,
        textScale: 1.3,
        child: SellerAppHeader(onNotifications: () {}),
      ),
    );

    expect(find.byKey(const Key('sellerModePill')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role typography inherits the selected global font', (
    tester,
  ) async {
    const preferences = AccessibilityPreferences(
      textSize: AppTextSize.medium,
      fontStyle: AccessibilityFontStyle.friendly,
      buttonStyle: AccessibilityButtonStyle.rounded,
    );
    await tester.pumpWidget(
      _foundationHarness(
        preferences: preferences,
        child: Builder(
          builder: (context) {
            final metrics = ApprovedReplicaScope.of(context);
            return Column(
              children: [
                Text(
                  'Buyer typography',
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.primaryBody,
                  ),
                ),
                Text('Seller typography', style: sellerText(metrics, 13)),
              ],
            );
          },
        ),
      ),
    );

    final buyer = tester.widget<Text>(find.text('Buyer typography'));
    final seller = tester.widget<Text>(find.text('Seller typography'));
    expect(buyer.style?.fontFamily, 'Lexend');
    expect(seller.style?.fontFamily, isNull);
    expect(
      Theme.of(
        tester.element(find.text('Seller typography')),
      ).textTheme.bodyMedium?.fontFamily,
      'Lexend',
    );
  });
}
