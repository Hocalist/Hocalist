import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'package:hocalist/data/phase2/meetings/meeting_adapter.dart';
import 'package:hocalist/domain/phase2/schedule.dart';

void main() {
  test(
    'legacy places omit new wire fields and coordinates never enter logs',
    () {
      final place = MeetingPlace(
        choice: MeetupPlaceChoice.specificPlace,
        label: 'Synthetic',
        latitude: 41.8765,
        longitude: -87.629,
      );
      expect(place.toString(), isNot(contains('41.8765')));
      expect(place.toString(), isNot(contains('-87.629')));
      final input = MeetingScheduleInput(
        schedule: LocalSchedule(
          date: LocalDate(year: 2026, month: 10, day: 5),
          startTime: LocalTime(hour: 15, minute: 0),
          timezoneId: 'America/Chicago',
        ),
        placeChoice: 'specific_place',
        placeLabel: 'Synthetic',
      );
      expect(input.toWire().containsKey('place_latitude'), isFalse);
      expect(input.toWire().containsKey('place_longitude'), isFalse);
    },
  );
  test('malformed coordinate pairs are refused by strict decoders', () {
    for (final pair in <Map<String, Object?>>[
      {'place_latitude': 41.8},
      {'place_latitude': '41.8', 'place_longitude': -87.6},
      {'place_latitude': 91, 'place_longitude': -87.6},
      {'place_latitude': 41.8, 'place_longitude': double.nan},
    ]) {
      expect(
        () => decodePlaceCoordinate(pair, 'place_latitude'),
        throwsA(isA<MarketplaceDecodeException>()),
      );
    }
    expect(decodePlaceCoordinate({}, 'place_latitude'), isNull);
    expect(
      decodePlaceCoordinate({
        'place_latitude': 0,
        'place_longitude': 0,
      }, 'place_latitude'),
      0,
    );
  });
  test('partial and out-of-range domain coordinates cannot form a place', () {
    expect(
      () => MeetingPlace(
        choice: MeetupPlaceChoice.specificPlace,
        label: 'Test',
        latitude: 41.8,
      ),
      throwsArgumentError,
    );
    expect(
      () => MeetingPlace(
        choice: MeetupPlaceChoice.specificPlace,
        label: 'Test',
        latitude: 91,
        longitude: 0,
      ),
      throwsArgumentError,
    );
  });
}
