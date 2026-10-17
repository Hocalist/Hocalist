// Seller notification preference wiring: server record load/save, the mapped
// meetings/deals field, the disabled lead switch and the local prototype
// fallback.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_fonts.dart';

class _FakeNotificationsBackend implements MarketplaceNotificationsBackend {
  _FakeNotificationsBackend({
    this.preferences = NotificationPreferences.defaults,
    this.revision = 1,
    this.failUpdate = false,
    this.supportsLeads = false,
  });

  NotificationPreferences preferences;
  int revision;
  bool failUpdate;
  bool supportsLeads;
  NotificationPreferences? lastUpdate;
  bool? lastIncludeLeads;
  int? lastExpectedRevision;
  Future<void>? updateGate;

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
        supportsLeads: supportsLeads,
      );

  @override
  Future<NotificationPreferencesRecord> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  }) async {
    final gate = updateGate;
    updateGate = null;
    if (gate != null) await gate;
    if (failUpdate) {
      throw const StoreBackendException(
        'Could not save notification preferences.',
      );
    }
    lastUpdate = preferences;
    lastExpectedRevision = expectedRevision;
    lastIncludeLeads = includeLeads;
    this.preferences = preferences;
    revision = expectedRevision + 1;
    return NotificationPreferencesRecord(
      preferences: preferences,
      revision: revision,
      supportsLeads: supportsLeads,
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
  testWidgets(
    'saving one seller switch leaves other choices active and queues their revision',
    (tester) async {
      final backend = _FakeNotificationsBackend();
      final repository = LocalMarketplaceRepository(
        notificationsBackend: backend,
      );
      await repository.refreshNotificationPreferences();
      await _pump(
        tester,
        ApprovedSellerNotificationPreferencesPage(
          onBack: () {},
          repository: repository,
        ),
      );
      final gate = Completer<void>();
      backend.updateGate = gate.future;
      await tester.tap(find.text('Offer updates'));
      await tester.pump();
      SwitchListTile tile(String title) => tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile('Offer updates').onChanged, isNull);
      expect(tile('Messages & chats').onChanged, isNotNull);
      expect(tile('Meetings').onChanged, isNotNull);
      await tester.ensureVisible(find.text('Messages & chats'));
      await tester.tap(find.text('Messages & chats'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(backend.preferences.offers, false);
      expect(backend.preferences.messages, false);
      expect(backend.preferences.deals, true);
      expect(backend.lastExpectedRevision, 2);
    },
  );

  testWidgets('real seller preferences save offers and meetings', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(
      preferences: const NotificationPreferences(offers: false),
      revision: 4,
    );
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotificationPreferences();
    await _pump(
      tester,
      ApprovedSellerNotificationPreferencesPage(
        onBack: () {},
        repository: repository,
      ),
    );
    expect(
      find.byKey(const Key('sellerNotificationPreferencesLoading')),
      findsNothing,
    );

    await tester.tap(find.text('Offer updates'));
    await tester.pumpAndSettle();
    expect(backend.lastUpdate!.offers, isTrue);
    expect(backend.lastExpectedRevision, 4);

    await tester.tap(find.text('Meetings'));
    await tester.pumpAndSettle();
    expect(backend.lastUpdate!.deals, isFalse);
    expect(backend.lastExpectedRevision, 5);
  });

  testWidgets('leads and safety stay unavailable in real mode', (tester) async {
    final backend = _FakeNotificationsBackend();
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotificationPreferences();
    await _pump(
      tester,
      ApprovedSellerNotificationPreferencesPage(
        onBack: () {},
        repository: repository,
      ),
    );
    await tester.tap(find.text('New leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account & safety alerts'));
    await tester.pumpAndSettle();
    expect(backend.lastUpdate, isNull);
  });

  testWidgets('a deployed leads topic enables the lead switch and saves it', (
    tester,
  ) async {
    final backend = _FakeNotificationsBackend(supportsLeads: true);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotificationPreferences();
    await _pump(
      tester,
      ApprovedSellerNotificationPreferencesPage(
        onBack: () {},
        repository: repository,
      ),
    );
    await tester.tap(find.text('New leads'));
    await tester.pumpAndSettle();
    expect(backend.lastUpdate?.leads, isFalse);
    expect(backend.lastIncludeLeads, isTrue);
    expect(backend.lastExpectedRevision, 1);
  });

  testWidgets('a failed seller preference save is reported', (tester) async {
    final backend = _FakeNotificationsBackend(failUpdate: true);
    final repository = LocalMarketplaceRepository(
      notificationsBackend: backend,
    );
    await repository.refreshNotificationPreferences();
    await _pump(
      tester,
      ApprovedSellerNotificationPreferencesPage(
        onBack: () {},
        repository: repository,
      ),
    );
    await tester.tap(find.text('Offer updates'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerNotificationPreferencesSaveError')),
      findsOneWidget,
    );
  });

  testWidgets('prototype mode still saves seller preferences on the device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _pump(
      tester,
      ApprovedSellerNotificationPreferencesPage(onBack: () {}),
    );
    await tester.tap(find.text('Offer updates'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('hocalist.seller.notifications.offers'),
      isFalse,
    );
  });
}
