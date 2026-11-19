import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_account_field.dart';
import 'package:hocalist/components/hocalist_section_tabs.dart';
import 'package:hocalist/main.dart'
    show AccessibilityFontStyle, AccessibilityPreferences, HocalistTheme;

void main() {
  for (final font in AccessibilityFontStyle.values) {
    testWidgets(
      'Account fields and tabs follow the ${font.name} font preference',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final preferences = AccessibilityPreferences.defaults.copyWith(
          fontStyle: font,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: HocalistTheme.lightFor(preferences),
            home: Scaffold(
              body: Column(
                children: [
                  HocalistAccountField(
                    label: 'Address',
                    controller: controller,
                  ),
                  HocalistSectionTabs(
                    accent: Colors.indigo,
                    sections: const {
                      'Profile': [Text('Profile details')],
                      'Settings': [Text('Preferences')],
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).style?.fontFamily,
          preferences.fontFamily,
        );
        expect(
          tester.widget<Text>(find.text('Settings')).style?.fontFamily,
          preferences.fontFamily,
        );
      },
    );
  }
  testWidgets('account fields and tabs use explicit approved typography', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultTextStyle(
            style: const TextStyle(fontSize: 30, fontFamily: 'serif'),
            child: Column(
              children: [
                HocalistAccountField(
                  label: 'Service area',
                  controller: controller,
                ),
                HocalistSectionTabs(
                  accent: Colors.blue,
                  sections: const {
                    'Seller info': [Text('Profile content')],
                    'Categories': [Text('Categories content')],
                    'Private contact': [Text('Contact content')],
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.labelText, isNull);
    expect(field.decoration!.filled, isTrue);
    expect(field.decoration!.fillColor, Colors.white);
    expect(field.style!.fontFamily, 'Nunito');
    expect(find.text('Service area'), findsOneWidget);
    final tab = tester.widget<Text>(find.text('Private contact'));
    expect(tab.style!.fontFamily, 'Nunito');
    expect(tab.style!.fontSize, lessThan(20));
    expect(tester.takeException(), isNull);
  });
}
