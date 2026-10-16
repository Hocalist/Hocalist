// Buyer notification preference wiring: server record load/save at the carried
// revision, the mandatory safety switch and the local prototype fallback.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_fonts.dart';

class _FakeNotificationsBackend implements MarketplaceNotificationsBackend {
  _FakeNotificationsBackend({
    this.preferences = NotificationPreferences.defaults,
    this.revision = 1,
    this.failUpdate = false,
  });

  NotificationPreferences preferences;
  int revision;
  bool failUpdate;
  NotificationPreferences? lastUpdate;
  int? lastExpectedRevision;

  @override
  Future<NotificationInboxPage> loadInbox({
    String? cursor,
    int limit = 50,
  }) async => NotificationInboxPage(items: const [], unreadCount: 0);

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<int> markAllRead() async => 0;

  @override
  Future<NotificationPreferencesRecord> loadPreferences() async =>
      NotificationPreferencesRecord(
        preferences: preferences,
        revision: revision,
      );

  @override
  Future<NotificationPreferencesRecord> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  }) async {
    if (failUpdate) {
      throw const StoreBackendException(
        'Could not save notification preferences.',
      );
    }
    lastUpdate = preferences;
    lastExpectedRevision = expectedRevision;
    this.preferences = preferences;
    revision = expectedRevision + 1;
    return NotificationPreferencesRecord(
      preferences: preferences,
      revision: revision,
    );
  }
}

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

  testWidgets('real preferences load and save at the carried revision', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(
      preferences: const NotificationPreferences(messages: false),
      revision: 3,
    );
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotificationPreferences();
    await _pump(
      tester,
      BuyerNotificationPreferencesPage(
        accent: const Color(0xff1917ff),
        repository: repository,
      ),
    );
    expect(
      find.byKey(const Key('buyerNotificationPreferencesLoading')),
      findsNothing,
    );

    await tester.tap(find.text('Messages & chats'));
    await tester.pumpAndSettle();
    expect(backend.lastUpdate, isNotNull);
    expect(backend.lastUpdate!.messages, isTrue);
    expect(backend.lastExpectedRevision, 3);
  });

  testWidgets('safety stays mandatory and a failed save is reported', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(failUpdate: true);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotificationPreferences();
    await _pump(
      tester,
      BuyerNotificationPreferencesPage(
        accent: const Color(0xff1917ff),
        repository: repository,
      ),
    );
    await tester.tap(find.text('Account & safety alerts'));
    await tester.pumpAndSettle();
    expect(backend.lastUpdate, isNull, reason: 'safety is always on');

    await tester.tap(find.text('Offers'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('buyerNotificationPreferencesSaveError')),
      findsOneWidget,
    );
  });

  testWidgets('prototype mode still saves preferences on the device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(
      tester,
      const BuyerNotificationPreferencesPage(accent: Color(0xff1917ff)),
    );
    await tester.tap(find.text('Offers'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('hocalist.buyer.notifications.offers'), isFalse);
  });
}
