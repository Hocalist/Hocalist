// Seller leads connection tests: real leads rendering, loading/error states,
// projection mapping and real offer submission with timezone handling.
import 'dart:async';
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
  String? buyerLocationTimezone,
}) => SellerLeadView(
  requestId: requestId,
  requestRevision: 3,
  categoryId: categoryId,
  buyerLocationTimezone: buyerLocationTimezone,
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
  await tester.ensureVisible(find.text('Prepare offer').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Prepare offer').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('sellerOfferPrice')));
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
  for(final width in [320.0,360.0,390.0,430.0]) {
    for(final scale in [1.0,1.15,1.3,1.6]) {
      testWidgets('offer fee breakdown fits $width at $scale',(tester)async{
        tester.view.physicalSize=Size(width,900);
        tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),
          home:Scaffold(body:ApprovedSellerLeadsPage(leads:[view()],
            offerPresentation:const SellerOfferPresentation.real(planLabel:'Free · Wallet rates',
              initialBid:'1.85 HC',winningBid:'4.50 HC',remainingWinningBid:'2.65 HC',
              rateHint:'Your deposit keeps the rates saved when it was added.'))),
        ));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Prepare offer'),250,
          scrollable:find.byWidgetPredicate((widget)=>widget is Scrollable&&widget.axisDirection==AxisDirection.down).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Prepare offer').first);
        await tester.pumpAndSettle();
        expect(find.text('Initial bid 1.85 HC'),findsOneWidget);
        expect(find.text('Winning total 4.50 HC'),findsOneWidget);
        expect(find.text('At purchase 2.65 HC'),findsNothing);
        expect(tester.takeException(),isNull);
      });
    }
  }
  testWidgets(
    'automatic timezone uses the saved business location without a picker',
    (tester) async {
      final submitted = <OfferTerms>[];
      await pumpLeads(
        tester,
        ApprovedSellerLeadsPage(
          leads: [view()],
          onRefreshLeads: () {},
          automaticTimezone: true,
          readBusinessAddress: () => 'TEST Chicago business',
          resolveBusinessPlace: (_) async => const SellerOfferPlace(
            name: 'TEST business',
            address: 'TEST Chicago address',
            timezoneId: 'America/Chicago',
          ),
          onSubmitOffer: (lead, terms, key) async {
            submitted.add(terms);
            return OfferSubmissionResult.success(_offer());
          },
        ),
      );
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetViewPadding);
      await openOfferSheet(tester);
      expect(find.byKey(const Key('sellerOfferTimezone')), findsNothing);
      expect(find.text('Meeting timezone: America/Chicago'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('sellerSendOfferCancel')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomRight(find.byKey(const Key('sellerSendOfferCancel')))
            .dy,
        lessThan(844 - 48),
      );
      await tapSubmit(tester);
      expect(submitted.single.schedule.timezoneId, 'America/Chicago');
      expect(submitted.single.place.address, 'TEST Chicago address');
    },
  );

  testWidgets(
    'buyer location shows shared area and supplies its saved timezone',
    (tester) async {
      final submitted = <OfferTerms>[];
      await pumpLeads(
        tester,
        ApprovedSellerLeadsPage(
          leads: [view(buyerLocationTimezone: 'America/New_York')],
          offerTimezones: const ['America/New_York'],
          onRefreshLeads: () {},
          onSubmitOffer: (lead, terms, key) async {
            submitted.add(terms);
            return OfferSubmissionResult.success(_offer());
          },
        ),
      );
      await openOfferSheet(tester);
      final choice = find.byKey(const Key('sellerMeetupBuyer'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Yonkers, NY. Exact address shared after selection.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Times are scheduled in America/New_York'),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(320, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapSubmit(tester);
      expect(submitted.single.place.choice, MeetupPlaceChoice.buyerLocation);
      expect(submitted.single.place.label, 'Yonkers, NY');
      expect(submitted.single.place.address, isNull);
      expect(submitted.single.schedule.timezoneId, 'America/New_York');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an existing active offer disables a second offer form', (
    tester,
  ) async {
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        offeredRequestIds: {view().requestId!},
        onRefreshLeads: () {},
      ),
    );
    expect(find.text('Offer sent'), findsOneWidget);
    expect(find.text('Prepare offer'), findsNothing);
    expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsNothing);
  });

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
    expect(find.text('Offer sent'), findsOneWidget);
    expect(find.text('Prepare offer'), findsNothing);
  });

  testWidgets('selected place automatically fills the meeting timezone', (
    tester,
  ) async {
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onChooseSpecificLocation: (_) async => const SellerOfferPlace(
          name: 'Synthetic meeting place',
          address: 'Synthetic address',
          timezoneId: 'America/New_York',
        ),
        onSubmitOffer: (lead, terms, key) async =>
            OfferSubmissionResult.success(_offer()),
      ),
    );
    await openOfferSheet(tester);
    final launcher = find.byKey(const Key('sellerOfferSpecificLocation'));
    await tester.ensureVisible(launcher);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: launcher, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Times are scheduled in America/New_York'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel during submission ignores a late successful response', (
    tester,
  ) async {
    final completion = Completer<OfferSubmissionResult>();
    await pumpLeads(
      tester,
      ApprovedSellerLeadsPage(
        leads: [view()],
        onRefreshLeads: () {},
        offerTimezones: const ['America/New_York'],
        onSubmitOffer: (lead, terms, key) => completion.future,
      ),
    );
    await openOfferSheet(tester);
    await selectNewYorkTimezone(tester);
    await tapSubmit(tester);
    await tester.ensureVisible(find.byKey(const Key('sellerSendOfferClose')));
    await tester.tap(find.byKey(const Key('sellerSendOfferClose')));
    await tester.pump(const Duration(milliseconds: 1));
    completion.complete(OfferSubmissionResult.success(_offer()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ApprovedSellerLeadsPage), findsOneWidget);
    expect(find.byKey(const Key('sellerOfferSubmittedNotice')), findsNothing);
  });

  testWidgets(
    'first successful submission closes safely with a focused input',
    (tester) async {
      final completion = Completer<OfferSubmissionResult>();
      await pumpLeads(
        tester,
        ApprovedSellerLeadsPage(
          leads: [view()],
          onRefreshLeads: () {},
          offerTimezones: const ['America/New_York'],
          onSubmitOffer: (lead, terms, key) => completion.future,
        ),
      );
      await openOfferSheet(tester);
      await selectNewYorkTimezone(tester);
      await tester.enterText(
        find.byKey(const Key('sellerOfferMessage')),
        'Synthetic offer',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('sellerSendOfferSubmit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
      await tester.pump();
      completion.complete(OfferSubmissionResult.success(_offer()));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sellerOfferSubmittedNotice')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejected offer can close without an inherited-widget assertion',
    (tester) async {
      await pumpLeads(
        tester,
        ApprovedSellerLeadsPage(
          leads: [view()],
          onRefreshLeads: () {},
          offerTimezones: const ['America/New_York'],
          onSubmitOffer: (lead, terms, key) async =>
              const OfferSubmissionResult.failure(
                'This request changed. Refresh and try again.',
              ),
        ),
      );
      await openOfferSheet(tester);
      await selectNewYorkTimezone(tester);
      await tapSubmit(tester);
      expect(find.byKey(const Key('sellerOfferSubmitError')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('sellerSendOfferClose')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sellerSendOfferClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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

    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('sellerOfferOccurrenceEarlier'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
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
