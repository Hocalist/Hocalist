import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/features/seller/approved_seller_reschedule_dialog.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'offered meeting review keeps details and permits edits $width/$scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => ApprovedSellerRescheduleDialog(
                        customerName: 'seller',
                        currentDate: '2030-10-20',
                        currentTime: '14:30',
                        initialDate: DateTime(2030, 10, 20),
                        initialTime: const TimeOfDay(hour: 14, minute: 30),
                        timezoneId: 'America/Chicago',
                        initialProposal: true,
                        offeredPlaceLabel: 'TEST Library, Chicago',
                        onChangeLocation: () async => 'TEST new location',
                        onSubmit: (date, time, occurrence, key) async =>
                            const MeetingActionResult.failure(
                              'Test remains open',
                            ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.text('TEST Library, Chicago'), findsOneWidget);
          expect(find.text('1. Select a date'), findsNothing);
          expect(find.text('Confirm these details'), findsOneWidget);
          await tester.tap(find.text('Change location'));
          await tester.pumpAndSettle();
          expect(find.text('TEST new location'), findsOneWidget);
          await tester.tap(find.text('Change date or time'));
          await tester.pumpAndSettle();
          expect(find.text('1. Select a date'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
