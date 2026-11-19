import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/features/account/business_address_editor.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'phase2/account/account_test_fakes.dart';

void main(){
 testWidgets('address and radius share one save and retry the same radius intent',(tester) async {
  final record=PrivateContactRecord(userId:'seller',contact:AccountContact(addressLine1:'Saved business',city:'Chicago',countryCode:'US'),stamp:RecordStamp(revision:1,createdAt:DateTime.utc(2026),updatedAt:DateTime.utc(2026)));
  final profile=roleProfile(role:HocalistRole.seller,areaLabel:'Chicago');
  final commands=<UpdateRoleProfileCommand>[];var addressSaves=0;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:BusinessAddressEditor(
    load:()async=>record,onLoaded:(_){},save:(command)async{addressSaves++;return record;},
    readProfile:()=>profile,saveProfile:(command)async{commands.add(command);if(commands.length==1)throw StateError('timeout');},
  )))));
  await tester.pumpAndSettle();
  expect(find.text('Save contact details'),findsNothing);expect(find.text('Discard changes'),findsNothing);
  await tester.ensureVisible(find.byKey(const Key('businessServiceRadius')));
  await tester.enterText(find.byKey(const Key('businessServiceRadius')),'50');
  await tester.ensureVisible(find.text('Save changes'));await tester.tap(find.text('Save changes'));await tester.pumpAndSettle();
  expect(commands.single.serviceRadiusMiles.valueOrNull,50);
  await tester.ensureVisible(find.text('Retry contact save'));await tester.tap(find.text('Retry contact save'));await tester.pumpAndSettle();
  expect(commands.length,2);expect(identical(commands[0],commands[1]),isTrue);expect(addressSaves,2);
  expect(find.text('Location settings saved.'),findsOneWidget);
 });
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
  await tester.ensureVisible(find.text('Save changes'));
  await tester.tap(find.text('Save changes'));await tester.pumpAndSettle();
  expect(record.contact.addressLine1,'New business street');
  await tester.pumpWidget(const SizedBox());await tester.pumpWidget(page());await tester.pumpAndSettle();
  expect(find.text('New business street'),findsOneWidget);
 });
}
