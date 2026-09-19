import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hocalist/main.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void useViewport(WidgetTester tester, Size size, {double textScale = 1}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
  }

  Widget accessibilityHarness({
    AccessibilityPreferences preferences = AccessibilityPreferences.defaults,
    ValueChanged<AccessibilityPreferences>? onApply,
    VoidCallback? onBack,
    Key? pageKey,
  }) {
    return MaterialApp(
      theme: HocalistTheme.lightFor(preferences),
      home: Scaffold(
        body: SafeArea(
          child: AccessibilityPage(
            key: pageKey,
            appliedPreferences: preferences,
            onApply: onApply ?? (_) {},
            onBack: onBack ?? () {},
          ),
        ),
      ),
    );
  }

  Future<void> scrollPageTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> precacheAccessibilityImages(WidgetTester tester) async {
    final context = tester.element(find.byType(AccessibilityPage));
    await tester.runAsync(() async {
      for (final asset in const [
        'assets/accessibility/icons/back-chevron.png',
        'assets/accessibility/icons/accessibility-person.png',
        'assets/accessibility/icons/selection-check.png',
        'assets/accessibility/icons/preview-eye-primary.png',
        'assets/accessibility/icons/preview-check-success.png',
        'assets/accessibility/icons/preview-eye-success.png',
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('390 default replica fits every approved section before nav', (
    tester,
  ) async {
    useViewport(tester, const Size(390, 844));
    await tester.pumpWidget(accessibilityHarness());
    await precacheAccessibilityImages(tester);

    expect(
      tester.getSize(find.byKey(const Key('accessibility-intro-panel'))),
      const Size(354, 78),
    );
    expect(
      tester.getSize(find.byKey(const Key('accessibility-text-preview-panel'))),
      const Size(354, 104),
    );

    final textCards = AppTextSize.values
        .map((size) => find.byKey(Key('text-size-${size.name}')))
        .toList();
    final textTop = tester.getTopLeft(textCards.first).dy;
    for (final card in textCards) {
      expect(tester.getTopLeft(card).dy, closeTo(textTop, 0.1));
      expect(tester.getSize(card), const Size(84, 63));
    }

    final fontCards = AccessibilityFontStyle.values
        .map((style) => find.byKey(Key('font-style-${style.name}')))
        .toList();
    final fontTop = tester.getTopLeft(fontCards.first).dy;
    for (final card in fontCards) {
      expect(tester.getTopLeft(card).dy, closeTo(fontTop, 0.1));
      expect(tester.getSize(card), const Size(114, 61));
    }

    final roundedCard = find.byKey(const Key('button-style-rounded'));
    final contrastCard = find.byKey(const Key('button-style-highContrast'));
    expect(tester.getSize(roundedCard), const Size(174, 73));
    expect(tester.getSize(contrastCard), const Size(174, 73));
    expect(
      tester.getTopLeft(contrastCard).dy,
      closeTo(tester.getTopLeft(roundedCard).dy, 0.1),
    );

    final roundedPreview = find.byKey(const Key('button-preview-rounded'));
    expect(tester.getSize(roundedPreview), const Size(135, 29));
    expect(
      tester.getTopRight(roundedCard).dx -
          tester.getTopRight(roundedPreview).dx,
      greaterThanOrEqualTo(19),
      reason: 'The approved check sits beside the sample, never over it.',
    );

    final finalPanel = find.byKey(
      const Key('accessibility-full-preview-panel'),
    );
    expect(tester.getSize(finalPanel), const Size(354, 74));
    expect(
      tester.getBottomRight(finalPanel).dy,
      lessThanOrEqualTo(742),
      reason: 'The green panel must finish above the shared bottom nav.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 default keeps the 390 composition proportionally scaled', (
    tester,
  ) async {
    useViewport(tester, const Size(320, 844));
    await tester.pumpWidget(accessibilityHarness());
    await precacheAccessibilityImages(tester);

    const scale = 320 / 390;
    final small = find.byKey(const Key('text-size-small'));
    final medium = find.byKey(const Key('text-size-medium'));
    final large = find.byKey(const Key('text-size-large'));
    final extraLarge = find.byKey(const Key('text-size-extraLarge'));
    final top = tester.getTopLeft(small).dy;
    for (final card in [small, medium, large, extraLarge]) {
      expect(tester.getTopLeft(card).dy, closeTo(top, 0.1));
      expect(tester.getSize(card).height, closeTo(63 * scale, 0.1));
    }

    expect(
      tester.getSize(find.byKey(const Key('accessibility-intro-panel'))).height,
      closeTo(78 * scale, 0.1),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('accessibility-text-preview-panel')))
          .height,
      closeTo(104 * scale, 0.1),
    );
    expect(
      tester.getSize(find.byKey(const Key('button-preview-rounded'))).height,
      closeTo(29 * scale, 0.1),
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const Key('accessibility-full-preview-panel')),
          )
          .dy,
      lessThan(620),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved phone widths retain the 4-3-2 option composition', (
    tester,
  ) async {
    useViewport(tester, const Size(390, 1000));
    const comparisonPreferences = AccessibilityPreferences(
      textSize: AppTextSize.large,
      fontStyle: AccessibilityFontStyle.standard,
      buttonStyle: AccessibilityButtonStyle.rounded,
    );

    await tester.pumpWidget(
      accessibilityHarness(preferences: comparisonPreferences),
    );
    await precacheAccessibilityImages(tester);

    final textCards = AppTextSize.values
        .map((size) => find.byKey(Key('text-size-${size.name}')))
        .toList();
    final textTop = tester.getTopLeft(textCards.first).dy;
    for (final card in textCards.skip(1)) {
      expect(tester.getTopLeft(card).dy, closeTo(textTop, 0.1));
    }

    await scrollPageTo(tester, find.byKey(const Key('font-style-standard')));
    final fontTop = tester
        .getTopLeft(find.byKey(const Key('font-style-standard')))
        .dy;
    expect(
      tester.getTopLeft(find.byKey(const Key('font-style-friendly'))).dy,
      closeTo(fontTop, 0.1),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('font-style-highContrast'))).dy,
      closeTo(fontTop, 0.1),
    );

    await scrollPageTo(tester, find.byKey(const Key('button-style-rounded')));
    final buttonTop = tester
        .getTopLeft(find.byKey(const Key('button-style-rounded')))
        .dy;
    expect(
      tester.getTopLeft(find.byKey(const Key('button-style-highContrast'))).dy,
      closeTo(buttonTop, 0.1),
    );
    final roundedPreview = find.byKey(const Key('button-preview-rounded'));
    final highContrastPreview = find.byKey(
      const Key('button-preview-highContrast'),
    );
    expect(tester.getSize(roundedPreview), const Size(135, 29));
    expect(tester.getSize(highContrastPreview), const Size(131, 29));

    final roundedCardRight = tester
        .getTopRight(find.byKey(const Key('button-style-rounded')))
        .dx;
    final roundedCardTop = tester
        .getTopLeft(find.byKey(const Key('button-style-rounded')))
        .dy;
    final roundedPreviewRight = tester.getTopRight(roundedPreview).dx;
    final roundedPreviewTop = tester.getTopLeft(roundedPreview).dy;
    expect(
      roundedCardRight - roundedPreviewRight,
      greaterThanOrEqualTo(19),
      reason: 'The selected check must sit beside the preview, not on it.',
    );
    expect(roundedPreviewTop - roundedCardTop, closeTo(13, 0.1));

    final roundedLabel = tester.widget<Text>(
      find.byKey(const Key('button-preview-label-rounded')),
    );
    expect(roundedLabel.style?.fontFamily, HocalistTheme.appFontFamily);
    expect(roundedLabel.style?.fontSize, 10.5);
    expect(roundedLabel.style?.fontWeight, FontWeight.w600);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(375, 900);
    await tester.pumpWidget(
      accessibilityHarness(
        preferences: comparisonPreferences,
        pageKey: const ValueKey('width-375'),
      ),
    );
    await tester.pumpAndSettle();

    final narrowNormalTop = tester.getTopLeft(textCards.first).dy;
    for (final card in textCards.skip(1)) {
      expect(tester.getTopLeft(card).dy, closeTo(narrowNormalTop, 0.1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Large preserves composition and Extra Large reflows locally', (
    tester,
  ) async {
    useViewport(tester, const Size(360, 900), textScale: 1.15);
    await tester.pumpWidget(accessibilityHarness());
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'initial accessibility view',
    );

    final small = find.byKey(const Key('text-size-small'));
    final medium = find.byKey(const Key('text-size-medium'));
    final large = find.byKey(const Key('text-size-large'));
    final extraLarge = find.byKey(const Key('text-size-extraLarge'));
    expect(
      tester.getTopLeft(small).dy,
      closeTo(tester.getTopLeft(medium).dy, 0.1),
    );
    expect(
      tester.getTopLeft(large).dy,
      closeTo(tester.getTopLeft(small).dy, 0.1),
    );
    expect(
      tester.getTopLeft(extraLarge).dy,
      closeTo(tester.getTopLeft(small).dy, 0.1),
    );
    expect(tester.takeException(), isNull, reason: 'text-size grid');

    final standard = find.byKey(const Key('font-style-standard'));
    final friendly = find.byKey(const Key('font-style-friendly'));
    await scrollPageTo(tester, standard);
    expect(tester.takeException(), isNull, reason: 'font grid scroll');
    expect(
      tester.getTopLeft(friendly).dy,
      closeTo(tester.getTopLeft(standard).dy, 0.1),
    );
    expect(tester.takeException(), isNull, reason: 'font grid');

    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pumpWidget(
      accessibilityHarness(pageKey: const ValueKey('extra-large-reflow')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Extra Large initial view');
    expect(
      tester.getTopLeft(large).dy,
      greaterThan(tester.getTopLeft(small).dy),
    );
    await scrollPageTo(
      tester,
      find.byKey(const Key('accessibility-full-preview-panel')),
    );
    expect(
      find.byKey(const Key('accessibility-full-preview-panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull, reason: 'Extra Large final panel');
  });

  testWidgets('draft choices apply together from the full preview', (
    tester,
  ) async {
    useViewport(tester, const Size(390, 1000));
    AccessibilityPreferences? applied;
    await tester.pumpWidget(
      accessibilityHarness(onApply: (value) => applied = value),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('text-size-extraLarge')));
    await tester.tap(find.byKey(const Key('font-style-friendly')));
    await scrollPageTo(
      tester,
      find.byKey(const Key('button-style-highContrast')),
    );
    await tester.tap(find.byKey(const Key('button-style-highContrast')));
    await tester.pumpAndSettle();
    expect(applied, isNull);

    await scrollPageTo(
      tester,
      find.byKey(const Key('show-accessibility-preview')),
    );
    await tester.tap(find.byKey(const Key('show-accessibility-preview')));
    await tester.pumpAndSettle();

    final previewContext = tester.element(find.text('Example request card'));
    expect(Theme.of(previewContext).textTheme.titleLarge?.fontFamily, 'Lexend');
    expect(
      Theme.of(
        previewContext,
      ).extension<HocalistAccessibilityVisuals>()?.buttonRadius,
      3,
    );

    await tester.ensureVisible(find.text('Apply changes'));
    await tester.tap(find.text('Apply changes'));
    await tester.pumpAndSettle();

    expect(
      applied,
      const AccessibilityPreferences(
        textSize: AppTextSize.extraLarge,
        fontStyle: AccessibilityFontStyle.friendly,
        buttonStyle: AccessibilityButtonStyle.highContrast,
      ),
    );
  });

  testWidgets('back confirms and discards an unapplied draft', (tester) async {
    useViewport(tester, const Size(390, 1000));
    var backCalled = false;
    var applyCalled = false;
    await tester.pumpWidget(
      accessibilityHarness(
        onApply: (_) => applyCalled = true,
        onBack: () => backCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('text-size-large')));
    await tester.tap(find.byKey(const Key('accessibility-back')));
    await tester.pumpAndSettle();
    expect(find.text('Discard accessibility changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
    expect(applyCalled, isFalse);
  });
}
