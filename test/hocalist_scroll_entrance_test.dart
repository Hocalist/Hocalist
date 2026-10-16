import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'below-fold cards reveal once when scrolled into view ($reduced)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: SingleChildScrollView(
                  controller: controller,
                  child: const Column(
                    children: [
                      SizedBox(height: 900),
                      HocalistEntrance(
                        key: Key('late-card'),
                        child: SizedBox(
                          height: 180,
                          width: 200,
                          child: Text('Later card'),
                        ),
                      ),
                      SizedBox(height: 700),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final opacity = find.descendant(
          of: find.byKey(const Key('late-card')),
          matching: find.byType(Opacity),
        );
        await tester.pump(const Duration(seconds: 1));
        if (reduced) {
          expect(opacity, findsNothing);
        } else {
          expect(tester.widget<Opacity>(opacity).opacity, 0);
        }
        controller.jumpTo(800);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 130));
        if (!reduced) {
          expect(tester.widget<Opacity>(opacity).opacity, greaterThan(0));
          expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));
        }
        await tester.pumpAndSettle();
        controller.jumpTo(0);
        await tester.pump();
        controller.jumpTo(800);
        await tester.pump();
        if (!reduced) expect(tester.widget<Opacity>(opacity).opacity, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
