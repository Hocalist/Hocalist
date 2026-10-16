import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/commercial/buyer_rewards_panel.dart';

import '../../test_fonts.dart';
import 'support/commercial_payloads.dart';

void main() {
  setUpAll(loadHocalistTestFonts);

  final value = RewardWalletView.fromJson(
    rewardWalletJson(),
  );

  testWidgets(
    'does not display a fabricated balance while loading or after failure',
    (tester) async {
      final pending = Completer<RewardWalletView>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BuyerRewardsPanel(load: () => pending.future)),
        ),
      );
      expect(find.textContaining('\$'), findsNothing);
      pending.completeError(StateError('private backend message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.textContaining('private backend'), findsNothing);
      expect(find.textContaining('\$'), findsNothing);
      // A retry is offered and re-invokes the loader.
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BuyerRewardsPanel(
              load: () async {
                retried++;
                throw StateError('still down');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('buyerRewardsRetry')));
      await tester.pumpAndSettle();
      expect(retried, 1);
    },
  );

  testWidgets('renders the authoritative earned/held/available split', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BuyerRewardsPanel(load: () async => value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buyerRewardsAvailable')), findsOneWidget);
    expect(find.text('\$0.00'), findsWidgets);
    expect(find.byKey(const Key('buyerRewardsEarned')), findsOneWidget);
    expect(find.byKey(const Key('buyerRewardsHeld')), findsOneWidget);
    expect(find.byKey(const Key('buyerRewardsPolicy')), findsOneWidget);
    expect(find.text('Sold laptop'), findsOneWidget);
    // Payout execution is off, so the withdrawal action stays honest.
    expect(
      find.byKey(const Key('buyerRewardsPayoutUnavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('not available yet'), findsOneWidget);
  });

  testWidgets('an unconfigured policy shows no assumed rate', (tester) async {
    final unconfigured = RewardWalletView.fromJson(
      rewardWalletJson(
        policyConfigured: false,
        withdrawalConfigured: false,
        earned: 0,
        held: 0,
        pending: 0,
        items: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BuyerRewardsPanel(load: () async => unconfigured)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('buyerRewardsPolicyUnavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('buyerRewardsWithdrawalUnavailable')),
      findsOneWidget,
    );
    expect(find.text('No earned rewards yet.'), findsOneWidget);
    expect(find.textContaining('\$0.15'), findsNothing);
    expect(find.textContaining('\$0.30'), findsNothing);
  });

  testWidgets('an unrecovered reversal is disclosed without a second debit', (
    tester,
  ) async {
    final withShortfall = RewardWalletView.fromJson(
      rewardWalletJson(
        earned: 7000,
        pending: 0,
        paid: 4000,
        shortfall: 4000,
        items: [
          {
            'id': 'paid-reward',
            'amount_minor': 4000,
            'created_at': '2026-09-23T12:00:00Z',
            'status': 'earned',
            'hold_minor': 0,
            'reversed_minor': 0,
            'shortfall_minor': 4000,
            'item_title': 'Paid reward',
          },
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BuyerRewardsPanel(load: () async => withShortfall),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buyerRewardsShortfall')), findsOneWidget);
    expect(find.textContaining(r'$40.00'), findsWidgets);
    // Availability is the unrelated remaining balance, not zeroed by the loss.
    expect(find.byKey(const Key('buyerRewardsAvailable')), findsOneWidget);
    expect(find.text(r'$30.00'), findsWidgets);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('reward content fits $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
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
                      child: BuyerRewardsPanel(load: () async => value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('buyerRewardsPanel')), findsOneWidget);
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
              final file = File('.codex-local/rewards-current.png');
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
