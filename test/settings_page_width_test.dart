import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/account/account_lifecycle_page.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 390.0, 800.0]) {
    for (final lifecycle in [true, false]) {
      testWidgets(
        '${lifecycle ? 'lifecycle' : 'accessibility'} uses available $width width',
        (t) async {
          t.view.physicalSize = Size(width, 1000);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: lifecycle
                    ? AccountLifecyclePage(onBack: () {})
                    : AccessibilityPage(
                        appliedPreferences: AccessibilityPreferences.defaults,
                        onApply: (_) {},
                        onBack: () {},
                      ),
              ),
            ),
          );
          await t.pumpAndSettle();
          final list = find.byType(ListView).first;
          expect(t.getSize(list).width, closeTo(width, 1));
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
