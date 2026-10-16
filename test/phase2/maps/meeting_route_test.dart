import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/maps/route_repository.dart';
import 'package:hocalist/features/approved/meeting_directions_page.dart';

void main() {
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
      await tester.tap(find.text('Show directions'));
      await tester.pump();
      expect(
        find.text('Enter a starting address, including the city.'),
        findsOneWidget,
      );
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), 'Public TEST origin');
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
      final list = find
          .descendant(
            of: find.byKey(const Key('meeting-directions-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Route map'),
        200,
        scrollable: list,
      );
      expect(find.text('Route map'), findsOneWidget);
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
    await tester.tap(find.text('Show directions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No route was found'), findsOneWidget);
    expect(find.text('Public TEST origin'), findsOneWidget);
    expect(find.text('Show directions'), findsOneWidget);
  });
}
