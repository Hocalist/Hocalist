/// Notification inbox contracts for Phase 2.
///
/// The inbox is a participant-owned read model over committed events. Content,
/// read markers and preferences are server-owned; this library carries the
/// identifiers, bounded values and typed results the screens need. Safety
/// alerts are mandatory and cannot be disabled.
library;

import 'common.dart';
import 'profiles.dart';

/// One inbox row.
class NotificationInboxItem {
  NotificationInboxItem({
    required String id,
    required String kind,
    required String title,
    this.body = '',
    this.activitySummary = '',
    this.deepLink,
    String? sourceId,
    this.payload,
    DateTime? readAt,
    required DateTime createdAt,
  }) : id = requireNonBlank(id, 'id'),
       kind = requireNonBlank(kind, 'kind'),
       title = requireNonBlank(title, 'title'),
       sourceId = optionalNonBlank(sourceId, 'sourceId'),
       readAt = readAt?.toUtc(),
       createdAt = createdAt.toUtc() {
    if (body.length > 500) {
      throw ArgumentError.value(body.length, 'body', 'must be at most 500');
    }
  }

  final String id;

  /// Server event kind: `new_offer`, `new_message`, `meeting_update`,
  /// `billing_update` or `account_update`.
  final String kind;
  final String title;
  final String body;

  /// Short authenticated inbox context for the home activity row.
  final String activitySummary;

  /// In-app route link (`hocalist://...`), when the server supplied one.
  final String? deepLink;
  final String? sourceId;
  final Map<String, Object?>? payload;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  @override
  String toString() => 'NotificationInboxItem($id, $kind, unread: $isUnread)';
}

/// One page of the inbox plus the caller's unread total.
class NotificationInboxPage {
  NotificationInboxPage({
    required List<NotificationInboxItem> items,
    this.nextCursor,
    required this.unreadCount,
  }) : items = List<NotificationInboxItem>.unmodifiable(items) {
    if (unreadCount < 0) {
      throw ArgumentError.value(
        unreadCount,
        'unreadCount',
        'must not be negative',
      );
    }
  }

  final List<NotificationInboxItem> items;

  /// Opaque server cursor, or null when this is the last page.
  final String? nextCursor;
  final int unreadCount;

  bool get hasMore => nextCursor != null;
}

/// Editable preferences plus their server revision.
class NotificationPreferencesRecord {
  const NotificationPreferencesRecord({
    required this.preferences,
    required this.revision,
    this.supportsLeads = false,
  });

  final NotificationPreferences preferences;

  /// 0 means the caller has no stored row yet (server defaults).
  final int revision;

  /// True when the deployed preferences RPC exposes the `leads` topic. Older
  /// servers must not receive an unknown field.
  final bool supportsLeads;
}
