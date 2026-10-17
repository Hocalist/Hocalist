import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets(
    'palette preserves light artwork colors and gives dark text contrast',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: HocalistTheme.light,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final color in [
        Colors.white,
        Colors.black,
        const Color(0xfff3efff),
        const Color(0xff10145b),
        Colors.red,
      ]) {
        expect(HocalistPalette.surface(context, color), color);
        expect(HocalistPalette.text(context, color), color);
        expect(HocalistPalette.border(context, color), color);
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: HocalistTheme.dark,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final background = HocalistPalette.surface(context, Colors.white);
      final text = HocalistPalette.text(context, const Color(0xff10145b));
      expect(background.computeLuminance(), lessThan(.05));
      expect(
        (text.computeLuminance() + .05) / (background.computeLuminance() + .05),
        greaterThan(4.5),
      );
    },
  );
  testWidgets(
    'buyer and seller screens follow live light/dark changes at phone scales',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = <Widget Function()>[
        () => ApprovedBuyerHomePage(
          name: 'Buyer',
          requestTitle: 'Request',
          requestPosted: false,
          onCreate: () {},
          onRequestDetails: () {},
          onOffers: () {},
          onRecentActivity: () {},
          onWallet: () {},
        ),
        () => ApprovedRequestFlowPage(
          accent: const Color(0xff1917ff),
          requestTitle: 'Request',
          budget: '',
          includeAppChrome: true,
          onTitleChanged: (_) {},
          onBudgetChanged: (_) {},
          onBack: () {},
          onNotifications: () {},
          onSubmit: () {},
        ),
        () => ApprovedSellerMorePage(
          sellerName: 'Seller',
          onProfile: () {},
          onEditProfile: () {},
          onSettings: () {},
          onNotifications: () {},
          onAccessibility: () {},
          onSafety: () {},
          onHelp: () {},
          onLogout: () {},
        ),
      ];
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final scale in [1.0, 1.15, 1.3, 1.6]) {
          for (final page in pages) {
            for (final dark in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: HocalistTheme.light,
                  darkTheme: HocalistTheme.dark,
                  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(body: page()),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$width / $scale / dark=$dark',
              );
              final heading = find
                  .byType(Text)
                  .evaluate()
                  .map((e) => e.widget as Text)
                  .where(
                    (t) =>
                        t.style?.color != null &&
                        (t.data == 'More' || t.data == 'Post a request'),
                  );
              if (dark) {
                for (final material in tester.widgetList<Material>(
                  find.byType(Material),
                )) {
                  if (material.color != null && material.color!.a > .9) {
                    expect(
                      material.color!.computeLuminance(),
                      lessThan(.5),
                      reason:
                          'Dark pages must not retain a light Material surface',
                    );
                  }
                }
                for (final text in heading) {
                  expect(
                    text.style!.color!.computeLuminance(),
                    greaterThan(.4),
                  );
                }
              }
            }
          }
        }
      }
    },
  );
}
