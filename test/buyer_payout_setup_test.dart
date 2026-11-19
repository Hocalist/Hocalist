import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/buyer_payout_setup.dart';

void main() {
  for (final saved in [false, true]) {
    testWidgets('one tap opens hosted form for saved=$saved', (tester) async {
      final actions = <String>[];
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BuyerPayoutSetup(
              request: (action) async {
                actions.add(action);
                return action == 'status'
                    ? {'saved': saved, 'ready': false}
                    : {'url': 'https://connect.stripe.com/test-only'};
              },
              open: (url) async {
                opened.add(url);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tester.tap(
        find.text(saved ? 'Edit payout details' : 'Manage payout'),
      );
      await tester.pumpAndSettle();
      expect(actions, ['status', 'manage']);
      expect(opened.single.host, 'connect.stripe.com');
    });
  }
}
