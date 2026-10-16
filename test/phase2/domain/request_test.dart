import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 2,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 2),
  );

  RequestDraft fullProductDraft() {
    return RequestDraft(
      kind: RequestKind.product,
      title: 'iPad Air, 5th gen or newer',
      description: 'Prefer 64GB or higher, in excellent condition.',
      condition: ProductCondition.used,
      quantity: 2,
      budget: MoneyRange(
        minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
        maximum: Money(minorUnits: 48000, currencyCode: 'USD'),
      ),
      acceptsHigherOffers: true,
      categoryId: 'category-tablets',
      location: const RequestLocation.homeAddress(),
    );
  }

  group('RequestDraft', () {
    test('carries every request form field', () {
      final draft = fullProductDraft();

      expect(draft.kind, RequestKind.product);
      expect(draft.title, 'iPad Air, 5th gen or newer');
      expect(draft.description, contains('64GB'));
      expect(draft.condition, ProductCondition.used);
      expect(draft.serviceType, isNull);
      expect(draft.quantity, 2);
      expect(draft.budget.minimum?.minorUnits, 35000);
      expect(draft.budget.maximum?.minorUnits, 48000);
      expect(draft.acceptsHigherOffers, isTrue);
      expect(draft.categoryId, 'category-tablets');
      expect(draft.location.useHomeAddress, isTrue);
    });

    test('valid product and service drafts report no issues', () {
      expect(fullProductDraft().validationIssues(), isEmpty);

      final service = RequestDraft(
        kind: RequestKind.service,
        title: 'House cleaning',
        description: 'Two-bedroom apartment.',
        serviceType: ServiceType.oneTime,
        location: RequestLocation.custom(
          address: const PostalAddress(
            line1: '123 Main St',
            city: 'Yonkers',
            state: 'NY',
            postalCode: '10701',
            country: 'United States',
          ),
        ),
      );

      expect(service.validationIssues(), isEmpty);
      expect(service.location.useHomeAddress, isFalse);
      expect(service.location.address?.city, 'Yonkers');
    });

    test('reports missing title, wrong kind fields and long description', () {
      final product = RequestDraft(kind: RequestKind.product);
      final issues = product.validationIssues();
      expect(
        issues.map((issue) => issue.field),
        containsAll(<String>['title', 'condition']),
      );

      final service = RequestDraft(
        kind: RequestKind.service,
        title: 'House cleaning',
        condition: ProductCondition.used,
        quantity: 3,
      );
      final serviceFields = service
          .validationIssues()
          .map((issue) => issue.field)
          .toList();
      expect(serviceFields, contains('serviceType'));
      expect(serviceFields, contains('condition'));
      expect(serviceFields, contains('quantity'));

      final longDescription = RequestDraft(
        kind: RequestKind.product,
        title: 'Tablet',
        description: 'x' * 501,
        condition: ProductCondition.newItem,
      );
      expect(
        longDescription.validationIssues().single.code,
        ValidationCodes.tooLong,
      );
    });

    test('rejects structurally invalid values', () {
      expect(
        () => RequestDraft(kind: RequestKind.product, quantity: 0),
        throwsArgumentError,
      );
      expect(
        () => RequestDraft(kind: RequestKind.product, quantity: 100),
        throwsArgumentError,
      );
      expect(
        () => RequestDraft(kind: RequestKind.product, categoryId: '  '),
        throwsArgumentError,
      );
      expect(
        () => RequestLocation.custom(address: const PostalAddress()),
        throwsArgumentError,
      );
    });

    test('copyWith preserves every untouched field', () {
      final draft = fullProductDraft();
      final updated = draft.copyWith(title: 'iPad Pro, 11-inch');

      expect(updated.title, 'iPad Pro, 11-inch');
      expect(updated.description, draft.description);
      expect(updated.condition, draft.condition);
      expect(updated.quantity, draft.quantity);
      expect(updated.budget, draft.budget);
      expect(updated.acceptsHigherOffers, draft.acceptsHigherOffers);
      expect(updated.categoryId, draft.categoryId);
      expect(updated.location, draft.location);
    });

    test('copyWith keeps values when a field is omitted', () {
      final draft = fullProductDraft();
      final updated = draft.copyWith(kind: RequestKind.service);

      expect(updated.condition, draft.condition);
      expect(updated.categoryId, draft.categoryId);
    });

    test('kind transition can clear the value that no longer applies', () {
      final product = fullProductDraft();
      final asService = product.copyWith(
        kind: RequestKind.service,
        clearCondition: true,
        serviceType: ServiceType.ongoing,
        quantity: 1,
      );

      expect(asService.condition, isNull);
      expect(asService.serviceType, ServiceType.ongoing);
      expect(asService.quantity, 1);
      expect(asService.validationIssues(), isEmpty);
      expect(product.condition, ProductCondition.used);

      final backToProduct = asService.copyWith(
        kind: RequestKind.product,
        clearServiceType: true,
        condition: ProductCondition.newItem,
      );

      expect(backToProduct.serviceType, isNull);
      expect(backToProduct.condition, ProductCondition.newItem);
      expect(backToProduct.validationIssues(), isEmpty);
      expect(asService.serviceType, ServiceType.ongoing);
    });

    test('a kind transition does not silently rewrite other fields', () {
      final product = fullProductDraft();
      final asService = product.copyWith(
        kind: RequestKind.service,
        clearCondition: true,
        serviceType: ServiceType.ongoing,
      );

      expect(asService.quantity, product.quantity);
      expect(
        asService.validationIssues().map((issue) => issue.field),
        contains('quantity'),
      );
    });

    test('category removal is explicit and preserves other fields', () {
      final draft = fullProductDraft();
      final withoutCategory = draft.copyWith(clearCategory: true);

      expect(withoutCategory.categoryId, isNull);
      expect(withoutCategory.title, draft.title);
      expect(withoutCategory.condition, draft.condition);
      expect(withoutCategory.budget, draft.budget);
      expect(withoutCategory.acceptsHigherOffers, draft.acceptsHigherOffers);
      expect(draft.categoryId, 'category-tablets');
    });

    test('clear flags cannot be combined with a replacement value', () {
      final draft = fullProductDraft();

      expect(
        () => draft.copyWith(
          condition: ProductCondition.newItem,
          clearCondition: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => draft.copyWith(
          serviceType: ServiceType.oneTime,
          clearServiceType: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => draft.copyWith(categoryId: 'x', clearCategory: true),
        throwsArgumentError,
      );
    });

    test('debug output redacts the buyer request title', () {
      final draft = fullProductDraft();
      expect(draft.toString().contains('iPad Air'), isFalse);
      expect(draft.toString(), contains('[redacted]'));
    });
  });

  group('MarketplaceRequest', () {
    test('links the record to the buyer profile and identity by id', () {
      final request = MarketplaceRequest(
        id: 'request-1',
        buyerProfileId: 'buyer-1',
        buyerUserId: 'auth-1',
        draft: fullProductDraft(),
        status: RequestStatus.active,
        stamp: stamp,
      );

      expect(request.buyerProfileId, 'buyer-1');
      expect(request.buyerUserId, 'auth-1');
      expect(request.status, RequestStatus.active);
      expect(request.stamp.revision, 2);
      expect(request.draft.title, 'iPad Air, 5th gen or newer');
    });

    test('rejects blank owner identifiers', () {
      expect(
        () => MarketplaceRequest(
          id: 'request-1',
          buyerProfileId: '',
          buyerUserId: 'auth-1',
          draft: fullProductDraft(),
          status: RequestStatus.active,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('copyWith keeps server state unless explicitly replaced', () {
      final request = MarketplaceRequest(
        id: 'request-1',
        buyerProfileId: 'buyer-1',
        buyerUserId: 'auth-1',
        draft: fullProductDraft(),
        status: RequestStatus.active,
        stamp: stamp,
      );
      final edited = request.copyWith(
        draft: request.draft.copyWith(quantity: 3),
        stamp: RecordStamp(
          revision: 3,
          createdAt: stamp.createdAt,
          updatedAt: DateTime.utc(2026, 5, 3),
        ),
      );

      expect(edited.draft.quantity, 3);
      expect(edited.status, RequestStatus.active);
      expect(edited.stamp.revision, 3);
      expect(request.draft.quantity, 2);
      expect(request.stamp.revision, 2);
    });
  });

  group('Request commands', () {
    test('carry complete values, expected revision and idempotency', () {
      final create = CreateRequestCommand(
        draft: fullProductDraft(),
        idempotencyKey: 'create-1',
      );
      expect(create.draft.condition, ProductCondition.used);
      expect(create.idempotencyKey, 'create-1');

      final update = UpdateRequestCommand(
        requestId: 'request-1',
        expectedRevision: 2,
        draft: fullProductDraft().copyWith(quantity: 5),
        idempotencyKey: 'update-1',
      );
      expect(update.expectedRevision, 2);
      expect(update.draft.quantity, 5);

      final close = CloseRequestCommand(
        requestId: 'request-1',
        expectedRevision: 2,
        idempotencyKey: 'close-1',
        reason: 'Bought locally',
      );
      expect(close.reason, 'Bought locally');

      final reopen = ReopenRequestCommand(
        requestId: 'request-1',
        expectedRevision: 4,
        idempotencyKey: 'reopen-1',
      );
      expect(reopen.expectedRevision, 4);
    });

    test('reject blank keys and revisions below one', () {
      expect(
        () =>
            CreateRequestCommand(draft: fullProductDraft(), idempotencyKey: ''),
        throwsArgumentError,
      );
      expect(
        () => UpdateRequestCommand(
          requestId: 'request-1',
          expectedRevision: 0,
          draft: fullProductDraft(),
          idempotencyKey: 'update-1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('SellerLeadProjection', () {
    SellerLeadProjection lead() {
      return SellerLeadProjection(
        requestId: 'request-1',
        kind: RequestKind.product,
        title: 'iPad Air, 5th gen or newer',
        description: 'Prefer 64GB or higher.',
        condition: ProductCondition.used,
        quantity: 1,
        budget: MoneyRange(
          minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
          maximum: Money(minorUnits: 50000, currencyCode: 'USD'),
        ),
        categoryId: 'category-tablets',
        buyerProfileId: 'buyer-1',
        buyerDisplayName: 'Maya Chen',
        areaLabel: 'Yonkers, NY',
        distanceMiles: 2.1,
        matchPercent: 95,
        verifiedPurchaseCount: 12,
        lastCompletedItemLabel: 'MacBook Air',
        preferredMeetupLabel: 'Public place',
        publishedAt: DateTime.parse('2026-05-01T10:00:00+02:00'),
        requestRevision: 4,
      );
    }

    test('carries the lead card fields and the request revision', () {
      final projection = lead();

      expect(projection.requestId, 'request-1');
      expect(projection.buyerProfileId, 'buyer-1');
      expect(projection.buyerDisplayName, 'Maya Chen');
      expect(projection.areaLabel, 'Yonkers, NY');
      expect(projection.distanceMiles, 2.1);
      expect(projection.matchPercent, 95);
      expect(projection.verifiedPurchaseCount, 12);
      expect(projection.lastCompletedItemLabel, 'MacBook Air');
      expect(projection.preferredMeetupLabel, 'Public place');
      expect(projection.budget.maximum?.minorUnits, 50000);
      expect(projection.requestRevision, 4);
      expect(projection.publishedAt?.isUtc, isTrue);
    });

    test('carries only an approximate area, never the private address', () {
      final projection = lead();
      final rendered = projection.toString();

      expect(rendered.contains('123 Main'), isFalse);
      expect(rendered.contains('line1'), isFalse);
      expect(rendered, contains('Yonkers, NY'));
    });

    test('optional reputation values may be withheld', () {
      final projection = SellerLeadProjection(
        requestId: 'request-1',
        kind: RequestKind.service,
        title: 'House cleaning',
        buyerProfileId: 'buyer-2',
        buyerDisplayName: 'Alicia C.',
        requestRevision: 1,
      );

      expect(projection.areaLabel, isNull);
      expect(projection.distanceMiles, isNull);
      expect(projection.matchPercent, isNull);
      expect(projection.verifiedPurchaseCount, isNull);
      expect(projection.lastCompletedItemLabel, isNull);
      expect(projection.preferredMeetupLabel, isNull);
    });

    test('rejects invalid ranking values and blank identities', () {
      expect(
        () => SellerLeadProjection(
          requestId: 'request-1',
          kind: RequestKind.product,
          title: 'iPad',
          buyerProfileId: 'buyer-1',
          buyerDisplayName: 'Maya Chen',
          matchPercent: 101,
          requestRevision: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SellerLeadProjection(
          requestId: 'request-1',
          kind: RequestKind.product,
          title: 'iPad',
          buyerProfileId: 'buyer-1',
          buyerDisplayName: 'Maya Chen',
          distanceMiles: -1,
          requestRevision: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SellerLeadProjection(
          requestId: 'request-1',
          kind: RequestKind.product,
          title: 'iPad',
          buyerProfileId: 'buyer-1',
          buyerDisplayName: 'Maya Chen',
          distanceMiles: double.nan,
          requestRevision: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SellerLeadProjection(
          requestId: 'request-1',
          kind: RequestKind.product,
          title: 'iPad',
          buyerProfileId: 'buyer-1',
          buyerDisplayName: 'Maya Chen',
          distanceMiles: double.infinity,
          requestRevision: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SellerLeadProjection(
          requestId: 'request-1',
          kind: RequestKind.product,
          title: 'iPad',
          buyerProfileId: 'buyer-1',
          buyerDisplayName: 'Maya Chen',
          requestRevision: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => SellerLeadProjection(
          requestId: 'request-1',
          kind: RequestKind.product,
          title: 'iPad',
          buyerProfileId: ' ',
          buyerDisplayName: 'Maya Chen',
          requestRevision: 1,
        ),
        throwsArgumentError,
      );
    });

    test('query carries the selected filters without deciding eligibility', () {
      final query = SellerLeadQuery(
        kind: RequestKind.product,
        categoryId: 'category-tablets',
        areaLabel: 'Yonkers',
        budgetFilter: MoneyRange(
          minimum: Money(minorUnits: 50000, currencyCode: 'USD'),
        ),
        sort: SellerLeadSort.mostPurchases,
        page: PageQuery(limit: 20),
      );

      expect(query.kind, RequestKind.product);
      expect(query.categoryId, 'category-tablets');
      expect(query.areaLabel, 'Yonkers');
      expect(query.budgetFilter?.minimum?.minorUnits, 50000);
      expect(query.sort, SellerLeadSort.mostPurchases);
      expect(query.page.limit, 20);
      expect(() => SellerLeadQuery(categoryId: '  '), throwsArgumentError);
    });
  });
}
