/// Integer minor-unit money for the Phase 2 Hocalist contracts.
///
/// Monetary values are stored as [Money.minorUnits] (for USD, cents) with an
/// ISO 4217 [Money.currencyCode]. No floating-point value is stored or used
/// for arithmetic. Formatting for display belongs to the UI layer, which knows
/// the currency's exponent; these models do not guess it.
///
/// This file performs no charging, billing or ledger work. HocaCredit batches,
/// reservations and rewards are separate future contracts.
library;

/// An exact monetary amount in integer minor units plus its currency.
class Money implements Comparable<Money> {
  factory Money({required int minorUnits, required String currencyCode}) {
    final normalized = currencyCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        currencyCode,
        'currencyCode',
        'must be a three-letter ISO 4217 code',
      );
    }
    return Money._(minorUnits: minorUnits, currencyCode: normalized);
  }

  const Money._({required this.minorUnits, required this.currencyCode});

  /// Zero in [currencyCode], for example `Money.zero('USD')`.
  factory Money.zero(String currencyCode) =>
      Money(minorUnits: 0, currencyCode: currencyCode);

  /// Smallest currency unit (for USD, cents). Never a floating-point value.
  final int minorUnits;

  /// Uppercase ISO 4217 code such as `USD`.
  final String currencyCode;

  bool get isZero => minorUnits == 0;

  bool get isPositive => minorUnits > 0;

  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(
      minorUnits: minorUnits + other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(
      minorUnits: minorUnits - other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  Money operator *(int factor) =>
      Money(minorUnits: minorUnits * factor, currencyCode: currencyCode);

  void _requireSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw ArgumentError.value(
        other.currencyCode,
        'other.currencyCode',
        'cannot combine $currencyCode with ${other.currencyCode}',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => '$currencyCode $minorUnits minor units';
}

/// An optional budget or price range. Both bounds are optional because the
/// request form allows an empty budget.
class MoneyRange {
  factory MoneyRange({Money? minimum, Money? maximum}) {
    if (minimum != null && minimum.isNegative) {
      throw ArgumentError.value(minimum, 'minimum', 'must not be negative');
    }
    if (maximum != null && maximum.isNegative) {
      throw ArgumentError.value(maximum, 'maximum', 'must not be negative');
    }
    if (minimum != null &&
        maximum != null &&
        minimum.currencyCode != maximum.currencyCode) {
      throw ArgumentError(
        'budget bounds must share one currency '
        '(${minimum.currencyCode} vs ${maximum.currencyCode})',
      );
    }
    if (minimum != null && maximum != null && maximum.compareTo(minimum) < 0) {
      throw ArgumentError.value(
        maximum,
        'maximum',
        'must not be less than the minimum',
      );
    }
    return MoneyRange._(minimum: minimum, maximum: maximum);
  }

  const MoneyRange._({this.minimum, this.maximum});

  /// A range with no bounds, matching an empty budget form.
  static const MoneyRange empty = MoneyRange._();

  final Money? minimum;
  final Money? maximum;

  bool get isEmpty => minimum == null && maximum == null;

  bool get isNotEmpty => !isEmpty;

  /// The shared currency when at least one bound is present.
  String? get currencyCode => minimum?.currencyCode ?? maximum?.currencyCode;

  @override
  bool operator ==(Object other) =>
      other is MoneyRange &&
      other.minimum == minimum &&
      other.maximum == maximum;

  @override
  int get hashCode => Object.hash(minimum, maximum);

  @override
  String toString() => 'MoneyRange(minimum: $minimum, maximum: $maximum)';
}
