import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/approved_replica_metrics.dart';
import 'package:hocalist/theme/responsive_foundation.dart';

void main() {
  group('ApprovedReplicaMetrics width classes', () {
    final cases =
        <
          ({
            double width,
            ApprovedReplicaWidthClass widthClass,
            double geometryScale,
            double typographyScale,
            double contentMaxWidth,
            bool scaledCanvas,
          })
        >[
          (
            width: 304,
            widthClass: ApprovedReplicaWidthClass.narrow320,
            geometryScale: 304 / 390,
            typographyScale: 304 / 390,
            contentMaxWidth: 304,
            scaledCanvas: true,
          ),
          (
            width: 320,
            widthClass: ApprovedReplicaWidthClass.narrow320,
            geometryScale: 320 / 390,
            typographyScale: 320 / 390,
            contentMaxWidth: 320,
            scaledCanvas: true,
          ),
          (
            width: 350,
            widthClass: ApprovedReplicaWidthClass.compact360,
            geometryScale: 350 / 390,
            typographyScale: 350 / 390,
            contentMaxWidth: 350,
            scaledCanvas: true,
          ),
          (
            width: 360,
            widthClass: ApprovedReplicaWidthClass.compact360,
            geometryScale: 360 / 390,
            typographyScale: 360 / 390,
            contentMaxWidth: 360,
            scaledCanvas: true,
          ),
          (
            width: 390,
            widthClass: ApprovedReplicaWidthClass.reference,
            geometryScale: 1,
            typographyScale: 1,
            contentMaxWidth: 390,
            scaledCanvas: false,
          ),
          (
            width: 430,
            widthClass: ApprovedReplicaWidthClass.reference,
            geometryScale: 1,
            typographyScale: 1,
            contentMaxWidth: 430,
            scaledCanvas: false,
          ),
          (
            width: 600,
            widthClass: ApprovedReplicaWidthClass.tablet,
            geometryScale: 1,
            typographyScale: 1 + (0.06 * 170 / 550),
            contentMaxWidth: 600,
            scaledCanvas: false,
          ),
          (
            width: 768,
            widthClass: ApprovedReplicaWidthClass.tablet,
            geometryScale: 1,
            typographyScale: 1 + (0.06 * 338 / 550),
            contentMaxWidth: 768,
            scaledCanvas: false,
          ),
          (
            width: 980,
            widthClass: ApprovedReplicaWidthClass.tablet,
            geometryScale: 1,
            typographyScale: 1.06,
            contentMaxWidth: 920,
            scaledCanvas: false,
          ),
        ];

    for (final item in cases) {
      test('${item.width} resolves bounded-fluid tokens', () {
        final metrics = ApprovedReplicaMetrics.resolve(
          availableWidth: item.width,
          textScaler: TextScaler.noScaling,
        );

        expect(metrics.widthClass, item.widthClass);
        expect(metrics.geometryScale, closeTo(item.geometryScale, 0.000001));
        expect(
          metrics.typographyScale,
          closeTo(item.typographyScale, 0.000001),
        );
        expect(metrics.contentMaxWidth, item.contentMaxWidth);
        expect(metrics.screenshotLocked, isTrue);
        expect(metrics.usesScaledReplicaCanvas, item.scaledCanvas);
        expect(
          metrics.geometry(39),
          closeTo(39 * item.geometryScale, 0.000001),
        );
        expect(
          metrics.fontSize(13),
          closeTo(13 * item.typographyScale, 0.000001),
        );
      });
    }
  });

  test('Small Medium and Large retain the approved composition', () {
    for (final scale in [0.9, 1.0, 1.15]) {
      final metrics = ApprovedReplicaMetrics.resolve(
        availableWidth: 320,
        textScaler: TextScaler.linear(scale),
      );

      expect(metrics.screenshotLocked, isTrue);
      expect(metrics.accessibilityReflow, isFalse);
      expect(metrics.accessibilityLayout, HocalistAccessibilityLayout.approved);
      expect(
        metrics.geometryScale,
        closeTo(ApprovedReplicaMetrics.narrowScale, 0.000001),
      );
    }
  });

  test('larger scales progressively enable adaptive and stacked layouts', () {
    for (final item in <({double scale, HocalistAccessibilityLayout layout})>[
      (scale: 1.2, layout: HocalistAccessibilityLayout.adaptive),
      (scale: 1.3, layout: HocalistAccessibilityLayout.adaptive),
      (scale: 1.6, layout: HocalistAccessibilityLayout.stacked),
    ]) {
      final metrics = ApprovedReplicaMetrics.resolve(
        availableWidth: 320,
        textScaler: TextScaler.linear(item.scale),
      );

      expect(metrics.screenshotLocked, isFalse);
      expect(metrics.accessibilityReflow, isTrue);
      expect(metrics.accessibilityLayout, item.layout);
      expect(
        metrics.geometryScale,
        closeTo(ApprovedReplicaMetrics.narrowScale, 0.000001),
      );
      expect(metrics.typographyScale, 1);
      expect(metrics.textScale, item.scale);
    }
  });

  test('accessibility reflow uses the fluid tablet content width', () {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: 768,
      textScaler: TextScaler.linear(1.3),
    );

    expect(metrics.accessibilityReflow, isTrue);
    expect(metrics.contentMaxWidth, 768);
    expect(metrics.usesScaledReplicaCanvas, isFalse);
    expect(metrics.typographyScale, 1);
  });

  test('text scaling does not reset phone geometry spacing or artwork', () {
    final normal = ApprovedReplicaMetrics.resolve(
      availableWidth: 320,
      textScaler: TextScaler.noScaling,
    );
    final extraLarge = ApprovedReplicaMetrics.resolve(
      availableWidth: 320,
      textScaler: TextScaler.linear(1.3),
    );

    expect(extraLarge.geometryScale, normal.geometryScale);
    expect(extraLarge.geometry(44), normal.geometry(44));
    expect(extraLarge.spacing(18), normal.spacing(18));
    expect(extraLarge.artSize(28), normal.artSize(28));
  });

  test('content width is capped without returning to a phone canvas', () {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: 1024,
      textScaler: TextScaler.noScaling,
    );

    expect(metrics.contentMaxWidth, 920);
    expect(metrics.contentMaxWidth, greaterThan(390));
    expect(metrics.typographyScale, 1.06);
  });

  test('spacing and artwork grow at independent bounded rates', () {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: 980,
      textScaler: TextScaler.noScaling,
    );

    expect(metrics.spacing(20), 27);
    expect(metrics.artSize(20), 23);
    expect(metrics.pageHorizontalPadding(20), 30);
    expect(metrics.geometry(20), 20);
  });

  test('geometry helpers preserve reference ratios', () {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: 360,
      textScaler: TextScaler.noScaling,
    );

    expect(
      metrics.geometryInsets(const EdgeInsets.fromLTRB(10, 20, 30, 40)),
      EdgeInsets.fromLTRB(
        10 * ApprovedReplicaMetrics.compactScale,
        20 * ApprovedReplicaMetrics.compactScale,
        30 * ApprovedReplicaMetrics.compactScale,
        40 * ApprovedReplicaMetrics.compactScale,
      ),
    );
    expect(metrics.geometrySize(const Size(39, 78)), const Size(36, 72));
    expect(
      metrics.innerContentMaxWidth(referenceHorizontalInset: 18),
      closeTo(360 - (36 * ApprovedReplicaMetrics.compactScale), 0.000001),
    );
    expect(
      metrics.lineHeight(referenceFontSize: 10, referenceLineHeight: 13),
      1.3,
    );
  });

  testWidgets('scope exposes resolved metrics to descendants', (tester) async {
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: 390,
      textScaler: TextScaler.noScaling,
    );
    late ApprovedReplicaMetrics resolved;

    await tester.pumpWidget(
      ApprovedReplicaScope(
        metrics: metrics,
        child: Builder(
          builder: (context) {
            resolved = ApprovedReplicaScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(identical(resolved, metrics), isTrue);
  });
}
