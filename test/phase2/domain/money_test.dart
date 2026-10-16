import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  group('Money', () {
    test('stores exact integer minor units and normalizes the currency', () {
      final price = Money(minorUnits: 65000, currencyCode: 'usd');

      expect(price.minorUnits, 65000);
      expect(price.currencyCode, 'USD');
      expect(price.isPositive, isTrue);
      expect(price.toString(), 'USD 65000 minor units');
    });

    test('adds, subtracts and multiplies without floating-point drift', () {
      final ten = Money(minorUnits: 10, currencyCode: 'USD');
      final twenty = Money(minorUnits: 20, currencyCode: 'USD');

      expect((ten + twenty).minorUnits, 30);
      expect((twenty - ten).minorUnits, 10);
      expect((ten * 3).minorUnits, 30);
      expect(Money.zero('USD').isZero, isTrue);
    });

    test('rejects invalid currency codes', () {
      expect(() => Money(minorUnits: 0, currencyCode: ''), throwsArgumentError);
      expect(
        () => Money(minorUnits: 0, currencyCode: 'US'),
        throwsArgumentError,
      );
      expect(
        () => Money(minorUnits: 0, currencyCode: 'US1'),
        throwsArgumentError,
      );
    });

    test('refuses to combine different currencies', () {
      final usd = Money(minorUnits: 100, currencyCode: 'USD');
      final eur = Money(minorUnits: 100, currencyCode: 'EUR');

      expect(() => usd + eur, throwsArgumentError);
      expect(() => usd - eur, throwsArgumentError);
      expect(() => usd.compareTo(eur), throwsArgumentError);
    });

    test('compares and equals by amount and currency', () {
      final exact = Money(minorUnits: 199, currencyCode: 'USD');
      expect(exact, Money(minorUnits: 199, currencyCode: 'usd'));
      expect(
        exact.compareTo(Money(minorUnits: 200, currencyCode: 'USD')),
        lessThan(0),
      );
      expect(exact, isNot(Money(minorUnits: 199, currencyCode: 'EUR')));
    });
  });

  group('MoneyRange', () {
    test('keeps both bounds and the shared currency', () {
      final range = MoneyRange(
        minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
        maximum: Money(minorUnits: 48000, currencyCode: 'USD'),
      );

      expect(range.isEmpty, isFalse);
      expect(range.minimum?.minorUnits, 35000);
      expect(range.maximum?.minorUnits, 48000);
      expect(range.currencyCode, 'USD');
    });

    test('empty range has no bounds', () {
      expect(MoneyRange.empty.isEmpty, isTrue);
      expect(MoneyRange.empty.currencyCode, isNull);
    });

    test('rejects inverted, negative or mixed-currency bounds', () {
      expect(
        () => MoneyRange(
          minimum: Money(minorUnits: 500, currencyCode: 'USD'),
          maximum: Money(minorUnits: 400, currencyCode: 'USD'),
        ),
        throwsArgumentError,
      );
      expect(
        () => MoneyRange(minimum: Money(minorUnits: -1, currencyCode: 'USD')),
        throwsArgumentError,
      );
      expect(
        () => MoneyRange(
          minimum: Money(minorUnits: 100, currencyCode: 'USD'),
          maximum: Money(minorUnits: 100, currencyCode: 'EUR'),
        ),
        throwsArgumentError,
      );
    });
  });
}
