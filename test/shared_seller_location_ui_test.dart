import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/patch.dart';
import 'package:hocalist/features/account/profile_details_editor.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'phase2/account/account_test_fakes.dart';
import 'test_fonts.dart';

void main() {
 setUpAll(loadHocalistTestFonts);
 testWidgets('verification radius editor preserves the shared business area', (tester) async {
  final profile=roleProfile(role:HocalistRole.seller,revision:7,areaLabel:'Chicago');
  UpdateRoleProfileCommand? saved;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProfileDetailsEditor(
   serviceAreaOnly:true,radiusOnly:true,readCurrent:()=>profile,onSave:(v) async {saved=v;},
  ))));
  expect(find.byKey(const Key('profileDetailsField0')),findsNothing);
  await tester.enterText(find.byKey(const Key('profileDetailsField3')),'50');
  await tester.tap(find.text('Save service area'));await tester.pumpAndSettle();
  expect(saved!.areaLabel,isA<PatchKeep<String>>());
  expect(saved!.serviceRadiusMiles.valueOrNull,50);
 });
 testWidgets('profile displays shared area without writing a competing area', (tester) async {
  final profile=roleProfile(role:HocalistRole.seller,revision:7,areaLabel:'Chicago');
  UpdateRoleProfileCommand? saved;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ProfileDetailsEditor(
   areaReadOnly:true,readCurrent:()=>profile,onSave:(v) async {saved=v;},
  )))));
  final field=tester.widget<TextField>(find.byKey(const Key('profileDetailsField0')));
  expect(field.readOnly,true);expect(field.controller!.text,'Chicago');
  await tester.enterText(find.byKey(const Key('profileDetailsField1')),'Updated business description');
  await tester.ensureVisible(find.text('Save profile details'));await tester.tap(find.text('Save profile details'));await tester.pumpAndSettle();
  expect(saved!.areaLabel,isA<PatchKeep<String>>());
 });
}

