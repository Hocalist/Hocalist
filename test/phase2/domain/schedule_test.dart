import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  group('RecordStamp', () {
    test('normalizes timestamps to UTC and keeps the revision', () {
      final stamp = RecordStamp(
        revision: 3,
        createdAt: DateTime.parse('2026-05-01T10:00:00+02:00'),
        updatedAt: DateTime.parse('2026-05-02T10:00:00+02:00'),
      );

      expect(stamp.revision, 3);
      expect(stamp.createdAt.isUtc, isTrue);
      expect(stamp.updatedAt.isUtc, isTrue);
      expect(stamp.createdAt.hour, 8);
    });

    test('rejects a revision below one', () {
      expect(
        () => RecordStamp(
          revision: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });
  });

  group('LocalDate', () {
    test('nextDay crosses month, year and leap-day boundaries exactly', () {
      expect(
        LocalDate(year: 2026, month: 5, day: 31).nextDay(),
        LocalDate(year: 2026, month: 6, day: 1),
      );
      expect(
        LocalDate(year: 2025, month: 12, day: 31).nextDay(),
        LocalDate(year: 2026, month: 1, day: 1),
      );
      expect(
        LocalDate(year: 2024, month: 2, day: 28).nextDay(),
        LocalDate(year: 2024, month: 2, day: 29),
      );
      expect(
        LocalDate(year: 2025, month: 2, day: 28).nextDay(),
        LocalDate(year: 2025, month: 3, day: 1),
      );
    });

    test('rejects impossible calendar dates', () {
      expect(
        () => LocalDate(year: 2026, month: 4, day: 31),
        throwsArgumentError,
      );
      expect(
        () => LocalDate(year: 2025, month: 2, day: 29),
        throwsArgumentError,
      );
      expect(
        () => LocalDate(year: 2026, month: 13, day: 1),
        throwsArgumentError,
      );
    });

    test('orders and formats as an ISO calendar date', () {
      final earlier = LocalDate(year: 2026, month: 5, day: 9);
      final later = LocalDate(year: 2026, month: 5, day: 10);

      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier.toString(), '2026-05-09');
    });
  });

  group('LocalTime and LocalSchedule', () {
    test('rejects impossible clock times', () {
      expect(() => LocalTime(hour: 24, minute: 0), throwsArgumentError);
      expect(() => LocalTime(hour: 0, minute: 60), throwsArgumentError);
    });

    test('schedule preserves local date, time and timezone', () {
      final schedule = LocalSchedule(
        date: LocalDate(year: 2026, month: 5, day: 20),
        startTime: LocalTime(hour: 15, minute: 0),
        timezoneId: 'America/New_York',
      );

      expect(schedule.date.day, 20);
      expect(schedule.startTime.hour, 15);
      expect(schedule.timezoneId, 'America/New_York');
      expect(schedule.toString(), '2026-05-20 15:00 (America/New_York)');
    });

    test('schedule rejects a blank timezone', () {
      expect(
        () => LocalSchedule(
          date: LocalDate(year: 2026, month: 5, day: 20),
          startTime: LocalTime(hour: 15, minute: 0),
          timezoneId: '  ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('MeetingPlace', () {
    test('specific place needs a label or provider id', () {
      expect(
        () => MeetingPlace(choice: MeetupPlaceChoice.specificPlace),
        throwsArgumentError,
      );
      expect(
        MeetingPlace(
          choice: MeetupPlaceChoice.specificPlace,
          label: 'Cross County Mall',
          address: '123 Private St',
          placeId: 'place-1',
        ).placeId,
        'place-1',
      );
    });

    test('seller business and buyer location choices need no extra value', () {
      expect(
        MeetingPlace(choice: MeetupPlaceChoice.sellerBusiness).choice,
        MeetupPlaceChoice.sellerBusiness,
      );
      expect(
        MeetingPlace(choice: MeetupPlaceChoice.buyerLocation).choice,
        MeetupPlaceChoice.buyerLocation,
      );
    });

    test('debug output redacts labels, addresses and provider ids', () {
      final place = MeetingPlace(
        choice: MeetupPlaceChoice.specificPlace,
        label: 'SENTINEL-MALL-NAME',
        address: 'SENTINEL-PRIVATE-STREET',
        placeId: 'SENTINEL-PLACE-ID',
      );

      expect(place.label, 'SENTINEL-MALL-NAME');
      expect(place.address, 'SENTINEL-PRIVATE-STREET');
      expect(place.placeId, 'SENTINEL-PLACE-ID');

      final rendered = place.toString();
      expect(rendered.contains('SENTINEL'), isFalse);
      expect(rendered, contains('specificPlace'));
      expect(rendered, contains('label: present'));
    });

    test('revision debug output redacts the nested place', () {
      final revision = AcceptedScheduleRevision(
        revision: 1,
        schedule: LocalSchedule(
          date: LocalDate(year: 2026, month: 5, day: 20),
          startTime: LocalTime(hour: 15, minute: 0),
          timezoneId: 'America/New_York',
        ),
        place: MeetingPlace(
          choice: MeetupPlaceChoice.specificPlace,
          label: 'SENTINEL-MALL-NAME',
        ),
        acceptedAt: DateTime.utc(2026, 5, 1),
        acceptedByUserId: 'auth-buyer',
      );

      final rendered = revision.toString();
      expect(rendered.contains('SENTINEL'), isFalse);
      expect(rendered, contains('2026-05-20 15:00'));
    });
  });
}
