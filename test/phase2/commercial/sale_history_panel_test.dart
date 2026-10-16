import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/commercial/sale_history_panel.dart';

import '../../test_fonts.dart';
import 'support/commercial_payloads.dart';

void main() {
  setUpAll(loadHocalistTestFonts);

  Future<void> pump(
    WidgetTester tester, {
    required Future<List<SaleHistoryEntryView>> Function({
      DateTime? beforeTime,
      String? beforeId,
    })
    load,
    Future<SaleDetailView> Function(String outcomeId)? loadDetail,
    double width = 390,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Nunito'),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1400),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: const Key('capture'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SaleHistoryPanel(load: load, loadDetail: loadDetail),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed read never shows a fabricated purchase', (tester) async {
    var calls = 0;
    await pump(
      tester,
      load: ({DateTime? beforeTime, String? beforeId}) async {
        calls++;
        throw StateError('history down');
      },
    );
    expect(find.byKey(const Key('saleHistoryError')), findsOneWidget);
    expect(find.textContaining('Sold'), findsNothing);
    await tester.tap(find.byKey(const Key('saleHistoryRetry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('renders purchases and sales with ledger facts', (tester) async {
    await pump(
      tester,
      load: ({DateTime? beforeTime, String? beforeId}) async => [
        SaleHistoryEntryView.fromJson(saleHistoryPurchaseJson()),
        SaleHistoryEntryView.fromJson(saleHistorySaleJson()),
      ],
      loadDetail: (id) async => SaleDetailView.fromJson(
        saleDetailJson(id: id, side: id == 'so-2' ? 'purchase' : 'sale'),
      ),
    );
    expect(find.byKey(const Key('saleHistoryEntry-so-2')), findsOneWidget);
    expect(find.text('Sold camera'), findsOneWidget);
    expect(find.byKey(const Key('saleHistoryEntry-so-1')), findsOneWidget);
    expect(find.text('Sold laptop'), findsOneWidget);
    expect(find.textContaining('Reward held'), findsOneWidget);
    expect(find.textContaining('Fee won'), findsOneWidget);
    expect(find.textContaining('150.00'), findsOneWidget);

    // Drill-down loads once and shows the zoned schedule and offline boundary.
    await tester.tap(find.byKey(const Key('saleHistoryEntry-so-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saleDetail-so-1')), findsOneWidget);
    expect(find.text('America/New_York'), findsOneWidget);
    expect(find.textContaining('Item payment happens offline'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saleHistoryEntry-so-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saleDetail-so-1')), findsNothing);
  });

  testWidgets('a failed drill-down is honest and retryable', (tester) async {
    var detailCalls = 0;
    await pump(
      tester,
      load: ({DateTime? beforeTime, String? beforeId}) async => [
        SaleHistoryEntryView.fromJson(saleHistorySaleJson()),
      ],
      loadDetail: (id) async {
        detailCalls++;
        throw StateError('detail down');
      },
    );
    await tester.tap(find.byKey(const Key('saleHistoryEntry-so-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saleDetailError-so-1')), findsOneWidget);
    await tester.tap(find.text('Retry details'));
    await tester.pumpAndSettle();
    expect(detailCalls, 2);
  });

  testWidgets('an empty history is explicit', (tester) async {
    await pump(
      tester,
      load: ({DateTime? beforeTime, String? beforeId}) async => const [],
    );
    expect(find.textContaining('No confirmed purchases yet'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('history content fits $width at $scale', (tester) async {
        await pump(
          tester,
          load: ({DateTime? beforeTime, String? beforeId}) async => [
            SaleHistoryEntryView.fromJson(saleHistoryPurchaseJson()),
            SaleHistoryEntryView.fromJson(saleHistorySaleJson()),
          ],
          loadDetail: (id) async => SaleDetailView.fromJson(
            saleDetailJson(id: id, side: id == 'so-2' ? 'purchase' : 'sale'),
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('saleHistoryPanel')), findsOneWidget);
        if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE')) {
          if (width == 390 && scale == 1.0) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('.codex-local/sale-history-current.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      });
    }
  }
}
