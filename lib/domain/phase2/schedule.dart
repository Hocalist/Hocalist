/// Calendar and meeting-place value objects for the Phase 2 contracts.
///
/// [LocalDate] and [LocalTime] are timezone-free calendar values. [LocalSchedule]
/// pairs them with an IANA timezone identifier supplied by the backend.
///
/// This file deliberately performs no timezone conversion: the supported
/// mechanism (for example a database `timestamptz` plus an approved IANA
/// database) is unresolved and must be agreed before implementation. Calendar
/// arithmetic such as [LocalDate.nextDay] is exact and never adds 24 hours.
library;

import 'common.dart';

/// A timezone-free calendar date.
class LocalDate implements Comparable<LocalDate> {
  factory LocalDate({required int year, required int month, required int day}) {
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(year, 'year', 'must be between 1 and 9999');
    }
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'day', 'must be between 1 and 31');
    }
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      throw ArgumentError.value(
        day,
        'day',
        'is not a valid day for $year-${month.toString().padLeft(2, '0')}',
      );
    }
    return LocalDate._(year: year, month: month, day: day);
  }

  const LocalDate._({
    required this.year,
    required this.month,
    required this.day,
  });

  /// Reads the calendar components of [value] without converting its zone.
  factory LocalDate.fromDateTime(DateTime value) =>
      LocalDate(year: value.year, month: value.month, day: value.day);

  final int year;
  final int month;
  final int day;

  /// The next calendar day. Month, year and leap-day boundaries are exact.
  LocalDate nextDay() {
    final next = DateTime.utc(year, month, day).add(const Duration(days: 1));
    return LocalDate._(year: next.year, month: next.month, day: next.day);
  }

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// A timezone-free clock time.
class LocalTime implements Comparable<LocalTime> {
  factory LocalTime({required int hour, required int minute}) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'must be between 0 and 23');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(minute, 'minute', 'must be between 0 and 59');
    }
    return LocalTime._(hour: hour, minute: minute);
  }

  const LocalTime._({required this.hour, required this.minute});

  /// Reads the clock components of [value] without converting its zone.
  factory LocalTime.fromDateTime(DateTime value) =>
      LocalTime(hour: value.hour, minute: value.minute);

  final int hour;
  final int minute;

  @override
  int compareTo(LocalTime other) {
    if (hour != other.hour) return hour.compareTo(other.hour);
    return minute.compareTo(other.minute);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

/// Which occurrence of a repeated local time a schedule refers to.
///
/// Only a DST fall-back repeats a wall time; the server requires this choice
/// then and rejects it when the local time is unique. The server resolves the
/// matching offset and UTC instant, so both parties share one interpretation.
enum RepeatedTimeOccurrence { earlier, later }

/// A local meeting window: calendar date, clock time and IANA timezone.
class LocalSchedule {
  factory LocalSchedule({
    required LocalDate date,
    required LocalTime startTime,
    required String timezoneId,
    RepeatedTimeOccurrence? occurrence,
  }) {
    requireNonBlank(timezoneId, 'timezoneId');
    return LocalSchedule._(
      date: date,
      startTime: startTime,
      timezoneId: timezoneId,
      occurrence: occurrence,
    );
  }

  const LocalSchedule._({
    required this.date,
    required this.startTime,
    required this.timezoneId,
    required this.occurrence,
  });

  final LocalDate date;
  final LocalTime startTime;

  /// IANA identifier such as `America/New_York`. The conversion mechanism is
  /// a backend integration decision; clients only display and submit it.
  final String timezoneId;

  /// Explicit occurrence for a repeated wall time, or null for a unique one.
  final RepeatedTimeOccurrence? occurrence;

  @override
  bool operator ==(Object other) =>
      other is LocalSchedule &&
      other.date == date &&
      other.startTime == startTime &&
      other.timezoneId == timezoneId &&
      other.occurrence == occurrence;

  @override
  int get hashCode => Object.hash(date, startTime, timezoneId, occurrence);

  @override
  String toString() =>
      '$date $startTime ($timezoneId${occurrence == null ? '' : ', ${occurrence!.name}'})';
}

/// How the seller proposes to meet.
enum MeetupPlaceChoice { sellerBusiness, buyerLocation, specificPlace }

/// A meeting place. The exact address stays private to participants until the
/// meeting is confirmed; public views show an approximate area only.
class MeetingPlace {
  factory MeetingPlace({
    required MeetupPlaceChoice choice,
    String? label,
    String? address,
    String? placeId,
    double? latitude,
    double? longitude,
    String? timezoneId,
  }) {
    if ((latitude == null) != (longitude == null) ||
        (latitude != null && (!latitude.isFinite || latitude.abs() > 90)) ||
        (longitude != null && (!longitude.isFinite || longitude.abs() > 180))) {
      throw ArgumentError('invalid confirmed place coordinates');
    }
    if (choice == MeetupPlaceChoice.specificPlace &&
        isBlank(label) &&
        isBlank(placeId)) {
      throw ArgumentError(
        'a specific meeting place needs a label or a provider place id',
      );
    }
    if (placeId != null && placeId.trim().isEmpty) {
      throw ArgumentError.value(placeId, 'placeId', 'must not be blank');
    }
    return MeetingPlace._(
      choice: choice,
      label: label,
      address: address,
      placeId: placeId,
      latitude: latitude,
      longitude: longitude,
      timezoneId: timezoneId,
    );
  }

  const MeetingPlace._({
    required this.choice,
    this.label,
    this.address,
    this.placeId,
    this.latitude,
    this.longitude,
    this.timezoneId,
  });

  final MeetupPlaceChoice choice;

  /// Display name, for example `Cross County Mall`.
  final String? label;

  /// Private street address. Never included in a public projection.
  final String? address;

  /// Provider reference from the agreed location service.
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final String? timezoneId;

  @override
  bool operator ==(Object other) =>
      other is MeetingPlace &&
      other.choice == choice &&
      other.label == label &&
      other.address == address &&
      other.placeId == placeId &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timezoneId == timezoneId;

  @override
  int get hashCode =>
      Object.hash(choice, label, address, placeId, latitude, longitude, timezoneId);

  /// Redacted on purpose: place labels, addresses and provider ids must not
  /// reach logs. Choice and presence flags keep debugging useful.
  @override
  String toString() =>
      'MeetingPlace(choice: ${choice.name}, '
      'label: ${isBlank(label) ? 'absent' : 'present'}, '
      'placeId: ${isBlank(placeId) ? 'absent' : 'present'}, '
      'address: ${isBlank(address) ? 'absent' : 'present'})';
}
