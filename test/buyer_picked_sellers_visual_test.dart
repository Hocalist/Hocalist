import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';

import 'test_fonts.dart';

class _ProjectAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith('assets/')) {
      return rootBundle.load(key);
    }
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

Future<void> _pumpSellers(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: _ProjectAssetBundle(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Nunito',
          scaffoldBackgroundColor: const Color(0xfff7f7fb),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
        ),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: ApprovedHocatrendsPickedSellersPage(
                  onBack: () {},
                  onChatSeller: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectOneLine(WidgetTester tester, String text, Finder card) {
  final rendered = tester.widget<Text>(
    find.descendant(of: card, matching: find.text(text)).first,
  );
  expect(rendered.maxLines, 1);
  expect(rendered.softWrap, isFalse);
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('Buyer seller cards separate commerce content at phone widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const sellers = <({String name, String price, String savings})>[
      (name: 'Northside Tech', price: '\$820', savings: 'Save \$180'),
      (name: 'Gadget Hub', price: '\$835', savings: 'Save \$165'),
      (name: 'Prime Tech Solutions', price: '\$845', savings: 'Save \$155'),
      (name: 'Tech World NY', price: '\$860', savings: 'Save \$140'),
      (name: 'Digital Depot', price: '\$875', savings: 'Save \$125'),
    ];

    for (final width in <double>[320, 360, 390, 430, 768, 980]) {
      await _pumpSellers(tester, width: width);
      for (final seller in sellers) {
        final card = find.byKey(
          ValueKey('approved-seller-card-${seller.name}'),
        );
        final chatText = find.descendant(
          of: card,
          matching: find.text('Chat Seller'),
        );
        final chatButton = find.ancestor(
          of: chatText,
          matching: find.byType(FilledButton),
        );
        final price = find.descendant(
          of: card,
          matching: find.text(seller.price),
        );
        final savings = find.descendant(
          of: card,
          matching: find.text(seller.savings),
        );

        _expectOneLine(tester, 'Chat Seller', card);
        final sellerName = tester.widget<Text>(
          find.descendant(of: card, matching: find.text(seller.name)).first,
        );
        expect(sellerName.style?.fontSize, greaterThanOrEqualTo(13.0));
        expect(
          tester.getRect(chatButton).overlaps(tester.getRect(price)),
          false,
        );
        expect(
          tester.getRect(chatButton).overlaps(tester.getRect(savings)),
          false,
        );
      }
      expect(tester.takeException(), isNull, reason: 'seller cards at $width');
    }
  });

  testWidgets('Buyer seller cards reflow for large text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scale in <double>[1.15, 1.3, 1.6]) {
      await _pumpSellers(tester, width: 320, textScale: scale);
      expect(tester.takeException(), isNull, reason: '320px at $scale');
      expect(find.text('Chat Seller'), findsNWidgets(5));
    }
  });
}
