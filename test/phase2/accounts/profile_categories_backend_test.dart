// Seller category backend tests: wire shapes, retired handling, conflict
// mapping and the session fence. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/profile_categories_backend.dart';
import 'package:hocalist/domain/phase2/catalogue.dart';

Map<String, Object?> _selectionJson() => {
  'membership_id': 'membership-seller',
  'revision': 3,
  'selected': [
    {
      'id': '80000000-0000-4000-8000-000000000001',
      'label': 'Electronics',
      'slug': 'electronics',
      'scope': 'both',
      'status': 'active',
      'selectable': true,
      'sort_order': 0,
    },
    {
      'id': '80000000-0000-4000-8000-000000000002',
      'label': 'Legacy electronics',
      'slug': null,
      'scope': 'product',
      'status': 'retired',
      'selectable': false,
      'sort_order': 1,
    },
  ],
  'available': [
    {
      'id': '80000000-0000-4000-8000-000000000001',
      'label': 'Electronics',
      'slug': 'electronics',
      'scope': 'both',
      'status': 'active',
      'sort_order': 0,
    },
  ],
};

void main() {
  test('load decodes selected, retired and available categories', () async {
    final backend = Phase2ProfileCategoriesBackend(
      identity: () => 'user-a',
      rpc: (function, params) async => _selectionJson(),
    );
    final selection = await backend.loadSellerCategories();
    expect(selection.revision, 3);
    expect(selection.selected, hasLength(2));
    expect(selection.retiredSelected.single.isRetired, isTrue);
    expect(selection.retiredSelected.single.selectable, isFalse);
    expect(selection.available.single.scope, CatalogueScope.both);
    expect(selection.available.single.selectable, isTrue);
  });

  test('update sends the revision and catalogue ids', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2ProfileCategoriesBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'membership_id': 'membership-seller',
          'revision': 4,
          'category_ids': ['80000000-0000-4000-8000-000000000001'],
        };
      },
    );
    final result = await backend.updateSellerCategories(
      expectedRevision: 3,
      categoryIds: const ['80000000-0000-4000-8000-000000000001'],
      operationKey: 'categories-1',
    );
    expect(result.revision, 4);
    expect(calls.single.$1, 'profile_categories_update');
    expect(calls.single.$2['p_expected_revision'], 3);
    expect(calls.single.$2['p_key'], 'categories-1');
  });

  test('a stale revision maps to a conflict', () async {
    final backend = Phase2ProfileCategoriesBackend(
      identity: () => 'user-a',
      rpc: (function, params) async =>
          throw const ProfileCategoriesRpcException(
            'revision_conflict',
            code: 'P0001',
            statusCode: 400,
          ),
    );
    await expectLater(
      backend.updateSellerCategories(
        expectedRevision: 1,
        categoryIds: const [],
        operationKey: 'categories-2',
      ),
      throwsA(isA<ProfileCategoriesConflictException>()),
    );
  });

  test('retired-only new selections map to a validation refusal', () async {
    final backend = Phase2ProfileCategoriesBackend(
      identity: () => 'user-a',
      rpc: (function, params) async =>
          throw const ProfileCategoriesRpcException(
            'retired_category_selection',
            code: '22023',
            statusCode: 400,
          ),
    );
    await expectLater(
      backend.updateSellerCategories(
        expectedRevision: 3,
        categoryIds: const ['80000000-0000-4000-8000-000000000009'],
        operationKey: 'categories-3',
      ),
      throwsA(isA<ProfileCategoriesUnavailableException>()),
    );
  });

  test('a signed-out session sends no request', () async {
    var called = false;
    final backend = Phase2ProfileCategoriesBackend(
      identity: () => null,
      rpc: (function, params) async {
        called = true;
        return _selectionJson();
      },
    );
    await expectLater(
      backend.loadSellerCategories(),
      throwsA(isA<ProfileCategoriesUnavailableException>()),
    );
    expect(called, isFalse);
  });

  test('a session change during dispatch discards the response', () async {
    var identity = 'user-a';
    final backend = Phase2ProfileCategoriesBackend(
      identity: () => identity,
      rpc: (function, params) async {
        identity = 'user-b';
        return _selectionJson();
      },
    );
    await expectLater(
      backend.loadSellerCategories(),
      throwsA(
        isA<ProfileCategoriesUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('session changed'),
        ),
      ),
    );
  });
}
