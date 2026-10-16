// Seller leads connection tests: real leads rendering, loading/error states,
// projection mapping and real offer submission with timezone handling.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';

import 'test_fonts.dart';

Offer _offer({RepeatedTimeOccurrence? occurrence}) => Offer(
  id: '40000000-0000-4000-8000-000000000001',
  requestId: '30000000-0000-4000-8000-000000000001',
  buyerUserId: 'user-a',
  sellerProfileId: '10000000-0000-4000-8000-00000000000b',
  sellerUserId: 'user-b',
  revisions: [
    OfferRevision(
      id: '41000000-0000-4000-8000-000000000001',
      offerId: '40000000-0000-4000-8000-000000000001',
      sequence: 1,
      terms: OfferTerms(
        price: Money(minorUnits: 2500, currencyCode: 'USD'),
        schedule: LocalSchedule(
          date: LocalDate(year: 2026, month: 10, day: 1),
          startTime: LocalTime(hour: 15, minute: 0),
          timezoneId: 'America/New_York',
          occurrence: occurrence,
        ),
        place: MeetingPlace(
          choice: MeetupPlaceChoice.sellerBusiness,
          label: 'Northside Tech business location',
        ),
      ),
      status: OfferRevisionStatus.proposed,
      proposedByUserId: 'user-b',
      createdAt: DateTime.utc(2026, 5, 1),
    ),
  ],
  status: OfferStatus.submitted,
  stamp: RecordStamp(
    revision: 1,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  ),
);

SellerLeadView view({
  String requestId = '30000000-0000-4000-8000-000000000001',
  String request = 'Synthetic request',
  String initials = 'BA',
  String? categoryId,
}) => SellerLeadView(
  requestId: requestId,
  requestRevision: 3,
  categoryId: categoryId,
  name: 'Buyer A',
  initials: initials,
  city: 'Yonkers, NY',
  distance: '—',
  request: request,
  description: 'Synthetic details',
  budget: r'$350 – $480',
  match: 0,
  purchases: 0,
  lastPurchase: '—',
  meeting: 'Public place',
  avatarColor: const Color(0xFFF0EDFF),
  initialColor: const Color(0xFF1717D5),
);

Future<void> pumpLeads(
  WidgetTester tester,
  Widget child, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> openOfferSheet(WidgetTester tester) async {
  await tester.tap(find.text('Prepare offer').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('sellerOfferPrice')), '550');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> selectNewYorkTimezone(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('sellerOfferTimezone')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sellerOfferTimezone')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('America/New_York').last);
  await tester.pumpAndSettle();
}

Future<void> tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('sellerSendOfferSubmit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('an unavailable refreshed lead never opens the offer form', (
    tester,
  ) async {
    var checks = 0;
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onValidateLead: (_) async {
          checks++;
          return null;
        },
      ),
    );
    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(find.byKey(const Key('sellerLeadUnavailable')), findsOneWidget);
    expect(find.byKey(const Key('sellerSendOfferSubmit')), findsNothing);
  });

  testWidgets('real leads replace the prototype list', (tester) async {
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(leads: [view()], onRefreshLeads: () {}),
    );
    expect(find.text('Synthetic request'), findsOneWidget);
    expect(find.text('Looking for iPad Air (5th gen)'), findsNothing);
  });

  testWidgets('real leads filter by admin-managed category ids', (
    tester,
  ) async {
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [
          view(categoryId: 'cat-electronics'),
          view(
            requestId: '30000000-0000-4000-8000-000000000002',
            request: 'Synthetic service request',
            initials: 'SS',
            categoryId: 'cat-services',
          ),
        ],
        categories: const [
          StoreCategoryOption(
            id: 'cat-electronics',
            label: 'Electronics',
            scope: 'both',
            status: 'active',
          ),
          StoreCategoryOption(
            id: 'cat-services',
            label: 'Services',
            scope: 'both',
            status: 'active',
          ),
          StoreCategoryOption(
            id: 'cat-retired',
            label: 'Retired category',
            scope: 'both',
            status: 'retired',
          ),
        ],
        onRefreshLeads: () {},
        onRefreshCategories: () {},
      ),
    );
    expect(find.text('Tablets'), findsNothing);
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    expect(find.text('Retired category'), findsNothing);
    await tester.tap(find.text('Electronics').last);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic request'), findsOneWidget);
    expect(find.text('Synthetic service request'), findsNothing);
  });

  testWidgets('real leads hide the category filter without a catalogue', (
    tester,
  ) async {
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(leads: [view()], onRefreshLeads: () {}),
    );
    expect(find.text('Category'), findsNothing);
    expect(find.text('Tablets'), findsNothing);
  });

  testWidgets('loading and error states are visible with retry', (
    tester,
  ) async {
    var retries = 0;
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: const [],
        leadsLoading: true,
        leadsError: 'Could not load buyer requests. Pull to retry.',
        onRefreshLeads: () => retries += 1,
      ),
      settle: false,
    );
    expect(find.byKey(const Key('sellerLeadsLoading')), findsOneWidget);
    expect(find.byKey(const Key('sellerLeadsError')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerLeadsRetry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(retries, 1);
  });

  testWidgets('real offers require a chosen timezone then submit', (
    tester,
  ) async {
    final submitted = <OfferTerms>[];
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onSubmitOffer: (lead, terms, key) async {
          submitted.add(terms);
          return OfferSubmissionResult.success(_offer());
        },
      ),
    );
    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: find.byKey(const Key('sellerOfferSpecificLocation')),
              matching: find.byType(TextButton),
            ),
          )
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    expect(find.text('Your Pro Plan'), findsNothing);
    expect(find.textContaining(r'$1.90'), findsNothing);
    expect(find.textContaining('256GB'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('sellerSendOfferBottomSheet')),
        matching: find.text('Buyer A  ✓'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sellerOfferPrice')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(find.byKey(const Key('sellerOfferPrice')), '550');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerOfferSubmitError')), findsOneWidget);
    expect(submitted, isEmpty);

    await tester.ensureVisible(find.byKey(const Key('sellerOfferTimezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerOfferTimezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('America/New_York').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerOfferTimezoneConfirmation')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();

    expect(submitted, hasLength(1));
    expect(submitted.single.schedule.timezoneId, 'America/New_York');
    expect(find.byKey(const Key('sellerOfferSubmittedNotice')), findsOneWidget);
  });

  testWidgets('specific location opens through keyboard activation', (
    tester,
  ) async {
    var picks = 0;
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        onChooseSpecificLocation: (_) async {
          picks += 1;
          return null;
        },
      ),
    );
    await openOfferSheet(tester);
    final launcher = find.byKey(const Key('sellerOfferSpecificLocation'));
    await tester.ensureVisible(launcher);
    await tester.pumpAndSettle();
    final button = find.descendant(
      of: launcher,
      matching: find.byType(TextButton),
    );
    expect(button, findsOneWidget);
    final label = find.descendant(
      of: button,
      matching: find.text('Choose a specific location'),
    );
    Focus.of(tester.element(label)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeated local time asks for the occurrence', (tester) async {
    var attempts = 0;
    final occurrences = <RepeatedTimeOccurrence?>[];
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onSubmitOffer: (lead, terms, key) async {
          attempts += 1;
          if (attempts == 1) {
            return const OfferSubmissionResult.failure(
              'This local time happens twice. Choose which occurrence applies.',
              ambiguousTime: true,
            );
          }
          occurrences.add(terms.schedule.occurrence);
          return OfferSubmissionResult.success(
            _offer(occurrence: terms.schedule.occurrence),
          );
        },
      ),
    );
    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sellerOfferPrice')), '550');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sellerOfferTimezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerOfferTimezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('America/New_York').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerOfferOccurrenceChooser')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sellerOfferOccurrenceEarlier')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();

    expect(occurrences, [RepeatedTimeOccurrence.earlier]);
    expect(find.byKey(const Key('sellerOfferSubmittedNotice')), findsOneWidget);
  });

  testWidgets('an uncertain outcome keeps its payload and key for retry', (
    tester,
  ) async {
    final keys = <String>[];
    final termsList = <OfferTerms>[];
    var firstAttempt = true;
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onSubmitOffer: (lead, terms, key) async {
          keys.add(key);
          termsList.add(terms);
          if (firstAttempt) {
            firstAttempt = false;
            return const OfferSubmissionResult.failure(
              'The offer could not be confirmed. Retry to check it safely.',
              outcomeUncertain: true,
            );
          }
          return OfferSubmissionResult.success(_offer());
        },
      ),
    );
    await openOfferSheet(tester);
    await selectNewYorkTimezone(tester);
    await tapSubmit(tester);

    expect(find.byKey(const Key('sellerOfferRetry')), findsOneWidget);
    expect(find.byKey(const Key('sellerOfferDiscard')), findsOneWidget);
    expect(keys, hasLength(1));

    await tester.tap(find.byKey(const Key('sellerOfferRetry')));
    await tester.pumpAndSettle();

    expect(keys, hasLength(2));
    expect(keys[1], keys[0]);
    expect(termsList[1], termsList[0]);
    expect(find.byKey(const Key('sellerOfferSubmittedNotice')), findsOneWidget);
  });

  testWidgets('a changed intent must discard the unresolved key first', (
    tester,
  ) async {
    final keys = <String>[];
    final prices = <Money>[];
    var firstAttempt = true;
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onSubmitOffer: (lead, terms, key) async {
          keys.add(key);
          prices.add(terms.price);
          if (firstAttempt) {
            firstAttempt = false;
            return const OfferSubmissionResult.failure(
              'The offer could not be confirmed. Retry to check it safely.',
              outcomeUncertain: true,
            );
          }
          return OfferSubmissionResult.success(_offer());
        },
      ),
    );
    await openOfferSheet(tester);
    await selectNewYorkTimezone(tester);
    await tapSubmit(tester);
    expect(keys, hasLength(1));

    await tester.ensureVisible(find.byKey(const Key('sellerOfferPrice')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sellerOfferPrice')), '700');
    await tester.pumpAndSettle();
    await tapSubmit(tester);

    expect(keys, hasLength(1), reason: 'changed intent must not reuse the key');
    expect(find.textContaining('may already have been sent'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('sellerOfferDiscard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerOfferDiscard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerOfferRetry')), findsNothing);

    await tapSubmit(tester);
    expect(keys, hasLength(2));
    expect(keys[1], isNot(keys[0]));
    expect(prices.last.minorUnits, 70000);
  });

  testWidgets('real offers do not fabricate product image uploads', (
    tester,
  ) async {
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onSubmitOffer: (lead, terms, key) async =>
            OfferSubmissionResult.success(_offer()),
      ),
    );
    await openOfferSheet(tester);
    final button = find.byKey(const Key('sellerOfferAddImages'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.textContaining('sent without images'), findsOneWidget);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerOfferImagePickerSheet')), findsNothing);
    expect(find.byKey(const Key('sellerOfferImagesEmpty')), findsOneWidget);
  });

  testWidgets('prototype mode keeps the placeholder image picker', (
    tester,
  ) async {
    await pumpLeads(tester, const ApprovedSellerLeadsPage());
    await openOfferSheet(tester);
    final button = find.byKey(const Key('sellerOfferAddImages'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerOfferImageLibrary')));
    await tester.pumpAndSettle();
    expect(find.text('iPad-product-library.jpg'), findsOneWidget);
  });

  testWidgets('projection mapping keeps identity and formats budget', (
    tester,
  ) async {
    final mapped = SellerLeadView.fromProjection(
      SellerLeadProjection(
        requestId: '30000000-0000-4000-8000-000000000009',
        kind: RequestKind.product,
        title: 'iPad Air',
        description: 'Good condition',
        quantity: 1,
        budget: MoneyRange(
          minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
          maximum: Money(minorUnits: 48050, currencyCode: 'USD'),
        ),
        buyerProfileId: '10000000-0000-4000-8000-00000000000a',
        buyerDisplayName: 'Maya Chen',
        areaLabel: 'Yonkers, NY',
        requestRevision: 4,
        acceptsHigherOffers: true,
      ),
    );
    expect(mapped.requestId, '30000000-0000-4000-8000-000000000009');
    expect(mapped.requestRevision, 4);
    expect(mapped.acceptsHigherOffers, isTrue);
    expect(mapped.initials, 'MC');
    expect(mapped.budget, r'$350 – $480.50');
    expect(mapped.request, 'iPad Air');
  });
}
