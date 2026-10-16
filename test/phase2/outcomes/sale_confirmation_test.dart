import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/outcomes/sale_confirmation.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/features/meetings/sale_confirmation_panel.dart';
import '../marketplace/support/marketplace_fakes.dart';

void main() {
  for (final buyer in [true, false]) {
    testWidgets(
      'explicit refresh reloads meeting before purchase buyer=$buyer',
      (tester) async {
        final order = <String>[];
        final gate = Completer<void>();
        final transport = FakeMarketplaceTransport()
          ..handler = (_) {
            order.add('purchase');
            return const MarketplaceTransportData({'status': 'unconfirmed'});
          };
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SaleConfirmationPanel(
                adapter: SaleConfirmationAdapter(
                  transport: transport,
                  session: FakeMarketplaceSession('a'),
                ),
                meetingId: 'm',
                isBuyer: buyer,
                meetingAccepted: false,
                onRefreshMeeting: () async {
                  order.add('meeting');
                  await gate.future;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(order, ['purchase']);
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('saleConfirmationRefresh')),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pump();
        expect(order, ['purchase', 'meeting']);
        gate.complete();
        await tester.pumpAndSettle();
        expect(order, ['purchase', 'meeting', 'purchase']);
      },
    );
  }
  for (final buyer in [true, false]) {
    testWidgets('unaccepted meeting has no PIN action for buyer=$buyer', (
      tester,
    ) async {
      final transport = FakeMarketplaceTransport()
        ..handler = (_) =>
            const MarketplaceTransportData({'status': 'unconfirmed'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SaleConfirmationPanel(
              adapter: SaleConfirmationAdapter(
                transport: transport,
                session: FakeMarketplaceSession('a'),
              ),
              meetingId: 'm',
              isBuyer: buyer,
              meetingAccepted: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saleConfirmationAction')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Both sides must accept'), findsOneWidget);
      expect(transport.calls.single.params['p_action'], 'status');
    });
  }
  test('PIN expiry must carry an explicit timezone', () async {
    final transport = FakeMarketplaceTransport()
      ..handler = (_) => const MarketplaceTransportData({
        'status': 'ready',
        'pin': '12345',
        'expires_at': '2026-10-01T00:00:00',
      });
    final adapter = SaleConfirmationAdapter(
      transport: transport,
      session: FakeMarketplaceSession('a'),
    );
    await expectLater(adapter.call('m', 'display'), throwsException);
  });
  test(
    'signed out and replacement identities cannot read PIN results',
    () async {
      final session = FakeMarketplaceSession(null);
      final transport = FakeMarketplaceTransport();
      final adapter = SaleConfirmationAdapter(
        transport: transport,
        session: session,
      );
      await expectLater(adapter.call('m', 'display'), throwsStateError);
      expect(transport.calls, isEmpty);
      session.currentUserId = 'a';
      final gate = Completer<void>();
      transport.gate = gate.future;
      final pending = adapter.call('m', 'display');
      session.currentUserId = 'b';
      gate.complete();
      await expectLater(pending, throwsStateError);
    },
  );
  test('reject unknown response and redact digits from debug output', () async {
    final transport = FakeMarketplaceTransport()
      ..handler = (_) => const MarketplaceTransportData({
        'status': 'ready',
        'pin': '123',
        'expires_at': '2026-10-01T00:00:00Z',
      });
    final adapter = SaleConfirmationAdapter(
      transport: transport,
      session: FakeMarketplaceSession('a'),
    );
    await expectLater(adapter.call('m', 'display'), throwsStateError);
    expect(
      const SaleConfirmationResult('ready', pin: '43891').toString(),
      isNot(contains('43891')),
    );
  });
  testWidgets('buyer PIN is transient and cleared when app backgrounds', (
    tester,
  ) async {
    final transport = FakeMarketplaceTransport()
      ..handler = (call) => MarketplaceTransportData(
        call.params['p_action'] == 'display'
            ? {
                'status': 'ready',
                'pin': '43891',
                'expires_at': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              }
            : {'status': 'unconfirmed'},
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaleConfirmationPanel(
            adapter: SaleConfirmationAdapter(
              transport: transport,
              session: FakeMarketplaceSession('a'),
            ),
            meetingId: 'm',
            isBuyer: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show my purchase PIN'));
    await tester.pumpAndSettle();
    expect(find.text('43891'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('43891'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('seller waits for server success and clears entered PIN', (
    tester,
  ) async {
    var confirmations = 0;
    final transport = FakeMarketplaceTransport()
      ..handler = (call) => MarketplaceTransportData({
        'outcome_id': '80000000-0000-4000-8000-000000000001',
        'confirmed_at': '2026-09-23T00:00:00Z',
        'status': call.params['p_action'] == 'verify'
            ? 'confirmed'
            : 'unconfirmed',
      });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaleConfirmationPanel(
            adapter: SaleConfirmationAdapter(
              transport: transport,
              session: FakeMarketplaceSession('b'),
            ),
            meetingId: 'm',
            isBuyer: false,
            onPurchaseConfirmed: () => confirmations++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(confirmations, 0);
    await tester.enterText(find.byType(TextField), '43891');
    await tester.tap(find.text('Confirm completed purchase'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Purchase confirmed.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(transport.calls.last.params['p_pin'], '43891');
    expect(confirmations, 1);
    expect(tester.takeException(), isNull);
  });
}
