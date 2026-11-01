import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_loading_indicator.dart';

void main() {
  testWidgets('accessible navigation keeps loading feedback rotating', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: true),
        child: Scaffold(body: HocalistLoadingIndicator()),
      ),
    ));
    final rotation = tester.widget<RotationTransition>(find.descendant(of: find.byType(HocalistLoadingIndicator), matching: find.byType(RotationTransition)));
    final first = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(first));
  });

  testWidgets('loading follows changes to reduced motion with accessible navigation', (tester) async {
    Future<void> show(bool reduced) => tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: true, disableAnimations: reduced),
        child: const Scaffold(body: HocalistLoadingIndicator()),
      ),
    ));
    await show(false);
    final rotation = tester.widget<RotationTransition>(find.descendant(of: find.byType(HocalistLoadingIndicator), matching: find.byType(RotationTransition)));
    await tester.pump(const Duration(milliseconds: 200));
    await show(true);
    final stopped = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, stopped);
    await show(false);
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(stopped));
  });

  testWidgets('small H artwork rotates without an outer ring', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: HocalistLoadingIndicator())),
      ),
    );
    final rotation = tester.widget<RotationTransition>(
      find.descendant(
        of: find.byType(HocalistLoadingIndicator),
        matching: find.byType(RotationTransition),
      ),
    );
    final first = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(first));
    expect(
      find.descendant(
        of: find.descendant(
          of: find.byType(HocalistLoadingIndicator),
          matching: find.byType(RotationTransition),
        ),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.getSize(find.byType(HocalistLoadingIndicator)),
      const Size(28, 28),
    );
  });
  testWidgets('reduced motion keeps the logo still', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: HocalistLoadingIndicator())),
        ),
      ),
    );
    final rotation = tester.widget<RotationTransition>(
      find.descendant(
        of: find.byType(HocalistLoadingIndicator),
        matching: find.byType(RotationTransition),
      ),
    );
    final first = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, first);
    expect(tester.takeException(), isNull);
  });
}

