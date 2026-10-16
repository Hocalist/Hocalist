import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_account_field.dart';
import 'package:hocalist/components/hocalist_section_tabs.dart';

void main() {
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
