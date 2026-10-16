import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_page_transition.dart';

void main() {
  testWidgets('departing page cannot receive taps during transition', (
    tester,
  ) async {
    var oldTaps = 0;
    Widget page(Widget child) =>
        MaterialApp(home: HocalistPageTransition(child: child));
    await tester.pumpWidget(
      page(
        TextButton(
          key: const ValueKey('old'),
          onPressed: () => oldTaps++,
          child: const Text('Old action'),
        ),
      ),
    );
    await tester.pumpWidget(
      page(const SizedBox(key: ValueKey('new'), width: 100, height: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Old action'), warnIfMissed: false);
    expect(oldTaps, 0);
    await tester.pumpAndSettle();
    expect(find.text('Old action'), findsNothing);
  });
  for (final reduced in [false, true]) {
    testWidgets('navigation respects reduced motion=$reduced', (tester) async {
      Widget page(String name) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: HocalistPageTransition(child: Text(name, key: ValueKey(name))),
        ),
      );
      await tester.pumpWidget(page('Home'));
      await tester.pumpWidget(page('Offers'));
      await tester.pump();
      expect(find.text('Offers'), findsOneWidget);
      if (reduced) {
        expect(find.text('Home'), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
      } else {
        expect(find.text('Home'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
