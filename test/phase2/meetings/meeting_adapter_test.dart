// Meeting adapter and repository tests. Fakes only; no provider or network.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/meetings/meeting_adapter.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/schedule.dart';

import '../marketplace/support/marketplace_fakes.dart';

const _meetingId = '80000000-0000-4000-8000-000000000001';
const _conversationId = '60000000-0000-4000-8000-000000000001';

Map<String, Object?> _revision({
  int sequence = 1,
  String status = 'proposed',
  String date = '2026-10-01',
  String time = '18:30',
}) => <String, Object?>{
  'id': '81000000-0000-4000-8000-00000000000$sequence',
  'meeting_id': _meetingId,
  'sequence': sequence,
  'schedule_date': date,
  'schedule_time': time,
  'schedule_timezone': 'America/New_York',
  'schedule_occurrence': null,
  'schedule_offset_minutes': -240,
  'schedule_instant': '${date}T22:30:00+00:00',
  'place_choice': 'specific_place',
  'place_label': 'Cross County Mall',
  'place_address': '123 Synthetic Ave',
  'place_id': 'place-1',
  'proposed_by_user_id': 'user-a',
  'status': status,
  'created_at': '2026-05-01T00:00:00+00:00',
  'resolved_at': null,
};

Map<String, Object?> _meeting({
  String status = 'proposed',
  int revision = 1,
  String? expiresAt,
  Map<String, Object?>? accepted,
  Map<String, Object?>? pending,
  List<Map<String, Object?>>? revisions,
}) => <String, Object?>{
  'id': _meetingId,
  'conversation_id': _conversationId,
  'request_id': '30000000-0000-4000-8000-000000000001',
  'offer_id': '40000000-0000-4000-8000-000000000001',
  'buyer_user_id': 'user-a',
  'seller_user_id': 'user-b',
  'status': status,
  'accepted_revision_id': accepted == null ? null : accepted['id'],
  'meeting_expires_at': expiresAt,
  'revision': revision,
  'created_at': '2026-05-01T00:00:00+00:00',
  'updated_at': '2026-05-01T00:00:00+00:00',
  'accepted_schedule': accepted,
  'pending_schedule': pending,
  'offer_summary': <String, Object?>{
    'title': 'iPad Air 5th Gen 64GB',
    'price_minor': 65000,
    'currency_code': 'USD',
    'revision_id': '41000000-0000-4000-8000-000000000001',
  },
  'revisions': revisions ?? [_revision()],
};

class FakeMeetingsBackend implements MarketplaceMeetingsBackend {
  Future<MeetingPageView> Function()? onLoad;
  Future<MeetingPageView> Function(String? cursor)? onLoadPage;
  Future<MeetingView> Function(String id)? onLoadOne;
  Future<MeetingView> Function(
    String conversationId,
    MeetingScheduleInput input,
    String operationKey,
  )?
  onPropose;
  Future<MeetingView> Function(
    String id,
    bool accept,
    int revision,
    String operationKey,
  )?
  onRespond;
  Future<MeetingView> Function(
    String id,
    MeetingScheduleInput input,
    int revision,
    String operationKey,
  )?
  onReschedule;
  Future<MeetingView> Function(String id, int revision, String operationKey)?
  onCancel;

  @override
  Future<MeetingPageView> loadMeetings({
    String? status,
    String? cursor,
    int limit = 50,
  }) =>
      onLoadPage?.call(cursor) ??
      onLoad?.call() ??
      Future.value(MeetingPageView(items: [meetingView()], nextCursor: null));

  @override
  Future<MeetingView> loadMeeting(String meetingId) =>
      onLoadOne?.call(meetingId) ?? Future.value(meetingView());

  @override
  Future<MeetingView> proposeMeeting({
    required String conversationId,
    required MeetingScheduleInput input,
    required String operationKey,
  }) =>
      onPropose?.call(conversationId, input, operationKey) ??
      Future.value(meetingView());

  @override
  Future<MeetingView> respondToMeeting({
    required String meetingId,
    required bool accept,
    required int expectedRevision,
    required String operationKey,
  }) =>
      onRespond?.call(meetingId, accept, expectedRevision, operationKey) ??
      Future.value(meetingView());

  @override
  Future<MeetingView> proposeReschedule({
    required String meetingId,
    required MeetingScheduleInput input,
    required int expectedRevision,
    required String operationKey,
  }) =>
      onReschedule?.call(meetingId, input, expectedRevision, operationKey) ??
      Future.value(meetingView());

  @override
  Future<MeetingView> cancelMeeting({
    required String meetingId,
    required int expectedRevision,
    required String operationKey,
  }) =>
      onCancel?.call(meetingId, expectedRevision, operationKey) ??
      Future.value(meetingView(status: 'cancelled'));
}

MeetingView meetingView({
  String status = 'proposed',
  int revision = 1,
  String? expiresAt,
}) {
  final accepted = status == 'accepted'
      ? decodeMeetingRevisionJson(_revision(status: 'accepted'), 'x')
      : null;
  return MeetingView(
    meetingId: _meetingId,
    conversationId: _conversationId,
    requestId: '30000000-0000-4000-8000-000000000001',
    offerId: '40000000-0000-4000-8000-000000000001',
    buyerUserId: 'user-a',
    sellerUserId: 'user-b',
    status: status,
    revision: revision,
    meetingExpiresAt: expiresAt == null
        ? null
        : DateTime.parse(expiresAt).toUtc(),
    acceptedSchedule: accepted,
    pendingSchedule: status == 'proposed'
        ? decodeMeetingRevisionJson(_revision(), 'x')
        : null,
    revisions: [
      decodeMeetingRevisionJson(
        _revision(status: status == 'accepted' ? 'accepted' : 'proposed'),
        'x',
      ),
    ],
  );
}

MeetingScheduleInput scheduleInput({RepeatedTimeOccurrence? occurrence}) =>
    MeetingScheduleInput(
      schedule: LocalSchedule(
        date: LocalDate(year: 2026, month: 10, day: 1),
        startTime: LocalTime(hour: 18, minute: 30),
        timezoneId: 'America/New_York',
        occurrence: occurrence,
      ),
      placeChoice: 'specific_place',
      placeLabel: 'Cross County Mall',
      placeAddress: '123 Synthetic Ave',
      placeId: 'place-1',
    );

void main() {
  group('MeetingDataAdapter', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late MeetingDataAdapter adapter;

    setUp(() {
      session = FakeMarketplaceSession('user-a');
      transport = FakeMarketplaceTransport();
      adapter = MeetingDataAdapter(transport: transport, session: session);
    });

    test('decodes a meeting page and detail', () async {
      transport.handler = (call) => MarketplaceTransportData(<String, Object?>{
        'items': [_meeting(pending: _revision())],
        'next_cursor': 'next',
      });
      final page = await adapter.fetchMeetings(limit: 10);
      expect(page.valueOrNull!.items.single.status, 'proposed');
      expect(
        page.valueOrNull!.items.single.pendingSchedule!.placeLabel,
        'Cross County Mall',
      );
      expect(page.valueOrNull!.nextCursor, 'next');
      expect(transport.calls.single.function, 'meeting_list');
      expect(transport.calls.single.params['p_limit'], 10);

      transport.handler = (call) => MarketplaceTransportData(
        _meeting(
          status: 'accepted',
          revision: 2,
          expiresAt: '2026-10-02T04:00:00+00:00',
          accepted: _revision(status: 'accepted'),
          pending: null,
        ),
      );
      final detail = await adapter.fetchMeeting(_meetingId);
      final meeting = detail.valueOrNull!;
      expect(meeting.status, 'accepted');
      expect(meeting.meetingExpiresAt, DateTime.utc(2026, 10, 2, 4));
      expect(meeting.acceptedSchedule!.offsetMinutes, -240);
      expect(meeting.pendingSchedule, isNull);
      expect(meeting.offerSummary!.title, 'iPad Air 5th Gen 64GB');
      expect(meeting.offerSummary!.priceMinor, 65000);
      expect(meeting.offerSummary!.priceLabel, r'$650');
      expect(
        meeting.offerSummary!.revisionId,
        '41000000-0000-4000-8000-000000000001',
      );
    });

    test('rejects malformed meeting payloads', () async {
      transport.handler = (call) =>
          const MarketplaceTransportData(<String, Object?>{'items': 'nope'});
      expect((await adapter.fetchMeetings()).isFailure, isTrue);

      transport.handler = (call) => MarketplaceTransportData(<String, Object?>{
        ..._meeting(),
        'revision': 'x',
      });
      expect((await adapter.fetchMeeting(_meetingId)).isFailure, isTrue);
    });

    test(
      'propose and reschedule send the resolved schedule fields and key',
      () async {
        transport.handler = (call) => MarketplaceTransportData(_meeting());
        await adapter.proposeMeeting(
          conversationId: _conversationId,
          input: scheduleInput(occurrence: RepeatedTimeOccurrence.later),
          operationKey: 'propose-key-1',
        );
        final input =
            transport.calls.single.params['p_input']! as Map<String, Object?>;
        expect(transport.calls.single.function, 'meeting_propose');
        expect(transport.calls.single.params['p_key'], 'propose-key-1');
        expect(input['schedule_timezone'], 'America/New_York');
        expect(input['schedule_occurrence'], 'later');
        expect(input['place_choice'], 'specific_place');

        transport.handler = (call) => MarketplaceTransportData(
          _meeting(status: 'reschedule_proposed', revision: 3),
        );
        await adapter.proposeReschedule(
          meetingId: _meetingId,
          input: scheduleInput(),
          expectedRevision: 2,
          operationKey: 'reschedule-key-1',
        );
        expect(transport.calls.last.function, 'meeting_reschedule_propose');
        expect(transport.calls.last.params['p_expected_revision'], 2);
        expect(transport.calls.last.params['p_key'], 'reschedule-key-1');
      },
    );

    test('respond and cancel carry the expected revision and key', () async {
      transport.handler = (call) => MarketplaceTransportData(
        _meeting(
          status: 'accepted',
          revision: 2,
          accepted: _revision(status: 'accepted'),
        ),
      );
      final accepted = await adapter.respondToMeeting(
        meetingId: _meetingId,
        accept: true,
        expectedRevision: 1,
        operationKey: 'respond-key-1',
      );
      expect(accepted.valueOrNull!.status, 'accepted');
      expect(transport.calls.single.params['p_accept'], true);
      expect(transport.calls.single.params['p_expected_revision'], 1);
      expect(transport.calls.single.params['p_key'], 'respond-key-1');

      transport.handler = (call) =>
          MarketplaceTransportData(_meeting(status: 'cancelled', revision: 3));
      await adapter.cancelMeeting(
        meetingId: _meetingId,
        expectedRevision: 2,
        operationKey: 'cancel-key-1',
      );
      expect(transport.calls.last.function, 'meeting_cancel');
      expect(transport.calls.last.params['p_key'], 'cancel-key-1');
    });

    test(
      'a lost-response retry reuses the key and a changed payload conflicts',
      () async {
        transport.handler = (call) => MarketplaceTransportData(_meeting());
        await adapter.proposeMeeting(
          conversationId: _conversationId,
          input: scheduleInput(),
          operationKey: 'retry-key-1',
        );
        await adapter.proposeMeeting(
          conversationId: _conversationId,
          input: scheduleInput(),
          operationKey: 'retry-key-1',
        );
        expect(transport.calls, hasLength(2));
        expect(transport.calls.first.params['p_key'], 'retry-key-1');
        expect(transport.calls.last.params['p_key'], 'retry-key-1');

        transport.handler = (call) => const MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.server,
          code: 'P0001',
          message: 'idempotency_conflict',
          statusCode: 409,
        );
        final conflict = await adapter.proposeMeeting(
          conversationId: _conversationId,
          input: scheduleInput(),
          operationKey: 'retry-key-1',
        );
        expect(conflict.isFailure, isTrue);
        expect(conflict.errorOrNull!.kind, RepositoryFailureKind.conflict);
      },
    );

    test('a replaced session rejects the in-flight result', () async {
      transport.handler = (call) => MarketplaceTransportData(_meeting());
      transport.gate = Future<void>.delayed(Duration.zero);
      final pending = adapter.fetchMeeting(_meetingId);
      session.replaceWith('user-b');
      expect((await pending).isFailure, isTrue);
    });
  });

  group('Phase2MarketplaceMeetingsBackend + repository', () {
    test('pagination deduplicates and stops a repeated cursor', () async {
      final cursors = <String?>[];
      final backend = FakeMeetingsBackend()
        ..onLoadPage = (cursor) async {
          cursors.add(cursor);
          return MeetingPageView(
            items: [meetingView()],
            nextCursor: 'page-two',
          );
        };
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);
      await repository.refreshMeetings();
      expect(repository.meetingsHasMore, isTrue);
      await repository.loadMoreMeetings();
      expect(repository.meetings, hasLength(1));
      expect(repository.meetingsHasMore, isFalse);
      await repository.loadMoreMeetings();
      expect(cursors, [null, 'page-two']);
      repository.dispose();
    });

    test('late pagination cannot append into a refreshed list', () async {
      final page = Completer<MeetingPageView>();
      final backend = FakeMeetingsBackend()
        ..onLoadPage = (cursor) async {
          if (cursor != null) return page.future;
          return MeetingPageView(
            items: [meetingView(revision: 2)],
            nextCursor: 'next',
          );
        };
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);
      await repository.refreshMeetings();
      final oldLoad = repository.loadMoreMeetings();
      await repository.refreshMeetings();
      page.complete(
        MeetingPageView(items: [meetingView(revision: 1)], nextCursor: null),
      );
      await oldLoad;
      expect(repository.meetings.single.revision, 2);
      expect(repository.meetingsHasMore, isTrue);
      repository.dispose();
    });
    test('late detail cannot overwrite a newer selected meeting', () async {
      final older = Completer<MeetingView>();
      final backend = FakeMeetingsBackend()
        ..onLoadOne = (id) => id == 'older'
            ? older.future
            : Future.value(meetingView(revision: 2));
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);
      final first = repository.loadMeeting('older');
      await repository.loadMeeting('newer');
      older.complete(meetingView(revision: 1));
      expect(await first, isNull);
      expect(repository.meetingDetail!.revision, 2);
      repository.dispose();
    });

    test(
      'failed detail clears previous record and exposes a safe error',
      () async {
        final backend = FakeMeetingsBackend();
        final repository = LocalMarketplaceRepository(meetingsBackend: backend);
        await repository.loadMeeting('first');
        backend.onLoadOne = (_) async => throw StateError('private diagnostic');
        expect(await repository.loadMeeting('second'), isNull);
        expect(repository.meetingDetail, isNull);
        expect(
          repository.meetingsError,
          'Could not load this meeting. Try again.',
        );
        repository.dispose();
      },
    );
    test('propose, respond and cancel update the cached list', () async {
      final backend = FakeMeetingsBackend();
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);
      await repository.refreshMeetings();
      expect(repository.meetings, hasLength(1));

      final proposed = await repository.proposeMeeting(
        conversationId: _conversationId,
        input: scheduleInput(),
        operationKey: 'propose-key-1',
      );
      expect(proposed.isSuccess, isTrue);
      expect(repository.meetings.single.meetingId, _meetingId);

      backend.onRespond = (_, accept, revision, _) async =>
          meetingView(status: 'accepted', revision: 2);
      final accepted = await repository.respondToMeeting(
        meetingId: _meetingId,
        accept: true,
        expectedRevision: 1,
        operationKey: 'respond-key-1',
      );
      expect(accepted.isSuccess, isTrue);
      expect(repository.meetings.single.status, 'accepted');
      expect(repository.meetingDetail!.status, 'accepted');
    });

    test('a revision conflict is a definitive failure', () async {
      final backend = FakeMeetingsBackend()
        ..onReschedule = (_, _, _, _) async =>
            throw const StoreBackendException(
              'This meeting changed. Refresh and try again.',
            );
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);
      final result = await repository.proposeMeetingReschedule(
        meetingId: _meetingId,
        input: scheduleInput(),
        expectedRevision: 1,
        operationKey: 'reschedule-key-1',
      );
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isFalse);
    });

    test('an ambiguous network failure is reported as uncertain', () async {
      final backend = FakeMeetingsBackend()
        ..onCancel = (_, _, _) async => throw const StoreBackendException(
          'The change could not be confirmed. Retry to check it safely.',
          ambiguous: true,
        );
      final repository = LocalMarketplaceRepository(meetingsBackend: backend);
      final result = await repository.cancelMeeting(
        meetingId: _meetingId,
        expectedRevision: 1,
        operationKey: 'cancel-key-1',
      );
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isTrue);
    });
  });
}
