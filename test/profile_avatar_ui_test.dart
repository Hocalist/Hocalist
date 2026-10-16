// Avatar pending-intent controls: Retry replays the retained change and
// Discard clears it, without uploading a new photo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/features/approved/approved_replica_metrics.dart';
import 'package:hocalist/features/media/private_remote_image.dart';
import 'package:hocalist/main.dart';

import 'test_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('buyer and seller More consume the adopted avatar reference', (
    tester,
  ) async {
    void noop() {}
    const id = '11111111-1111-4111-8111-111111111111';
    await _pump(
      tester,
      ApprovedReplicaScope(
        metrics: ApprovedReplicaMetrics.resolve(
          availableWidth: 390,
          textScaler: TextScaler.noScaling,
        ),
        child: SupportPage(
          accent: Colors.pink,
          name: 'Buyer',
          email: 'test@example.com',
          avatarMediaId: id,
          onNotifications: noop,
          onSaved: noop,
          onSafety: noop,
          onReport: noop,
          onHelp: noop,
          onEditProfile: noop,
          onSettings: noop,
          onLogout: noop,
        ),
      ),
    );
    expect(
      tester.widget<PrivateRemoteImage>(find.byType(PrivateRemoteImage)).id,
      id,
    );
    expect(find.text('Edit profile'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerMorePage(
            sellerName: 'Seller',
            avatarMediaId: id,
            onProfile: noop,
            onEditProfile: noop,
            onSettings: noop,
            onNotifications: noop,
            onAccessibility: noop,
            onSafety: noop,
            onHelp: noop,
            onLogout: noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<PrivateRemoteImage>(find.byType(PrivateRemoteImage)).id,
      id,
    );
    expect(find.text('Edit profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buyer avatar pending card exposes retry and discard', (
    tester,
  ) async {
    var retries = 0;
    var discards = 0;
    await _pump(
      tester,
      BuyerProfileEditPage(
        name: 'Maya Chen',
        onNameChanged: (_) {},
        onDone: () {},
        avatarPending: true,
        onRetryAvatar: () => retries += 1,
        onDiscardAvatar: () => discards += 1,
      ),
    );
    expect(find.byKey(const Key('buyerAvatarPendingCard')), findsOneWidget);
    expect(
      find.byKey(const Key('buyerEditProfileChangePhoto')),
      findsOneWidget,
      reason: 'the approved photo controls stay in place',
    );
    await tester.tap(find.byKey(const Key('buyerAvatarRetry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
    await tester.tap(find.byKey(const Key('buyerAvatarDiscard')));
    await tester.pumpAndSettle();
    expect(discards, 1);
  });

  testWidgets('seller avatar pending card exposes retry and discard', (
    tester,
  ) async {
    var retries = 0;
    var discards = 0;
    await _pump(
      tester,
      ApprovedSellerEditProfilePage(
        name: 'Northside Tech',
        onNameChanged: (_) {},
        onBack: () {},
        onDone: () {},
        contactEditor: const SizedBox.shrink(),
        avatarPending: true,
        onRetryAvatar: () => retries += 1,
        onDiscardAvatar: () => discards += 1,
      ),
    );
    expect(find.byKey(const Key('sellerAvatarPendingCard')), findsOneWidget);
    expect(
      find.byKey(const Key('sellerEditProfileChangePhoto')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sellerAvatarRetry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
    await tester.tap(find.byKey(const Key('sellerAvatarDiscard')));
    await tester.pumpAndSettle();
    expect(discards, 1);
  });

  testWidgets('avatar cards stay hidden without a pending intent', (
    tester,
  ) async {
    await _pump(
      tester,
      BuyerProfileEditPage(
        name: 'Maya Chen',
        onNameChanged: (_) {},
        onDone: () {},
      ),
    );
    expect(find.byKey(const Key('buyerAvatarPendingCard')), findsNothing);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('buyer avatar pending card fits $width at scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BuyerProfileEditPage(
                  name: 'Maya Chen',
                  onNameChanged: (_) {},
                  onDone: () {},
                  avatarPending: true,
                  onRetryAvatar: () {},
                  onDiscardAvatar: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('buyerAvatarPendingCard')), findsOneWidget);
      });
    }
  }
}
