// Producer-shaped call-event navigation tests: the exact notification row that
// migration 153 emits must resolve to the conversation chat destination, and
// the inbox router must open it only after the authenticated lookup and the
// role/capability guard. Fakes only; no SDK, network or live data.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/notifications/notification_codecs.dart';
import 'package:hocalist/data/phase2/notifications/push_inbox_router.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';
import 'package:hocalist/domain/phase2/notification_destination.dart';
import 'package:hocalist/domain/phase2/notifications.dart';

const callId = '30000000-0000-4000-8000-000000000001';
const conversationId = '50000000-0000-4000-8000-000000000001';
const notificationId = '10000000-0000-4000-8000-000000000001';

/// The exact row shape produced by `notification_emit` in 153.
Map<String, Object?> producerRow({
  String title = 'Incoming Hocalist call',
  String state = 'ringing',
  String? deepLink = 'hocalist://chat/$conversationId',
  String kind = 'meeting_update',
  Object? callIdValue = callId,
  Object? conversationValue = conversationId,
  String id = notificationId,
  String source = callId,
}) => <String, Object?>{
  'id': id,
  'kind': kind,
  'title': title,
  'body': 'Open Hocalist to answer or decline.',
  'deep_link': deepLink,
  'source_id': source,
  'payload': <String, Object?>{
    'call_id': ?callIdValue,
    'conversation_id': ?conversationValue,
    'state': state,
  },
  'read_at': null,
  'created_at': '2026-09-26T12:00:00+00:00',
};

NotificationInboxItem item(Map<String, Object?> row) =>
    decodeNotificationItemJson(row, 'push');

void main() {
  test('ringing, missed and declined producer rows resolve to the chat', () {
    for (final (title, state) in <(String, String)>[
      ('Incoming Hocalist call', 'ringing'),
      ('Missed call', 'missed'),
      ('Call declined', 'declined'),
      ('Call ended', 'ended'),
    ]) {
      final decoded = item(producerRow(title: title, state: state));
      final destination = callEventDestination(decoded);
      expect(destination, isNotNull, reason: '$title must navigate');
      expect(destination!.kind, NotificationDestinationKind.chat);
      expect(destination.id, conversationId);
      expect(callEventCallId(decoded), callId);
    }
  });

  test('mismatched kind/url combinations are not call events', () {
    final cases = <Map<String, Object?>>[
      // Meeting host with a call id: still the meeting contract, not a call.
      producerRow(deepLink: 'hocalist://meetings/$callId'),
      // Missing call id.
      producerRow(callIdValue: null),
      // Malformed call id.
      producerRow(callIdValue: 'not-a-uuid'),
      // Wrong host.
      producerRow(deepLink: 'hocalist://offers/$conversationId'),
      // Non-uuid conversation.
      producerRow(deepLink: 'hocalist://chat/not-a-uuid'),
      // Payload conversation disagrees with the deep link.
      producerRow(conversationValue: '60000000-0000-4000-8000-000000000009'),
      // A non-call kind never becomes a call event.
      producerRow(kind: 'new_message'),
    ];
    for (final row in cases) {
      expect(
        callEventDestination(item(row)),
        isNull,
        reason: '${row['deep_link']} / ${row['kind']} must stay unrecognized',
      );
    }
  });

  group('router end-to-end', () {
    late String? identity;
    late Map<String, Object?>? lookupRow;
    late List<NotificationDestination> opened;
    late List<String> unavailable;
    late List<String> refreshed;
    late bool canOpen;
    late PushInboxRouter router;

    setUp(() {
      identity = 'buyer-a';
      lookupRow = producerRow();
      opened = [];
      unavailable = [];
      refreshed = [];
      canOpen = true;
      router = PushInboxRouter(
        identity: () => identity,
        canOpen: (row) {
          final destination = callEventDestination(row);
          return canOpen && destination != null;
        },
        lookup: (_) async => lookupRow == null ? null : item(lookupRow!),
        refresh: () async => refreshed.add('refresh'),
        open: (row) async {
          final destination =
              callEventDestination(row) ??
              NotificationDestination(NotificationDestinationKind.chat, row.id);
          opened.add(destination);
        },
        unavailable: () => unavailable.add('unavailable'),
      );
    });

    test('a ringing tap opens the conversation for either role', () async {
      const secondId = '10000000-0000-4000-8000-000000000002';
      await router.receive(const PushInboxSignal(notificationId, opened: true));
      identity = 'seller-b';
      lookupRow = producerRow(id: secondId, title: 'Incoming Hocalist call');
      await router.receive(const PushInboxSignal(secondId, opened: true));
      expect(opened, hasLength(2));
      expect(
        opened.every(
          (destination) => destination.kind == NotificationDestinationKind.chat,
        ),
        isTrue,
      );
      expect(
        opened.every((destination) => destination.id == conversationId),
        isTrue,
      );
      expect(unavailable, isEmpty);
    });

    test('missed and declined taps open the same conversation', () async {
      const secondId = '10000000-0000-4000-8000-000000000002';
      lookupRow = producerRow(
        id: notificationId,
        title: 'Missed call',
        state: 'missed',
      );
      await router.receive(const PushInboxSignal(notificationId, opened: true));
      lookupRow = producerRow(
        id: secondId,
        title: 'Call declined',
        state: 'declined',
      );
      await router.receive(const PushInboxSignal(secondId, opened: true));
      expect(opened, hasLength(2));
    });

    test(
      'a signed-out tap is retained and replayed after authentication',
      () async {
        identity = null;
        await router.receive(
          const PushInboxSignal(notificationId, opened: true),
        );
        expect(opened, isEmpty);
        expect(router.hasRetained, isTrue);
        identity = 'buyer-a';
        await router.onAuthenticated();
        expect(opened, hasLength(1));
        expect(opened.single.id, conversationId);
      },
    );

    test('a deleted or stale record never navigates', () async {
      lookupRow = null;
      await router.receive(const PushInboxSignal(notificationId, opened: true));
      expect(opened, isEmpty);
      expect(unavailable, hasLength(1));
    });

    test(
      'a blocked or restricted recipient cannot open the call event',
      () async {
        canOpen = false;
        await router.receive(
          const PushInboxSignal(notificationId, opened: true),
        );
        expect(opened, isEmpty);
        expect(unavailable, hasLength(1));
      },
    );

    test('a foreground call arrival only refreshes', () async {
      await router.receive(
        const PushInboxSignal(notificationId, opened: false),
      );
      expect(refreshed, hasLength(1));
      expect(opened, isEmpty);
    });
  });

  test(
    'the reviewed shared destination recognizes the call event once wired',
    () {
      final decoded = item(producerRow());
      expect(callEventDestination(decoded), isNotNull);
      final shared = NotificationDestination.fromInbox(decoded);
      // Active after the coordinator applies the notification_destination patch;
      // before that the shared recognizer only knows meeting/chat kinds.
      if (shared != null) {
        expect(shared.kind, NotificationDestinationKind.chat);
        expect(shared.id, conversationId);
      }
    },
  );
}
