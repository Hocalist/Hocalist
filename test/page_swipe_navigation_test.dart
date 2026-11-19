import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/page_swipe_navigation.dart';
import 'package:hocalist/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets('clear swipes navigate, short and vertical drags do not', (tester) async {
    var next = 0;
    var previous = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSwipeNavigation(
      onNext: () => next++, onPrevious: () => previous++,
      child: const SizedBox.expand(),
    ))));
    await tester.dragFrom(const Offset(400, 250), const Offset(-200, 0));
    await tester.dragFrom(const Offset(400, 250), const Offset(200, 0));
    expect(next, 1); expect(previous, 1);
    await tester.dragFrom(const Offset(400, 250), const Offset(40, 0));
    await tester.dragFrom(const Offset(400, 250), const Offset(0, 200));
    expect(next, 1); expect(previous, 1);
  });
  testWidgets('horizontal lists retain their own swipes', (tester) async {
    var navigations = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSwipeNavigation(
      onNext: () => navigations++, onPrevious: () => navigations++,
      child: ListView(controller: scroll, scrollDirection: Axis.horizontal,
        children: List.generate(10, (_) => const SizedBox(width: 300))),
    ))));
    await tester.dragFrom(const Offset(400, 250), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0)); expect(navigations, 0);
  });
  testWidgets('disabled navigation does not respond', (tester) async {
    var navigations = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSwipeNavigation(
      enabled: false, onNext: () => navigations++, child: const SizedBox.expand(),
    ))));
    await tester.dragFrom(const Offset(400, 250), const Offset(-200, 0));
    expect(navigations, 0);
  });
  for (final role in ['buyer', 'seller']) {
    testWidgets('$role swipes follow tab order and return from subpages', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final home = role == 'buyer' ? AppPage.buyerDashboard : AppPage.sellerDashboard;
      final next = role == 'buyer' ? AppPage.hocatrends : AppPage.sellerStore;
      SharedPreferences.setMockInitialValues({
        'hocalist.hasSession': true, 'hocalist.authenticated': true,
        'hocalist.role': role, 'hocalist.page': home.name,
      });
      await tester.pumpWidget(const HocalistApp());
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(HocalistPrototype));
      Future<void> swipe(double dx) async {
        await tester.dragFrom(const Offset(195, 45), Offset(dx, 0));
        await tester.pumpAndSettle();
      }
      await swipe(150); expect(state.page, home); // no wrap at first tab
      await swipe(-150); expect(state.page, next);
      await swipe(150); expect(state.page, home);
      final tabs = role == 'buyer'
          ? [home, AppPage.hocatrends, AppPage.offersReceived, AppPage.buyerChats, AppPage.buyerSupport]
          : [home, AppPage.sellerStore, AppPage.sellerMeets, AppPage.sellerChat, AppPage.sellerMore];
      for (final tab in tabs.skip(1)) {
        await swipe(-150); expect(state.page, tab);
      }
      await swipe(-150); expect(state.page, tabs.last);
      for (final tab in tabs.reversed.skip(1)) {
        await swipe(150); expect(state.page, tab);
      }
      state.go(AppPage.accessibility);
      await tester.pumpAndSettle();
      await swipe(-150); expect(state.page, AppPage.accessibility);
      await swipe(150); expect(state.page, home);
      expect(tester.takeException(), isNull);
    });
  }
}
