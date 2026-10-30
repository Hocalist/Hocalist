import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';
import 'package:hocalist/components/hocalist_section_tabs.dart';

void main() {
  testWidgets(
    'entrance becomes visible after ancestor movement without scrolling',
    (tester) async {
      final offset = ValueNotifier<double>(1000);
      addTearDown(offset.dispose);
      const card = HocalistEntrance(
        child: SizedBox(height: 100, child: Text('Sent offer')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<double>(
                valueListenable: offset,
                child: card,
                builder: (_, value, child) =>
                    Transform.translate(offset: Offset(0, value), child: child),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      offset.value = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      final opacity = find.ancestor(
        of: find.text('Sent offer'),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(opacity.first).opacity, 1);
    },
  );

  testWidgets('entrance cards reveal when a retained tab becomes active', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HocalistSectionTabs(
              accent: Colors.blue,
              sections: const {
                'Credits': [Text('Balance')],
                'Activity': [
                  HocalistEntrance(
                    child: SizedBox(
                      height: 100,
                      child: Text('Reserved target'),
                    ),
                  ),
                ],
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-tab-Activity')));
    await tester.pumpAndSettle();
    final opacity = find.ancestor(
      of: find.text('Reserved target'),
      matching: find.byType(Opacity),
    );
    for (final widget in tester.widgetList<Opacity>(opacity)) {
      expect(widget.opacity, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding details settle immediately with reduced motion', (
    tester,
  ) async {
    Widget detail(double height) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: HocalistExpand(child: SizedBox(width: 100, height: height)),
        ),
      ),
    );
    await tester.pumpWidget(detail(40));
    await tester.pumpWidget(detail(160));
    await tester.pump();
    expect(tester.getSize(find.byType(HocalistExpand)).height, 160);
    expect(tester.hasRunningAnimations, isFalse);
  });
  for (final reduced in [false, true]) {
    testWidgets('press feedback preserves action and geometry ($reduced)', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: HocalistPressFeedback(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(HocalistPressFeedback));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Continue')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        reduced ? 1 : .985,
      );
      expect(tester.getSize(find.byType(HocalistPressFeedback)), size);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });
  }

  testWidgets('cancel and disabling a pressed control restore its scale', (
    tester,
  ) async {
    Widget button(bool enabled) => MaterialApp(
      home: Scaffold(
        body: HocalistPressFeedback(
          enabled: enabled,
          child: const SizedBox(width: 100, height: 44),
        ),
      ),
    );
    await tester.pumpWidget(button(true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HocalistPressFeedback)),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    final second = await tester.startGesture(
      tester.getCenter(find.byType(HocalistPressFeedback)),
    );
    await tester.pumpWidget(button(false));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await second.up();
  });
}
