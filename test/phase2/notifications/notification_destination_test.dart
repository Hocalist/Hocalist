import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/notification_destination.dart';
import 'package:hocalist/domain/phase2/notifications.dart';

const id = '90000000-0000-4000-8000-000000000001';
NotificationInboxItem item(
  String kind,
  String link, {
  Map<String, Object?>? payload,
}) => NotificationInboxItem(
  id: id,
  kind: kind,
  title: 'Update',
  deepLink: link,
  payload: payload,
  createdAt: DateTime.utc(2026),
);

void main() {
  test('chat notifications retain their exact validated deal identity', () {
    final destination=NotificationDestination.fromInbox(item('new_message','hocalist://chat/$id',payload:{'offer_id':id}));
    expect(destination!.offerId,id);
    expect(NotificationDestination.fromInbox(item('new_message','hocalist://chat/$id',payload:{'offer_id':'bad'}))!.offerId,isNull);
  });
  test('recognizes the three deployed producer destinations', () {
    expect(
      NotificationDestination.fromInbox(
        item('new_message', 'hocalist://chat/$id'),
      )!.kind,
      NotificationDestinationKind.chat,
    );
    expect(
      NotificationDestination.fromInbox(
        item('meeting_update', 'hocalist://meetings/$id'),
      )!.kind,
      NotificationDestinationKind.meeting,
    );
    final offer = NotificationDestination.fromInbox(
      item('new_offer', 'hocalist://offers/$id', payload: {'request_id': id}),
    );
    expect(offer!.kind, NotificationDestinationKind.offer);
    expect(offer.requestId, id);
    final update = NotificationDestination.fromInbox(
      item(
        'request_update',
        'hocalist://offers/$id',
        payload: {'request_id': id, 'offer_id': id},
      ),
    );
    expect(update!.kind, NotificationDestinationKind.offer);
    expect(update.requestId, id);
    expect(
      NotificationDestination.fromInbox(
        item('billing_update', 'hocalist://billing/$id'),
      )!.kind,
      NotificationDestinationKind.billing,
    );
    expect(
      NotificationDestination.fromInbox(
        item('account_update', 'hocalist://account/$id'),
      )!.kind,
      NotificationDestinationKind.account,
    );
  });
  test('refuses external, malformed or mismatched destinations', () {
    for (final link in [
      'https://example.com/$id',
      'hocalist://chat/not-an-id',
      'hocalist://chat/$id/extra',
      'hocalist://user@chat/$id',
      'hocalist://chat:443/$id',
      'hocalist://chat/$id?next=admin',
      'hocalist://chat/$id#extra',
      'hocalist://admin/$id',
      'hocalist://meetings/$id',
    ]) {
      expect(
        NotificationDestination.fromInbox(item('new_message', link)),
        isNull,
        reason: link,
      );
    }
  });
  test('offers require an explicit valid request identity', () {
    for (final payload in [
      null,
      <String, Object?>{},
      {'request_id': 5},
      {'request_id': 'unknown'},
    ]) {
      expect(
        NotificationDestination.fromInbox(
          item('new_offer', 'hocalist://offers/$id', payload: payload),
        ),
        isNull,
      );
    }
  });
}
