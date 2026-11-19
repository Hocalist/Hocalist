import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/seller/approved_seller_reschedule_dialog.dart';

void main() {
  testWidgets(
    'repeated meeting time requires a choice and submits the chosen occurrence',
    (tester) async {
      final choices = <RepeatedTimeOccurrence?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ApprovedSellerRescheduleDialog(
                    customerName: 'Buyer',
                    currentDate: 'November 1',
                    currentTime: '1:30 AM',
                    initialDate: DateTime(DateTime.now().year + 1, 11, 1),
                    initialTime: const TimeOfDay(hour: 1, minute: 30),
                    timezoneId: 'America/Chicago',
                    offeredPlaceLabel: 'Pickup location',
                    onSubmit: (_, _, choice, _) async {
                      choices.add(choice);
                      return const MeetingActionResult.failure(
                        'Choose which occurrence you mean.',
                        code: 'ambiguous_local_time',
                      );
                    },
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
      final send = find.byKey(const Key('sellerSendReschedule'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      final select = find.text('Select a time');
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(find.text('Earlier occurrence'), findsOneWidget);
      await tester.tap(find.text('Later occurrence'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(choices, [null, RepeatedTimeOccurrence.later]);
    },
  );
}
