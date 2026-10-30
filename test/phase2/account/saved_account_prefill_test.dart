import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/features/account/private_contact_editor.dart';
import 'package:hocalist/features/account/profile_details_editor.dart';
import 'account_test_fakes.dart';

void main() {
  testWidgets('address arrives after opening and refresh preserves edits', (
    tester,
  ) async {
    PrivateContactRecord? current;
    Future<void> render() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PrivateContactEditor(
              readCurrent: () => current,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    await render();
    current = privateContact(phone: '123456', city: 'Chicago');
    await render();
    expect(find.text('Chicago'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('privateContact3')),
      'My draft city',
    );
    current = privateContact(phone: '987654', city: 'Boston', revision: 2);
    await render();
    expect(find.text('My draft city'), findsOneWidget);
    expect(find.text('Boston'), findsNothing);
  });

  testWidgets('profile arrives after opening and refresh preserves edits', (
    tester,
  ) async {
    AccountRoleProfile? current;
    Future<void> render() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileDetailsEditor(
              readCurrent: () => current,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    await render();
    current = roleProfile(areaLabel: 'Chicago', profileNote: 'Saved note');
    await render();
    expect(find.text('Chicago'), findsOneWidget);
    expect(find.text('Saved note'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profileDetailsField0')),
      'My draft area',
    );
    current = roleProfile(areaLabel: 'Boston', revision: 2);
    await render();
    expect(find.text('My draft area'), findsOneWidget);
    expect(find.text('Boston'), findsNothing);
  });
}
