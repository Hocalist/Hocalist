import 'dart:async';
import 'package:hocalist/domain/phase2/category_answers.dart';
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
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/data/phase2/maps/places_transport.dart';

class _BuyerAddressPlaces implements PlacesTransport, AddressPlacesTransport {
  @override
  Future<PlacesTransportResult> address({required String address, required String sessionToken}) async {
    if (address.contains('Unresolvable')) throw StateError('Provider unavailable');
    return details(placeId: 'buyer-place', sessionToken: sessionToken);
  }
  @override
  Future<PlacesTransportResult> autocomplete({required String input,required String sessionToken})async=>
    const PlacesTransportResult({'suggestions':[{'placeId':'buyer-place','label':'Selected meeting area, Chicago'}]});
  @override
  Future<PlacesTransportResult> details({required String placeId,required String sessionToken})async=>
    const PlacesTransportResult({'placeId':'buyer-place','address':'Selected meeting area, Chicago, IL',
      'latitude':40.9,'longitude':-73.8,'timezoneId':'America/Chicago',
      'postalAddress':{'line1':'Selected meeting area','city':'Chicago','state':'IL','postalCode':'60605','country':'US'},'attributions':<Object?>[]});
}

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

Future<List<CategoryQuestion>> _noQuestions(String categoryId) async => [];

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
  if (find.text('Select a category').evaluate().isNotEmpty) {
    final category = find.byKey(const Key('approved-request-category-select'));
    await tester.ensureVisible(category); await tester.pumpAndSettle();
    await tester.tap(category); await tester.pumpAndSettle();
    await tester.tap(find.text('Electronics').last); await tester.pumpAndSettle();
  }
  final continueAction = find.text('Continue');
  await tester.ensureVisible(continueAction);
  await tester.pumpAndSettle();
  await tester.tap(continueAction);
  await tester.pumpAndSettle();
  await _tapPost(tester);
}

void main() {
  testWidgets('location editor reopens the latest selected request address', (tester) async {
    final selected = RequestLocation.custom(address: const PostalAddress(
      line1: 'Test meeting place', city: 'Chicago', state: 'IL', country: 'US'));
    final received = <RequestLocation>[];
    await _pump(tester, ApprovedBuyerRequestDetailsPage(
      questionLoader: _noQuestions, accent: const Color(0xff1917ff),
      requestTitle: 'Test request', budget: '', onBack: () {},
      onNotifications: () {}, onOffers: () {}, includeAppChrome: true,
      request: _request(),
      onUpdateRequest: (_, _) async => throw StateError('No save expected'),
      onEditLocation: (_, initial) async { received.add(initial); return selected; },
    ));
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Edit location'));
      await tester.tap(find.text('Edit location'));
      await tester.pumpAndSettle();
    }
    expect(received.first, _request().draft.location);
    expect(received.last, selected);
  });
  setUpAll(loadHocalistTestFonts);
  testWidgets('title typing retains focus across parent value updates', (tester) async {
    var title = '';
    await _pump(tester, StatefulBuilder(builder: (context, update) => ApprovedRequestFlowPage(
      questionLoader: _noQuestions, accent: const Color(0xff1917ff), requestTitle: title,
      includeAppChrome: true,
      budget: '', onTitleChanged: (value) => update(() => title = value),
      onBudgetChanged: (_) {}, onBack: () {}, onNotifications: () {}, onSubmit: () {},
    )));
    final titleField = find.widgetWithText(TextFormField, 'e.g., iPad Air 5th Gen, 64GB, Space Gray');
    await tester.ensureVisible(titleField);
    await tester.tap(titleField);
    await tester.pump();
    for (final text in ['T', 'TE', 'TEST ONLY unsent title']) {
      tester.testTextInput.updateEditingValue(TextEditingValue(text: text,
        selection: TextSelection.collapsed(offset: text.length)));
      await tester.pump();
      expect(title, text);
      final editable = tester.widget<EditableText>(find.descendant(of: titleField, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, true);
      expect(editable.controller.text, text);
    }
  });

  for (final footer in [false, true]) {
  testWidgets('Back footer=$footer preserves an unsaved request until discard is confirmed', (tester) async {
    var left = 0;
    await _pump(tester, ApprovedRequestFlowPage(
      questionLoader: _noQuestions, accent: const Color(0xff1917ff),
      requestTitle: '', budget: '', includeAppChrome: true,
      onTitleChanged: (_) {}, onBudgetChanged: (_) {}, onBack: () => left++,
      onNotifications: () {}, onSubmit: () {},
      onSubmitDraft: (_, _) async => throw StateError('must not submit'),
    ));
    final description = find.byWidgetPredicate((w) => w is TextField && w.maxLength == 500);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Keep this unsaved request description');
    final back = footer ? find.text('Back').last : find.byTooltip('Back').first;
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(left, 0);
    expect(find.byKey(const Key('request-discard-draft-sheet')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this unsaved request description'), findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(left, 1);
  });
  }

  testWidgets('rapid post taps and a stale success callback create once', (tester) async {
    final pending = Completer<RequestSubmissionResult>();
    var calls = 0;
    await _pump(tester, ApprovedRequestFlowPage(
      questionLoader: _noQuestions,
      homeAddress: const PostalAddress(line1: 'Saved test address', country: 'US'),
      accent: const Color(0xff1917ff), requestTitle: 'Synthetic rapid post', budget: '',
      includeAppChrome: true,
      onTitleChanged: (_) {}, onBudgetChanged: (_) {}, onBack: () {},
      onNotifications: () {}, onSubmit: () {},
      onSubmitDraft: (_, key) { calls++; return pending.future; },
      categories: const [CatalogueCategoryOption(id: '20000000-0000-4000-8000-000000000001',label: 'Electronics',scope: 'product',status: 'active')],
    ));
    final category = find.byKey(const Key('approved-request-category-select'));
    await tester.ensureVisible(category); await tester.pumpAndSettle();
    await tester.tap(category); await tester.pumpAndSettle();
    await tester.tap(find.text('Electronics').last); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue')); await tester.pumpAndSettle();
    await tester.tap(find.text('Continue')); await tester.pumpAndSettle();
    final post = find.byKey(const Key('approvedRequestPostButton'));
    await tester.ensureVisible(post); await tester.pumpAndSettle();
    // No frame between taps: both use the previously enabled control.
    await tester.tap(post); await tester.tap(post);
    expect(calls, 1);
    pending.complete(RequestSubmissionResult.success(_request()));
    await tester.pumpAndSettle();
    await tester.tap(post); await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real requests never submit a missing home address', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        questionLoader: _noQuestions,
        categories: const [CatalogueCategoryOption(id: '20000000-0000-4000-8000-000000000001',label: 'Electronics',scope: 'product',status: 'active')],
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
    expect(find.text('Add photo'), findsNothing);
    expect(find.text('Your photos'), findsNothing);
    await _postRequest(tester);
    expect(calls, 0);
    expect(find.text('No saved home address'), findsOneWidget);
    expect(find.text('123 Main Street'), findsNothing);
    expect(find.text('Choose a location or enter an address.'), findsOneWidget);
  });

  testWidgets(
    'street search submits private coordinates and address edit clears them',
    (tester) async {
      final drafts = <RequestDraft>[];
      await _pump(
        tester,
        ApprovedRequestFlowPage(
        questionLoader: _noQuestions,
          homeAddress: const PostalAddress(
            line1: 'Saved test address',
            country: 'US',
          ),
          accent: const Color(0xff1917ff),
          requestTitle: 'Mapped request',
          places:PlacesRepository(transport:_BuyerAddressPlaces()),
          categories: const [CatalogueCategoryOption(id: '20000000-0000-4000-8000-000000000001',label: 'Electronics',scope: 'product',status: 'active')],
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
  if (find.text('Select a category').evaluate().isNotEmpty) {
    final category = find.byKey(const Key('approved-request-category-select'));
    await tester.ensureVisible(category); await tester.pumpAndSettle();
    await tester.tap(category); await tester.pumpAndSettle();
    await tester.tap(find.text('Electronics').last); await tester.pumpAndSettle();
  }
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('requestChooseMapLocation')),findsNothing);
      await tester.ensureVisible(find.text('Enter a different address'));
      await tester.tap(find.text('Enter a different address'));
      await tester.pumpAndSettle();
      final street=find.byKey(const Key('approved-request-address-street-address'));
      await tester.ensureVisible(street);
      await tester.tap(street);
      const composing=TextEditingValue(text:'Selected meet',selection:TextSelection.collapsed(offset:8),composing:TextRange(start:0,end:13));
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      final streetController=tester.widget<TextFormField>(street).controller!;
      expect(streetController.value,composing);
      await tester.enterText(street,'Selected meeting');
      await tester.pump(const Duration(milliseconds:400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('buyerAddress-buyer-place')));
      await tester.tap(find.byKey(const ValueKey('buyerAddress-buyer-place')));
      await tester.pumpAndSettle();
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
      expect(drafts.single.location.timezoneId,'America/Chicago');
      final address = find.byKey(
        const Key('approved-request-address-street-address'),
      );
      await tester.ensureVisible(address);
      await tester.enterText(address, 'Manual replacement');
      await tester.pumpAndSettle();
      await _tapPost(tester);
      expect(drafts.last.location.coordinates?.latitude, 40.9);
      expect(drafts.last.location.timezoneId, 'America/Chicago');
      expect(drafts.last.location.address?.line1, 'Manual replacement');
      expect(drafts.last.location.address?.city, 'Chicago');
      expect(drafts.last.location.address?.state, 'IL');
      final submitted = drafts.length;
      await tester.ensureVisible(address);
      await tester.enterText(address, 'Unresolvable address');
      await tester.pumpAndSettle();
      await _tapPost(tester);
      expect(drafts.length, submitted);
      expect(find.textContaining('We could not confirm this address'), findsOneWidget);
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
        questionLoader: _noQuestions,
        homeAddress: const PostalAddress(
          line1: 'Unresolvable address already selected in popup',
          country: 'US',
        ),
        homeCoordinates: RequestCoordinates(latitude: 43.07, longitude: -89.4),
        homeTimezoneId: 'America/Chicago',
        places: PlacesRepository(transport: _BuyerAddressPlaces()),
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
    expect(draft.location.coordinates?.latitude, 43.07);
    expect(draft.location.coordinates?.longitude, -89.4);
    expect(draft.location.timezoneId, 'America/Chicago');
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
        questionLoader: _noQuestions,
        categories: const [CatalogueCategoryOption(id: '20000000-0000-4000-8000-000000000001',label: 'Electronics',scope: 'product',status: 'active')],
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
        questionLoader: _noQuestions,
        categories: const [CatalogueCategoryOption(id: '20000000-0000-4000-8000-000000000001',label: 'Electronics',scope: 'product',status: 'active')],
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
    await tester.ensureVisible(find.text('Enter a different address'));
    await tester.tap(find.text('Enter a different address'));
    await tester.pumpAndSettle();
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
        questionLoader: _noQuestions,
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
        questionLoader: _noQuestions,
        categories: const [CatalogueCategoryOption(id: '20000000-0000-4000-8000-000000000001',label: 'Electronics',scope: 'product',status: 'active')],
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(submitted, isFalse);
    expect(find.text('Add a clear request title.'), findsOneWidget);
    expect(find.byKey(const Key('approvedRequestPostButton')), findsNothing);
  });

  testWidgets('accepted request locks edits and keeps deals reachable', (tester) async {
    var opened = false;
    await _pump(tester, ApprovedBuyerRequestDetailsPage(
      questionLoader: _noQuestions, accent: const Color(0xff1917ff),
      requestTitle: 'Accepted request', budget: 'Budget', onBack: () {},
      includeAppChrome: true,
      onNotifications: () {}, onOffers: () => opened = true,
      request: _request().copyWith(firstAcceptedAt: DateTime.utc(2026, 10, 31)),
      onUpdateRequest: (_, _) async => throw StateError('must not update'),
    ));
    expect(find.byKey(const Key('save-request-changes')), findsNothing);
    expect(find.byKey(const Key('request-edit-locked')), findsOneWidget);
    expect(find.ancestor(of: find.byKey(const Key('request-title-field')),
      matching: find.byWidgetPredicate((w) => w is AbsorbPointer && w.absorbing)), findsOneWidget);
    final offers = find.byKey(const Key('realRequestReviewOffers'));
    await tester.ensureVisible(offers); await tester.pumpAndSettle();
    await tester.tap(offers); await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('edit policy rejects terminal states and elapsed expiry', () {
    final now = DateTime.utc(2026, 10, 31);
    expect(_request().canEditAt(now), isTrue);
    for (final status in [RequestStatus.closed, RequestStatus.expired, RequestStatus.cancelled]) {
      expect(_request(status: status).canEditAt(now), isFalse);
    }
    expect(_request().copyWith(acceptanceExpiresAt: now).canEditAt(now), isFalse);
    expect(_request().copyWith(firstAcceptedAt: now).canEditAt(now), isFalse);
    expect(_request().copyWith(purchaseOfferId: 'selected').canEditAt(now), isFalse);
  });

  testWidgets('closed request is read-only and keeps offers reachable', (tester) async {
    var offersOpened = false;
    var recoveryOpened = false;
    await _pump(tester, ApprovedBuyerRequestDetailsPage(
      questionLoader: _noQuestions, accent: const Color(0xff1917ff),
      requestTitle: 'Closed request', budget: 'Budget', onBack: () {},
      includeAppChrome: true,
      onNotifications: () {}, onOffers: () => offersOpened = true,
      onRecovery: () => recoveryOpened = true,
      request: _request(status: RequestStatus.closed),
      onUpdateRequest: (_, _) async => throw StateError('must not update'),
    ));
    expect(find.byKey(const Key('save-request-changes')), findsNothing);
    expect(find.text('This request is read-only. Its offers and conversations are kept.'), findsOneWidget);
    final field = find.byKey(const Key('request-title-field'));
    expect(find.ancestor(of: field, matching: find.byWidgetPredicate(
      (widget) => widget is AbsorbPointer && widget.absorbing,
    )), findsOneWidget);
    final offers = find.byKey(const Key('realRequestReviewOffers'));
    await tester.ensureVisible(offers);
    await tester.pumpAndSettle();
    await tester.tap(offers);
    await tester.pumpAndSettle();
    expect(offersOpened, isTrue);
    final recovery = find.byKey(const Key('request-recovery-options'));
    await tester.ensureVisible(recovery);
    await tester.pumpAndSettle();
    await tester.tap(recovery);
    expect(recoveryOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a legacy home request resolves coordinates without changing home choice', (tester) async {
    RequestDraft? saved;
    var resolutions = 0;
    await _pump(tester, ApprovedBuyerRequestDetailsPage(
      questionLoader: _noQuestions, accent: const Color(0xff1917ff),
      requestTitle: 'Home request', budget: 'Budget', includeAppChrome: true,
      onBack: () {}, onNotifications: () {}, onOffers: () {}, request: _request(),
      onResolveHomeLocation: () async {
        resolutions++;
        return RequestLocation.homeAddress(coordinates: RequestCoordinates(latitude: 40.6, longitude: -74.4), timezoneId: 'America/New_York');
      },
      onUpdateRequest: (draft, _) async { saved = draft; return RequestSubmissionResult.success(_request().copyWith(draft: draft)); },
    ));
    final save = find.byKey(const Key('save-request-changes'));
    await tester.ensureVisible(save); await tester.pumpAndSettle(); await tester.tap(save); await tester.pumpAndSettle();
    await tester.tap(find.text('Update request')); await tester.pumpAndSettle();
    expect(resolutions, 1); expect(saved!.location.useHomeAddress, true);
    expect(saved!.location.coordinates!.latitude, 40.6); expect(saved!.location.address, isNull);
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
        questionLoader: _noQuestions,
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
    final minimum = find.byKey(const ValueKey('approved-request-budget-min'));
    final maximum = find.byKey(const ValueKey('approved-request-budget-max'));
    await tester.ensureVisible(minimum);
    await tester.enterText(minimum, '375.25');
    await tester.enterText(maximum, '500.50');

    final saveAction = find.byKey(const Key('save-request-changes'));
    await tester.ensureVisible(saveAction);
    await tester.pumpAndSettle();
    await tester.tap(saveAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update request'));
    await tester.pumpAndSettle();

    expect(drafts.single.title, 'iPad Pro, 11-inch');
    expect(drafts.single.budget.minimum!.minorUnits, 37525);
    expect(drafts.single.budget.maximum!.minorUnits, 50050);
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
        questionLoader: _noQuestions,
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
