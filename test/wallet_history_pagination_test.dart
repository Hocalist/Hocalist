import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/wallet_history_list.dart';
import 'test_fonts.dart';

List<WalletHistoryEntry> entries(int count) => List.generate(
  count,
  (i) => WalletHistoryEntry(
    id: '$i',
    title: 'Request ${i + 1} with a longer title',
    date: DateTime.utc(2026, 10, 1 + i),
    amount: '4.50 HC',
    status: 'Completed',
    facts: const {
      'Initial bid': '1.85 HC',
      'Total charged': '4.50 HC',
      'Still reserved': '0.00 HC',
    },
    note: 'Saved deposit rates apply.',
  ),
);

Future<void> pump(
  WidgetTester tester, {
  int count = 12,
  String kind = 'activity',
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Nunito'),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: const Key('capture'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: WalletHistoryList(entries: entries(count), kind: kind),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final kind in ['activity', 'creditBatch']) {
    testWidgets(
      '$kind pages all records and clamps after a shorter refreshed list',
      (tester) async {
        await pump(tester, kind: kind);
        expect(find.text('Page 1 of 3'), findsOneWidget);
        expect(
          find.byType(InkWell),
          findsNWidgets(7),
        ); // five rows plus two page controls
        expect(find.text('Request 12 with a longer title'), findsOneWidget);
        expect(find.text('Request 7 with a longer title'), findsNothing);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Previous'))
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 3'), findsOneWidget);
        expect(find.text('Request 7 with a longer title'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Page 3 of 3'), findsOneWidget);
        expect(find.text('Request 1 with a longer title'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Next'))
              .onPressed,
          isNull,
        );
        await pump(tester, kind: kind, count: 2);
        expect(find.text('Page 1 of 1'), findsOneWidget);
        expect(find.text('Request 2 with a longer title'), findsOneWidget);
      },
    );
  }
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('history row and popup fit $width/$scale', (tester) async {
        await pump(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('activity-11')));
        await tester.pumpAndSettle();
        expect(find.text('Total charged'), findsOneWidget);
        expect(find.text('Still reserved'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Total charged'), findsNothing);
        expect(find.text('Page 1 of 3'), findsOneWidget);
        if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') &&
            width == 390 &&
            scale == 1) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '.codex-local/wallet-paginated-list.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
