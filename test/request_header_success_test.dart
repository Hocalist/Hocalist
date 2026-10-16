import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets('request logo never overlaps buyer mode across phone sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ApprovedRequestFlowPage(
              accent: const Color(0xff1917ff),
              requestTitle: 'Test request',
              budget: '',
              includeAppChrome: true,
              onTitleChanged: (_) {},
              onBudgetChanged: (_) {},
              onBack: () {},
              onNotifications: () {},
              onSubmit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final logo = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.semanticLabel == 'Hocalist Reverse Marketplace',
        );
        final mode = find.textContaining('Buyer').first;
        expect(
          tester.getRect(logo).right,
          lessThanOrEqualTo(tester.getRect(mode).left),
          reason: '$width / $scale',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'width $width scale $scale',
        );
      }
    }
  });
  testWidgets('request posted popup keeps view and home actions', (
    tester,
  ) async {
    var viewed = false;
    var home = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedRequestPostedDialog(
            onViewRequest: () => viewed = true,
            onHome: () => home = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Request posted'), findsOneWidget);
    await tester.tap(find.text('View request'));
    expect(viewed, true);
    await tester.tap(find.text('Back to dashboard'));
    expect(home, true);
  });
}
