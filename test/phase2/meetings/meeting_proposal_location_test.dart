import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/meetings/meeting_proposal_location.dart';

void main() {
  final schedule = LocalSchedule(
    date: LocalDate(year: 2026, month: 10, day: 1),
    startTime: LocalTime(hour: 15, minute: 0),
    timezoneId: 'America/Chicago',
  );
  MeetingPlace confirmed(MeetupPlaceChoice choice) => MeetingPlace(
    choice: choice,
    label: 'TEST public meeting point',
    address: '100 Test Street, Chicago',
    placeId: 'synthetic-place',
    latitude: 41.8765,
    longitude: -87.629,
  );

  for (final choice in [
    MeetupPlaceChoice.buyerLocation,
    MeetupPlaceChoice.sellerBusiness,
  ]) {
    test('$choice resolves only a participant-confirmed location', () async {
      var confirmations = 0;
      final input = await prepareMeetingProposalLocation(
        schedule: schedule,
        place: MeetingPlace(choice: choice, label: 'Generic location'),
        isCurrent: () => true,
        confirmPlace: (_) async {
          confirmations++;
          return confirmed(choice);
        },
      );
      expect(confirmations, 1);
      expect(input!.placeAddress, '100 Test Street, Chicago');
      expect(input.placeId, 'synthetic-place');
      expect(input.toWire()['place_latitude'], 41.8765);
      expect(input.toWire()['place_longitude'], -87.629);
      expect(input.schedule, same(schedule));
      expect(input.schedule.timezoneId, 'America/Chicago');
      expect(
        input.placeChoice,
        choice == MeetupPlaceChoice.buyerLocation
            ? 'buyer_location'
            : 'seller_business',
      );
    });
  }

  test(
    'accepted destination remains unchanged without opening capture',
    () async {
      final input = await prepareMeetingProposalLocation(
        schedule: schedule,
        place: confirmed(MeetupPlaceChoice.specificPlace),
        isCurrent: () => true,
        confirmPlace: (_) => throw StateError('must not open capture'),
      );
      expect(input!.placeAddress, '100 Test Street, Chicago');
      expect(input.placeChoice, 'specific_place');
      expect(input.latitude, 41.8765);
      expect(input.longitude, -87.629);
    },
  );

  test('cancelling capture produces no proposal', () async {
    final input = await prepareMeetingProposalLocation(
      schedule: schedule,
      place: MeetingPlace(choice: MeetupPlaceChoice.buyerLocation),
      isCurrent: () => true,
      confirmPlace: (_) async => null,
    );
    expect(input, isNull);
  });

  for (final change in [
    'identity replacement',
    'conversation change',
    'navigation',
  ]) {
    test('$change while capturing discards the result', () async {
      var current = true;
      final capture = Completer<MeetingPlace?>();
      final result = prepareMeetingProposalLocation(
        schedule: schedule,
        place: MeetingPlace(choice: MeetupPlaceChoice.buyerLocation),
        isCurrent: () => current,
        confirmPlace: (_) => capture.future,
      );
      current = false;
      capture.complete(confirmed(MeetupPlaceChoice.buyerLocation));
      expect(await result, isNull);
    });
  }

  test('an already stale context never opens capture', () async {
    final input = await prepareMeetingProposalLocation(
      schedule: schedule,
      place: confirmed(MeetupPlaceChoice.specificPlace),
      isCurrent: () => false,
      confirmPlace: (_) => throw StateError('must not open capture'),
    );
    expect(input, isNull);
  });

  test('a generic label alone cannot produce a destination', () async {
    final input = await prepareMeetingProposalLocation(
      schedule: schedule,
      place: MeetingPlace(choice: MeetupPlaceChoice.sellerBusiness),
      isCurrent: () => true,
      confirmPlace: (_) async => MeetingPlace(
        choice: MeetupPlaceChoice.sellerBusiness,
        label: 'Seller business location',
      ),
    );
    expect(input, isNull);
  });
}
