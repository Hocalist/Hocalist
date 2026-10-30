import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/features/account/business_address_editor.dart';

void main(){
 testWidgets('business editor loads stored values, saves manual changes and reloads independently',(tester) async {
  var record=PrivateContactRecord(userId:'seller',contact:AccountContact(addressLine1:'Saved business',city:'Chicago',countryCode:'US'),stamp:RecordStamp(revision:1,createdAt:DateTime.utc(2026),updatedAt:DateTime.utc(2026)));
  Widget page()=>MaterialApp(home:Scaffold(body:SingleChildScrollView(child:BusinessAddressEditor(
    load:() async=>record,onLoaded:(_){},save:(command) async {
      record=record.copyWith(contact:AccountContact(addressLine1:command.addressLine1.valueOrNull,city:command.city.valueOrNull,countryCode:command.countryCode.valueOrNull),stamp:RecordStamp(revision:2,createdAt:DateTime.utc(2026),updatedAt:DateTime.utc(2026)));
      return record;
    },
  ))));
  await tester.pumpWidget(page());await tester.pumpAndSettle();
  expect(find.text('Saved business'),findsOneWidget);
  expect(find.byKey(const Key('privateContact0')),findsNothing);
  await tester.enterText(find.byKey(const Key('privateContact1')),'New business street');
  await tester.ensureVisible(find.text('Save contact details'));
  await tester.tap(find.text('Save contact details'));await tester.pumpAndSettle();
  expect(record.contact.addressLine1,'New business street');
  await tester.pumpWidget(const SizedBox());await tester.pumpWidget(page());await tester.pumpAndSettle();
  expect(find.text('New business street'),findsOneWidget);
 });
}
