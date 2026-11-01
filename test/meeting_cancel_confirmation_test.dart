import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/meetings/meeting_cancel_confirmation.dart';

void main() {
  for (final choice in ['Keep meeting', 'Cancel meeting']) {
    testWidgets('$choice only confirms cancellation when explicitly selected', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        TextButton(onPressed: () async { result = await confirmMeetingCancellation(context); }, child: const Text('Open'))))));
      await tester.tap(find.text('Open')); await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Cancel this meeting?'), findsOneWidget);
      await tester.tap(find.text(choice)); await tester.pumpAndSettle();
      expect(result, choice == 'Cancel meeting');
    });
  }
}
