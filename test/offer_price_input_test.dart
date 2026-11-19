import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/offer_price_input.dart';
void main() {
  test('accepts normal and formatted positive offer amounts', () {
    expect(parseOfferPrice('425'), 425);
    expect(parseOfferPrice(' 425.50 '), 425.50);
    expect(parseOfferPrice('1,250.50'), 1250.50);
    expect(parseOfferPrice(r'$1,250.50'), 1250.50);
  });
  test('rejects malformed grouping and invalid money', () {
    for (final value in ['', '0', '-2', 'NaN', 'Infinity', '1e3', '12,50', '1.234', 'abc']) {
      expect(parseOfferPrice(value), isNull, reason: value);
    }
  });
}
