import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'dialog timing and close action respect reduced motion ($reduced)',
      (tester) async {
        AnimationStyle? style;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () {
                      style = HocalistMotion.dialogStyle(context);
                      showDialog<void>(
                        context: context,
                        animationStyle: style,
                        builder: (context) => AlertDialog(
                          title: const Text('Confirm change'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Keep current'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        expect(style!.duration, Duration(milliseconds: reduced ? 0 : 200));
        expect(
          style!.reverseDuration,
          Duration(milliseconds: reduced ? 0 : 150),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep current'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm change'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
