// Conversation-deal scan regression: the chat must collect every matching
// meeting across pages, and report its page cap honestly. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/meetings/meeting_adapter.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/chat/conversation_deal_groups.dart';

class _PagedMeetings implements MarketplaceMeetingsBackend {
  _PagedMeetings(this.pages);

  final List<MeetingPageView> pages;
  int calls = 0;
  bool failFirst = false;

  @override
  Future<MeetingPageView> loadMeetings({
    String? status,
    String? cursor,
    int limit = 50,
  }) async {
    calls += 1;
    if (failFirst && calls == 1) {
      throw const StoreBackendException('Meetings failed.');
    }
    final index = calls - 1;
    if (index >= pages.length) {
      return MeetingPageView(items: const [], nextCursor: null);
    }
    return pages[index];
  }

  @override
  Future<MeetingView> loadMeeting(String meetingId) =>
      throw UnimplementedError();

  @override
  Future<MeetingView> proposeMeeting({
    required String conversationId,
    required MeetingScheduleInput input,
    required String operationKey,
  }) => throw UnimplementedError();

  @override
  Future<MeetingView> respondToMeeting({
    required String meetingId,
    required bool accept,
    required int expectedRevision,
    required String operationKey,
  }) => throw UnimplementedError();

  @override
  Future<MeetingView> proposeReschedule({
    required String meetingId,
    required MeetingScheduleInput input,
    required int expectedRevision,
    required String operationKey,
  }) => throw UnimplementedError();

  @override
  Future<MeetingView> cancelMeeting({
    required String meetingId,
    required int expectedRevision,
    required String operationKey,
  }) => throw UnimplementedError();
}

MeetingView _meeting(
  String id,
  String conversationId, {
  String status = 'accepted',
}) => MeetingView(
  meetingId: id,
  conversationId: conversationId,
  requestId: 'request-1',
  offerId: 'offer-1',
  buyerUserId: 'buyer-1',
  sellerUserId: 'seller-1',
  status: status,
  revision: 1,
  acceptedSchedule: MeetingScheduleView(
    sequence: 1,
    date: LocalDate(year: 2026, month: 11, day: 5),
    startTime: LocalTime(hour: 18, minute: 30),
    timezoneId: 'America/New_York',
    offsetMinutes: -300,
    instant: DateTime.utc(2026, 11, 5, 23, 30),
    placeChoice: 'specific_place',
    placeLabel: 'Synthetic place',
    proposedByUserId: 'buyer-1',
    status: 'accepted',
    createdAt: DateTime.utc(2026, 11, 1),
  ),
  offerSummary: MeetingOfferSummary(
    title: 'Item $id',
    priceMinor: 42000,
    currencyCode: 'USD',
    revisionId: 'revision-$id',
  ),
  revisions: const [],
);

void main() {
  test('confirmed and cancelled meetings belong to Previous, never Active', () {
    final groups = ConversationDealGroups(
      [
        _meeting('open', 'conversation'),
        _meeting('completed', 'conversation'),
        _meeting('cancelled', 'conversation', status: 'cancelled'),
      ],
      {'completed'},
    );
    expect(groups.active.map((meeting) => meeting.meetingId), ['open']);
    expect(groups.previous!.map((meeting) => meeting.meetingId), [
      'completed',
      'cancelled',
    ]);
  });
  test(
    'missing completion read is unknown, never an invented empty history',
    () {
      final groups = ConversationDealGroups([
        _meeting('accepted', 'conversation'),
      ], null);
      expect(groups.previous, isNull);
      expect(groups.active.single.meetingId, 'accepted');
    },
  );
  test('known empty completion read preserves accepted meetings', () {
    final groups = ConversationDealGroups([
      _meeting('accepted', 'conversation'),
    ], {});
    expect(groups.previous, isEmpty);
    expect(groups.active.single.meetingId, 'accepted');
  });
  test('the documented scan limits match the repository page read', () {
    expect(conversationDealsMeetingPageSize, 50);
    expect(conversationDealsMaxPages, 20);
  });

  test(
    'the scan collects matches from every page, not only the first',
    () async {
      final backend = _PagedMeetings([
        MeetingPageView(
          items: [_meeting('m1', 'conv-1'), _meeting('m9', 'other')],
          nextCursor: 'c1',
        ),
        MeetingPageView(items: [_meeting('m2', 'conv-1')], nextCursor: 'c2'),
        MeetingPageView(items: [_meeting('m8', 'other')], nextCursor: null),
      ]);
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);

      final result = await collectConversationMeetings(
        repository,
        conversationId: 'conv-1',
      );

      expect(result.matches.map((meeting) => meeting.meetingId), ['m1', 'm2']);
      expect(result.pagesScanned, 3);
      expect(result.truncated, isFalse);
      expect(
        backend.calls,
        3,
        reason: 'the scan continues after the first matching page',
      );
    },
  );

  test('the scan stops at its page cap and reports truncation', () async {
    final backend = _PagedMeetings([
      MeetingPageView(items: [_meeting('m1', 'conv-1')], nextCursor: 'c1'),
      MeetingPageView(items: [_meeting('m2', 'conv-1')], nextCursor: 'c2'),
    ]);
    final repository = LocalMarketplaceRepository(meetingsBackend: backend);

    final result = await collectConversationMeetings(
      repository,
      conversationId: 'conv-1',
      maxPages: 2,
    );

    expect(result.matches.map((meeting) => meeting.meetingId), ['m1', 'm2']);
    expect(result.pagesScanned, 2);
    expect(result.truncated, isTrue);
    expect(backend.calls, 2);
  });

  test('a failed page read is reported without inventing matches', () async {
    final backend = _PagedMeetings([
      MeetingPageView(items: [_meeting('m1', 'conv-1')], nextCursor: 'c1'),
    ])..failFirst = true;
    final repository = LocalMarketplaceRepository(meetingsBackend: backend);

    final result = await collectConversationMeetings(
      repository,
      conversationId: 'conv-1',
    );

    expect(result.matches, isEmpty);
    expect(result.truncated, isFalse);
    expect(repository.meetingsError, isNotNull);
  });
}
