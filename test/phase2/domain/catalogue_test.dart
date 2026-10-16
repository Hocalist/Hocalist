import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 2,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 2),
  );

  CatalogueCategory category({
    String? parentId,
    String? slug,
    CatalogueEntryStatus status = CatalogueEntryStatus.active,
  }) {
    return CatalogueCategory(
      id: 'category-tablets',
      parentId: parentId,
      label: 'Tablets',
      slug: slug,
      scope: CatalogueScope.product,
      status: status,
      sortOrder: 3,
      stamp: stamp,
    );
  }

  group('CatalogueCategory', () {
    test('keeps all admin-managed values through copyWith', () {
      final original = category(
        parentId: 'category-electronics',
        slug: 'tablets',
      );
      final updated = original.copyWith(label: 'Tablets & e-readers');

      expect(updated.label, 'Tablets & e-readers');
      expect(updated.id, original.id);
      expect(updated.parentId, 'category-electronics');
      expect(updated.slug, 'tablets');
      expect(updated.scope, CatalogueScope.product);
      expect(updated.status, CatalogueEntryStatus.active);
      expect(updated.sortOrder, 3);
      expect(updated.stamp, stamp);
    });

    test('supports explicit parent and slug clearing', () {
      final original = category(
        parentId: 'category-electronics',
        slug: 'tablets',
      );
      final cleared = original.copyWith(clearParent: true, clearSlug: true);

      expect(cleared.parentId, isNull);
      expect(cleared.slug, isNull);
      expect(cleared.label, original.label);
      expect(cleared.scope, original.scope);
      expect(
        () => original.copyWith(parentId: 'x', clearParent: true),
        throwsArgumentError,
      );
      expect(
        () => original.copyWith(slug: 'x', clearSlug: true),
        throwsArgumentError,
      );
    });

    test('retired status is preserved and readable', () {
      final retired = category(status: CatalogueEntryStatus.retired);

      expect(retired.isActive, isFalse);
      expect(
        retired.copyWith(label: 'Legacy tablets').status,
        CatalogueEntryStatus.retired,
      );
    });

    test('rejects blank labels, blank ids and negative ordering', () {
      expect(
        () => CatalogueCategory(
          id: ' ',
          label: 'Tablets',
          scope: CatalogueScope.product,
          status: CatalogueEntryStatus.active,
          sortOrder: 0,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => CatalogueCategory(
          id: 'category-tablets',
          label: '',
          scope: CatalogueScope.product,
          status: CatalogueEntryStatus.active,
          sortOrder: 0,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => CatalogueCategory(
          id: 'category-tablets',
          label: 'Tablets',
          scope: CatalogueScope.product,
          status: CatalogueEntryStatus.active,
          sortOrder: -1,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(() => category(parentId: '  '), throwsArgumentError);
    });

    test('a category cannot be its own parent', () {
      expect(() => category(parentId: 'category-tablets'), throwsArgumentError);
    });

    test('scope helpers describe which listing kinds may select it', () {
      expect(CatalogueScope.product.supportsProduct, isTrue);
      expect(CatalogueScope.product.supportsService, isFalse);
      expect(CatalogueScope.service.supportsProduct, isFalse);
      expect(CatalogueScope.service.supportsService, isTrue);
      expect(CatalogueScope.both.supportsProduct, isTrue);
      expect(CatalogueScope.both.supportsService, isTrue);
    });
  });

  group('CatalogueOptionGroup and options', () {
    test('groups keep their category link and selection mode', () {
      final group = CatalogueOptionGroup(
        id: 'group-condition',
        categoryId: 'category-tablets',
        label: 'Condition',
        selectionMode: CatalogueSelectionMode.single,
        isRequired: true,
        status: CatalogueEntryStatus.active,
        sortOrder: 1,
        stamp: stamp,
      );
      final updated = group.copyWith(label: 'Item condition');

      expect(updated.categoryId, 'category-tablets');
      expect(updated.selectionMode, CatalogueSelectionMode.single);
      expect(updated.isRequired, isTrue);
      expect(updated.label, 'Item condition');
      expect(updated.stamp, stamp);
    });

    test('options keep their group link through copyWith', () {
      final option = CatalogueOption(
        id: 'option-used',
        groupId: 'group-condition',
        label: 'Used',
        status: CatalogueEntryStatus.active,
        sortOrder: 2,
        stamp: stamp,
      );
      final retired = option.copyWith(
        status: CatalogueEntryStatus.retired,
        stamp: RecordStamp(
          revision: 3,
          createdAt: stamp.createdAt,
          updatedAt: DateTime.utc(2026, 5, 3),
        ),
      );

      expect(retired.groupId, 'group-condition');
      expect(retired.label, 'Used');
      expect(retired.status, CatalogueEntryStatus.retired);
      expect(retired.stamp.revision, 3);
      expect(option.status, CatalogueEntryStatus.active);
    });

    test('rejects blank category/group ids and negative ordering', () {
      expect(
        () => CatalogueOptionGroup(
          id: 'group-condition',
          categoryId: '',
          label: 'Condition',
          selectionMode: CatalogueSelectionMode.single,
          status: CatalogueEntryStatus.active,
          sortOrder: 0,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => CatalogueOption(
          id: 'option-used',
          groupId: 'group-condition',
          label: 'Used',
          status: CatalogueEntryStatus.active,
          sortOrder: -2,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Catalogue commands', () {
    test('carry complete admin values with revision and idempotency', () {
      final create = CreateCatalogueCategoryCommand(
        parentId: 'category-electronics',
        label: 'Tablets',
        slug: 'tablets',
        scope: CatalogueScope.product,
        sortOrder: 4,
        idempotencyKey: 'cat-1',
      );
      expect(create.parentId, 'category-electronics');
      expect(create.scope, CatalogueScope.product);
      expect(create.sortOrder, 4);

      final update = UpdateCatalogueCategoryCommand(
        categoryId: 'category-tablets',
        expectedRevision: 2,
        parentId: 'category-electronics',
        label: 'Tablets & e-readers',
        slug: 'tablets',
        scope: CatalogueScope.both,
        sortOrder: 5,
        idempotencyKey: 'cat-2',
      );
      expect(update.expectedRevision, 2);
      expect(update.scope, CatalogueScope.both);
      expect(
        () => UpdateCatalogueCategoryCommand(
          categoryId: 'category-tablets',
          expectedRevision: 2,
          parentId: 'category-electronics',
          clearParent: true,
          label: 'Tablets',
          scope: CatalogueScope.product,
          sortOrder: 0,
          idempotencyKey: 'cat-3',
        ),
        throwsArgumentError,
      );

      final groupCreate = CreateCatalogueOptionGroupCommand(
        categoryId: 'category-tablets',
        label: 'Condition',
        selectionMode: CatalogueSelectionMode.single,
        isRequired: true,
        idempotencyKey: 'group-1',
      );
      expect(groupCreate.isRequired, isTrue);

      final groupUpdate = UpdateCatalogueOptionGroupCommand(
        groupId: 'group-condition',
        expectedRevision: 1,
        label: 'Item condition',
        selectionMode: CatalogueSelectionMode.multiple,
        isRequired: false,
        sortOrder: 1,
        idempotencyKey: 'group-2',
      );
      expect(groupUpdate.selectionMode, CatalogueSelectionMode.multiple);

      final optionCreate = CreateCatalogueOptionCommand(
        groupId: 'group-condition',
        label: 'Used',
        idempotencyKey: 'option-1',
      );
      expect(optionCreate.groupId, 'group-condition');

      final optionUpdate = UpdateCatalogueOptionCommand(
        optionId: 'option-used',
        expectedRevision: 1,
        label: 'Gently used',
        sortOrder: 2,
        idempotencyKey: 'option-2',
      );
      expect(optionUpdate.label, 'Gently used');
    });

    test('status command addresses any entry type and keeps revisions', () {
      final command = SetCatalogueEntryStatusCommand(
        entryType: CatalogueEntryType.option,
        entryId: 'option-used',
        expectedRevision: 1,
        status: CatalogueEntryStatus.retired,
        idempotencyKey: 'status-1',
      );

      expect(command.entryType, CatalogueEntryType.option);
      expect(command.status, CatalogueEntryStatus.retired);

      final result = CatalogueEntryStatusResult(
        entryType: command.entryType,
        entryId: command.entryId,
        status: command.status,
        stamp: stamp,
      );
      expect(result.entryId, 'option-used');
      expect(result.status, CatalogueEntryStatus.retired);
    });

    test('reject blank keys and revisions below one', () {
      expect(
        () => CreateCatalogueCategoryCommand(
          label: 'Tablets',
          scope: CatalogueScope.product,
          idempotencyKey: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateCatalogueOptionCommand(
          optionId: 'option-used',
          expectedRevision: 0,
          label: 'Used',
          sortOrder: 0,
          idempotencyKey: 'option-2',
        ),
        throwsArgumentError,
      );
      expect(
        () => SetCatalogueEntryStatusCommand(
          entryType: CatalogueEntryType.category,
          entryId: 'category-tablets',
          expectedRevision: 1,
          status: CatalogueEntryStatus.active,
          idempotencyKey: '',
        ),
        throwsArgumentError,
      );
    });
  });
}
