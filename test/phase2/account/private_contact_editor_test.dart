import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/account/private_contact_editor.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/common.dart';

void main() {
  testWidgets(
    'private contacts retain revision and retry payload until acknowledgement',
    (tester) async {
      final current = PrivateContactRecord(
        userId: 'a',
        contact: AccountContact(
          phone: 'old',
          addressLine1: 'Old street',
          countryCode: 'US',
        ),
        stamp: RecordStamp(
          revision: 4,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final commands = <UpdateContactCommand>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrivateContactEditor(
                readCurrent: () => current,
                onSave: (c) async {
                  commands.add(c);
                  if (commands.length == 1) throw Exception('private failure');
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('privateContact0')), '');
      await tester.enterText(
        find.byKey(const Key('privateContact1')),
        'New street',
      );
      await tester.ensureVisible(find.text('Save contact details'));
      await tester.tap(find.text('Save contact details'));
      await tester.pumpAndSettle();
      expect(find.text('Private contact details saved.'), findsNothing);
      expect(commands.single.expectedRevision, 4);
      expect(commands.single.phone.isClear, true);
      expect(commands.single.addressLine1.valueOrNull, 'New street');
      await tester.ensureVisible(find.text('Retry contact save'));
      await tester.tap(find.text('Retry contact save'));
      await tester.pumpAndSettle();
      expect(identical(commands.first, commands.last), true);
      expect(find.text('Private contact details saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
