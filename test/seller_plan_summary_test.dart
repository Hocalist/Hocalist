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
  for (final plan in ['free','pro','elite']) {
    for (final width in [320.0,360.0,390.0,430.0]) {
      for (final scale in [1.0,1.15,1.3,1.6]) {
        testWidgets('$plan plan fits $width at text scale $scale', (tester) async {
          tester.view.devicePixelRatio=1;
          tester.view.physicalSize=Size(width,850);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final value=SellerEntitlementView.fromJson(entitlementJson(
            effectivePlan:plan,effectiveSource:plan=='free'?'free':'billing',
            billingPlan:plan=='free'?null:plan,calendarConfigured:true,
          ));
          await tester.pumpWidget(MaterialApp(theme:ThemeData(fontFamily:'Nunito'),home:MediaQuery(
            data:MediaQueryData(size:Size(width,850),textScaler:TextScaler.linear(scale)),
            child:Scaffold(body:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(12),child:
              RepaintBoundary(key:const Key('planCapture'),child:SellerPlanSummary(value:value))))),
          )));
          await tester.pumpAndSettle();
          expect(tester.takeException(),isNull);
          expect(find.text('CURRENT PLAN'),findsOneWidget);
          if(const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') && width==390 && scale==1) {
            final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('planCapture')));
            await tester.runAsync(() async {
              final image=await boundary.toImage();
              final data=await image.toByteData(format:ui.ImageByteFormat.png);
              await File('.codex-local/plan-$plan-current.png').writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}
