import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/account_role_switch.dart';
import 'package:hocalist/domain/phase2/profiles.dart';

void main() {
  testWidgets('header menu shows the active role and switches explicitly', (tester) async {
    HocalistRole? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountRoleSwitchScope(
      onSelect: (role) => selected = role,
      child: const AccountRoleSwitch(role: HocalistRole.buyer, child: Text('Buyer mode')),
    ))));
    final trigger = find.byType(PopupMenuButton<HocalistRole>);
    final feedback = tester.widget<InkWell>(
      find.descendant(of: trigger, matching: find.byType(InkWell)),
    );
    final surface = tester.widget<Ink>(
      find.descendant(of: trigger, matching: find.byType(Ink)),
    );
    expect(feedback.borderRadius, BorderRadius.circular(99));
    expect((surface.decoration as BoxDecoration).borderRadius, feedback.borderRadius);
    await tester.tap(find.text('Buyer mode'));
    await tester.pumpAndSettle();
    expect(find.text('Buyer'), findsOneWidget);
    expect(find.text('Seller'), findsOneWidget);
    await tester.tap(find.text('Seller'));
    await tester.pumpAndSettle();
    expect(selected, HocalistRole.seller);
  });
}
