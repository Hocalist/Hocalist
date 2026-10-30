import 'package:hocalist/components/pull_refresh.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/saved/saved_item_button.dart';
import 'package:hocalist/data/phase2/marketplace/saved_item_reference.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_saved_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'support/marketplace_fakes.dart';
import '../../test_fonts.dart';

void main() {
  testWidgets('bookmark retry preserves desired state and operation key', (
    tester,
  ) async {
    var saved = false;
    final keys = <String>[];
    final targets = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedItemButton(
            read: () async => saved,
            setSaved: (target, key) async {
              keys.add(key);
              targets.add(target);
              saved = target;
              if (keys.length == 1) throw StateError('lost acknowledgement');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save request'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from saved'), findsNothing);
    await tester.tap(find.text('Retry saved action'));
    await tester.pumpAndSettle();
    expect(targets, [true, true]);
    expect(keys[0], keys[1]);
    expect(find.text('Remove from saved'), findsOneWidget);
  });

  testWidgets('saved removal waits for acknowledgement and keeps retry key', (
    tester,
  ) async {
    final keys = <String>[];
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SavedItemsPage(
              accent: Colors.green,
              realMode: true,
              load: () async => removed
                  ? []
                  : [
                      const SavedContent(
                        title: 'Saved record',
                        description: 'Description',
                        kind: 'Request',
                        reference: SavedItemReference(
                          id: requestId,
                          type: 'request',
                        ),
                      ),
                    ],
              remove: (_, key) async {
                keys.add(key);
                if (keys.length == 1) throw StateError('network');
                removed = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Saved record'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(keys[0], keys[1]);
    expect(find.text('Nothing saved yet'), findsOneWidget);
  });
  setUpAll(loadHocalistTestFonts);
  late FakeMarketplaceSession session;
  late FakeMarketplaceTransport transport;
  late MarketplaceSavedBackend backend;
  setUp(() {
    session = FakeMarketplaceSession(buyerId);
    transport = FakeMarketplaceTransport();
    backend = MarketplaceSavedBackend(
      MarketplaceDataAdapter(transport: transport, session: session),
      buyerId,
    );
  });
  test('saved references resolve through authorized request reads', () async {
    transport.handler = (call) => MarketplaceTransportData(
      call.function == 'marketplace_saved_items'
          ? {
              'items': [
                {'item_type': 'request', 'item_id': requestId},
              ],
            }
          : requestJson(),
    );
    final items = await backend.load();
    expect(items.single.title, requestJson()['title']);
    expect(transport.calls.map((call) => call.function), [
      'marketplace_saved_items',
      'marketplace_request',
    ]);
  });
  test('replaced session cannot issue saved reads', () async {
    session.replaceWith('other');
    await expectLater(backend.load(), throwsStateError);
    expect(transport.calls, isEmpty);
  });
  test('duplicate saved references are rejected', () async {
    final row = {'item_type': 'request', 'item_id': requestId};
    transport.handler = (_) => MarketplaceTransportData({
      'items': [row, row],
    });
    await expectLater(backend.load(), throwsStateError);
    expect(transport.calls, hasLength(1));
  });
  testWidgets('saved loading failure is not presented as an empty account', (
    tester,
  ) async {
    final pending = Completer<List<SavedContent>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SavedItemsPage(
              accent: Colors.green,
              realMode: true,
              load: () => pending.future,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nothing saved yet'), findsNothing);
    expect(find.text('SAVED CONTENT'), findsOneWidget);
    expect(find.text('Finding your saved content'), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load saved items. Try again.'), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsNothing);
    expect(find.text('SAVED CONTENT'), findsOneWidget);
    expect(find.text('Your saved content is not available'), findsOneWidget);
  });
  testWidgets(
    'refresh retains content and retry recovers without a false empty state',
    (tester) async {
      var calls = 0;
      final refresh = Completer<List<SavedContent>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SavedItemsPage(
                accent: Colors.green,
                realMode: true,
                load: () {
                  calls++;
                  if (calls == 2) return refresh.future;
                  return Future.value([
                    const SavedContent(
                      title: 'Actual saved request',
                      description: 'Actual description',
                      kind: 'Request',
                    ),
                  ]);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<PullRefreshAction>(find.byType(PullRefreshAction).first).onRefresh!();
      await tester.pump();
      expect(find.text('Actual saved request'), findsOneWidget);
      expect(find.text('Updating your saved content…'), findsOneWidget);
      expect(tester.widget<PullRefreshAction>(find.byType(PullRefreshAction).first).onRefresh, isNull);
      refresh.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Actual saved request'), findsOneWidget);
      expect(find.text('Nothing saved yet'), findsNothing);
      tester.widget<PullRefreshAction>(find.byType(PullRefreshAction).first).onRefresh!();
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(find.text('Could not load saved items. Try again.'), findsNothing);
      expect(find.text('Actual saved request'), findsOneWidget);
    },
  );
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('saved content fits width $width scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SavedItemsPage(
                  accent: Colors.green,
                  realMode: true,
                  load: () async => [
                    const SavedContent(
                      title: 'Actual saved request',
                      description: 'Actual description',
                      kind: 'Request',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Actual saved request'), findsOneWidget);
        expect(find.text('Nothing saved yet'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
