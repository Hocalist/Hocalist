// Seller notification feed wiring: real inbox rows, filters, read markers and
// the empty/error states. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';

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
  String id = '90000000-0000-4000-8000-000000000011',
  String kind = 'new_offer',
  String title = 'Your offer was selected',
  String body = 'Maya selected your iPad Air offer.',
  DateTime? readAt,
}) => NotificationInboxItem(
  id: id,
  kind: kind,
  title: title,
  body: body,
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
  testWidgets('real destination callback replaces the informational sheet', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(items: [_item()]);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    NotificationInboxItem? opened;
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () {},
        repository: repository,
        onOpenNotification: (item) => opened = item,
      ),
    );
    await tester.tap(find.text('Your offer was selected'));
    await tester.pumpAndSettle();
    expect(opened?.id, backend.items.single.id);
    expect(
      find.byKey(const Key('sellerNotificationDetailsSheet')),
      findsNothing,
    );
  });
  setUpAll(loadHocalistTestFonts);

  testWidgets('real inbox rows replace the prototype seller activity', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(items: [_item()]);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () {},
        repository: repository,
      ),
    );
    expect(find.text('Your offer was selected'), findsOneWidget);
    expect(find.text('New buyer request nearby'), findsNothing);
  });

  testWidgets('the approved filters apply to real rows', (tester) async {
    final backend = _FakeNotificationsBackend(
      items: [
        _item(),
        _item(
          id: '90000000-0000-4000-8000-000000000012',
          kind: 'billing_update',
          title: 'Targeting credit restored',
        ),
      ],
    );
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () {},
        repository: repository,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('sellerNotificationFilter-billing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Targeting credit restored'), findsOneWidget);
    expect(find.text('Your offer was selected'), findsNothing);
  });

  testWidgets('opening a real row marks it read and shows its details', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(items: [_item()]);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () {},
        repository: repository,
      ),
    );
    await tester.tap(find.text('Your offer was selected'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerNotificationDetailsSheet')),
      findsOneWidget,
    );
    expect(backend.markedRead, ['90000000-0000-4000-8000-000000000011']);
  });

  testWidgets('an empty seller inbox shows the empty state', (tester) async {
    final backend = _FakeNotificationsBackend();
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () {},
        repository: repository,
      ),
    );
    expect(find.byKey(const Key('sellerNotificationsEmpty')), findsOneWidget);
  });

  testWidgets('a failed load shows the error and retries', (tester) async {
    final backend = _FakeNotificationsBackend(failLoad: true);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotifications();
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () {},
        repository: repository,
      ),
    );
    expect(find.byKey(const Key('sellerNotificationsError')), findsOneWidget);

    backend.failLoad = false;
    backend.items = [_item(title: 'Buyer request changed')];
    await tester.tap(find.byKey(const Key('sellerNotificationsRetry')));
    await tester.pumpAndSettle();
    expect(find.text('Buyer request changed'), findsOneWidget);
    expect(find.byKey(const Key('sellerNotificationsError')), findsNothing);
  });

  testWidgets('prototype mode keeps the approved seller fixtures', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedSellerNotificationsPage(onBack: () {}, onPreferences: () {}),
    );
    expect(find.text('New buyer request nearby'), findsOneWidget);
    expect(find.byKey(const Key('sellerNotificationsEmpty')), findsNothing);
  });
}
