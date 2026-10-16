import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_codecs.dart';
import 'package:hocalist/data/phase2/accounts/timestamptz.dart';

void main() {
  DateTime parse(String value) =>
      parsePostgresTimestamptz(value, context: 'test.created_at');

  group('accepted PostgreSQL formats', () {
    test('accepts PostgREST and PostgreSQL offset variants', () {
      final expected = DateTime.utc(2026, 5, 1);
      for (final value in [
        '2026-05-01T00:00:00+00:00',
        '2026-05-01T00:00:00+0000',
        '2026-05-01T00:00:00+00',
        '2026-05-01T00:00:00Z',
        '2026-05-01 00:00:00+00:00',
      ]) {
        expect(parse(value), expected, reason: value);
      }
    });

    test('normalizes offsets to the same UTC instant', () {
      expect(parse('2026-05-01T02:00:00+02:00'), parse('2026-05-01T00:00:00Z'));
      expect(parse('2026-04-30T19:00:00-05:00'), DateTime.utc(2026, 5, 1));
      expect(parse('2026-05-01T05:30:00+05:30'), DateTime.utc(2026, 5, 1));
    });

    test('preserves fractional second precision', () {
      expect(
        parse('2026-05-01T00:00:00.5Z'),
        DateTime.utc(2026, 5, 1, 0, 0, 0, 500),
      );
      expect(
        parse('2026-05-01T00:00:00.123456Z'),
        DateTime.utc(2026, 5, 1, 0, 0, 0, 123, 456),
      );
      expect(
        parse('2026-05-01T00:00:00.123456+00:00'),
        DateTime.utc(2026, 5, 1, 0, 0, 0, 123, 456),
      );
    });

    test('accepts a real leap day', () {
      expect(parse('2024-02-29T12:00:00Z'), DateTime.utc(2024, 2, 29, 12));
    });
  });

  group('rejected values', () {
    test('requires an explicit timezone offset', () {
      for (final value in [
        '2026-05-01T00:00:00',
        '2026-05-01T00:00:00.123',
        '2026-05-01 00:00:00',
        '2026-05-01',
      ]) {
        expect(
          () => parse(value),
          throwsA(
            isA<AccountDecodeException>().having(
              (error) => error.detail,
              'detail',
              'test.created_at',
            ),
          ),
          reason: value,
        );
      }
    });

    test('rejects impossible calendar and clock values', () {
      for (final value in [
        '2026-02-30T00:00:00Z',
        '2025-02-29T00:00:00Z',
        '2026-13-01T00:00:00Z',
        '2026-00-10T00:00:00Z',
        '2026-05-00T00:00:00Z',
        '2026-05-01T24:00:00Z',
        '2026-05-01T12:60:00Z',
        '2026-05-01T12:00:60Z',
      ]) {
        expect(
          () => parse(value),
          throwsA(isA<AccountDecodeException>()),
          reason: value,
        );
      }
    });

    test('rejects malformed shapes and invalid offsets', () {
      for (final value in [
        '',
        'not-a-date',
        '2026-5-01T00:00:00Z',
        '26-05-01T00:00:00Z',
        '2026-05-01T00:00:00+00:60',
        '2026-05-01T00:00:00+24:00',
        '2026-05-01T00:00:00ZZ',
      ]) {
        expect(
          () => parse(value),
          throwsA(isA<AccountDecodeException>()),
          reason: value,
        );
      }
    });

    test('the failure never echoes the raw value', () {
      const sentinel = '2026-02-30T00:00:00Z-SENTINEL';
      try {
        parse(sentinel);
        fail('expected an AccountDecodeException');
      } on AccountDecodeException catch (error) {
        expect(error.toString().contains('SENTINEL'), isFalse);
        expect(error.detail, 'test.created_at');
      }
    });
  });
}
