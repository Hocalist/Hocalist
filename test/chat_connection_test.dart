// Chat connection tests: real inbox rows, real history bubbles and mute/send
// state on the approved conversation body. Fakes only.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/chat/chat_codecs.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/media_reference.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';

import 'test_fonts.dart';
import 'phase2/marketplace/support/marketplace_fakes.dart' as marketplace;

ChatThreadView _thread({
  String conversationId = '60000000-0000-4000-8000-000000000001',
  String name = 'Seller B',
  String preview = 'Can meet tomorrow.',
  int unread = 0,
  bool muted = false,
}) => ChatThreadView(
  conversationId: conversationId,
  counterpartName: name,
  initials: 'SB',
  preview: preview,
  timeLabel: '9:30 AM',
  unreadCount: unread,
  muted: muted,
);

class _AttachmentChatBackend
    implements MarketplaceChatBackend, MarketplaceChatAttachmentBackend {
  bool ambiguousOnce = false;
  int attempts = 0;
  String? lastKey;
  Completer<void>? gate;

  @override
  bool get chatAttachmentsEnabled => true;

  @override
  Future<Offer?> loadMeetingOffer(String conversationId) async => null;

  @override
  Future<List<ConversationSummary>> loadInbox() async => const [];

  @override
  Future<List<ConversationMessage>> loadMessages(String conversationId) async =>
      const [];

  @override
  Future<ConversationMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientMessageId,
  }) async => throw UnimplementedError();

  @override
  Future<ConversationMessage> sendAttachment({
    required String conversationId,
    required String text,
    required List<String> mediaIds,
    required String clientMessageId,
  }) async {
    attempts += 1;
    lastKey = clientMessageId;
    await gate?.future;
    if (ambiguousOnce && attempts == 1) {
      throw const StoreBackendException(
        'The change could not be confirmed.',
        ambiguous: true,
      );
    }
    return ConversationMessage(
      id: '80000000-0000-4000-8000-00000000000$attempts',
      conversationId: conversationId,
      senderUserId: 'user-a',
      kind: MessageKind.attachment,
      text: text,
      attachments: [
        MediaReference(
          id: mediaIds.first,
          kind: MediaKind.image,
          fileName: 'chat-image-1.jpg',
          contentType: 'image/jpeg',
        ),
      ],
      sentAt: DateTime.utc(2026, 5, 1),
      clientMessageId: clientMessageId,
    );
  }

  @override
  Future<ConversationMember> markRead({
    required String conversationId,
    required String messageId,
  }) async => ConversationMember(
    userId: 'user-a',
    profileId: '10000000-0000-4000-8000-00000000000a',
    role: HocalistRole.buyer,
    joinedAt: DateTime.utc(2026, 5, 1),
  );

  @override
  Future<ConversationMember> setMuted({
    required String conversationId,
    required bool muted,
  }) async => ConversationMember(
    userId: 'user-a',
    profileId: '10000000-0000-4000-8000-00000000000a',
    role: HocalistRole.buyer,
    joinedAt: DateTime.utc(2026, 5, 1),
    isMuted: muted,
  );
}

class _PlainChatBackend implements MarketplaceChatBackend {
  @override
  Future<Offer?> loadMeetingOffer(String conversationId) async => null;

  @override
  Future<List<ConversationSummary>> loadInbox() async => const [];

  @override
  Future<List<ConversationMessage>> loadMessages(String conversationId) async =>
      const [];

  @override
  Future<ConversationMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientMessageId,
  }) async => throw UnimplementedError();

  @override
  Future<ConversationMember> markRead({
    required String conversationId,
    required String messageId,
  }) async => throw UnimplementedError();

  @override
  Future<ConversationMember> setMuted({
    required String conversationId,
    required bool muted,
  }) async => throw UnimplementedError();
}

ApprovedBuyerNavigation _navigation() => ApprovedBuyerNavigation(
  onHome: () {},
  onHocatrends: () {},
  onOffers: () {},
  onChats: () {},
  onMore: () {},
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'chat date separators use viewer calendar dates across month and year boundaries',
    () {
      final now = DateTime(2026, 1, 1, 0, 5);
      expect(conversationTimeLabel(now), '12:05 AM');
      expect(conversationTimeLabel(DateTime(2025, 12, 31, 14, 9)), '2:09 PM');
      expect(conversationDateLabel(DateTime(2026, 1, 1), now: now), 'Today');
      expect(
        conversationDateLabel(DateTime(2025, 12, 31, 23, 59), now: now),
        'Yesterday',
      );
      expect(
        conversationDateLabel(DateTime(2025, 11, 15), now: now),
        '15 November 2025',
      );
      expect(
        sameConversationDay(DateTime(2026, 1, 1), DateTime(2026, 1, 1, 23)),
        isTrue,
      );
      expect(sameConversationDay(null, now), isFalse);
      expect(sameConversationDay(DateTime(2025, 12, 31), now), isFalse);
    },
  );

  setUpAll(loadHocalistTestFonts);

  testWidgets('only the seller receives payment recovery navigation and the draft stays visible', (tester) async {
    var opened=0;
    Widget body(bool seller)=>ApprovedConversationBody(
      onBack:(){},onPrimary:(){},onCall:(){},onMore:(){},onRequestChange:(){},onChangeLocation:(){},
      onAttach:(){},onSend:(_){},onLearnMore:(){},realEntries:const[],viewerIsSeller:seller,
      initialDraft:'Preserved draft',sendError:'This deal needs a payment update.',onManagePayment:()=>opened++,
    );
    await _pump(tester,body(true));
    await tester.ensureVisible(find.byKey(const Key('approvedChatManagePayment')));
    await tester.tap(find.byKey(const Key('approvedChatManagePayment')));
    expect(opened,1);
    expect(find.text('Preserved draft'),findsOneWidget);
    await _pump(tester,body(false));
    expect(find.byKey(const Key('approvedChatManagePayment')),findsNothing);
  });

  testWidgets(
    'deal cards select their own notice and the chat header stays pinned',
    (tester) async {
      var selected = 'offer-a';
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, update) => ApprovedConversationBody(
            onBack: () {},
            onPrimary: () {},
            onCall: () {},
            onMore: () {},
            onRequestChange: () {},
            onChangeLocation: () {},
            onAttach: () {},
            onSend: (_) {},
            onLearnMore: () {},
            realContactName: 'Test counterpart',
            realEntries: List.generate(
              30,
              (i) => ApprovedConversationEntry(
                isOutgoing: i.isEven,
                time: '10:00',
                text: 'Synthetic message $i',
                sentAt: DateTime.now(),
              ),
            ),
            realDeals: const [
              ApprovedDealView(
                meetingId: 'meeting-a',
                offerId: 'offer-a',
                title: 'Deal A',
                priceLabel: '100',
                statusLabel: 'Waiting for acceptance',
              ),
              ApprovedDealView(
                meetingId: 'meeting-b',
                offerId: 'offer-b',
                title: 'Deal B',
                priceLabel: '200',
                statusLabel: 'Meeting set',
              ),
            ],
            selectedDealId: selected,
            onSelectRealDeal: (id) => update(
              () => selected = id == 'meeting-b' ? 'offer-b' : 'offer-a',
            ),
            onOpenRealDeal: (id) => openedDeal = id,
          ),
        ),
      );
      expect(find.text('Selected deal: Deal A'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Meeting not scheduled'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('active-deal-meeting-b')));
      await tester.pumpAndSettle();
      expect(find.text('Selected deal: Deal B'), findsOneWidget);
      expect(find.textContaining('Notice for'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('deal-details-meeting-b')));
      expect(openedDeal, 'meeting-b');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      final before = tester.getTopLeft(find.text('Test counterpart')).dy;
      await tester.drag(
        find.byKey(const Key('approved-chat-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.text('Test counterpart')).dy;
      expect((before - after).abs(), lessThanOrEqualTo(8));
      expect(
        find.byKey(const ValueKey('deal-details-meeting-b')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('selected offer has a deal identity before a meeting exists', () {
    final offer = decodeOfferJson(
      marketplace.offerJson(
        status: 'selected',
        acceptedRevisionId: marketplace.revisionId,
        conversationId: 'conversation-a',
      ),
      'offer',
    );
    final view = ApprovedDealView.fromSelectedOffer(offer);
    expect(view.id, offer.id);
    expect(view.meetingId, isNull);
    expect(view.offerId, offer.id);
    expect(view.priceLabel, BuyerOfferView.fromOffer(offer).priceLabel);
    expect(view.statusLabel, 'Awaiting buyer confirmation');
    expect(view.actionLabel, 'Confirm seller');
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('real chat name and avatar fit $width / $scale', (
        tester,
      ) async {
        await _pump(
          tester,
          ApprovedConversationBody(
            onBack: () {},
            onPrimary: () {},
            onCall: () {},
            onMore: () {},
            onRequestChange: () {},
            onChangeLocation: () {},
            onAttach: () {},
            onSend: (_) {},
            onLearnMore: () {},
            realContactName: 'Hocalist Flow Seller with a Longer Display Name',
            realEntries: const [
              ApprovedConversationEntry(
                isOutgoing: false,
                time: '7:01 AM',
                text: 'Synthetic chat test only.',
              ),
            ],
          ),
          width: width,
          textScale: scale,
        );
        expect(
          find.text('Hocalist Flow Seller with a Longer Display Name'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('prototype-message-presence')),
          findsNothing,
        );
        final composer = find.byKey(const Key('approved-chat-message'));
        final beforeScroll = tester.getRect(composer);
        expect(beforeScroll.bottom, greaterThan(800));
        await tester.drag(
          find.byKey(const Key('approved-chat-scroll')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(composer), beforeScroll);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('failed mute callback releases the guard for a retry', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        muted: false,
        onMuteChanged: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('network failure');
        },
      ),
    );

    Future<void> attemptMute() async {
      await tester.tap(find.byKey(const Key('approved-chat-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mute chat messages'));
      await tester.pumpAndSettle();
    }

    await attemptMute();
    expect(attempts, 1);
    expect(find.text('Mute could not be saved. Try again.'), findsOneWidget);
    await attemptMute();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real change request sends exact chat intent and retries without changing terms',
    (tester) async {
      final calls = <String>[];
      var attempts = 0;
      await _pump(
        tester,
        ApprovedConversationBody(
          onBack: () {},
          onPrimary: () {},
          onCall: () {},
          onMore: () {},
          onRequestChange: () => fail('prototype action should not run'),
          onChangeLocation: () {},
          onAttach: () {},
          onSend: (_) {},
          onLearnMore: () {},
          realEntries: const [],
          onSubmitMessage: (text) async {
            calls.add(text);
            attempts++;
            return attempts == 2;
          },
        ),
      );
      await tester.tap(find.byKey(const Key('approved-chat-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask for a change'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('offer and meeting stay as they are'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('real-change-request-text')),
        'Could we meet after six?',
      );
      await tester.tap(find.byKey(const Key('real-change-request-send')));
      await tester.pumpAndSettle();
      expect(calls, ['Change request: Could we meet after six?']);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('real-change-request-text')),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('real-change-request-send')));
      await tester.pumpAndSettle();
      expect(calls, [
        'Change request: Could we meet after six?',
        'Change request: Could we meet after six?',
      ]);
      expect(find.byKey(const Key('real-change-request-text')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('real seller chat omits prototype request-updated claim', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        viewerIsSeller: true,
        requestChangePending: true,
        realEntries: const [],
      ),
    );
    expect(
      find.byKey(const Key('seller-request-updated-notice')),
      findsNothing,
    );
    expect(find.byTooltip('Call buyer'), findsOneWidget);
    expect(find.byTooltip('Call seller'), findsNothing);
  });

  testWidgets(
    'real chat restores the approved Active Deals states without prototype data',
    (tester) async {
      var opened = 0;
      await _pump(
        tester,
        ApprovedConversationBody(
          onBack: () {},
          onPrimary: () => opened++,
          onCall: () {},
          onMore: () {},
          onRequestChange: () {},
          onChangeLocation: () {},
          onAttach: () {},
          onSend: (_) {},
          onLearnMore: () {},
          realEntries: const [],
        ),
      );
      expect(find.text('John D.'), findsNothing);
      expect(find.text('Verified Seller'), findsNothing);
      expect(find.text('Active now'), findsNothing);
      expect(find.text('Active Deals'), findsOneWidget);
      expect(find.text('Meeting details'), findsNothing);
      expect(find.byKey(const Key('active-deal-ipad')), findsNothing);
      expect(find.byKey(const Key('active-deals-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('active-deal-new')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('approved-manage-conversation-deals')),
      );
      await tester.pumpAndSettle();
      // The management sheet is reachable; it never falls back to the meeting
      // route or shows a fabricated deal.
      expect(opened, 0);
      expect(
        find.byKey(const Key('approved-conversation-deals-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('approved-real-deals-unavailable')),
        findsOneWidget,
      );
    },
  );

  testWidgets('real chat deal cards open the authoritative management sheet', (
    tester,
  ) async {
    String? openedMeeting;
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        realDeals: const [
          ApprovedDealView(
            meetingId: 'meeting-1',
            title: 'Sold camera',
            priceLabel: r'$420',
            statusLabel: 'Meeting set',
            statusTone: BuyerNoticeTone.success,
            scheduleLabel: '2026-11-05 18:30',
            zoneLabel: 'America/New_York',
            placeLabel: 'Synthetic place',
          ),
        ],
        onOpenRealDeal: (meetingId) => openedMeeting = meetingId,
      ),
    );
    expect(find.text('Active Deals (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-deal-meeting-1')), findsOneWidget);
    expect(find.text('Sold camera'), findsOneWidget);
    expect(find.text('Meeting set'), findsOneWidget);
    expect(find.text('2026-11-05 18:30'), findsOneWidget);
    // Prototype deals never stand in for real ones.
    expect(find.byKey(const Key('active-deal-ipad')), findsNothing);
    expect(find.text(r'$650'), findsNothing);
    expect(find.text('iPad Air 5th Gen 64GB'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('active-deal-meeting-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('approved-active-deal-sheet')),
      findsOneWidget,
    );
    expect(find.text('America/New_York'), findsOneWidget);
    expect(find.text('Synthetic place'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Inspect the item before paying the seller offline.')).dy, greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('approved-real-deal-open-meeting'))).dy));
    expect(find.textContaining('15230'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('approved-real-deal-open-meeting')),
    );
    await tester.pumpAndSettle();
    expect(openedMeeting, 'meeting-1');

    await tester.tap(
      find.byKey(const Key('approved-manage-conversation-deals')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('approved-real-deal-row-meeting-1')),
      findsOneWidget,
    );
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('long deal place fits at $width / $scale', (tester) async {
        await _pump(
          tester,
          ApprovedConversationBody(
            onBack: () {},
            onPrimary: () {},
            onCall: () {},
            onMore: () {},
            onRequestChange: () {},
            onChangeLocation: () {},
            onAttach: () {},
            onSend: (_) {},
            onLearnMore: () {},
            realEntries: const [],
            realDeals: const [
              ApprovedDealView(
                meetingId: 'long-place',
                purchaseSelected: true,
                title: 'Synthetic meeting',
                priceLabel: r'$25',
                statusLabel: 'Waiting for the other person to accept',
                statusTone: BuyerNoticeTone.success,
                scheduleLabel: '2026-10-10 23:00',
                zoneLabel: 'America/Chicago',
                placeLabel:
                    'Harold Washington Library, South State Street, Chicago, IL',
              ),
            ],
            onOpenRealDeal: (_) {},
          ),
          width: width,
          textScale: scale,
        );
        await tester.tap(find.byKey(const ValueKey('active-deal-long-place')));
        await tester.pumpAndSettle();
        final label = find.text('Place');
        final place = find.text(
          'Harold Washington Library, South State Street, Chicago, IL',
        );
        expect(label, findsOneWidget);
        expect(place, findsOneWidget);
        expect(tester.getSize(label).width, greaterThan(40));
        expect(tester.getRect(place).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('real chat deal states stay designed and honest', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Nunito'),
        home: Scaffold(
          body: SafeArea(
            child: ApprovedConversationBody(
              onBack: () {},
              onPrimary: () {},
              onCall: () {},
              onMore: () {},
              onRequestChange: () {},
              onChangeLocation: () {},
              onAttach: () {},
              onSend: (_) {},
              onLearnMore: () {},
              realEntries: const [],
              realDealsLoading: true,
            ),
          ),
        ),
      ),
    );
    // The loading strip animates indefinitely; inspect without settling.
    await tester.pump();
    expect(find.byKey(const ValueKey('active-deals-loading')), findsOneWidget);

    var refreshes = 0;
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        realDeals: const [],
        realDealsError: 'Meetings could not be loaded.',
        onRefreshRealDeals: () => refreshes++,
      ),
    );
    expect(find.byKey(const ValueKey('active-deals-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('active-deals-retry')));
    await tester.pumpAndSettle();
    expect(refreshes, 1);

    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        realDeals: const [],
      ),
    );
    expect(find.text('Active Deals'), findsOneWidget);
    expect(find.byKey(const Key('active-deal-new')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('approved-manage-conversation-deals')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('approved-real-deals-empty')),
      findsOneWidget,
    );
  });

  for (final seller in [false, true]) {
    testWidgets(
      'empty real deals can propose a meeting (${seller ? 'seller' : 'buyer'})',
      (tester) async {
        var proposals = 0;
        await _pump(
          tester,
          ApprovedConversationBody(
            viewerIsSeller: seller,
            onBack: () {},
            onPrimary: () => proposals++,
            onCall: () {},
            onMore: () {},
            onRequestChange: () {},
            onChangeLocation: () {},
            onAttach: () {},
            onSend: (_) {},
            onLearnMore: () {},
            realEntries: const [],
            realDeals: const [],
          ),
        );
        await tester.tap(
          find.byKey(const Key('approved-manage-conversation-deals')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('approved-real-deals-propose')),
        );
        await tester.pumpAndSettle();
        expect(proposals, 1);
        expect(
          find.byKey(const Key('approved-conversation-deals-sheet')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real chat keeps the approved Previous group with designed states',
    (tester) async {
      Future<void> openSheet(Widget body) async {
        // Reset the tree so a sheet left open by the previous step cannot
        // swallow the Manage tap or mask the next sheet content.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await _pump(tester, body);
        await tester.tap(
          find.byKey(const Key('approved-manage-conversation-deals')),
        );
        await tester.pumpAndSettle();
      }

      ApprovedConversationBody body({
        List<ApprovedDealView>? previousDeals,
        bool truncated = false,
      }) => ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        realDeals: const [
          ApprovedDealView(
            meetingId: 'meeting-1',
            title: 'Sold camera',
            priceLabel: r'$420',
            statusLabel: 'Meeting set',
            statusTone: BuyerNoticeTone.success,
          ),
        ],
        realDealsTruncated: truncated,
        previousDeals: previousDeals,
        onOpenRealDeal: (_) {},
      );

      // Missing history read: the group stays visible with a designed state.
      await openSheet(body());
      expect(find.text('Previous'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('approved-real-previous-unavailable')),
        findsOneWidget,
      );
      expect(find.textContaining('not available yet'), findsOneWidget);

      // Known empty history keeps the group with an empty state.
      await openSheet(body(previousDeals: const []));
      expect(find.text('Previous'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('approved-real-previous-empty')),
        findsOneWidget,
      );

      // A provided history read renders authoritative previous rows.
      await openSheet(
        body(
          previousDeals: const [
            ApprovedDealView(
              meetingId: 'old-1',
              title: 'Old laptop',
              priceLabel: r'$100',
              statusLabel: 'Cancelled',
              statusTone: BuyerNoticeTone.error,
            ),
          ],
        ),
      );
      expect(
        find.byKey(const ValueKey('approved-real-previous-row-old-1')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('approved-real-previous-row-old-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('approved-active-deal-sheet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('approved-active-deal-sheet')),
          matching: find.text('Old laptop'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'completed-only conversation opens history instead of proposing another meeting',
    (tester) async {
      String? opened;
      String? selected;
      var proposals = 0;
      await _pump(
        tester,
        ApprovedConversationBody(
          onBack: () {},
          onPrimary: () => proposals++,
          onCall: () {},
          onMore: () {},
          onRequestChange: () {},
          onChangeLocation: () {},
          onAttach: () {},
          onSend: (_) {},
          onLearnMore: () {},
          realEntries: const [],
          realDeals: const [],
          previousDeals: const [
            ApprovedDealView(
              meetingId: 'completed-meeting',
              title: 'Confirmed item',
              priceLabel: '\$25',
              statusLabel: 'PIN confirmed',
              statusTone: BuyerNoticeTone.success,
            ),
          ],
          onOpenRealDeal: (id) => opened = id,
          onSelectRealDeal: (id) => selected = id,
        ),
      );
      await tester.tap(
        find.byKey(const Key('approved-manage-conversation-deals')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Propose meeting'), findsNothing);
      await tester.tap(find.text('View previous deal'));
      await tester.pumpAndSettle();
      expect(find.text('PIN confirmed'), findsOneWidget);
      expect(selected, 'completed-meeting');
      await tester.tap(find.text('Open meeting details'));
      await tester.pumpAndSettle();
      expect(opened, 'completed-meeting');
      expect(proposals, 0);
    },
  );

  testWidgets(
    'the Previous group stays visible while Active deals are unavailable',
    (tester) async {
      await _pump(
        tester,
        ApprovedConversationBody(
          onBack: () {},
          onPrimary: () {},
          onCall: () {},
          onMore: () {},
          onRequestChange: () {},
          onChangeLocation: () {},
          onAttach: () {},
          onSend: (_) {},
          onLearnMore: () {},
          realEntries: const [],
        ),
      );
      await tester.tap(
        find.byKey(const Key('approved-manage-conversation-deals')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('approved-real-deals-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Previous'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('approved-real-previous-unavailable')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a capped meeting scan reports truncation in the deals sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        realDeals: const [
          ApprovedDealView(
            meetingId: 'meeting-1',
            title: 'Sold camera',
            priceLabel: r'$420',
            statusLabel: 'Meeting set',
            statusTone: BuyerNoticeTone.success,
          ),
        ],
        realDealsTruncated: true,
        onOpenRealDeal: (_) {},
      ),
    );
    await tester.tap(
      find.byKey(const Key('approved-manage-conversation-deals')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('approved-real-deals-truncated')),
      findsOneWidget,
    );
    expect(find.textContaining('not scanned'), findsOneWidget);
  });

  testWidgets(
    'real composer retains failed text and clears only after acknowledgement',
    (tester) async {
      var response = Completer<bool>();
      var calls = 0;
      await _pump(
        tester,
        ApprovedConversationBody(
          onBack: () {},
          onPrimary: () {},
          onCall: () {},
          onMore: () {},
          onRequestChange: () {},
          onChangeLocation: () {},
          onAttach: () {},
          onSend: (_) {},
          onLearnMore: () {},
          realEntries: const [],
          onSubmitMessage: (_) {
            calls++;
            return response.future;
          },
        ),
      );
      final composer = find.byKey(const Key('approved-chat-message'));
      final send = find.byKey(const Key('approved-chat-send'));
      await tester.enterText(composer, 'Keep this until confirmed');
      await tester.tap(send);
      await tester.tap(send);
      expect(calls, 1);
      response.complete(false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep this until confirmed',
      );
      response = Completer<bool>();
      await tester.tap(send);
      response.complete(true);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    },
  );

  testWidgets('real conversation entries replace the prototype history', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realContactName: 'Authoritative Seller Name',
        realEntries: const [
          ApprovedConversationEntry(
            isOutgoing: false,
            time: '9:30 AM',
            text: 'Can meet tomorrow.',
          ),
          ApprovedConversationEntry(
            isOutgoing: true,
            time: '9:31 AM',
            text: 'Sounds good.',
          ),
        ],
      ),
    );
    expect(find.text('Can meet tomorrow.'), findsOneWidget);
    expect(find.text('Authoritative Seller Name'), findsOneWidget);
    expect(find.text('Sounds good.'), findsOneWidget);
    expect(find.byKey(const Key('prototype-message-presence')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith('john-avatar.png'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('approved-chat-message-incoming-1')),
      findsNothing,
    );
  });

  testWidgets('real history shows loading, error and empty states', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        messagesLoading: true,
      ),
    );
    expect(find.byKey(const Key('approvedChatLoading')), findsOneWidget);

    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        messagesError: 'Could not load this conversation.',
        onRefreshMessages: () {},
      ),
    );
    expect(find.byKey(const Key('approvedChatError')), findsOneWidget);
    expect(find.byKey(const Key('approvedChatRetry')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('Messaging is unavailable'), findsOneWidget);

    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
      ),
    );
    expect(find.byKey(const Key('approvedChatEmpty')), findsOneWidget);
  });

  testWidgets('a real send reports the composer text once', (tester) async {
    final sent = <String>[];
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: sent.add,
        onLearnMore: () {},
        realEntries: const [],
      ),
    );
    await tester.enterText(
      find.byKey(const Key('approved-chat-message')),
      'On my way.',
    );
    await tester.tap(find.byKey(const Key('approved-chat-send')));
    await tester.pumpAndSettle();
    expect(sent, ['On my way.']);
  });

  testWidgets('real history shows the send error', (tester) async {
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: const [],
        sendError: 'The message could not be sent.',
      ),
    );
    expect(find.byKey(const Key('approvedChatSendError')), findsOneWidget);
  });

  testWidgets('buyer inbox shows real rows and opens the right thread', (
    tester,
  ) async {
    ChatThreadView? opened;
    await _pump(
      tester,
      BuyerChatsPage(
        onBack: () {},
        onOpenChat: () {},
        onOffers: () {},
        realThreads: [_thread(name: 'Loop Resale', unread: 2)],
        onOpenThread: (thread) => opened = thread,
      ),
    );
    expect(find.text('Loop Resale'), findsOneWidget);
    expect(find.text('2 unread'), findsNothing);
    expect(find.text('Active conversation'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Northside Tech'), findsNothing);
    await tester.tap(find.text('Loop Resale'));
    await tester.pumpAndSettle();
    expect(opened?.conversationId, '60000000-0000-4000-8000-000000000001');
  });

  testWidgets('buyer inbox shows loading, error and empty states', (
    tester,
  ) async {
    await _pump(
      tester,
      BuyerChatsPage(
        onBack: () {},
        onOpenChat: () {},
        onOffers: () {},
        realThreads: const [],
        threadsLoading: true,
      ),
    );
    expect(find.byKey(const Key('buyerChatsLoading')), findsOneWidget);

    await _pump(
      tester,
      BuyerChatsPage(
        onBack: () {},
        onOpenChat: () {},
        onOffers: () {},
        realThreads: const [],
        threadsError: 'Could not load your conversations.',
        onRefreshThreads: () {},
      ),
    );
    expect(find.byKey(const Key('buyerChatsError')), findsOneWidget);
    expect(find.byKey(const Key('buyerChatsRetry')), findsOneWidget);

    await _pump(
      tester,
      BuyerChatsPage(
        onBack: () {},
        onOpenChat: () {},
        onOffers: () {},
        realThreads: const [],
      ),
    );
    expect(find.byKey(const Key('buyerChatsEmpty')), findsOneWidget);
  });

  testWidgets('a conversation summary maps to an inbox row', (tester) async {
    final summary = ConversationSummary(
      conversation: Conversation(
        id: '60000000-0000-4000-8000-000000000009',
        origin: ConversationOrigin.targetedRequest,
        members: [
          ConversationMember(
            userId: 'user-a',
            profileId: '10000000-0000-4000-8000-00000000000a',
            role: HocalistRole.buyer,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
          ConversationMember(
            userId: 'user-b',
            profileId: '10000000-0000-4000-8000-00000000000b',
            role: HocalistRole.seller,
            joinedAt: DateTime.utc(2026, 5, 1),
            isMuted: true,
          ),
        ],
        status: ConversationStatus.open,
        requestId: '30000000-0000-4000-8000-000000000001',
        stamp: RecordStamp(
          revision: 1,
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      ),
      counterpartDisplayName: 'Maya Chen',
      unreadCount: 3,
    );
    final view = ChatThreadView.fromSummary(
      summary,
      viewerUserId: 'user-b',
      now: DateTime.utc(2026, 5, 1, 12),
    );
    expect(view.counterpartName, 'Maya Chen');
    expect(view.initials, 'MC');
    expect(view.unreadCount, 3);
    expect(view.muted, isTrue);
    expect(view.preview, 'No messages yet.');
    expect(view.counterpartProfileId, isNull);
  });

  testWidgets('a conversation summary maps the counterpart public profile', (
    tester,
  ) async {
    const counterpartProfileId = '10000000-0000-4000-8000-00000000000b';
    final summary = ConversationSummary(
      conversation: Conversation(
        id: '60000000-0000-4000-8000-000000000009',
        origin: ConversationOrigin.targetedRequest,
        members: [
          ConversationMember(
            userId: 'user-a',
            profileId: '10000000-0000-4000-8000-00000000000a',
            role: HocalistRole.buyer,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
          ConversationMember(
            userId: 'user-b',
            profileId: counterpartProfileId,
            role: HocalistRole.seller,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
        ],
        status: ConversationStatus.open,
        requestId: '30000000-0000-4000-8000-000000000001',
        stamp: RecordStamp(
          revision: 1,
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      ),
      counterpartDisplayName: 'Seller B',
      counterpartProfileId: counterpartProfileId,
      unreadCount: 0,
    );
    final view = ChatThreadView.fromSummary(summary, viewerUserId: 'user-a');
    expect(view.counterpartName, 'Seller B');
    expect(view.counterpartProfileId, counterpartProfileId);
  });

  testWidgets('attachment messages decode with their owned media references', (
    tester,
  ) async {
    final message = decodeMessageJson({
      'id': '70000000-0000-4000-8000-00000000000a',
      'conversation_id': '60000000-0000-4000-8000-000000000001',
      'sender_user_id': 'user-a',
      'kind': 'attachment',
      'text': 'Look at this.',
      'attachment_media_ids': const ['50000000-0000-4000-8000-00000000000a'],
      'sent_at': '2026-05-01T12:00:00Z',
    });
    expect(message.kind, MessageKind.attachment);
    expect(message.text, 'Look at this.');
    expect(message.attachments, hasLength(1));
    expect(
      message.attachments.single.id,
      '50000000-0000-4000-8000-00000000000a',
    );
    expect(message.attachments.single.isImage, isTrue);

    expect(
      () => decodeMessageJson({
        'id': '70000000-0000-4000-8000-00000000000b',
        'conversation_id': '60000000-0000-4000-8000-000000000001',
        'sender_user_id': 'user-a',
        'kind': 'attachment',
        'text': '',
        'sent_at': '2026-05-01T12:00:00Z',
      }),
      throwsA(isA<ChatDecodeException>()),
      reason: 'an attachment message without a reference is invalid',
    );
  });

  testWidgets('attachment sends freeze the intent and reuse the client key', (
    tester,
  ) async {
    final backend = _AttachmentChatBackend();
    final repository = LocalMarketplaceRepository(chatBackend: backend);
    await repository.openChatConversation(
      '60000000-0000-4000-8000-000000000001',
    );
    expect(repository.chatAttachmentsSupported, isTrue);

    backend.ambiguousOnce = true;
    final first = await repository.sendChatAttachment(
      text: 'Look at this.',
      mediaIds: const ['50000000-0000-4000-8000-00000000000a'],
    );
    expect(first.isSuccess, isFalse);
    expect(first.outcomeUncertain, isTrue);
    final frozenKey = backend.lastKey;
    expect(frozenKey, isNotNull);

    final changed = await repository.sendChatAttachment(
      text: 'Look at this.',
      mediaIds: const ['50000000-0000-4000-8000-00000000000b'],
    );
    expect(changed.isSuccess, isFalse);
    expect(changed.outcomeUncertain, isTrue);
    expect(backend.attempts, 1, reason: 'a changed intent is refused');

    final retry = await repository.sendChatAttachment(
      text: 'Look at this.',
      mediaIds: const ['50000000-0000-4000-8000-00000000000a'],
    );
    expect(retry.isSuccess, isTrue);
    expect(
      backend.lastKey,
      frozenKey,
      reason: 'retry reuses the operation key',
    );
    expect(repository.chatMessages.single.kind, MessageKind.attachment);
    expect(repository.chatMessages.single.attachments, hasLength(1));
  });

  testWidgets('a backend without the attachment capability stays honest', (
    tester,
  ) async {
    final repository = LocalMarketplaceRepository(
      chatBackend: _PlainChatBackend(),
    );
    await repository.openChatConversation(
      '60000000-0000-4000-8000-000000000001',
    );
    expect(repository.chatAttachmentsSupported, isFalse);
    await expectLater(
      repository.sendChatAttachment(
        text: '',
        mediaIds: const ['50000000-0000-4000-8000-00000000000a'],
      ),
      throwsA(isA<StoreBackendException>()),
    );
  });

  testWidgets('the real attach action stays honest until the flag is on', (
    tester,
  ) async {
    var hostCalls = 0;
    await _pump(
      tester,
      ApprovedBuyerChatPage(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () => hostCalls += 1,
        attachmentsEnabled: false,
        onSend: (_) {},
        onLearnMore: () {},
        navigation: _navigation(),
        realEntries: const [],
        onSubmitMessage: (_) async => true,
      ),
    );
    await tester.tap(find.byKey(const Key('approved-chat-attach')));
    await tester.pumpAndSettle();
    expect(find.text('Attachments are not connected yet.'), findsOneWidget);

    await _pump(
      tester,
      ApprovedBuyerChatPage(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () => hostCalls += 1,
        attachmentsEnabled: true,
        onSend: (_) {},
        onLearnMore: () {},
        navigation: _navigation(),
        realEntries: const [],
        onSubmitMessage: (_) async => true,
      ),
    );
    await tester.tap(find.byKey(const Key('approved-chat-attach')));
    await tester.pumpAndSettle();
    expect(hostCalls, 1, reason: 'the enabled host owns picking and sending');
  });

  testWidgets('real attachment entries render sealed image slots', (
    tester,
  ) async {
    const mediaId = '50000000-0000-4000-8000-00000000000a';
    await _pump(
      tester,
      ApprovedBuyerChatPage(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        navigation: _navigation(),
        realEntries: const [
          ApprovedConversationEntry(
            isOutgoing: false,
            time: '9:30 AM',
            text: '',
            attachmentMediaIds: [mediaId],
          ),
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('incoming-attachment-$mediaId')),
      findsOneWidget,
    );
  });

  testWidgets('a delayed upload is fenced to its original conversation', (
    tester,
  ) async {
    const mediaId = '50000000-0000-4000-8000-00000000000a';
    const original = '60000000-0000-4000-8000-000000000001';
    final backend = _AttachmentChatBackend();
    final repository = LocalMarketplaceRepository(chatBackend: backend);
    await repository.openChatConversation(original);

    // The user switches chats while the upload is still in flight.
    await repository.openChatConversation(
      '60000000-0000-4000-8000-000000000002',
    );
    final fenced = await repository.sendChatAttachment(
      text: '',
      mediaIds: const [mediaId],
      expectedConversationId: original,
    );
    expect(fenced.isSuccess, isFalse);
    expect(
      backend.attempts,
      0,
      reason: 'the delayed photo must never enter the new chat',
    );
    expect(
      repository.hasUnconfirmedChatAttachment,
      isFalse,
      reason: 'the new chat has no pending photo',
    );

    // Returning to the original conversation exposes the retained photo and
    // retrying sends it with the same key without uploading again.
    await repository.openChatConversation(original);
    expect(repository.hasUnconfirmedChatAttachment, isTrue);
    expect(repository.pendingChatAttachment!.mediaIds.single, mediaId);
    final retry = await repository.retryChatAttachment();
    expect(retry.isSuccess, isTrue);
    expect(backend.attempts, 1);
    expect(repository.hasUnconfirmedChatAttachment, isFalse);
  });

  testWidgets('the pending photo card exposes retry and discard', (
    tester,
  ) async {
    var retries = 0;
    var discards = 0;
    await _pump(
      tester,
      ApprovedBuyerChatPage(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        navigation: _navigation(),
        realEntries: const [],
        pendingAttachmentMediaId: '50000000-0000-4000-8000-00000000000a',
        onRetryAttachment: () => retries += 1,
        onDiscardAttachment: () => discards += 1,
      ),
    );
    expect(
      find.byKey(const Key('approved-pending-remote-attachment')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('approved-chat-attachment-retry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
    await tester.tap(find.byKey(const Key('approved-chat-attachment-discard')));
    await tester.pumpAndSettle();
    expect(discards, 1);
  });

  testWidgets('the pending photo card fits a narrow phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedBuyerChatPage(
            onBack: () {},
            onPrimary: () {},
            onCall: () {},
            onMore: () {},
            onRequestChange: () {},
            onChangeLocation: () {},
            onAttach: () {},
            onSend: (_) {},
            onLearnMore: () {},
            navigation: _navigation(),
            realEntries: const [],
            pendingAttachmentMediaId: '50000000-0000-4000-8000-00000000000a',
            onRetryAttachment: () {},
            onDiscardAttachment: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('approved-pending-remote-attachment')),
      findsOneWidget,
    );
  });

  testWidgets('a second attachment send is refused while one is in flight', (
    tester,
  ) async {
    final backend = _AttachmentChatBackend()..gate = Completer<void>();
    final repository = LocalMarketplaceRepository(chatBackend: backend);
    await repository.openChatConversation(
      '60000000-0000-4000-8000-000000000001',
    );
    final first = repository.sendChatAttachment(
      text: '',
      mediaIds: const ['50000000-0000-4000-8000-00000000000a'],
    );
    await tester.pump();
    final second = await repository.sendChatAttachment(
      text: '',
      mediaIds: const ['50000000-0000-4000-8000-00000000000b'],
    );
    expect(second.isSuccess, isFalse);
    expect(second.error, contains('already being sent'));
    expect(
      backend.attempts,
      1,
      reason: 'the duplicate intent never reaches the backend',
    );
    backend.gate!.complete();
    expect((await first).isSuccess, isTrue);
  });

  testWidgets('discarding clears only the active conversation photo', (
    tester,
  ) async {
    const mediaId = '50000000-0000-4000-8000-00000000000a';
    const first = '60000000-0000-4000-8000-000000000001';
    const second = '60000000-0000-4000-8000-000000000002';
    final backend = _AttachmentChatBackend();
    final repository = LocalMarketplaceRepository(chatBackend: backend);
    await repository.openChatConversation(first);
    await repository.sendChatAttachment(
      text: '',
      mediaIds: const [mediaId],
      expectedConversationId: second,
    );
    expect(
      repository.hasUnconfirmedChatAttachment,
      isFalse,
      reason: 'the first chat has no pending photo',
    );
    await repository.openChatConversation(second);
    expect(repository.hasUnconfirmedChatAttachment, isTrue);
    repository.discardChatAttachment();
    expect(repository.hasUnconfirmedChatAttachment, isFalse);
    expect(repository.pendingChatAttachment, isNull);
    await repository.openChatConversation(first);
    expect(repository.hasUnconfirmedChatAttachment, isFalse);
  });
}

String? openedDeal;
