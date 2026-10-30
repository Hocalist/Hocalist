import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/brand_home_link.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/features/seller/seller_app_shell.dart';
import 'package:hocalist/components/pull_refresh.dart';

void main() {
  testWidgets('global header keeps home and notifications independent', (tester) async {
    final semantics = tester.ensureSemantics();
    var visits = 0;
    var notifications = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrandHomeScope(
      onHome: () => visits++,
      child: HocalistGlobalHeader(role: UserRole.seller, accent: Colors.blue,
        onNotifications: () => notifications++),
    ))));
    expect(find.bySemanticsLabel('Hocalist home'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications'));
    expect(notifications, 1);
    expect(visits, 0);
    await tester.tap(find.byType(BrandHomeLink));
    expect(visits, 1);
    semantics.dispose();
  });
  testWidgets('seller shell logo invokes home', (tester) async {
    var visits = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrandHomeScope(
      onHome: () => visits++,
      child: Column(children: [SellerAppHeader(onNotifications: () {})]),
    ))));
    await tester.runAsync(() => precacheImage(
      const AssetImage('assets/brand/hocalist-wordmark.png'),
      tester.element(find.byType(SellerAppHeader)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BrandHomeLink));
    expect(visits, 1);
  });
  testWidgets('pull down refreshes even a short app page', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PullRefreshHost(child: AppFrame(
      onRefresh: () async { refreshes++; },
      child: const Text('Saved information'),
    )))));
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });
  testWidgets('buyer and seller header logos invoke their home destination', (tester) async {
    for (final role in UserRole.values) {
      var visits = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrandHomeScope(
        onHome: () => visits++,
        child: HocalistGlobalHeader(role: role, accent: Colors.blue, onNotifications: () {}),
      ))));
      await tester.tap(find.byType(BrandHomeLink));
      expect(visits, 1);
    }
  });
  testWidgets('buyer header keeps home shortcut at narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var visits = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrandHomeScope(
      onHome: () => visits++,
      child: BuyerTopLevelHeader(onNotifications: () {}),
    ))));
    await tester.tap(find.byType(BrandHomeLink));
    expect(visits, 1);
    expect(tester.takeException(), isNull);
  });
}
