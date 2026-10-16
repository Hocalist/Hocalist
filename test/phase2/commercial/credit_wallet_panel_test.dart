import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/commercial/credit_wallet_panel.dart';

import '../../test_fonts.dart';
import 'support/commercial_payloads.dart';

void main() {
  setUpAll(loadHocalistTestFonts);

  Future<void> pump(
    WidgetTester tester,
    Future<CreditWalletView> Function() load, {
    double width = 390,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Nunito'),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1200),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: const Key('capture'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CreditWalletPanel(load: load),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed read shows no fabricated credits and offers retry', (
    tester,
  ) async {
    var calls = 0;
    await pump(tester, () async {
      calls++;
      throw StateError('ledger down');
    });
    expect(find.byKey(const Key('creditWalletError')), findsOneWidget);
    expect(find.textContaining('HC'), findsNothing);
    expect(find.byKey(const Key('creditWalletAvailable')), findsNothing);
    await tester.tap(find.byKey(const Key('creditWalletRefresh')));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('renders authoritative availability, quota and batch rates', (
    tester,
  ) async {
    final view = CreditWalletView.fromJson(creditWalletJson());
    final semantics = tester.ensureSemantics();
    await pump(tester, () async => view);
    final progress = tester.getSemantics(find.byType(LinearProgressIndicator));
    expect(progress.label, 'Weekly targeting capacity, 2 of 10 used');
    expect(progress.value, '20');
    semantics.dispose();
    expect(find.byKey(const Key('creditWalletAvailable')), findsOneWidget);
    expect(find.text('52.50 HC'), findsOneWidget);
    expect(find.text('54.70 HC'), findsWidgets);
    expect(find.text('2.20 HC'), findsWidgets);
    expect(find.text('5.30 HC'), findsWidgets);
    expect(find.text('2 / 10'), findsOneWidget);
    expect(find.byKey(const Key('creditWalletWeekly')), findsOneWidget);
    expect(find.byKey(const Key('creditBatch-bt-1')), findsNothing);
    expect(find.byKey(const Key('creditWalletNoPacks')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('creditDepositDetailsToggle')),
    );
    await tester.tap(find.byKey(const Key('creditDepositDetailsToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('creditBatch-bt-1')), findsOneWidget);
    expect(find.text('Deposit pricing'), findsWidgets);
    expect(find.textContaining('rate v40'), findsNothing);
    expect(find.textContaining('Immutable batch rates'), findsWidgets);
    expect(find.byKey(const Key('creditTarget-tg-1')), findsOneWidget);
    expect(find.text('Sold camera'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('creditPacksToggle')));
    await tester.tap(find.byKey(const Key('creditPacksToggle')));
    await tester.pumpAndSettle();
    // No packs are configured, so no pack rate may appear.
    expect(find.byKey(const Key('creditWalletNoPacks')), findsOneWidget);
    expect(find.textContaining('No credit packs available'), findsOneWidget);
    expect(find.textContaining('Item payment stays offline'), findsOneWidget);
  });

  testWidgets('empty ledger renders honest empty states', (tester) async {
    final view = CreditWalletView.fromJson(
      creditWalletJson(
        balance: 0,
        reserved: 0,
        charged: 0,
        deposited: 0,
        batches: const [],
        targets: const [],
      ),
    );
    await pump(tester, () async => view);
    await tester.tap(find.byKey(const Key('creditDepositDetailsToggle')));
    await tester.pumpAndSettle();
    expect(find.text('No deposits yet'), findsOneWidget);
    expect(find.byKey(const Key('creditWalletNoTargets')), findsOneWidget);
    expect(find.text('0.00 HC'), findsWidgets);
  });

  testWidgets('configured packs render their immutable snapshot', (
    tester,
  ) async {
    final view = CreditWalletView.fromJson(
      creditWalletJson(
        optionsConfigured: true,
        options: [
          {
            'id': 'opt-1',
            'amount_minor': 4000,
            'initial_fee_minor': 145,
            'winning_total_minor': 325,
            'rate_version': 'v40',
            'active': true,
            'revision': 1,
            'sort_order': 0,
          },
        ],
      ),
    );
    await pump(tester, () async => view);
    expect(find.byKey(const Key('creditOption-opt-1')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('creditPacksToggle')));
    await tester.tap(find.byKey(const Key('creditPacksToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('creditOption-opt-1')), findsOneWidget);
    expect(find.textContaining('40.00 HC pack'), findsOneWidget);
    expect(find.textContaining('Initial 1.45 HC'), findsOneWidget);
    expect(find.byKey(const Key('creditWalletNoPacks')), findsNothing);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('wallet content fits $width at $scale', (tester) async {
        final view = CreditWalletView.fromJson(creditWalletJson());
        await pump(tester, () async => view, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('creditWalletPanel')), findsOneWidget);
        expect(find.byKey(const Key('creditWalletWeekly')), findsOneWidget);
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
              final file = File('.codex-local/credit-wallet-current.png');
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
