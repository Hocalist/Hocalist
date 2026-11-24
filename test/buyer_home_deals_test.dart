import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/features/approved/buyer_deal_card.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'test_fonts.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'visual_proof_capture.dart';

final _now = DateTime.utc(2030, 11, 20);
Offer _offer(String id, {bool newerProposal = false, OfferStatus status = OfferStatus.selected}) {
  final terms = OfferTerms(price: Money(minorUnits: 65000, currencyCode: 'USD'), message: 'Includes charger.',
    schedule: LocalSchedule(date: LocalDate(year: 2030, month: 11, day: 23), startTime: LocalTime(hour: 15, minute: 0), timezoneId: 'America/Chicago'),
    place: MeetingPlace(choice: MeetupPlaceChoice.sellerBusiness, label: 'Business address'));
  return Offer(id: id, requestId: 'request-$id', buyerUserId: 'buyer', sellerUserId: 'seller', sellerProfileId: 'seller-profile',
    sellerDisplayName: 'Jonathan Sanchez', requestTitle: 'iPad Air 5th Gen (64GB)',
    status: status, conversationId: status == OfferStatus.submitted ? null : 'chat-$id',
    acceptedRevisionId: status == OfferStatus.submitted ? null : 'accepted-$id',
    stamp: RecordStamp(revision: 2, createdAt: _now, updatedAt: _now),
    revisions: [OfferRevision(id: 'accepted-$id', offerId: id, sequence: 1, terms: terms,
      status: OfferRevisionStatus.accepted, proposedByUserId: 'seller', createdAt: _now),
      if (newerProposal) OfferRevision(id: 'new-$id', offerId: id, sequence: 2,
        terms: terms.copyWith(price: Money(minorUnits: 90000, currencyCode: 'USD')), status: OfferRevisionStatus.proposed,
        proposedByUserId: 'seller', createdAt: _now)]);
}

MeetingView _meeting({MeetingScheduleView? accepted, MeetingScheduleView? pending, String status = 'accepted'}) {
  final schedule = MeetingScheduleView(sequence: 1, date: LocalDate(year: 2030, month: 11, day: 23), startTime: LocalTime(hour: 15, minute: 0),
    timezoneId: 'America/Chicago', offsetMinutes: -360, instant: DateTime.utc(2030, 11, 23, 21),
    placeChoice: 'seller_business', placeLabel: 'Business address',
    placeAddress: '112 N Green St, Chicago, IL 60607, USA',
    proposedByUserId: 'seller', status: 'accepted', createdAt: _now);
  return MeetingView(meetingId: 'meeting', conversationId: 'chat-agreed', requestId: 'request-agreed', offerId: 'agreed',
    buyerUserId: 'buyer', sellerUserId: 'seller', status: status, revision: 2,
    purchaseSelected: true, acceptedSchedule: accepted ?? schedule, pendingSchedule: pending,
    revisions: [accepted ?? schedule, if (pending != null) pending],
    meetingExpiresAt: DateTime.utc(2030, 11, 24, 6));
}

void main() {
  testWidgets('cancelled meeting stays out of both active Home sections', (t) async {
    await t.pumpWidget(MaterialApp(home: ApprovedBuyerHomePage(
      name: 'Buyer', requestTitle: '', requestPosted: false,
      onCreate: () {}, onRequestDetails: () {}, onOffers: () {}, onRecentActivity: () {}, onWallet: () {},
      realRequests: const [], realMeetings: [_meeting(status: 'cancelled')],
      homeOffers: [_offer('agreed')],
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-negotiation-agreed')), findsNothing);
    expect(find.text('Accept offer and meet'), findsNothing);
    expect(find.text('No upcoming meetings yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('a newly received offer appears on Home before chat starts', (t) async {
    Offer? opened;
    t.view.physicalSize = const Size(390, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Nunito'), home: ApprovedBuyerHomePage(
      name: 'Buyer', requestTitle: '', requestPosted: false,
      onCreate: () {}, onRequestDetails: () {}, onOffers: () {}, onRecentActivity: () {}, onWallet: () {},
      realRequests: const [], realMeetings: const [],
      homeOffers: [_offer('new', status: OfferStatus.submitted), _offer('closed', status: OfferStatus.declined)],
      onOpenNegotiation: (offer) => opened = offer,
      onAcceptNegotiation: (_) {}, onNegotiationOptions: (_) {},
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-negotiation-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-negotiation-closed')), findsNothing);
    expect(find.text('Accept offer and meet'), findsOneWidget);
    await t.ensureVisible(find.byTooltip('Chat with seller'));
    await t.tap(find.byTooltip('Chat with seller'));
    expect(opened?.id, 'new');
    expect(opened?.conversationId, isNull);
    expect(t.takeException(), isNull);
  });
  setUpAll(() async {
    await loadHocalistTestFonts();
    if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE')) {
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  test('participant address wins over generic label; missing address stays safe', () {
    final view = BuyerOfferView.fromOffer(_offer('agreed'), meeting: _meeting());
    expect(view.placeLabel, '112 N Green St, Chicago, IL 60607, USA');
    expect(BuyerOfferView.formatPlaceLabel(address: ' ', label: 'Business address'), 'Business address');
    expect(BuyerOfferView.formatPlaceLabel(), 'View meeting location');
  });
  test('agreed view keeps accepted price when a new revision is proposed', () {
    final offer = _offer('agreed', newerProposal: true);
    expect(BuyerOfferView.fromOffer(offer).priceLabel, r'$900');
    expect(BuyerOfferView.fromOffer(offer, agreedTerms: true).priceLabel, r'$650');
  });
  test('cards follow agreed rescheduling and ignore an unaccepted proposal', () {
    MeetingScheduleView schedule(int day, int hour, String status) => MeetingScheduleView(
      sequence: day, date: LocalDate(year: 2030, month: 11, day: day),
      startTime: LocalTime(hour: hour, minute: 0), timezoneId: 'America/Chicago',
      offsetMinutes: -360, instant: DateTime.utc(2030, 11, day, hour + 6),
      placeChoice: 'specific_place', placeLabel: 'Agreed location', latitude: 0, longitude: 1,
      proposedByUserId: 'buyer', status: status, createdAt: _now);
    final offer = _offer('agreed');
    final accepted = schedule(24, 16, 'accepted');
    final proposed = schedule(25, 17, 'proposed');
    final waiting = BuyerOfferView.fromOffer(offer, agreedTerms: true,
      meeting: _meeting(pending: proposed));
    expect(waiting.meetingLabel, contains('3:00 PM'));
    expect(waiting.meetingLabel, isNot(contains('5:00 PM')));
    final revised = BuyerOfferView.fromOffer(offer, agreedTerms: true,
      meeting: _meeting(accepted: accepted, pending: proposed),
      origin: RequestCoordinates(latitude: 0, longitude: 0));
    expect(revised.meetingLabel, contains('Nov 24'));
    expect(revised.meetingLabel, contains('4:00 PM'));
    expect(revised.placeLabel, 'Agreed location');
    expect(revised.distanceLabel, '~69.1 mi away');
    expect(BuyerOfferView.fromOffer(offer, meeting: _meeting(accepted: accepted)).distanceLabel, isNull);
    final otherDeal = BuyerOfferView.fromOffer(_offer('other'), meeting: _meeting(accepted: accepted));
    expect(otherDeal.meetingLabel, contains('3:00 PM'));
    expect(otherDeal.placeLabel, isNot('Agreed location'));
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        testWidgets('home deals and meeting fit $platform $width/$scale and keep actions scoped', (t) async {
          t.view.devicePixelRatio = 1; t.view.physicalSize = Size(width, 2400);
          addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
          String? accepted, chatted, mapped, called, messaged;
          await t.pumpWidget(MaterialApp(theme: ThemeData(platform: platform, fontFamily: 'Nunito'),
            home: MediaQuery(data: MediaQueryData(size: Size(width, 2400), textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: const Key('home-deals-proof'), child: ApprovedBuyerHomePage(
                name: 'Alex', requestTitle: 'iPad', requestPosted: false,
                onCreate: () {}, onRequestDetails: () {}, onOffers: () {}, onRecentActivity: () {}, onWallet: () {},
                realRequests: const [], realMeetings: [_meeting()],
                homeOffers: [_offer('negotiating', newerProposal: true), _offer('agreed', newerProposal: true)],
                loadDealSeller: (_) => SynchronousFuture(const BuyerDealSeller(verified: true, rating: 4.9, reviewCount: 128, sales: 42)),
                onOpenNegotiation: (o) => chatted = o.id, onAcceptNegotiation: (o) => accepted = o.id,
                onNegotiationOptions: (_) {}, onOpenMeeting: (_) {},
                onMeetingDirections: (m) => mapped = m.meetingId,
                onMeetingCall: (m) => called = m.meetingId,
                onMeetingMessage: (m) => messaged = m.meetingId,
              )))));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('Deals in progress'), findsOneWidget);
          expect(find.text('112 N Green St, Chicago, IL 60607, USA'), findsOneWidget);
          expect(find.byWidgetPredicate((w) => w is BuyerAssetIcon && w.asset.endsWith('/meeting-map.png')), findsOneWidget);
          final sectionLinks = t.widgetList<Text>(find.text('View all')).toList();
          expect(sectionLinks.length, greaterThanOrEqualTo(3));
          for (final link in sectionLinks.skip(1)) {
            expect(link.style, sectionLinks.first.style,
              reason: 'All Home section links must use the same approved typography.');
          }
          expect(find.text('Accept offer and meet'), findsOneWidget);
          expect(find.text(r'$900'), findsNothing);
          await t.ensureVisible(find.text('Accept offer and meet'));
          await t.tap(find.text('Accept offer and meet')); expect(accepted, 'negotiating');
          await t.tap(find.byTooltip('Chat with seller')); expect(chatted, 'negotiating');
          for (final label in ['Maps', 'Call', 'Message']) {
            await t.ensureVisible(find.text(label)); await t.tap(find.text(label));
          }
          expect(mapped, 'meeting'); expect(called, 'meeting'); expect(messaged, 'meeting');
          expect(t.takeException(), isNull);
          if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE')) {
            if (platform == TargetPlatform.android && scale == 1) {
              await t.ensureVisible(find.text('Deals in progress'));
              await t.pumpAndSettle();
              await writeProofImage(t, find.byKey(const Key('home-deals-proof')), 'buyer-home-deals-${width.toInt()}.png');
            }
          }
        });
      }
    }
  }
}
