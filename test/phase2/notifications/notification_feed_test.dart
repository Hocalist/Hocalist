// Buyer notification feed wiring: real inbox rows, read markers and the
// loading/error/empty states. Fakes only; the prototype fixtures stay covered
// by the approved visual suites.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';

import '../../test_fonts.dart';

class _FakeNotificationsBackend implements MarketplaceNotificationsBackend {
  _FakeNotificationsBackend({this.items = const [], this.failLoad = false});

  List<NotificationInboxItem> items;
  bool failLoad;
  final List<String> markedRead = <String>[];

  @override
  Future<NotificationInboxPage> loadInbox({
    String? cursor,
    int limit = 50,
  }) async {
    if (failLoad) {
      throw const StoreBackendException('Could not load notifications.');
    }
    return NotificationInboxPage(
      items: items,
      unreadCount: items.where((item) => item.isUnread).length,
    );
  }

  @override
  Future<void> markRead(String notificationId) async {
    markedRead.add(notificationId);
  }

  @override
  Future<int> markAllRead() async => 0;

  @override
  Future<NotificationPreferencesRecord> loadPreferences() async =>
      const NotificationPreferencesRecord(
        preferences: NotificationPreferences.defaults,
        revision: 1,
      );

  @override
  Future<NotificationPreferencesRecord> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  }) async => NotificationPreferencesRecord(
    preferences: preferences,
    revision: expectedRevision + 1,
  );
}

NotificationInboxItem _item({
  String id = '90000000-0000-4000-8000-000000000001',
  String kind = 'new_offer',
  String title = 'Northside Tech sent you a new offer',
  DateTime? readAt,
}) => NotificationInboxItem(
  id: id,
  kind: kind,
  title: title,
  body: 'Open Hocalist to review it.',
  createdAt: DateTime.utc(2026, 9, 20, 12),
  readAt: readAt,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('real inbox rows replace the prototype activity', (tester) async {
    final backend = _FakeNotificationsBackend(items: [_item()]);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}, repository: repository),
    );
    expect(find.text('Northside Tech sent you a new offer'), findsOneWidget);
    expect(find.text('Open Hocalist to review it.'), findsOneWidget);
    expect(find.text('2 minutes ago'), findsNothing);
    expect(find.byKey(const Key('approvedActivityUnread')), findsOneWidget);
  });

  testWidgets('tapping an unread row marks it read after the server ack', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(items: [_item()]);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    NotificationInboxItem? opened;
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedBuyerNotificationsPage(
        onBack: () {},
        repository: repository,
        onOpenNotification: (item) => opened = item,
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'approved-activity-tap-90000000-0000-4000-8000-000000000001',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.markedRead, ['90000000-0000-4000-8000-000000000001']);
    expect(opened?.id, backend.items.single.id);
    expect(find.byKey(const Key('approvedActivityUnread')), findsNothing);
  });

  testWidgets('empty and error states stay on the approved surface', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(failLoad: true);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}, repository: repository),
    );
    expect(find.byKey(const Key('approvedActivityError')), findsOneWidget);

    backend.failLoad = false;
    backend.items = [_item(title: 'Your meeting was confirmed')];
    await tester.tap(find.byKey(const Key('approvedActivityRetry')));
    await tester.pumpAndSettle();
    expect(find.text('Your meeting was confirmed'), findsOneWidget);
    expect(find.byKey(const Key('approvedActivityError')), findsNothing);
  });

  testWidgets('an empty inbox shows the empty state', (tester) async {
    final backend = _FakeNotificationsBackend();
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}, repository: repository),
    );
    expect(find.byKey(const Key('approvedActivityEmpty')), findsOneWidget);
  });

  testWidgets('prototype mode keeps the approved fixtures', (tester) async {
    await _pump(tester, ApprovedBuyerNotificationsPage(onBack: () {}));
    expect(find.text('Northside Tech sent you a new offer'), findsOneWidget);
    expect(find.byKey(const Key('approvedActivityEmpty')), findsNothing);
  });
}
