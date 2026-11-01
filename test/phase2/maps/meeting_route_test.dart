import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/route_repository.dart';
import 'package:hocalist/features/approved/meeting_directions_page.dart';

void main() {
  testWidgets('route panel expands with mouse dragging on web', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MeetingDirectionsPage(meetingId: 'meeting', destination: 'Test meeting place')));
    final panel = find.byKey(const Key('meeting-directions-scroll'));
    final before = tester.getTopLeft(panel).dy;
    final gesture = await tester.startGesture(tester.getCenter(find.text('Meet here')), kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, -300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(panel).dy, lessThan(before));
    expect(tester.takeException(), isNull);
  });
  test('decodes route geometry and rejects malformed/cross-meeting data', () {
    final data = {
      'meetingId': 'meeting',
      'distanceMeters': 1000,
      'duration': '123s',
      'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      'steps': ['Head north'],
    };
    final result = decodeMeetingRoute(data, 'meeting');
    expect(result.points.length, 3);
    expect(result.points.first.latitude, 38.5);
    expect(result.points.first.longitude, -120.2);
    expect(result.points[1].longitude, -120.95);
    expect(result.seconds, 123);
    expect(
      () => decodeMeetingRoute(data, 'other'),
      throwsA(isA<RouteFailure>()),
    );
    expect(
      () => decodeMeetingRoute({...data, 'polyline': '_'}, 'meeting'),
      throwsA(isA<RouteFailure>()),
    );
  });
  testWidgets(
    'in-app directions validates, disables duplicate submits, renders route and retry',
    (tester) async {
      final pending = Completer<MeetingRoute>();
      var calls = 0;
      tester.view.physicalSize = const Size(390, 1200);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.resetPhysicalSize);
addTearDown(tester.view.resetDevicePixelRatio);
await tester.pumpWidget(
        MaterialApp(
          home: MeetingDirectionsPage(
            meetingId: 'meeting',
            destination: 'Public TEST meeting address',
            mapBuilder: (_) => const Text('Route map'),
            load: (id, origin, mode) {
              calls++;
              expect(id, 'meeting');
              expect(mode, 'DRIVE');
              return pending.future;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Show directions'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show directions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show directions'));
      await tester.pump();
      expect(
        find.text('Enter a starting address, including the city.'),
        findsOneWidget,
      );
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), 'Public TEST origin');
      await tester.ensureVisible(find.text('Show directions'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show directions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show directions'));
      await tester.pump();
      expect(find.text('Finding route…'), findsOneWidget);
      expect(calls, 1);
      pending.complete(
        MeetingRoute(
          distanceMeters: 1000,
          seconds: 120,
          points: const [RoutePoint(41, -87), RoutePoint(41.1, -87.1)],
          steps: const ['Turn right'],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('meeting-map-panel'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('meeting-directions-scroll'))).dy),
      );
      final list = find
          .descendant(
            of: find.byKey(const Key('meeting-directions-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;

      expect(find.text('Route map'), findsOneWidget);
      expect(find.text('Turn right'), findsNothing);
      await tester.ensureVisible(find.text('Step-by-step directions'));
      await tester.tap(find.text('Step-by-step directions'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Turn right'),
        200,
        scrollable: list,
      );
      expect(find.text('Turn right'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('route failures retain input and offer retry inside app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.resetPhysicalSize);
addTearDown(tester.view.resetDevicePixelRatio);
await tester.pumpWidget(
      MaterialApp(
        home: MeetingDirectionsPage(
          meetingId: 'meeting',
          destination: 'Public TEST place',
          load: (_, _, _) async => throw const RouteFailure('no_route'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Public TEST origin');
    await tester.ensureVisible(find.text('Show directions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show directions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No route was found'), findsOneWidget);
    expect(find.text('Public TEST origin'), findsOneWidget);
    expect(find.text('Show directions'), findsOneWidget);
  });
}
