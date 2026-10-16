// Withdrawal panel tests: verification gate, explicit net amount, server
// acknowledgement and honest failure states. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/withdrawal_backend.dart';
import 'package:hocalist/features/commercial/withdrawal_panel.dart';

import 'test_fonts.dart';

WithdrawalStatusView _status({
  bool email = true,
  bool phone = true,
  int available = 5000,
  List<WithdrawalRequestView> requests = const [],
}) => WithdrawalStatusView(
  minimumMinor: 2000,
  feeMinor: 250,
  earnedMinor: 5000,
  processingMinor: 5000 - available,
  availableMinor: available,
  emailVerified: email,
  phoneVerified: phone,
  requests: requests,
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<WithdrawalStatusView> Function() load,
  required Future<WithdrawalRequestView> Function(int, String) submit,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WithdrawalPanel(load: load, submit: submit),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('unverified contacts keep the gate and hide submission', (
    tester,
  ) async {
    await _pump(
      tester,
      load: () async => _status(phone: false),
      submit: (_, _) async => throw StateError('unused'),
    );
    expect(find.byKey(const Key('withdrawalVerificationGate')), findsOneWidget);
    expect(find.byKey(const Key('withdrawalSubmit')), findsNothing);
  });

  testWidgets('the net amount is shown before the server acknowledges', (
    tester,
  ) async {
    final calls = <(int, String)>[];
    await _pump(
      tester,
      load: () async => _status(),
      submit: (amount, key) async {
        calls.add((amount, key));
        return WithdrawalRequestView(
          id: '80000000-0000-4000-8000-000000000001',
          amountMinor: amount,
          feeMinor: 250,
          netMinor: amount - 250,
          status: 'processing',
          createdAt: DateTime.utc(2026, 5, 1),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('withdrawalAmountField')),
      '3000',
    );
    await tester.pumpAndSettle();
    expect(find.text(r'Net payout after the $2.50 deduction: $27.50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('withdrawalSubmit')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.$1, 3000);
    expect(calls.single.$2, isNotEmpty);
    expect(find.text('Processing - funds reserved'), findsOneWidget);
    expect(find.textContaining('Paid'), findsNothing);
  });

  testWidgets('below-minimum input is refused before any call', (tester) async {
    var called = false;
    await _pump(
      tester,
      load: () async => _status(),
      submit: (_, _) async {
        called = true;
        throw StateError('unused');
      },
    );
    await tester.enterText(find.byKey(const Key('withdrawalAmountField')), '500');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('withdrawalSubmit')));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.byKey(const Key('withdrawalSubmitError')), findsOneWidget);
  });

  testWidgets('a failed request reports restored funds', (tester) async {
    await _pump(
      tester,
      load: () async => _status(
        requests: [
          WithdrawalRequestView(
            id: '80000000-0000-4000-8000-000000000002',
            amountMinor: 3000,
            feeMinor: 250,
            netMinor: 2750,
            status: 'failed',
            failureReason: 'account closed',
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        ],
      ),
      submit: (_, _) async => throw StateError('unused'),
    );
    expect(find.text('Failed - funds restored'), findsOneWidget);
    expect(find.text('account closed'), findsOneWidget);
  });
}
