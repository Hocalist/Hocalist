import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/commercial/seller_plan_summary.dart';
import 'phase2/commercial/support/commercial_payloads.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets(
    'all seller plans list benefits and open the matching billing choice',
    (tester) async {
      final opened = <Uri>[];
      final value = SellerEntitlementView.fromJson(
        entitlementJson(
          effectivePlan: 'pro',
          effectiveSource: 'billing',
          billingPlan: 'pro',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SellerPlanSummary(
                value: value,
                openBilling: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      final heading = tester.getTopLeft(find.text('Seller plans'));
      final panel = tester.getTopLeft(find.byType(SellerPlanSummary));
      expect(heading.dx - panel.dx, greaterThanOrEqualTo(16));
      expect(heading.dy - panel.dy, greaterThanOrEqualTo(16));
      for (final limit in [10, 50, 100]) {
        expect(
          find.text('Target up to $limit different buyers per week'),
          findsOneWidget,
        );
      }
      for (final limit in [3, 15, 50]) {
        expect(
          find.text('List up to $limit products or services'),
          findsOneWidget,
        );
      }
      expect(
        find.text('Customer insights before sending an offer'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Viewing competing offers removes the waiver'),
        findsOneWidget,
      );
      for (final (label, plan) in [
        ('Switch to Free', 'free'),
        ('Manage Pro Seller', 'pro'),
        ('Switch to Elite Seller', 'elite'),
      ]) {
        final action = find.text(label);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          opened.last.toString(),
          'https://hocalist.com/billing?plan=$plan#seller-plans',
        );
      }
      expect(opened, hasLength(3));
    },
  );

  for (final plan in ['free', 'pro', 'elite']) {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        testWidgets('$plan plan fits $width at text scale $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 850);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final value = SellerEntitlementView.fromJson(
            entitlementJson(
              effectivePlan: plan,
              effectiveSource: plan == 'free' ? 'free' : 'billing',
              billingPlan: plan == 'free' ? null : plan,
              calendarConfigured: true,
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'Nunito'),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 850),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: RepaintBoundary(
                        key: const Key('planCapture'),
                        child: SellerPlanSummary(value: value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('CURRENT PLAN'), findsOneWidget);
          if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') &&
              width == 390 &&
              scale == 1) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('planCapture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '.codex-local/plan-$plan-current.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}
