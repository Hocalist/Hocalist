import 'package:hocalist/components/pull_refresh.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/support/support_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/features/support/support_cases_page.dart';
import '../marketplace/support/marketplace_fakes.dart';

const caseId = '10000000-0000-4000-8000-000000000001';
void main() {
  for (final width in [320.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('context report fits $width at $scale', (tester) async {
        final transport = FakeMarketplaceTransport();
        transport.handler = (_) =>
            const MarketplaceTransportData({'items': [], 'next_cursor': null});
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SupportCasesPage(
                  adapter: SupportAdapter(
                    transport: transport,
                    session: FakeMarketplaceSession('a'),
                  ),
                  onBack: () {},
                  conversationId: caseId,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Send report'));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('supportConversation')), findsOneWidget);
      });
    }
  }
  late FakeMarketplaceSession session;
  late FakeMarketplaceTransport transport;
  late SupportAdapter adapter;
  setUp(() {
    session = FakeMarketplaceSession('a');
    transport = FakeMarketplaceTransport();
    adapter = SupportAdapter(transport: transport, session: session);
  });
  test(
    'signed out never dispatches; replacement discards in-flight report',
    () async {
      session.currentUserId = null;
      expect((await adapter.cases()).isFailure, true);
      expect(transport.calls, isEmpty);
      session.currentUserId = 'a';
      final gate = Completer<void>();
      transport.gate = gate.future;
      transport.handler = (_) => const MarketplaceTransportData({
        'id': caseId,
        'status': 'open',
        'revision': 1,
      });
      final pending = adapter.submit(
        reason: 'safety',
        body: 'Synthetic concern',
        operationKey: 'same-key',
      );
      session.currentUserId = 'b';
      gate.complete();
      expect((await pending).errorOrNull?.kind.name, 'permissionDenied');
    },
  );
  test(
    'submission wire preserves intent and server controls identity',
    () async {
      transport.handler = (_) => const MarketplaceTransportData({
        'id': caseId,
        'status': 'open',
        'revision': 1,
      });
      expect(
        (await adapter.submit(
          reason: 'safety',
          body: 'Synthetic concern',
          operationKey: 'same-key',
        )).valueOrNull,
        caseId,
      );
      expect(transport.calls.single.params, {
        'p_operation': 'create',
        'p_key': 'same-key',
        'p_input': {'reason_code': 'safety', 'body': 'Synthetic concern'},
      });
    },
  );
  test('malformed case list is safely rejected', () async {
    transport.handler = (_) => const MarketplaceTransportData({
      'items': [
        {'id': caseId, 'body': 'secret'},
      ],
      'next_cursor': null,
    });
    expect((await adapter.cases()).errorOrNull?.kind.name, 'malformedResponse');
  });
  testWidgets(
    'validation keeps case state visible and does not claim a loading failure',
    (tester) async {
      transport.handler = (_) =>
          const MarketplaceTransportData({'items': [], 'next_cursor': null});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportCasesPage(adapter: adapter, onBack: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(find.text('Check your report'), findsOneWidget);
      expect(
        find.text('Choose a reason and add at least 10 characters.'),
        findsOneWidget,
      );
      expect(find.text('Support could not be loaded'), findsNothing);
      expect(find.byKey(const Key('supportError')), findsNothing);
      expect(find.text('No reports submitted yet.'), findsOneWidget);
      expect(
        transport.calls.where((call) => call.function == 'support_command'),
        isEmpty,
      );
    },
  );
  testWidgets(
    'report waits for acknowledgement and uncertain retry keeps same key',
    (tester) async {
      var attempts = 0;
      transport.handler = (call) {
        if (call.function == 'support_reasons') {
          return const MarketplaceTransportData({
            'items': [
              {'code': 'safety', 'label': 'Unsafe interaction'},
            ],
          });
        }
        if (call.function == 'support_list') {
          return const MarketplaceTransportData({
            'items': [],
            'next_cursor': null,
          });
        }
        if (++attempts == 1) {
          return const MarketplaceTransportError(
            kind: MarketplaceTransportErrorKind.connectivity,
          );
        }
        return const MarketplaceTransportData({
          'id': caseId,
          'status': 'open',
          'revision': 1,
        });
      };
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportCasesPage(
              adapter: adapter,
              onBack: () {},
              conversationId: caseId,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select report reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unsafe interaction').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('supportBody')),
        'Please review this synthetic safety concern.',
      );
      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supportAcknowledged')), findsNothing);
      expect(find.text('Retry report'), findsOneWidget);
      expect(find.text('Report not confirmed'), findsOneWidget);
      expect(find.text('Support could not be loaded'), findsNothing);
      expect(find.text('No reports submitted yet.'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry report'));
      await tester.tap(find.text('Retry report'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supportAcknowledged')), findsOneWidget);
      final writes = transport.calls
          .where((c) => c.function == 'support_command')
          .toList();
      expect(writes, hasLength(2));
      expect(writes[0].params, writes[1].params);
      expect(
        (writes[0].params['p_input'] as Map)['body'],
        'Please review this synthetic safety concern.\n\nConversation reference: $caseId',
      );
      expect(find.byKey(const Key('supportConversation')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('supportBody')))
            .maxLength,
        4000 - '\n\nConversation reference: $caseId'.length,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed next page preserves cases and retries same cursor', (
    tester,
  ) async {
    var moreCalls = 0;
    transport.handler = (call) {
      if (call.function == 'support_reasons') {
        return const MarketplaceTransportData({'items': []});
      }
      if (call.params['p_cursor'] != null) {
        moreCalls++;
        expect(call.params['p_cursor'], caseId);
        return const MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.connectivity,
        );
      }
      return const MarketplaceTransportData({
        'items': [
          {
            'id': caseId,
            'reason': 'Safety',
            'body': 'Existing case details',
            'status': 'open',
            'revision': 1,
            'created_at': '2026-09-23T10:00:00Z',
          },
        ],
        'next_cursor': caseId,
      });
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportCasesPage(adapter: adapter, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.ensureVisible(find.text('Load more cases'));
      await tester.tap(find.text('Load more cases'));
      await tester.pumpAndSettle();
      expect(find.text('Existing case details'), findsOneWidget);
      expect(find.text('No reports submitted yet.'), findsNothing);
    }
    expect(moreCalls, 2);
  });
  testWidgets('failed refresh retains previously loaded cases', (tester) async {
    var reads = 0;
    transport.handler = (call) {
      if (call.function == 'support_reasons') {
        return const MarketplaceTransportData({'items': []});
      }
      if (++reads > 1) {
        return const MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.connectivity,
        );
      }
      return const MarketplaceTransportData({
        'items': [
          {
            'id': caseId,
            'reason': 'Safety',
            'body': 'Existing case details',
            'status': 'open',
            'revision': 1,
            'created_at': '2026-09-23T10:00:00Z',
          },
        ],
        'next_cursor': null,
      });
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportCasesPage(adapter: adapter, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<PullRefreshAction>(find.byType(PullRefreshAction).first).onRefresh!();
    await tester.pumpAndSettle();
    expect(find.text('Existing case details'), findsOneWidget);
    expect(find.text('Support could not be loaded'), findsOneWidget);
    expect(find.text('No reports submitted yet.'), findsNothing);
  });
}
