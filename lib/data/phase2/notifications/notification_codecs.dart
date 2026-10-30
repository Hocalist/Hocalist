/// Strict decoders for the notification inbox RPC payloads.
library;

import '../../../domain/phase2/notifications.dart';
import '../../../domain/phase2/profiles.dart';
import '../marketplace/marketplace_codecs.dart';

/// Decodes `notification_inbox` into a page plus the unread total.
NotificationInboxPage decodeNotificationInboxJson(
  Map<String, Object?> row,
  String context,
) {
  final rawItems = row['items'];
  final items = <NotificationInboxItem>[];
  if (rawItems != null) {
    final rows = decodeObjectList(rawItems, '$context.items');
    for (var index = 0; index < rows.length; index++) {
      items.add(
        decodeNotificationItemJson(rows[index], '$context.items[$index]'),
      );
    }
  }
  final unread = row['unread_count'];
  if (unread is! num || unread < 0) {
    throw MarketplaceDecodeException('$context.unread_count');
  }
  final nextCursor = row['next_cursor'];
  if (nextCursor != null &&
      (nextCursor is! String || nextCursor.trim().isEmpty)) {
    throw MarketplaceDecodeException('$context.next_cursor');
  }
  return NotificationInboxPage(
    items: items,
    nextCursor: nextCursor as String?,
    unreadCount: unread.toInt(),
  );
}

/// Decodes one inbox row.
NotificationInboxItem decodeNotificationItemJson(
  Map<String, Object?> row,
  String context,
) {
  final id = row['id'];
  final kind = row['kind'];
  final title = row['title'];
  final body = row['body'];
  final createdAt = row['created_at'];
  if (id is! String ||
      kind is! String ||
      title is! String ||
      createdAt is! String) {
    throw MarketplaceDecodeException(context);
  }
  final payload = row['payload'];
  final sourceId = row['source_id'];
  final deepLink = row['deep_link'];
  final readAt = row['read_at'];
  try {
    return NotificationInboxItem(
      id: id,
      kind: kind,
      title: title,
      body: body is String ? body : '',
      activitySummary: row['activity_summary'] is String
          ? (row['activity_summary'] as String)
          : '',
      deepLink: deepLink is String ? deepLink : null,
      sourceId: sourceId is String ? sourceId : null,
      payload: payload is Map
          ? payload.map((key, value) => MapEntry('$key', value))
          : null,
      readAt: readAt is String ? DateTime.tryParse(readAt)?.toUtc() : null,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  } on FormatException {
    throw MarketplaceDecodeException('$context.created_at');
  } on ArgumentError {
    throw MarketplaceDecodeException(context);
  }
}

/// Decodes the preferences RPC payload.
NotificationPreferencesRecord decodeNotificationPreferencesJson(
  Map<String, Object?> row,
  String context,
) {
  bool flag(String field, bool fallback) {
    final value = row[field];
    if (value == null) return fallback;
    if (value is! bool) throw MarketplaceDecodeException('$context.$field');
    return value;
  }

  final revision = row['revision'];
  if (revision is! num || revision < 0) {
    throw MarketplaceDecodeException('$context.revision');
  }
  // Safety is mandatory server-side; a payload that disables it is invalid.
  if (row['safety'] == false) {
    throw MarketplaceDecodeException('$context.safety');
  }
  return NotificationPreferencesRecord(
    preferences: NotificationPreferences(
      offers: flag('offers', true),
      messages: flag('messages', true),
      deals: flag('deals', true),
      leads: flag('leads', true),
      safety: true,
    ),
    revision: revision.toInt(),
    supportsLeads: row.containsKey('leads'),
  );
}
