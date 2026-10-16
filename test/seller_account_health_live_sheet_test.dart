import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';

import 'test_fonts.dart';

typedef HealthState = ({
  SellerAccountHealthView? value,
  bool busy,
  String? error,
});

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('open health sheet updates in place at $width / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final state = ValueNotifier<HealthState>((
          value: null,
          busy: false,
          error: null,
        ));
        var refreshes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<HealthState>(
                valueListenable: state,
                builder: (_, snapshot, _) => ApprovedSellerHomePage(
                  sellerName: 'Test seller',
                  realLeads: const [],
                  onLeads: () {},
                  onBrowseRequests: () {},
                  accountHealth: snapshot.value,
                  accountHealthLoading: snapshot.busy,
                  accountHealthError: snapshot.error,
                  onRefreshAccountHealth: () => refreshes++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sellerAccountHealth')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('sellerAccountHealthSheet')),
          findsOneWidget,
        );

        state.value = (value: null, busy: true, error: null);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Checking your account…'), findsOneWidget);
        final busyButton = tester.widget<OutlinedButton>(
          find.descendant(
            of: find.byKey(const Key('sellerAccountHealthRefresh')),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(busyButton.onPressed, isNull);
        expect(tester.takeException(), isNull);

        state.value = (
          value: const SellerAccountHealthView(
            emailVerified: true,
            phoneVerified: false,
            reviewStatus: 'approved',
            restrictions: [],
          ),
          busy: false,
          error: null,
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == '2 of 3 verification steps complete',
          ),
          findsOneWidget,
        );
        expect(find.text('Email verified'), findsOneWidget);
        expect(find.text('Phone not verified'), findsOneWidget);
        expect(find.text('Evidence review: approved'), findsOneWidget);
        expect(find.text('Checking your account…'), findsNothing);

        state.value = (
          value: state.value.value,
          busy: false,
          error: 'Connection unavailable. Try again.',
        );
        await tester.pumpAndSettle();
        expect(find.text('Connection unavailable. Try again.'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == '2 of 3 verification steps complete',
          ),
          findsOneWidget,
        );
        expect(find.text('Email verified'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('sellerAccountHealthRefresh')),
        );
        await tester.tap(find.byKey(const Key('sellerAccountHealthRefresh')));
        await tester.pump();
        expect(refreshes, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  }
}
