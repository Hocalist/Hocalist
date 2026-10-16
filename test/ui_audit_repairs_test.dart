import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_account_field.dart';
import 'package:hocalist/components/hocalist_section_tabs.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';
import 'package:hocalist/main.dart' show HocalistTheme;

void main() {
  testWidgets('inactive tabs inherit readable dark-surface foreground', (
    tester,
  ) async {
    final theme = ThemeData.dark();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: HocalistSectionTabs(
            accent: Color(0xff1917ff),
            sections: {
              'Security': [Text('Security content')],
              'Preferences': [Text('Preference content')],
            },
          ),
        ),
      ),
    );
    final label = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const ValueKey('section-tab-Preferences')),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(label.text.style!.color, theme.colorScheme.onSurface);
  });
  testWidgets('reduced motion keeps the onboarding preview stable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ApprovedBuyerBenefitsPage(
              name: 'Buyer',
              onClose: () {},
              onFinish: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .toList();
    await tester.pump(const Duration(seconds: 9));
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .toList(),
      before,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'password visibility retains the entered draft and disabled fence',
    (tester) async {
      final controller = TextEditingController(text: 'test draft');
      addTearDown(controller.dispose);
      Future<void> mount(bool enabled) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HocalistAccountField(
              label: 'New password',
              controller: controller,
              obscureText: true,
              enabled: enabled,
              autofillHints: const [AutofillHints.newPassword],
            ),
          ),
        ),
      );
      await mount(true);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('Show new password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      expect(controller.text, 'test draft');
      await mount(false);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).autofillHints, [
        AutofillHints.newPassword,
      ]);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('full tab labels remain reachable $width/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: HocalistSectionTabs(
                  accent: BuyerUiTokens.action,
                  sections: const {
                    'Security': [Text('Password form')],
                    'Preferences': [Text('Preference form')],
                    'Privacy': [Text('Privacy form')],
                  },
                ),
              ),
            ),
          ),
        );
        final text = tester.widget<Text>(find.text('Preferences'));
        final size = tester.getSize(find.text('Preferences'));
        final painter = TextPainter(
          text: TextSpan(text: text.data, style: text.style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout();
        expect(size.width, greaterThanOrEqualTo(painter.width - .1));
        await tester.ensureVisible(find.text('Privacy'));
        await tester.tap(find.text('Privacy'));
        await tester.pumpAndSettle();
        expect(find.text('Privacy form'), findsOneWidget);
        expect(find.text('Password form'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'real seller profile preserves approved information sections without fixtures',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ApprovedSellerPublicProfilePage(
                realMode: true,
                realSellerName: 'Actual seller',
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in [
        'Trust details',
        'What this seller offers',
        'Meetup preferences',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('John D.'), findsNothing);
      expect(find.text('98%'), findsNothing);
    },
  );

  test(
    'success text has sufficient contrast while original accents remain',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
      }

      expect(
        contrast(BuyerUiTokens.successText, const Color(0xffecf8ee)),
        greaterThan(4.5),
      );
      expect(
        contrast(SellerUiColors.greenText, SellerUiColors.greenSurface),
        greaterThan(4.5),
      );
      expect(BuyerUiTokens.success, const Color(0xff109b4e));
      expect(SellerUiColors.green, const Color(0xff119527));
      final toast = HocalistTheme.dark.snackBarTheme;
      expect(
        contrast(toast.contentTextStyle!.color!, toast.backgroundColor!),
        greaterThan(4.5),
      );
    },
  );
}
