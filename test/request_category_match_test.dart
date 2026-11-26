import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/features/approved/request_category_match.dart';

void main() {
  const catalogue = [
    CatalogueCategoryOption(
      id: 'electronics',
      label: 'Electronics',
      scope: 'product',
      status: 'active',
    ),
    CatalogueCategoryOption(
      id: 'tv',
      label: 'TVs & audio',
      scope: 'product',
      status: 'active',
      parentId: 'electronics',
    ),
    CatalogueCategoryOption(
      id: 'phone',
      label: 'Phones & tablets',
      scope: 'product',
      status: 'active',
      parentId: 'electronics',
    ),
    CatalogueCategoryOption(
      id: 'couch',
      label: 'Sofas & chairs',
      scope: 'product',
      status: 'active',
    ),
    CatalogueCategoryOption(
      id: 'table',
      label: 'Tables & desks',
      scope: 'product',
      status: 'active',
    ),
    CatalogueCategoryOption(
      id: 'mount',
      label: 'TV mounting',
      scope: 'service',
      status: 'active',
    ),
    CatalogueCategoryOption(
      id: 'custom',
      label: 'Ceramic figurines',
      scope: 'product',
      status: 'active',
    ),
    CatalogueCategoryOption(
      id: 'retired',
      label: 'Retired item',
      scope: 'product',
      status: 'retired',
    ),
  ];

  String? category(String title, {bool product = true}) =>
      matchRequestCategory(title, catalogue, product: product)?.id;

  test('ranks item aliases and specific phrases within the selected kind', () {
    expect(category('A used 65-inch Samsung TV'), 'tv');
    expect(category('Gray sectional couch'), 'couch');
    expect(category('Looking for a TV stand'), 'table');
    expect(category('iPad Air'), 'phone');
    expect(category('Someone to mount a TV', product: false), 'mount');
    expect(category('Ceramic figurines'), 'custom');
  });

  test(
    'leaves unclear titles and inactive or wrong-kind entries unassigned',
    () {
      expect(category('Good deal please'), isNull);
      expect(category('TV or sofa'), isNull);
      expect(category('Retired item'), isNull);
      expect(category('TV', product: false), isNull);
    },
  );
}
