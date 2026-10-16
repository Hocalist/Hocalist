import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('sheet opens and dismisses with accessible timing ($reduced)', (
      tester,
    ) async {
      AnimationStyle? style;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    style = HocalistMotion.sheetStyle(context);
                    showModalBottomSheet<void>(
                      context: context,
                      sheetAnimationStyle: style,
                      builder: (context) => TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close sheet'),
                      ),
                    );
                  },
                  child: const Text('Open sheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pump();
      expect(style!.duration, Duration(milliseconds: reduced ? 0 : 260));
      expect(style!.reverseDuration, Duration(milliseconds: reduced ? 0 : 180));
      await tester.pumpAndSettle();
      expect(find.text('Close sheet'), findsOneWidget);
      await tester.tap(find.text('Close sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Close sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
