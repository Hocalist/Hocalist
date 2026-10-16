import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';
import 'package:hocalist/components/hocalist_section_tabs.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('new state replaces old actions immediately ($reduced)', (
      tester,
    ) async {
      Widget view(String state) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: HocalistStateTransition(
            stateKey: state,
            child: TextButton(onPressed: () {}, child: Text(state)),
          ),
        ),
      );
      await tester.pumpWidget(view('old'));
      await tester.pumpWidget(view('new'));
      expect(find.text('old'), findsNothing);
      expect(find.text('new'), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(HocalistStateTransition),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, reduced ? 1 : 0);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  }
  testWidgets('tab selection animates and retains draft input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HocalistSectionTabs(
            accent: Colors.purple,
            sections: {
              'Profile': [const TextField()],
              'Privacy': [const Text('Private contact')],
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    await tester.tap(find.byKey(const ValueKey('section-tab-Privacy')));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-tab-Profile')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved draft'), findsOneWidget);
  });
}
