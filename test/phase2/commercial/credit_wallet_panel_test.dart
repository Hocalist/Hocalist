import 'package:hocalist/components/pull_refresh.dart';
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
        builder: (context, child) => RepaintBoundary(
          key: const Key('walletScreen'),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
            body: PullRefreshHost(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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

  testWidgets('current seller fees open their explanation', (tester) async {
    await pump(tester, () async => CreditWalletView.fromJson(creditWalletJson()));
    expect(find.text('Your current targeting fees'), findsOneWidget);
    final help = find.text('How fees work');
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('Do I pay both amounts?'), findsOneWidget);
    expect(find.textContaining('winning total includes the initial fee'), findsOneWidget);
  });

  testWidgets('activity help explains every displayed status, including on an empty ledger', (tester) async {
    await pump(tester, () async => CreditWalletView.fromJson(creditWalletJson(targets: [])), width: 320);
    final help = find.byTooltip('What do these statuses mean?');
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('Activity statuses'), findsOneWidget);
    for (final label in ['Reserved', 'Initial fee charged', 'Completed', 'Released', 'Refunded']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Activity statuses'), findsNothing);
    expect(find.text('No activity here yet'), findsOneWidget);
  });

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
    expect(find.text('Reload'), findsNothing);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
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
    expect(find.text('Resets Mon, Sep 28 · 00:00 UTC'), findsOneWidget);
    expect(find.byKey(const Key('creditWalletWeekly')), findsOneWidget);
    expect(find.byKey(const Key('creditBatch-bt-1')), findsOneWidget);
    expect(find.byKey(const Key('creditWalletNoPacks')), findsOneWidget);
    expect(find.byKey(const Key('creditBatch-bt-1')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('creditBatch-bt-1')));
    await tester.tap(find.byKey(const Key('creditBatch-bt-1')));
    await tester.pumpAndSettle();
    expect(find.text('Winning total'), findsOneWidget);
    expect(find.textContaining('These rates were saved'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rate v40'), findsNothing);
    expect(find.textContaining('Immutable batch rates'), findsNothing);
    expect(find.byKey(const Key('creditTarget-recent-tg-1')), findsOneWidget);
    expect(find.text('Sold camera'), findsOneWidget);
    // No packs are configured, so no pack rate may appear.
    expect(find.byKey(const Key('creditWalletNoPacks')), findsOneWidget);
    expect(find.textContaining('No credit packs available'), findsOneWidget);
    expect(find.textContaining('Item payment stays offline'), findsOneWidget);
  });

  testWidgets('seller opens the reserved total for holds outside recent activity', (tester) async {
    final json = creditWalletJson(reserved: 550, reversalHold: 100, targets: [])
      ..['reserved_offers'] = [
        {'request_title': 'Kitchen repair', 'request_id': 'req-1', 'offer_id': 'abcd-1234',
         'held_minor': 450, 'charged_minor': 0, 'next_step': 'meeting'},
      ];
    await pump(tester, () async => CreditWalletView.fromJson(json), width: 320, scale: 1.6);
    await tester.tap(find.byKey(const Key('creditWalletReserved')));
    await tester.pumpAndSettle();
    expect(find.text('5.50 HC held in your wallet'), findsOneWidget);
    expect(find.text('Kitchen repair'), findsOneWidget);
    expect(find.text('4.50 HC'), findsOneWidget);
    expect(find.textContaining('Your meeting is active'), findsOneWidget);
    expect(find.text('Payment review'), findsOneWidget);
    expect(find.text('Other reserved credits'), findsNothing);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('walletScreen')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${Directory.systemTemp.path}/reserved-seller-layout.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('previous wallet response shows only outstanding holds', (tester) async {
    final json = creditWalletJson(targets: [targetJson(), targetJson(title: 'Finished',
      status: 'won', reserved: 0, charged: 375)]);
    await pump(tester, () async => CreditWalletView.fromJson(json));
    await tester.tap(find.byKey(const Key('creditWalletReserved')));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('Sold camera')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Finished')), findsNothing);
    expect(find.textContaining('The initial fee has been charged'), findsOneWidget);
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
    // Pricing is visible immediately; closing and reopening retains it.
    expect(find.byKey(const Key('creditOption-opt-1')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('creditPacksToggle')));
    await tester.tap(find.byKey(const Key('creditPacksToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('creditOption-opt-1')), findsNothing);
    await tester.tap(find.byKey(const Key('creditPacksToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('creditOption-opt-1')), findsOneWidget);
    expect(find.text('40.00 HC'), findsWidgets);
    expect(find.text('1.45 HC'), findsOneWidget);
    expect(find.text('Winning total'), findsOneWidget);
    expect(find.byKey(const Key('creditWalletNoPacks')), findsNothing);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('wallet content fits $width at $scale', (tester) async {
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
        await pump(tester, () async => view, width: width, scale: scale);
        expect(find.byKey(const Key('creditBatch-bt-1')), findsOneWidget);
        expect(find.byKey(const Key('walletPage-creditBatch')), findsOneWidget);
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
              final file = File('${Directory.systemTemp.path}/credit-wallet-current.png');
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
