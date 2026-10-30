import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/seller_subscription_panel.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'phase2/commercial/support/commercial_payloads.dart';

void main() {
  testWidgets('authoritative earned access replaces subscription-only status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SellerSubscriptionPanel(
            loadEntitlement: () async => SellerEntitlementView.fromJson(
              entitlementJson(
                effectivePlan: 'pro',
                effectiveSource: 'earned',
                calendarConfigured: true,
                overlapConfigured: true,
                earnedApplied: true,
              ),
            ),
          )),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pro Seller'), findsOneWidget);
    expect(find.textContaining('Earned Pro'), findsOneWidget);
    expect(find.textContaining('Stripe TEST subscription'), findsNothing);
  });

  testWidgets('failed entitlement never falls back to a guessed free plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerSubscriptionPanel(
            loadEntitlement: () async => throw StateError('private'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load your plan'), findsOneWidget);
    expect(find.text('Free Seller plan'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
  });
  Future<void> show(
    WidgetTester tester,
    Future<Map<String, dynamic>?> Function() load,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SellerSubscriptionPanel(load: load)),
    ),
  );

  testWidgets('reads free plan instead of a static disconnected claim', (
    tester,
  ) async {
    await show(tester, () async => {'plan': 'free'});
    await tester.pumpAndSettle();
    expect(find.text('Free Seller plan'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
  });
  testWidgets('loading and retry never fabricate a paid plan', (tester) async {
    final pending = Completer<Map<String, dynamic>?>();
    var calls = 0;
    await show(tester, () {
      calls++;
      return calls == 1 ? pending.future : Future.value({'plan': 'pro'});
    });
    expect(find.text('Loading your plan…'), findsOneWidget);
    pending.completeError(StateError('private provider detail'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your plan'), findsOneWidget);
    expect(find.textContaining('private provider'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Pro Seller plan'), findsOneWidget);
  });
  testWidgets('review and cancellation remain authoritative', (tester) async {
    await show(
      tester,
      () async => {
        'plan': 'free',
        'requires_review': true,
        'cancel_at_period_end': true,
      },
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('needs review'), findsOneWidget);
    expect(find.textContaining('Cancellation is scheduled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
