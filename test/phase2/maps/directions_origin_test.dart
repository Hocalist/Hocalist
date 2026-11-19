import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/places_contract.dart';
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/features/approved/meeting_directions_page.dart';

class FakePlaces implements PlacesRepository {
  final queries = <String>[];
  PlaceDetails place(String address) => PlaceDetails(placeId:'test',address:address,latitude:41,longitude:-87);
  @override
  Future<List<PlaceSuggestion>> search({required String input,required PlacesSession session}) async {
    queries.add(input);
    return [PlaceSuggestion(placeId:'test',label:'Test Street, Chicago')];
  }
  @override
  Future<PlaceDetails> resolve({required String placeId,required PlacesSession session}) async => place('123 Test Street, Chicago');
  @override
  Future<PlaceDetails> resolveCoordinates({required double latitude,required double longitude}) async => place('Current starting address');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('location timeout unlocks input and ignores a late reading', (t) async {
    final reading = Completer<LocationReading>();
    t.view.physicalSize = const Size(390, 1200);
t.view.devicePixelRatio = 1;
addTearDown(t.view.resetPhysicalSize);
addTearDown(t.view.resetDevicePixelRatio);
await t.pumpWidget(MaterialApp(home:MeetingDirectionsPage(
      meetingId:'test', destination:'Confirmed destination address', places:FakePlaces(),
      locationReader:() => reading.future,
    )));
    await t.tap(find.text('Use my current location'));
    await t.pump();
    expect(find.text('Getting your location…'), findsOneWidget);
    await t.pump(const Duration(seconds:16));
    await t.pumpAndSettle();
    expect(find.textContaining('took too long'), findsOneWidget);
    await t.enterText(find.byType(TextField),'Manual address');
    reading.complete(const LocationReading(latitude:41,longitude:-87));
    await t.pump(const Duration(milliseconds:400));
    await t.pumpAndSettle();
    expect(find.text('Manual address'),findsOneWidget);
    expect(find.text('Current starting address'),findsNothing);
  });
  testWidgets('cancelling location keeps manual entry and ignores late results', (t) async {
    final reading = Completer<LocationReading>();
    t.view.physicalSize = const Size(390, 1200);
t.view.devicePixelRatio = 1;
addTearDown(t.view.resetPhysicalSize);
addTearDown(t.view.resetDevicePixelRatio);
await t.pumpWidget(MaterialApp(home:MeetingDirectionsPage(
      meetingId:'test', destination:'Confirmed destination address', places:FakePlaces(),
      locationReader:() => reading.future,
    )));
    await t.tap(find.text('Use my current location'));
    await t.pump();
    await t.tap(find.text('Cancel location lookup'));
    await t.pump();
    await t.enterText(find.byType(TextField),'Manual address');
    reading.complete(const LocationReading(latitude:41,longitude:-87));
    await t.pump(const Duration(milliseconds:400));
    await t.pumpAndSettle();
    expect(find.text('Manual address'),findsOneWidget);
    expect(find.text('Current starting address'),findsNothing);
  });
  testWidgets('suggestion selection fills origin while retaining destination', (t) async {
    final places=FakePlaces();
    t.view.physicalSize = const Size(390, 1200);
t.view.devicePixelRatio = 1;
addTearDown(t.view.resetPhysicalSize);
addTearDown(t.view.resetDevicePixelRatio);
await t.pumpWidget(MaterialApp(home:MeetingDirectionsPage(meetingId:'test',destination:'Confirmed destination address',places:places)));
    await t.enterText(find.byType(TextField),'Test');
    await t.pump(const Duration(milliseconds:400));
    await t.pumpAndSettle();
    expect(places.queries,['Test']);
    await t.tap(find.text('Test Street, Chicago'));
    await t.pumpAndSettle();
    expect(find.text('123 Test Street, Chicago'),findsOneWidget);
    expect(find.text('Confirmed destination address'),findsOneWidget);
    expect(find.byType(ListTile),findsNothing);
  });
  for(final denied in [false,true]) {
    testWidgets('location is requested only on tap, denied=$denied',(t) async {
      var calls=0;
      t.view.physicalSize = const Size(390, 1200);
t.view.devicePixelRatio = 1;
addTearDown(t.view.resetPhysicalSize);
addTearDown(t.view.resetDevicePixelRatio);
await t.pumpWidget(MaterialApp(home:MeetingDirectionsPage(meetingId:'test',destination:'Confirmed destination address',places:FakePlaces(),locationReader:() async {
        calls++;
        if(denied) throw const LocationFailure(LocationFailureCode.denied);
        return const LocationReading(latitude:41,longitude:-87);
      })));
      expect(calls,0);
      await t.tap(find.text('Use my current location'));
      await t.pumpAndSettle();
      expect(calls,1);
      if(denied) {
        expect(find.textContaining('permission was denied'),findsOneWidget);
        await t.enterText(find.byType(TextField),'Manual');
        await t.pump(const Duration(milliseconds:400));
        await t.pumpAndSettle();
        expect(find.text('Manual'),findsOneWidget);
      } else {
        expect(find.text('Current starting address'),findsOneWidget);
      }
    });
  }
}
