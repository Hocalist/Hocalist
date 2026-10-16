import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_flow_stages.dart';
import 'package:hocalist/components/hocalist_motion.dart';
import 'package:hocalist/components/hocalist_section_intro.dart';
import 'package:hocalist/components/hocalist_status_fact.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('supplemental hierarchy fits $width at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Nunito'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      HocalistSectionIntro(
                        title: 'Your cases',
                        icon: Icons.inbox_outlined,
                        trailing: TextButton(
                          onPressed: () {},
                          child: const Text('Refresh'),
                        ),
                      ),
                      const HocalistFlowStages(
                        labels: ['Find a place', 'Review & confirm'],
                        active: 1,
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: HocalistStatusFact(
                              label: 'Email verified',
                              confirmed: true,
                              icon: Icons.alternate_email_rounded,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: HocalistStatusFact(
                              label: 'Phone not verified',
                              confirmed: false,
                              icon: Icons.phone_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Phone not verified'), findsOneWidget);
      });
    }
  }
  testWidgets('incoming state removes the previous action immediately', (
    tester,
  ) async {
    Widget state(String name) => MaterialApp(
      home: HocalistEntrance(
        key: ValueKey(name),
        child: TextButton(onPressed: () {}, child: Text(name)),
      ),
    );
    await tester.pumpWidget(state('Old action'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(state('New action'));
    expect(find.text('Old action'), findsNothing);
    expect(find.text('New action'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
