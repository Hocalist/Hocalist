/// Strict PostgreSQL `timestamptz` text parsing for account rows.
///
/// PostgREST returns timestamptz values as ISO-like text with an explicit
/// offset, for example `2026-05-01T00:00:00+00:00`,
/// `2026-05-01T00:00:00.123456Z` or `2026-05-01 00:00:00+00`. The parser
/// requires an explicit `Z` or numeric offset and validates calendar and clock
/// ranges itself instead of relying on `DateTime.parse` normalization, so an
/// impossible date cannot silently roll over. Valid instants are normalized to
/// UTC.
library;

import 'account_codecs.dart';

final RegExp _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?'
  r'(Z|[+-]\d{2}(?::?\d{2})?)$',
);

/// Parses one PostgreSQL timestamptz string into a UTC [DateTime].
///
/// Throws [AccountDecodeException] with [context] when the value is missing a
/// timezone, has an invalid shape, or contains an impossible calendar/clock
/// value. [context] must be a safe field path such as `memberships.created_at`.
DateTime parsePostgresTimestamptz(String value, {required String context}) {
  final match = _timestampPattern.firstMatch(value);
  if (match == null) {
    throw AccountDecodeException(context);
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  if (year < 1 || year > 9999) throw AccountDecodeException(context);
  if (month < 1 || month > 12) throw AccountDecodeException(context);
  if (day < 1 || day > _daysInMonth(year, month)) {
    throw AccountDecodeException(context);
  }
  if (hour > 23 || minute > 59 || second > 59) {
    throw AccountDecodeException(context);
  }

  final fraction = match.group(7);
  var milliseconds = 0;
  var microseconds = 0;
  if (fraction != null) {
    final padded = fraction.padRight(6, '0');
    microseconds = int.parse(padded.substring(3));
    milliseconds = int.parse(padded.substring(0, 3));
  }

  final offsetMinutes = _parseOffsetMinutes(match.group(8)!, context);
  final localAsUtc = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    milliseconds,
    microseconds,
  );
  return localAsUtc.subtract(Duration(minutes: offsetMinutes)).toUtc();
}

int _parseOffsetMinutes(String offset, String context) {
  if (offset == 'Z') return 0;
  final sign = offset.startsWith('-') ? -1 : 1;
  final digits = offset.substring(1).replaceAll(':', '');
  final hours = int.parse(digits.substring(0, 2));
  final minutes = digits.length == 4 ? int.parse(digits.substring(2)) : 0;
  if (hours > 23 || minutes > 59) {
    throw AccountDecodeException(context);
  }
  return sign * (hours * 60 + minutes);
}

int _daysInMonth(int year, int month) {
  switch (month) {
    case 1:
    case 3:
    case 5:
    case 7:
    case 8:
    case 10:
    case 12:
      return 31;
    case 4:
    case 6:
    case 9:
    case 11:
      return 30;
    case 2:
      final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
      return leap ? 29 : 28;
    default:
      return 0;
  }
}
