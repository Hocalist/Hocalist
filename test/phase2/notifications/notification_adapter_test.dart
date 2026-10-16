// Notification inbox adapter and repository tests. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/notifications/notification_adapter.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/profiles.dart';

import '../marketplace/support/marketplace_fakes.dart';

Map<String, Object?> _item({
  String id = '70000000-0000-4000-8000-000000000001',
  String kind = 'new_offer',
  String title = 'New offer',
  String? readAt,
}) => <String, Object?>{
  'id': id,
  'kind': kind,
  'title': title,
  'body': 'Body text',
  'deep_link': 'hocalist://offers/1',
  'source_id': '40000000-0000-4000-8000-000000000001',
  'payload': <String, Object?>{'k': 1},
  'read_at': readAt,
  'created_at': '2026-05-01T00:00:00+00:00',
};

Map<String, Object?> _inbox({
  List<Map<String, Object?>>? items,
  String? nextCursor,
  int unread = 1,
}) => <String, Object?>{
  'items': items ?? [_item()],
  'next_cursor': nextCursor,
  'unread_count': unread,
};

Map<String, Object?> _preferences({
  bool offers = true,
  bool messages = true,
  bool deals = true,
  int revision = 0,
}) => <String, Object?>{
  'offers': offers,
  'messages': messages,
  'deals': deals,
  'safety': true,
  'revision': revision,
  'updated_at': revision == 0 ? null : '2026-05-01T00:00:00+00:00',
};

NotificationInboxItem notificationItem() => NotificationInboxItem(
  id: '70000000-0000-4000-8000-000000000001',
  kind: 'new_offer',
  title: 'New offer',
  body: 'Body text',
  deepLink: 'hocalist://offers/1',
  sourceId: '40000000-0000-4000-8000-000000000001',
  payload: const <String, Object?>{'k': 1},
  createdAt: DateTime.utc(2026, 5, 1),
);

class FakeNotificationsBackend implements MarketplaceNotificationsBackend {
  Future<NotificationInboxPage> Function({String? cursor, int limit})? onLoad;
  Future<void> Function(String id)? onMarkRead;
  Future<int> Function()? onMarkAll;
  Future<NotificationPreferencesRecord> Function()? onLoadPreferences;
  Future<NotificationPreferencesRecord> Function(
    NotificationPreferences preferences,
    int revision,
  )?
  onUpdate;

  @override
  Future<NotificationInboxPage> loadInbox({String? cursor, int limit = 50}) =>
      onLoad?.call(cursor: cursor, limit: limit) ??
      Future.value(
        NotificationInboxPage(items: [notificationItem()], unreadCount: 1),
      );

  @override
  Future<void> markRead(String notificationId) =>
      onMarkRead?.call(notificationId) ?? Future.value();

  @override
  Future<int> markAllRead() => onMarkAll?.call() ?? Future.value(1);

  @override
  Future<NotificationPreferencesRecord> loadPreferences() =>
      onLoadPreferences?.call() ??
      Future.value(
        NotificationPreferencesRecord(
          preferences: NotificationPreferences.defaults,
          revision: 0,
        ),
      );

  @override
  Future<NotificationPreferencesRecord> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  }) =>
      onUpdate?.call(preferences, expectedRevision) ??
      Future.value(
        NotificationPreferencesRecord(
          preferences: preferences,
          revision: expectedRevision + 1,
        ),
      );
}

void main() {
  group('NotificationDataAdapter', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late NotificationDataAdapter adapter;

    setUp(() {
      session = FakeMarketplaceSession('user-a');
      transport = FakeMarketplaceTransport();
      adapter = NotificationDataAdapter(transport: transport, session: session);
    });

    test('decodes an inbox page with unread count and cursor', () async {
      transport.handler = (call) =>
          MarketplaceTransportData(_inbox(nextCursor: 'next', unread: 2));
      final result = await adapter.fetchInbox(limit: 10);
      expect(result.isSuccess, isTrue);
      final page = result.valueOrNull!;
      expect(page.items.single.kind, 'new_offer');
      expect(page.items.single.deepLink, 'hocalist://offers/1');
      expect(page.unreadCount, 2);
      expect(page.nextCursor, 'next');
      expect(transport.calls.single.function, 'notification_inbox');
      expect(transport.calls.single.params['p_limit'], 10);
    });

    test('rejects malformed inbox payloads', () async {
      transport.handler = (call) =>
          MarketplaceTransportData(_inbox(unread: -1));
      final negative = await adapter.fetchInbox();
      expect(negative.isFailure, isTrue);

      transport.handler = (call) => const MarketplaceTransportData(
        <String, Object?>{'items': 'not-a-list', 'unread_count': 0},
      );
      final malformed = await adapter.fetchInbox();
      expect(malformed.isFailure, isTrue);
    });

    test('rejects an out-of-range limit before the transport', () async {
      final result = await adapter.fetchInbox(limit: 0);
      expect(result.isFailure, isTrue);
      expect(transport.calls, isEmpty);
    });

    test('mark read and mark all read call the reviewed RPCs', () async {
      transport.handler = (call) =>
          const MarketplaceTransportData(<String, Object?>{});
      await adapter.markRead('70000000-0000-4000-8000-000000000001');
      expect(transport.calls.single.function, 'notification_mark_read');
      expect(
        transport.calls.single.params['p_notification'],
        '70000000-0000-4000-8000-000000000001',
      );

      transport.handler = (call) =>
          const MarketplaceTransportData(<String, Object?>{'marked': 3});
      final marked = await adapter.markAllRead();
      expect(marked.valueOrNull, 3);

      transport.handler = (call) =>
          const MarketplaceTransportData(<String, Object?>{'marked': 'x'});
      expect((await adapter.markAllRead()).isFailure, isTrue);
    });

    test(
      'preferences decode defaults and send the expected revision',
      () async {
        transport.handler = (call) => MarketplaceTransportData(_preferences());
        final loaded = await adapter.fetchPreferences();
        expect(loaded.valueOrNull!.revision, 0);
        expect(loaded.valueOrNull!.preferences.offers, isTrue);

        transport.handler = (call) =>
            MarketplaceTransportData(_preferences(offers: false, revision: 1));
        final updated = await adapter.updatePreferences(
          preferences: const NotificationPreferences(offers: false),
          expectedRevision: 0,
        );
        expect(updated.valueOrNull!.preferences.offers, isFalse);
        expect(updated.valueOrNull!.revision, 1);
        final input =
            transport.calls.last.params['p_input']! as Map<String, Object?>;
        expect(input['expected_revision'], 0);
        expect(input['safety'], true);
      },
    );

    test('a payload that disables safety is rejected', () async {
      transport.handler = (call) => MarketplaceTransportData(<String, Object?>{
        ..._preferences(),
        'safety': false,
      });
      final result = await adapter.fetchPreferences();
      expect(result.isFailure, isTrue);
    });

    test('a replaced session rejects the in-flight result', () async {
      transport.handler = (call) => MarketplaceTransportData(_inbox());
      transport.gate = Future<void>.delayed(Duration.zero);
      final pending = adapter.fetchInbox();
      session.replaceWith('user-b');
      final result = await pending;
      expect(result.isFailure, isTrue);
    });
  });

  group('Phase2MarketplaceNotificationsBackend + repository', () {
    test('loads, marks read and marks all read', () async {
      final backend = FakeNotificationsBackend();
      final repository = LocalMarketplaceRepository(
        notificationsBackend: backend,
      );
      await repository.refreshNotifications();
      expect(repository.notifications, hasLength(1));
      expect(repository.notificationsUnreadCount, 1);

      final marked = await repository.markNotificationRead(
        '70000000-0000-4000-8000-000000000001',
      );
      expect(marked, isTrue);
      expect(repository.notifications.single.isUnread, isFalse);
      expect(repository.notificationsUnreadCount, 0);

      await repository.refreshNotifications();
      expect(repository.notificationsUnreadCount, 1);
      final all = await repository.markAllNotificationsRead();
      expect(all, 1);
      expect(repository.notificationsUnreadCount, 0);
    });

    test('a failed read marker leaves the row unread', () async {
      final backend = FakeNotificationsBackend()
        ..onMarkRead = (_) async =>
            throw const StoreBackendException('Could not mark read.');
      final repository = LocalMarketplaceRepository(
        notificationsBackend: backend,
      );
      await repository.refreshNotifications();
      final marked = await repository.markNotificationRead(
        '70000000-0000-4000-8000-000000000001',
      );
      expect(marked, isFalse);
      expect(repository.notifications.single.isUnread, isTrue);
    });

    test('preferences load and update with the carried revision', () async {
      final backend = FakeNotificationsBackend();
      final repository = LocalMarketplaceRepository(
        notificationsBackend: backend,
      );
      await repository.refreshNotificationPreferences();
      expect(repository.notificationPreferences!.revision, 0);

      final result = await repository.updateNotificationPreferences(
        const NotificationPreferences(offers: false),
      );
      expect(result.isSuccess, isTrue);
      expect(result.record!.revision, 1);
      expect(repository.notificationPreferences!.preferences.offers, isFalse);
    });
  });
}
