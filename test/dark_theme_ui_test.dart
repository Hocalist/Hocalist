import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/control_foundation.dart';
import 'package:hocalist/theme/approved_interface_icons.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  test('dark text and outline button icons have readable default colors', () {
    for (final style in [HocalistTheme.dark.textButtonTheme.style!, HocalistTheme.dark.outlinedButtonTheme.style!]) {
      final foreground = style.foregroundColor!.resolve({})!;
      expect((foreground.computeLuminance() + .05) /
        (HocalistTheme.dark.scaffoldBackgroundColor.computeLuminance() + .05), greaterThan(3));
    }
  });
  testWidgets('dark glyph tint preserves light icons and colored artwork', (tester) async {
    for (final theme in [HocalistTheme.light, HocalistTheme.dark]) {
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Row(children: [
        BuyerAssetIcon(asset: 'assets/approved_offers_chat/header-bell.png', slotSize: 24),
        BuyerAssetIcon(asset: 'assets/approved_onboarding_home/dashboard-plus.png', slotSize: 24),
        BuyerAssetIcon(asset: 'assets/approved_onboarding_home/dashboard-trophy-glyph.png', slotSize: 24),
        BuyerAssetIcon(asset: 'assets/approved_trends_notifications/transparent/trend-filter.png', slotSize: 24),
        BuyerAssetIcon(asset: 'assets/approved_onboarding_home/ready-gift.png', slotSize: 24),
      ])));
      await tester.pumpAndSettle();
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images[0].color, theme.brightness == Brightness.dark ? isNotNull : isNull);
      expect(images[1].color, theme.brightness == Brightness.dark ? isNotNull : isNull);
      expect(images[2].color, isNull);
      expect(find.byType(ApprovedInterfaceIcon), findsNWidgets(2));
    }
  });
  testWidgets('filter chips keep dark surfaces with readable labels and icons', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: HocalistTheme.dark, home: Scaffold(body:
      HocalistFilterChip(role: HocalistControlRole.buyer, label: 'All levels', selected: true,
        icon: Icons.tune, onSelected: (_) {}))));
    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.backgroundColor!.computeLuminance(), lessThan(.1));
    expect(chip.selectedColor!.computeLuminance(), lessThan(.1));
    expect((tester.widget<Icon>(find.byType(Icon)).color!.computeLuminance() + .05) /
      (chip.selectedColor!.computeLuminance() + .05), greaterThan(3));
  });
  testWidgets('seller meeting filter labels have contrast in both states', (tester) async {
    for (final selected in [false, true]) {
      await tester.pumpWidget(MaterialApp(theme: HocalistTheme.dark,
        home: Scaffold(body: HocalistFilterChip(
          role: HocalistControlRole.seller, label: 'Today', selected: selected,
          onSelected: (_) {},
        ))));
      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      final background = selected ? chip.selectedColor! : chip.backgroundColor!;
      expect((chip.labelStyle!.color!.computeLuminance() + .05) /
        (background.computeLuminance() + .05), greaterThan(4.5));
    }
  });
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
