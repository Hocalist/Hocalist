// Place capture tests: search, confirmation, current location, manual fallback
// and provider failure states. Fakes only; the map surface is stubbed.
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/places_contract.dart';
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/data/phase2/maps/places_transport.dart';
import 'package:hocalist/features/approved/hocalist_map_surface.dart';
import 'package:hocalist/features/approved/place_capture_sheet.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';

import 'test_fonts.dart';

class _StubTransport implements PlacesTransport, CoordinatePlacesTransport {
  _StubTransport({this.fail = false, this.ambiguous = false});

  final bool fail;
  final bool ambiguous;

  @override
  Future<PlacesTransportResult> coordinates({required double latitude, required double longitude, required String sessionToken}) async {
    if (fail) throw const PlacesFailure(PlacesFailureCode.unavailable);
    return PlacesTransportResult({
      'placeId':'place-1', 'address':'Moved pin address',
      'latitude':latitude,'longitude':longitude,'timezoneId':'America/New_York',
      'postalAddress':{'state':'NY','country':'US'},'attributions':<Object?>[],
    });
  }

  @override
  Future<PlacesTransportResult> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    if (fail) throw const PlacesFailure(PlacesFailureCode.unavailable);
    if (ambiguous) {
      return const PlacesTransportResult(<String, Object?>{
        'suggestions': [
          {'placeId': 'place-1', 'label': 'First matching address'},
          {'placeId': 'place-2', 'label': 'Second matching address'},
        ],
      });
    }
    return const PlacesTransportResult(<String, Object?>{
      'suggestions': [
        <String, Object?>{'placeId': 'place-1', 'label': 'Cross County Mall'},
      ],
    });
  }

  @override
  Future<PlacesTransportResult> details({
    required String placeId,
    required String sessionToken,
  }) async {
    if (fail) throw const PlacesFailure(PlacesFailureCode.rateLimited);
    return const PlacesTransportResult(<String, Object?>{
      'placeId': 'place-1',
      'address': '123 Synthetic Ave',
      'latitude': 40.9,
      'longitude': -73.8,
      'timezoneId': 'America/New_York',
      'attributions': [
        <String, Object?>{
          'provider': 'Google Maps',
          'uri': 'https://maps.google.com',
        },
      ],
    });
  }
}

class _DelayedPinTransport extends _StubTransport {
  final requests = <Completer<PlacesTransportResult>>[];
  final positions = <(double, double)>[];

  @override
  Future<PlacesTransportResult> coordinates({required double latitude, required double longitude, required String sessionToken}) {
    positions.add((latitude, longitude));
    final request = Completer<PlacesTransportResult>();
    requests.add(request);
    return request.future;
  }

  void complete(int index, String address) {
    final (latitude, longitude) = positions[index];
    requests[index].complete(PlacesTransportResult({
      'placeId':'pin-$index','address':address,'latitude':latitude,'longitude':longitude,
      'timezoneId':'America/New_York','attributions':<Object?>[],
    }));
  }
}

class _NoMatchesTransport extends _StubTransport implements AddressPlacesTransport {
  final resolvedAddresses = <String>[];
  @override
  Future<PlacesTransportResult> autocomplete({required String input,required String sessionToken}) async =>
    const PlacesTransportResult({'suggestions':<Object?>[]});
  @override
  Future<PlacesTransportResult> address({required String address,required String sessionToken}) async {
    resolvedAddresses.add(address);
    return const PlacesTransportResult({
      'placeId':'complete-address','address':'1 Synthetic Street, Test City, NY, US',
      'latitude':40.7,'longitude':-74.0,'timezoneId':'America/New_York',
      'postalAddress':{'line1':'1 Synthetic Street','city':'Test City','state':'NY','country':'US'},
      'attributions':<Object?>[],
    });
  }
}

class _RecoveringTransport implements PlacesTransport {
  _RecoveringTransport({
    this.autocompleteFailures = 0,
    this.detailsFailures = 0,
  });

  int autocompleteFailures;
  int detailsFailures;
  final List<String> autocompleteTokens = <String>[];
  final List<String> detailsTokens = <String>[];

  @override
  Future<PlacesTransportResult> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    autocompleteTokens.add(sessionToken);
    if (autocompleteFailures > 0) {
      autocompleteFailures--;
      throw const PlacesFailure(PlacesFailureCode.sessionExpired);
    }
    return const PlacesTransportResult(<String, Object?>{
      'suggestions': [
        <String, Object?>{'placeId': 'place-1', 'label': 'Cross County Mall'},
      ],
    });
  }

  @override
  Future<PlacesTransportResult> details({
    required String placeId,
    required String sessionToken,
  }) async {
    detailsTokens.add(sessionToken);
    if (detailsFailures > 0) {
      detailsFailures--;
      throw const PlacesFailure(PlacesFailureCode.suggestionRequired);
    }
    return const PlacesTransportResult(<String, Object?>{
      'placeId': 'place-1',
      'address': '123 Synthetic Ave',
      'latitude': 40.9,
      'longitude': -73.8,
      'attributions': [
        <String, Object?>{
          'provider': 'Google Maps',
          'uri': 'https://maps.google.com',
        },
      ],
    });
  }
}

Widget _stubMapBuilder(
  BuildContext context, {
  required double latitude,
  required double longitude,
  required ValueChanged<HocalistCoordinates> onMoved,
}) {
  return Column(
    children: [
      const Text('stub map'),
      Text(
        '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}',
        key: const Key('stubCoordinates'),
      ),
      TextButton(
        key: const Key('stubMovePin'),
        onPressed: () =>
            onMoved(HocalistCoordinates(latitude + 0.01, longitude + 0.01)),
        child: const Text('move'),
      ),
    ],
  );
}

class _Capture {
  _Capture(this.results);

  final List<PlaceCaptureResult?> results;
}

Future<_Capture> _openSheet(
  WidgetTester tester,
  PlaceCaptureSheet sheet,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final results = <PlaceCaptureResult?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('openSheet'),
              onPressed: () async {
                final result = await showPlaceCaptureSheet(
                  context: context,
                  requireTimezone: sheet.requireTimezone,
                  places: sheet.places,
                  mapBuilder: sheet.mapBuilder,
                  locationReader: sheet.locationReader,
                  initial: sheet.initial,
                  loadAreas: sheet.loadAreas,
                );
                results.add(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openSheet')));
  await tester.pumpAndSettle();
  return _Capture(results);
}

void main() {
  testWidgets('one address field expands missing details without a manual-entry switch', (tester) async {
    final transport=_NoMatchesTransport();
    final capture=await _openSheet(tester,PlaceCaptureSheet(requireTimezone:true,places:PlacesRepository(transport:transport)));
    expect(find.text('Enter manually'),findsNothing);
    expect(find.byKey(const Key('hocalistPlaceManualToggle')),findsNothing);
    expect(find.byType(TextField),findsOneWidget);
    await tester.enterText(find.byKey(const Key('hocalistPlaceSearchField')),'1 Synthetic Street');
    await tester.pump(const Duration(milliseconds:450)); await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceAddressField')),findsNothing);
    await tester.enterText(find.byKey(const Key('hocalistPlaceCityField')),'Test City');
    await tester.enterText(find.byKey(const Key('hocalistPlaceRegionField')),'NY');
    await tester.enterText(find.byKey(const Key('hocalistPlaceCountryField')),'US');
    await tester.ensureVisible(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm'))); await tester.pumpAndSettle();
    expect(transport.resolvedAddresses.single,'1 Synthetic Street, Test City, NY, US');
    expect(capture.results.single?.timezoneId,'America/New_York');
    expect(capture.results.single?.postalAddress?.city,'Test City');
    expect(capture.results.single?.latitude,40.7);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('pin lookup progress fits $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transport = _DelayedPinTransport();
        await tester.pumpWidget(MaterialApp(
          theme:ThemeData(fontFamily:'Nunito'),
          home:MediaQuery(data:MediaQueryData(size:Size(width,900),textScaler:TextScaler.linear(scale)),
            child:Scaffold(body:RepaintBoundary(key:const Key('pin-progress-capture'),
              child:PlaceCaptureSheet(requireTimezone:true,places:PlacesRepository(transport:transport),mapBuilder:_stubMapBuilder,
                initial:const PlaceCaptureResult(label:'Meeting place',address:'Synthetic Street',latitude:40,longitude:-74,
                  timezoneId:'America/New_York',source:PlaceCaptureSource.search)),
            ))),
        ));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('stubMovePin')));
        await tester.tap(find.byKey(const Key('stubMovePin')));
        await tester.pump(const Duration(milliseconds:450));
        expect(find.text('Finding address and timezone…'),findsOneWidget);
        expect(tester.takeException(),isNull);
        if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') && scale == 1.0 && (width == 320 || width == 390)) {
          final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('pin-progress-capture')));
          await tester.runAsync(()async{
            final image=await boundary.toImage();
            final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('.codex-local/pin-progress-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        transport.complete(0,'Resolved synthetic address');
        await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
      });
    }
  }

  testWidgets('editing an address cannot retain coordinates from the previous address', (tester) async {
    final capture=await _openSheet(tester,const PlaceCaptureSheet(
      initial:PlaceCaptureResult(label:'Original',address:'Original street',latitude:40,longitude:-74,
        timezoneId:'America/New_York',placeId:'old',source:PlaceCaptureSource.manual),
    ));
    await tester.enterText(find.byKey(const Key('hocalistPlaceSearchField')),'Different street');
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.address,'Different street');
    expect(capture.results.single?.latitude,isNull);
    expect(capture.results.single?.timezoneId,isNull);
    expect(capture.results.single?.placeId,isNull);
  });

  testWidgets('late pin responses cannot replace the newest address', (tester) async {
    final transport = _DelayedPinTransport();
    final capture = await _openSheet(tester, PlaceCaptureSheet(
      requireTimezone: true, places: PlacesRepository(transport: transport),
      mapBuilder: _stubMapBuilder,
      initial: const PlaceCaptureResult(label:'Original',address:'Original street',
        latitude:40,longitude:-74,timezoneId:'America/New_York',source:PlaceCaptureSource.search),
    ));
    await tester.tap(find.byKey(const Key('stubMovePin')));
    await tester.pump(const Duration(milliseconds:450));
    expect(transport.requests.length,1);
    expect(tester.widget<BuyerPrimaryButton>(find.byKey(const Key('hocalistPlaceConfirm'))).onPressed,isNull);
    await tester.tap(find.byKey(const Key('stubMovePin')));
    await tester.pump(const Duration(milliseconds:450));
    expect(transport.requests.length,2);
    transport.complete(1,'Newest street');
    await tester.pumpAndSettle();
    transport.complete(0,'Stale street');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.address,'Newest street');
    expect(capture.results.single?.latitude,closeTo(40.02,0.00001));
  });

  testWidgets('failed pin lookup never confirms an old address or timezone', (tester) async {
    final capture = await _openSheet(tester, PlaceCaptureSheet(
      requireTimezone:true,places:PlacesRepository(transport:_StubTransport(fail:true)),mapBuilder:_stubMapBuilder,
      initial:const PlaceCaptureResult(label:'Original',address:'Original street',latitude:40,longitude:-74,
        timezoneId:'America/New_York',source:PlaceCaptureSource.search),
    ));
    await tester.tap(find.byKey(const Key('stubMovePin')));
    await tester.pump(const Duration(milliseconds:450));
    await tester.pumpAndSettle();
    expect(find.textContaining('We could not find the address for this pin'),findsOneWidget);
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results,isEmpty);
  });

  testWidgets('device location resolves address and timezone together', (tester) async {
    final capture = await _openSheet(tester,PlaceCaptureSheet(
      requireTimezone:true,places:PlacesRepository(transport:_StubTransport()),mapBuilder:_stubMapBuilder,
      locationReader:()async=>const LocationReading(latitude:40,longitude:-74),
    ));
    await tester.tap(find.byKey(const Key('hocalistPlaceUseLocation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.address,'Moved pin address');
    expect(capture.results.single?.timezoneId,'America/New_York');
  });

  testWidgets('configured areas start a search without confirming an address', (
    tester,
  ) async {
    await _openSheet(
      tester,
      PlaceCaptureSheet(
        places: PlacesRepository(transport: _StubTransport()),
        loadAreas: () async => ['TEST configured area'],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST configured area'), findsOneWidget);
    await tester.tap(find.text('TEST configured area'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Cross County Mall'), findsWidgets);
    expect(find.text('123 Synthetic Ave'), findsNothing);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('place sheet fits $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Nunito'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: Key('place-design-capture'),
                  child: PlaceCaptureSheet(places:PlacesRepository(transport:_NoMatchesTransport())),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('hocalistPlaceSearchField')),'1 Synthetic Street');
        await tester.pump(const Duration(milliseconds:450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('hocalistPlaceConfirm')), findsOneWidget);
        if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') &&
            width == 390 &&
            scale == 1.0) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('place-design-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '.codex-local/place-design-current.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
  setUpAll(() async {
    await loadHocalistTestFonts();
    if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE')) {
      final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  testWidgets('typed meeting address resolves before returning its timezone', (tester) async {
    final capture = await _openSheet(tester, PlaceCaptureSheet(
      requireTimezone: true,
      places: PlacesRepository(transport: _StubTransport()),
      initial: const PlaceCaptureResult(label: 'Business', address: '123 Synthetic Ave', source: PlaceCaptureSource.manual),
    ));
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.timezoneId, 'America/New_York');
    expect(capture.results.single?.address, '123 Synthetic Ave');
  });

  testWidgets('ambiguous typed addresses still require a selection', (tester) async {
    final capture = await _openSheet(tester, PlaceCaptureSheet(
      requireTimezone: true,
      places: PlacesRepository(transport: _StubTransport(ambiguous: true)),
      initial: const PlaceCaptureResult(label: 'Business', address: 'Synthetic Ave', source: PlaceCaptureSource.manual),
    ));
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results, isEmpty);
    expect(find.text('First matching address'), findsOneWidget);
    expect(find.text('Second matching address'), findsOneWidget);
  });

  testWidgets('editing a saved request starts at its saved address and pin', (
    tester,
  ) async {
    final capture = await _openSheet(
      tester,
      const PlaceCaptureSheet(
        initial: PlaceCaptureResult(
          label: 'Saved request location',
          address: '123 Synthetic Ave',
          latitude: 40.9,
          longitude: -73.8,
          source: PlaceCaptureSource.manual,
        ),
        mapBuilder: _stubMapBuilder,
      ),
    );
    expect(find.textContaining('123 Synthetic Ave'), findsWidgets);
    expect(find.text('stub map'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.latitude, 40.9);
    expect(capture.results.single?.longitude, -73.8);
    expect(capture.results.single?.address, '123 Synthetic Ave');
  });

  testWidgets('manual entry works without a Places repository', (tester) async {
    final capture = await _openSheet(tester, const PlaceCaptureSheet());
    expect(find.byKey(const Key('hocalistPlaceCaptureSheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceLabelField')),
      'Central Library',
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      '1 Library Way',
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    final result = capture.results.single;
    expect(result?.source, PlaceCaptureSource.manual);
    expect(result?.label, 'Central Library');
    expect(result?.address, '1 Library Way');
    expect(result?.placeId, isNull);
  });

  testWidgets('search resolves a place with coordinates and attribution', (
    tester,
  ) async {
    final capture = await _openSheet(
      tester,
      PlaceCaptureSheet(
        initial: const PlaceCaptureResult(label: 'Old manual place', address: 'Old synthetic address', source: PlaceCaptureSource.manual),
        places: PlacesRepository(transport: _StubTransport()),
        mapBuilder: _stubMapBuilder,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      'Cross County',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Cross County Mall'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('hocalistPlaceSuggestion-place-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceConfirmed')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hocalistPlaceSearchField')))
          .controller!
          .text,
      '123 Synthetic Ave',
    );
    expect(find.text('stub map'), findsOneWidget);
    expect(find.byKey(const Key('hocalistPlaceAddressField')), findsNothing);
    expect(find.text('Google Maps'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stubMovePin')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('40.91,-73.79'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    final result = capture.results.single;
    expect(result?.source, PlaceCaptureSource.search);
    expect(result?.placeId, 'place-1');
    expect(result?.latitude, closeTo(40.91, 0.001));
    expect(result?.address, 'Moved pin address');
    expect(result?.timezoneId, 'America/New_York');
    expect(result?.postalAddress?.state, 'NY');
  });

  testWidgets('a provider failure keeps manual entry available', (
    tester,
  ) async {
    final capture = await _openSheet(
      tester,
      PlaceCaptureSheet(
        places: PlacesRepository(transport: _StubTransport(fail: true)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      'Cross County',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceSearchError')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceLabelField')),
      'Manual place',
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.source, PlaceCaptureSource.manual);
  });

  testWidgets('searched address stays confirmable without a Maps SDK', (
    tester,
  ) async {
    final capture = await _openSheet(
      tester,
      PlaceCaptureSheet(places: PlacesRepository(transport: _StubTransport())),
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      'Cross County',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('hocalistPlaceSuggestion-place-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistMapPlaceholder')), findsOneWidget);
    expect(find.textContaining('Move the pin'), findsNothing);
    expect(
      find.textContaining('Pin movement needs the map preview'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.placeId, 'place-1');
    expect(capture.results.single?.latitude, 40.9);
  });

  testWidgets('current location fills coordinates', (tester) async {
    await _openSheet(
      tester,
      PlaceCaptureSheet(
        locationReader: () async =>
            const LocationReading(latitude: 40.7, longitude: -74.0),
        mapBuilder: _stubMapBuilder,
      ),
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceUseLocation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceConfirmed')), findsOneWidget);
    expect(find.text('40.70,-74.00'), findsOneWidget);
  });

  testWidgets('denied location is explained and manual entry stays', (
    tester,
  ) async {
    await _openSheet(
      tester,
      PlaceCaptureSheet(
        locationReader: () async =>
            throw const LocationFailure(LocationFailureCode.denied),
      ),
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceUseLocation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceLocationError')), findsOneWidget);
    expect(find.textContaining('permission'), findsOneWidget);
    expect(find.byKey(const Key('hocalistPlaceLabelField')), findsOneWidget);
  });

  testWidgets('permanently denied location points to settings', (tester) async {
    await _openSheet(
      tester,
      PlaceCaptureSheet(
        locationReader: () async =>
            throw const LocationFailure(LocationFailureCode.deniedForever),
      ),
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceUseLocation')));
    await tester.pumpAndSettle();
    expect(find.textContaining('system settings'), findsOneWidget);
  });

  testWidgets('the map placeholder is used without a map builder', (
    tester,
  ) async {
    await _openSheet(
      tester,
      PlaceCaptureSheet(
        locationReader: () async =>
            const LocationReading(latitude: 40.7, longitude: -74.0),
      ),
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceUseLocation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistMapPlaceholder')), findsOneWidget);
  });

  testWidgets('an expired search session restarts once and succeeds', (
    tester,
  ) async {
    final transport = _RecoveringTransport(autocompleteFailures: 1);
    await _openSheet(
      tester,
      PlaceCaptureSheet(places: PlacesRepository(transport: transport)),
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      'Cross County',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Cross County Mall'), findsWidgets);
    expect(transport.autocompleteTokens, hasLength(2));
    expect(
      transport.autocompleteTokens.first,
      isNot(transport.autocompleteTokens.last),
      reason: 'the retry must use a fresh session',
    );
  });

  testWidgets('a suggestion-required details call re-runs the search first', (
    tester,
  ) async {
    final transport = _RecoveringTransport(detailsFailures: 1);
    final capture = await _openSheet(
      tester,
      PlaceCaptureSheet(
        places: PlacesRepository(transport: transport),
        mapBuilder: _stubMapBuilder,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      'Cross County',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('hocalistPlaceSuggestion-place-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceConfirmed')), findsOneWidget);
    expect(transport.detailsTokens, hasLength(2));
    expect(
      transport.detailsTokens.last,
      transport.autocompleteTokens.last,
      reason: 'the resolve retry must reuse the session that just re-searched',
    );
    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    expect(capture.results.single?.placeId, 'place-1');
  });

  testWidgets('a persistent suggestion failure keeps manual entry available', (
    tester,
  ) async {
    final transport = _RecoveringTransport(detailsFailures: 2);
    await _openSheet(
      tester,
      PlaceCaptureSheet(places: PlacesRepository(transport: transport)),
    );
    await tester.enterText(
      find.byKey(const Key('hocalistPlaceSearchField')),
      'Cross County',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('hocalistPlaceSuggestion-place-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hocalistPlaceSearchError')), findsOneWidget);
    expect(find.byKey(const Key('hocalistPlaceLabelField')), findsOneWidget);
  });
}
