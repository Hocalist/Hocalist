import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets('saved chat opens after loading without rendering Home', (tester) async {
    SharedPreferences.setMockInitialValues({
      'hocalist.hasSession': true,
      'hocalist.authenticated': true,
      'hocalist.role': 'buyer',
      'hocalist.page': 'buyerChats',
    });
    await tester.pumpWidget(const HocalistApp());
    expect(find.byKey(const Key('restoring-saved-page')), findsOneWidget);
    expect(find.byType(ApprovedNoAccountHomePage), findsNothing);
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(HocalistPrototype));
    expect(state.page, AppPage.buyerChats);
    expect(find.byKey(const Key('restoring-saved-page')), findsNothing);
  });
  testWidgets('startup hides Home until saved navigation is restored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HocalistApp());
    expect(find.byKey(const Key('restoring-saved-page')), findsOneWidget);
    expect(find.byType(ApprovedNoAccountHomePage), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restoring-saved-page')), findsNothing);
    expect(find.byType(ApprovedNoAccountHomePage), findsOneWidget);
  });
}
