// Shared-domain destination proof for producer-shaped call events.
//
// This test belongs with the integration patch that lets
// `NotificationDestination.fromInbox` delegate to the reviewed call-event
// contract. It verifies the exact 153 producer shape, mismatch rejection and
// the untouched existing mappings.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/notification_destination.dart';
import 'package:hocalist/domain/phase2/notifications.dart';

const callId = '30000000-0000-4000-8000-000000000001';
const conversationId = '50000000-0000-4000-8000-000000000001';

NotificationInboxItem item({
  String kind = 'meeting_update',
  String? deepLink = 'hocalist://chat/$conversationId',
  Map<String, Object?>? payload = const {
    'call_id': callId,
    'conversation_id': conversationId,
    'state': 'ringing',
  },
}) => NotificationInboxItem(
  id: '10000000-0000-4000-8000-000000000001',
  kind: kind,
  title: 'Call event',
  deepLink: deepLink,
  payload: payload,
  createdAt: DateTime.utc(2026, 9, 26),
);

void main() {
  test('producer-shaped call events map to the conversation chat', () {
    for (final state in ['ringing', 'missed', 'declined', 'ended']) {
      final destination = NotificationDestination.fromInbox(
        item(
          payload: {
            'call_id': callId,
            'conversation_id': conversationId,
            'state': state,
          },
        ),
      );
      expect(destination, isNotNull, reason: state);
      expect(destination!.kind, NotificationDestinationKind.chat);
      expect(destination.id, conversationId);
    }
  });

  test('mismatched kind/url combinations stay rejected', () {
    final cases = <NotificationInboxItem>[
      item(deepLink: 'hocalist://offers/$conversationId'),
      item(deepLink: 'hocalist://chat/$conversationId', payload: null),
      item(
        deepLink: 'hocalist://chat/$conversationId',
        payload: const {'call_id': 'not-a-uuid'},
      ),
      item(
        deepLink: 'hocalist://chat/$conversationId',
        payload: const {
          'call_id': callId,
          'conversation_id': '60000000-0000-4000-8000-000000000009',
        },
      ),
    ];
    for (final row in cases) {
      expect(
        NotificationDestination.fromInbox(row),
        isNull,
        reason: '${row.kind} / ${row.deepLink} / ${row.payload}',
      );
    }
  });

  test('the existing reviewed mappings are unchanged', () {
    final message = NotificationDestination.fromInbox(
      item(kind: 'new_message', deepLink: 'hocalist://chat/$conversationId', payload: null),
    );
    expect(message?.kind, NotificationDestinationKind.chat);
    expect(message?.id, conversationId);

    final offer = NotificationDestination.fromInbox(
      item(
        kind: 'new_offer',
        deepLink: 'hocalist://offers/$callId',
        payload: const {'request_id': conversationId},
      ),
    );
    expect(offer?.kind, NotificationDestinationKind.offer);
    expect(offer?.id, callId);
    expect(offer?.requestId, conversationId);

    final meeting = NotificationDestination.fromInbox(
      item(
        kind: 'meeting_update',
        deepLink: 'hocalist://meetings/$callId',
        payload: null,
      ),
    );
    expect(meeting?.kind, NotificationDestinationKind.meeting);
    expect(meeting?.id, callId);
  });
}
