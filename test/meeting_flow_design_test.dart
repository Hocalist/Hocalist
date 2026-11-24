import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/meeting_directions_page.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'test_fonts.dart';
import 'visual_proof_capture.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final seller in [false, true]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.15, 1.3, 1.6]) {
          testWidgets('directions shared controls $seller $platform $width/$scale', (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = Size(width, 1000);
            addTearDown(t.view.resetDevicePixelRatio);
            addTearDown(t.view.resetPhysicalSize);
            await t.pumpWidget(MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: HocalistTheme.light.copyWith(platform: platform),
              home: MediaQuery(data: MediaQueryData(size: Size(width, 1000), textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: const Key('directions-proof'), child: MeetingDirectionsPage(
                  meetingId: 'test', seller: seller,
                  destination: '123 Test Street, Los Angeles, CA, 90017, US',
                  destinationLatitude: 34, destinationLongitude: -118,
                  destinationMapBuilder: (_) => const ColoredBox(color: Color(0xffeeedf5)),
                ))),
            ));
            await t.pumpAndSettle();
            final driving = find.text('Driving'), walking = find.text('Walking');
            expect(t.getCenter(driving).dy, closeTo(t.getCenter(walking).dy, 1));
            expect(t.widget<Text>(find.text('Meet here')).style!.fontSize, lessThan(20));
            await t.ensureVisible(walking);
            await t.tap(walking);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            if (const bool.fromEnvironment('HOCALIST_MEETING_DESIGN_CAPTURE') && !seller &&
                platform == TargetPlatform.android && (width == 320 || width == 390) && (scale == 1 || scale == 1.6)) {
              await t.drag(find.byKey(const Key('meeting-route-sheet')), const Offset(0, -480));
              await t.pumpAndSettle();
              await writeProofImage(t, find.byKey(const Key('directions-proof')), 'meeting-directions-${width.toInt()}-$scale.png');
            }
          });
        }
      }
    }
  }
}
