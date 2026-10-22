// Place capture tests: search, confirmation, current location, manual fallback
// and provider failure states. Fakes only; the map surface is stubbed.
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/places_contract.dart';
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/data/phase2/maps/places_transport.dart';
import 'package:hocalist/features/approved/hocalist_map_surface.dart';
import 'package:hocalist/features/approved/place_capture_sheet.dart';

import 'test_fonts.dart';

class _StubTransport implements PlacesTransport {
  _StubTransport({this.fail = false});

  final bool fail;

  @override
  Future<PlacesTransportResult> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    if (fail) throw const PlacesFailure(PlacesFailureCode.unavailable);
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
      'attributions': [
        <String, Object?>{
          'provider': 'Google Maps',
          'uri': 'https://maps.google.com',
        },
      ],
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
              child: const Scaffold(
                body: RepaintBoundary(
                  key: Key('place-design-capture'),
                  child: PlaceCaptureSheet(),
                ),
              ),
            ),
          ),
        );
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
  setUpAll(loadHocalistTestFonts);

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
      find.byKey(const Key('hocalistPlaceAddressField')),
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
      'Cross County Mall',
    );
    expect(find.text('stub map'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stubMovePin')));
    await tester.pumpAndSettle();
    expect(find.text('40.91,-73.79'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hocalistPlaceConfirm')));
    await tester.pumpAndSettle();
    final result = capture.results.single;
    expect(result?.source, PlaceCaptureSource.search);
    expect(result?.placeId, 'place-1');
    expect(result?.latitude, closeTo(40.91, 0.001));
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
