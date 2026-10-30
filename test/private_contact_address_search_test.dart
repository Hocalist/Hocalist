import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/places_transport.dart';
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/features/account/private_contact_editor.dart';
import 'test_fonts.dart';

class _Places implements PlacesTransport {
  Completer<PlacesTransportResult>? pending;
  bool failDetails = false;
  @override
  Future<PlacesTransportResult> autocomplete({required String input,required String sessionToken}) async =>
    const PlacesTransportResult({'suggestions':[{'placeId':'test-place','label':'TEST Street, Chicago, IL, US'}]});
  @override
  Future<PlacesTransportResult> details({required String placeId,required String sessionToken}) async {
    if (failDetails) throw StateError('Synthetic lookup failure');
    return pending?.future ?? resolved;
  }
  static const resolved=PlacesTransportResult({
    'placeId':'test-place','address':'1 TEST Street, Chicago, IL 60605, US',
    'latitude':41.8,'longitude':-87.6,'timezoneId':'America/Chicago',
    'postalAddress':{'line1':'1 TEST Street','city':'Chicago','state':'IL','postalCode':'60605','country':'US'},
    'attributions':<Object?>[],
  });
}
PrivateContactRecord get _record=>PrivateContactRecord(
  userId:'test',contact:AccountContact(phone:'unchanged',addressLine1:'Saved street',countryCode:'US'),
  stamp:RecordStamp(revision:1,createdAt:DateTime.utc(2026),updatedAt:DateTime.utc(2026)),
);
String field(WidgetTester tester,int index)=>tester.widget<TextField>(find.byKey(Key('privateContact$index'))).controller!.text;
Future<void> search(WidgetTester tester, {String query = 'TEST Street'}) async {
  await tester.ensureVisible(find.byKey(const Key('privateContact1')));
  await tester.enterText(find.byKey(const Key('privateContact1')),query);
  await tester.pump(const Duration(milliseconds:400)); await tester.pumpAndSettle();
}
void main(){
  testWidgets('failed details remove expired suggestions and a new search recovers', (tester) async {
    final provider = _Places()..failDetails = true;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:PrivateContactEditor(
      readCurrent:()=>_record, places:PlacesRepository(transport:provider), onSave:(_)async{},
    )))));
    await search(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('contactAddress-test-place')));
    await tester.tap(find.byKey(const ValueKey('contactAddress-test-place')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contactAddress-test-place')), findsNothing);
    expect(find.textContaining('This address could not be loaded'), findsOneWidget);
    provider.failDetails = false;
    await search(tester, query: 'TEST Street Chicago');
    await tester.ensureVisible(find.byKey(const ValueKey('contactAddress-test-place')));
    await tester.tap(find.byKey(const ValueKey('contactAddress-test-place')));
    await tester.pumpAndSettle();
    expect(field(tester, 1), '1 TEST Street');
    expect(find.textContaining('This address could not be loaded'), findsNothing);
  });
  setUpAll(() async {
    await loadHocalistTestFonts();
    if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE')) {
      final loader=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await loader.load();
    }
  });
  for(final width in [320.0,360.0,390.0,430.0]) {
    for(final scale in [1.0,1.15,1.3,1.6]) {
      testWidgets('street search fills business fields without saving $width/$scale',(tester) async {
        tester.view.devicePixelRatio=1; tester.view.physicalSize=Size(width,900);
        tester.platformDispatcher.textScaleFactorTestValue=scale;
        addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var saves=0; String? timezone;
        await tester.pumpWidget(MaterialApp(theme:ThemeData(fontFamily:'Nunito'),home:Scaffold(body:RepaintBoundary(key:const Key('contact-address-capture'),child:SingleChildScrollView(child:PrivateContactEditor(
          seller:true,places:PlacesRepository(transport:_Places()),readCurrent:()=>_record,
          onResolvedAddress:(place)=>timezone=place.timezoneId,onSave:(_)async{saves++;},
        ))))));
        await search(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('contactAddress-test-place')));
        if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') && scale==1.0 && (width==320 || width==390)) {
          await tester.pumpAndSettle();
          final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('contact-address-capture')));
          await tester.runAsync(()async{
            final image=await boundary.toImage();
            final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('.codex-local/contact-address-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const ValueKey('contactAddress-test-place'))); await tester.pumpAndSettle();
        expect(field(tester,0),'unchanged'); expect(field(tester,1),'1 TEST Street');
        expect(field(tester,3),'Chicago'); expect(field(tester,4),'IL');
        expect(field(tester,5),'60605'); expect(field(tester,6),'US');
        expect(timezone,'America/Chicago'); expect(saves,0); expect(tester.takeException(),isNull);
      });
    }
  }
  testWidgets('discard closes the address popup without saving or accepting a late result',(tester) async {
    final provider=_Places()..pending=Completer<PlacesTransportResult>();
    var saves=0; var resolved=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(
      onPressed:()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheetContext)=>SafeArea(
        child:SingleChildScrollView(child:PrivateContactEditor(seller:true,
          readCurrent:()=>_record,places:PlacesRepository(transport:provider),onSave:(_)async{saves++;},
          onResolvedAddress:(_)=>resolved++,onDiscard:()=>Navigator.of(sheetContext).pop(),
        )),
      )),child:const Text('Business address'),
    )))));
    await tester.tap(find.text('Business address')); await tester.pumpAndSettle();
    await search(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('contactAddress-test-place')));
    await tester.tap(find.byKey(const ValueKey('contactAddress-test-place'))); await tester.pump();
    await tester.ensureVisible(find.text('Discard changes')); await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle(); expect(find.byType(PrivateContactEditor),findsNothing);
    provider.pending!.complete(_Places.resolved); await tester.pumpAndSettle();
    expect(saves,0); expect(resolved,0); expect(tester.takeException(),isNull);
  });
  testWidgets('page editor discard retains its page and reloads saved fields',(tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:PrivateContactEditor(
      readCurrent:()=>_record,onSave:(_)async{},
    )))));
    await tester.enterText(find.byKey(const Key('privateContact1')),'Unsaved street');
    await tester.ensureVisible(find.text('Discard changes')); await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivateContactEditor),findsOneWidget);expect(field(tester,1),'Saved street');
  });
}
