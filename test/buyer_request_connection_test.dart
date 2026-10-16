// Buyer request create/detail connection tests: complete draft submission,
// operation-key reconciliation and real-mode detail updates. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';

import 'test_fonts.dart';

MarketplaceRequest _request({
  int revision = 1,
  RequestStatus status = RequestStatus.active,
  String title = 'iPad Air, 5th gen or newer',
  String description = 'Needs to be in good condition.',
}) => MarketplaceRequest(
  id: '30000000-0000-4000-8000-000000000001',
  buyerProfileId: '10000000-0000-4000-8000-00000000000a',
  buyerUserId: 'user-a',
  draft: RequestDraft(
    kind: RequestKind.product,
    title: title,
    description: description,
    condition: ProductCondition.used,
    quantity: 1,
    budget: MoneyRange(
      minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
      maximum: Money(minorUnits: 48000, currencyCode: 'USD'),
    ),
    acceptsHigherOffers: false,
    categoryId: '20000000-0000-4000-8000-000000000001',
  ),
  status: status,
  stamp: RecordStamp(
    revision: revision,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  ),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPost(WidgetTester tester) async {
  final postAction = find.byKey(const Key('approvedRequestPostButton'));
  await tester.ensureVisible(postAction);
  await tester.pumpAndSettle();
  await tester.tap(postAction);
  await tester.pumpAndSettle();
}

Future<void> _postRequest(WidgetTester tester) async {
  final continueAction = find.text('Continue');
  await tester.ensureVisible(continueAction);
  await tester.pumpAndSettle();
  await tester.tap(continueAction);
  await tester.pumpAndSettle();
  await _tapPost(tester);
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('real requests never submit a missing home address', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'My request',
        budget: '',
        includeAppChrome: true,
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        onSubmitDraft: (_, _) async {
          calls++;
          return const RequestSubmissionResult.failure('Unexpected call');
        },
      ),
    );
    await _postRequest(tester);
    expect(calls, 0);
    expect(find.text('No saved home address'), findsOneWidget);
    expect(find.text('123 Main Street'), findsNothing);
    expect(find.text('Choose a location or enter an address.'), findsOneWidget);
  });

  testWidgets(
    'map selection submits private coordinates and manual edit clears them',
    (tester) async {
      final drafts = <RequestDraft>[];
      await _pump(
        tester,
        ApprovedRequestFlowPage(
          homeAddress: const PostalAddress(
            line1: 'Saved test address',
            country: 'US',
          ),
          accent: const Color(0xff1917ff),
          requestTitle: 'Mapped request',
          includeAppChrome: true,
          budget: '',
          onTitleChanged: (_) {},
          onBudgetChanged: (_) {},
          onBack: () {},
          onNotifications: () {},
          onSubmit: () {},
          onChooseLocation: (context) async {
            expect(Navigator.of(context), isNotNull);
            return RequestLocation.custom(
              address: const PostalAddress(
                line1: 'Selected meeting area',
                city: 'Chicago',
                state: 'IL',
                postalCode: '60605',
                country: 'US',
              ),
              coordinates: RequestCoordinates(latitude: 40.9, longitude: -73.8),
            );
          },
          onSubmitDraft: (draft, key) async {
            drafts.add(draft);
            return const RequestSubmissionResult.failure('Try again.');
          },
        ),
      );
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('requestChooseMapLocation')),
      );
      await tester.tap(find.byKey(const Key('requestChooseMapLocation')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Selected: Selected meeting area'),
        findsOneWidget,
      );
      for (final entry in {
        'street-address': 'Selected meeting area',
        'city': 'Chicago',
        'state': 'IL',
        'zip-code': '60605',
      }.entries) {
        final field = tester.widget<TextFormField>(
          find.byKey(Key('approved-request-address-${entry.key}')),
        );
        expect(field.controller!.text, entry.value);
      }
      await _tapPost(tester);
      expect(drafts.single.location.coordinates?.latitude, 40.9);
      final address = find.byKey(
        const Key('approved-request-address-street-address'),
      );
      await tester.ensureVisible(address);
      await tester.enterText(address, 'Manual replacement');
      await tester.pumpAndSettle();
      await _tapPost(tester);
      expect(drafts.last.location.coordinates, isNull);
      expect(drafts.last.location.address?.line1, 'Manual replacement');
    },
  );

  testWidgets('real create submits the complete draft and opens the record', (
    tester,
  ) async {
    final drafts = <RequestDraft>[];
    final keys = <String>[];
    MarketplaceRequest? created;
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        homeAddress: const PostalAddress(
          line1: 'Saved test address',
          country: 'US',
        ),
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
        onSubmitDraft: (draft, operationKey) async {
          drafts.add(draft);
          keys.add(operationKey);
          return RequestSubmissionResult.success(_request());
        },
        onCreated: (request) => created = request,
        categories: const [
          CatalogueCategoryOption(
            id: '20000000-0000-4000-8000-000000000001',
            label: 'Electronics',
            scope: 'product',
            status: 'active',
          ),
        ],
      ),
    );

    await _postRequest(tester);

    expect(drafts, hasLength(1));
    final draft = drafts.single;
    expect(draft.kind, RequestKind.product);
    expect(draft.title, 'iPad Air, 5th gen or newer');
    expect(draft.condition, ProductCondition.newItem);
    expect(draft.serviceType, isNull);
    expect(draft.quantity, 1);
    expect(draft.acceptsHigherOffers, isTrue);
    expect(draft.location.useHomeAddress, isTrue);
    expect(keys.single, isNotEmpty);
    expect(created?.id, '30000000-0000-4000-8000-000000000001');
  });

  testWidgets('an uncertain create keeps its payload and key for retry', (
    tester,
  ) async {
    final drafts = <RequestDraft>[];
    final keys = <String>[];
    var firstAttempt = true;
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        homeAddress: const PostalAddress(
          line1: 'Saved test address',
          country: 'US',
        ),
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
        onSubmitDraft: (draft, operationKey) async {
          drafts.add(draft);
          keys.add(operationKey);
          if (firstAttempt) {
            firstAttempt = false;
            return const RequestSubmissionResult.failure(
              'The request could not be confirmed. Retry to check it safely.',
              outcomeUncertain: true,
            );
          }
          return RequestSubmissionResult.success(_request());
        },
      ),
    );

    await _postRequest(tester);
    expect(find.byKey(const Key('approvedRequestSubmitError')), findsOneWidget);
    expect(find.byKey(const Key('approvedRequestDiscard')), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(drafts, hasLength(2));
    expect(keys[1], keys[0]);
    expect(drafts[1], same(drafts[0]));
  });

  testWidgets('a changed create cannot reuse an unresolved key', (
    tester,
  ) async {
    final keys = <String>[];
    var firstAttempt = true;
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        homeAddress: const PostalAddress(
          line1: 'Saved test address',
          country: 'US',
        ),
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
        onSubmitDraft: (draft, operationKey) async {
          keys.add(operationKey);
          if (firstAttempt) {
            firstAttempt = false;
            return const RequestSubmissionResult.failure(
              'The request could not be confirmed. Retry to check it safely.',
              outcomeUncertain: true,
            );
          }
          return RequestSubmissionResult.success(_request());
        },
      ),
    );

    await _postRequest(tester);
    expect(keys, hasLength(1));

    // Change the meeting location, then try to post a changed intent.
    final street = find.byKey(
      const ValueKey('approved-request-address-street-address'),
    );
    await tester.ensureVisible(street);
    await tester.pumpAndSettle();
    await tester.enterText(street, '42 Test Avenue');
    await tester.pumpAndSettle();
    await _tapPost(tester);

    expect(keys, hasLength(1), reason: 'changed intent must not reuse the key');
    expect(find.textContaining('may already have been posted'), findsOneWidget);

    final discard = find.byKey(const Key('approvedRequestDiscard'));
    await tester.ensureVisible(discard);
    await tester.pumpAndSettle();
    await tester.tap(discard);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Post request'));
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(keys[1], isNot(keys[0]));
  });

  testWidgets('a service request sends the selected catalogue category', (
    tester,
  ) async {
    final drafts = <RequestDraft>[];
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        homeAddress: const PostalAddress(
          line1: 'Saved test address',
          country: 'US',
        ),
        accent: const Color(0xff1917ff),
        requestTitle: 'House cleaning',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        initialKind: ApprovedRequestKind.service,
        includeAppChrome: true,
        onSubmitDraft: (draft, operationKey) async {
          drafts.add(draft);
          return RequestSubmissionResult.success(_request());
        },
        categories: const [
          CatalogueCategoryOption(
            id: '20000000-0000-4000-8000-000000000002',
            label: 'Cleaning',
            scope: 'service',
            status: 'active',
          ),
          CatalogueCategoryOption(
            id: '20000000-0000-4000-8000-000000000003',
            label: 'Retired service',
            scope: 'service',
            status: 'retired',
          ),
        ],
      ),
    );

    await tester.ensureVisible(
      find.byKey(const Key('approved-request-category-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-request-category-select')));
    await tester.pumpAndSettle();
    expect(find.text('Cleaning'), findsOneWidget);
    expect(find.text('Retired service'), findsNothing);
    await tester.tap(find.text('Cleaning'));
    await tester.pumpAndSettle();

    await _postRequest(tester);

    expect(drafts.single.kind, RequestKind.service);
    expect(drafts.single.serviceType, ServiceType.oneTime);
    expect(drafts.single.condition, isNull);
    expect(drafts.single.categoryId, '20000000-0000-4000-8000-000000000002');
  });

  testWidgets('an empty title blocks Continue on the details step', (
    tester,
  ) async {
    var submitted = false;
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        homeAddress: const PostalAddress(
          line1: 'Saved test address',
          country: 'US',
        ),
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
        onSubmitDraft: (draft, operationKey) async {
          submitted = true;
          return RequestSubmissionResult.success(_request());
        },
      ),
    );

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(submitted, isFalse);
    expect(find.text('Add a clear request title.'), findsOneWidget);
    expect(find.byKey(const Key('approvedRequestPostButton')), findsNothing);
  });

  testWidgets('real detail saves an update with the expected revision', (
    tester,
  ) async {
    final drafts = <RequestDraft>[];
    final keys = <String>[];
    MarketplaceRequest? updated;
    await _pump(
      tester,
      ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () {},
        includeAppChrome: true,
        request: _request(revision: 3),
        onUpdateRequest: (draft, operationKey) async {
          drafts.add(draft);
          keys.add(operationKey);
          return RequestSubmissionResult.success(_request(revision: 4));
        },
        onUpdated: (request) => updated = request,
      ),
    );

    final titleField = find.byKey(const Key('request-title-field'));
    await tester.ensureVisible(titleField);
    await tester.pumpAndSettle();
    await tester.enterText(titleField, 'iPad Pro, 11-inch');
    await tester.pumpAndSettle();

    final saveAction = find.byKey(const Key('save-request-changes'));
    await tester.ensureVisible(saveAction);
    await tester.pumpAndSettle();
    await tester.tap(saveAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update request'));
    await tester.pumpAndSettle();

    expect(drafts.single.title, 'iPad Pro, 11-inch');
    expect(keys.single, isNotEmpty);
    expect(updated?.stamp.revision, 4);
  });

  testWidgets('real request detail excludes prototype offer and reward facts', (
    tester,
  ) async {
    var offersOpened = false;
    await _pump(
      tester,
      ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'Prototype title',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () => offersOpened = true,
        includeAppChrome: true,
        request: _request(title: 'Test desk lamp'),
        onUpdateRequest: (_, _) async =>
            RequestSubmissionResult.success(_request()),
      ),
    );
    expect(find.text('Test desk lamp'), findsWidgets);
    expect(find.text('32 offers'), findsNothing);
    expect(find.text(r'$6.40'), findsNothing);
    expect(find.bySemanticsLabel('iPad Air request product'), findsNothing);
    final review = find.byKey(const Key('realRequestReviewOffers'));
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    await tester.tap(review);
    expect(offersOpened, isTrue);
  });
}
