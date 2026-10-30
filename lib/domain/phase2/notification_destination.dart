import 'communication_completion.dart';
import 'notifications.dart';

enum NotificationDestinationKind { offer, chat, meeting, billing, account }

/// Only recognized inbox routes become navigation intents. An intent never
/// grants access: the destination must still be loaded through authorized RPCs.
class NotificationDestination {
  const NotificationDestination(
    this.kind,
    this.id, {
    this.requestId,
    this.offerId,
  });

  final NotificationDestinationKind kind;
  final String id;
  final String? requestId;
  final String? offerId;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static NotificationDestination? fromInbox(NotificationInboxItem item) {
    // Producer-shaped call events (migration 153): `meeting_update` rows with a
    // `hocalist://chat/<conversationId>` link and a payload `call_id`. Only
    // that exact combination is accepted; everything else falls through to the
    // existing kind/host mapping below.
    final callEvent = callEventDestination(item);
    if (callEvent != null) return callEvent;
    final uri = Uri.tryParse(item.deepLink ?? '');
    if (uri == null ||
        uri.scheme != 'hocalist' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        !_uuid.hasMatch(uri.pathSegments.single)) {
      return null;
    }
    final kind = switch ((item.kind, uri.host)) {
      ('new_offer', 'offers') => NotificationDestinationKind.offer,
      ('request_update', 'offers') => NotificationDestinationKind.offer,
      ('new_message', 'chat') => NotificationDestinationKind.chat,
      ('meeting_update', 'meetings') => NotificationDestinationKind.meeting,
      ('billing_update', 'billing') => NotificationDestinationKind.billing,
      ('account_update', 'account') => NotificationDestinationKind.account,
      _ => null,
    };
    if (kind == null) return null;
    final requestId = item.payload?['request_id'];
    if (kind == NotificationDestinationKind.offer &&
        (requestId is! String || !_uuid.hasMatch(requestId))) {
      return null;
    }
    return NotificationDestination(
      kind,
      uri.pathSegments.single,
      requestId: requestId is String ? requestId : null,
      offerId:
          item.payload?['offer_id'] is String &&
              _uuid.hasMatch(item.payload!['offer_id'] as String)
          ? item.payload!['offer_id'] as String
          : null,
    );
  }
}
