import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/buyer_bottom_navigation.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';
import 'package:hocalist/main.dart' show BuyerProfileEditPage;

import 'test_fonts.dart';

const _captureKey = ValueKey('scoped-buyer-capture');
const _proofSize = Size(390, 844);

/// Capture-only comparisons against ignored `.codex-local/` goldens. They stay
/// out of the default suite so `flutter test` never depends on local pixel
/// state; run explicitly with
/// `flutter test --dart-define=HOCALIST_VISUAL_CAPTURE=true`.
const bool _captureEnabled = bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE');

void main() {
  if (!_captureEnabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadHocalistTestFonts);

  testWidgets('capture buyer home at narrow phone widths', (tester) async {
    for (final width in <double>[304, 390]) {
      await _pump(
        tester,
        ApprovedBuyerHomePage(
          name: 'Maya Chen',
          requestTitle: 'iPad Air, 5th gen or newer',
          requestPosted: true,
          onCreate: () {},
          onRequestDetails: () {},
          onOffers: () {},
          onRecentActivity: () {},
          onWallet: () {},
        ),
        size: Size(width, 844),
      );

      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '../.codex-local/buyer-targeted/buyer-home-corrected-${width.toInt()}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('capture owner follow-up surfaces at 430', (tester) async {
    const size = Size(430, 844);

    await _pump(
      tester,
      ApprovedBuyerHomePage(
        name: 'Maya Chen',
        requestTitle: 'iPad Air, 5th gen or newer',
        requestPosted: true,
        onCreate: () {},
        onRequestDetails: () {},
        onOffers: () {},
        onRecentActivity: () {},
        onWallet: () {},
      ),
      size: size,
    );
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/buyer-home-owner-fix-430.png',
      ),
    );

    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
      ),
      size: size,
    );
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/product-owner-fix-430.png',
      ),
    );
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _scrollRequestToTop(tester);
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/location-owner-fix-430.png',
      ),
    );

    await _pump(
      tester,
      ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () {},
        includeAppChrome: true,
      ),
      size: size,
    );
    await _scrollRequestToTop(tester);
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/request-details-owner-fix-430.png',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture product at 390', (tester) async {
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
      ),
    );
    await _scrollRequestToTop(tester);

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/product-current-390.png',
      ),
    );
  });

  testWidgets('capture product at 304', (tester) async {
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
      ),
      size: const Size(304, 844),
    );

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/product-corrected-304.png',
      ),
    );
  });

  testWidgets('capture location at 390', (tester) async {
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
      ),
    );
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _scrollRequestToTop(tester);

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/location-current-390.png',
      ),
    );
  });

  testWidgets('capture location at 304', (tester) async {
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: const Color(0xff1917ff),
        requestTitle: '',
        budget: '',
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
        includeAppChrome: true,
      ),
      size: const Size(304, 844),
    );
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _scrollRequestToTop(tester);

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/location-corrected-304.png',
      ),
    );
  });

  testWidgets('capture request details at 390', (tester) async {
    await _pump(
      tester,
      ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () {},
        includeAppChrome: true,
      ),
    );
    await _scrollRequestToTop(tester);

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/request-details-current-390.png',
      ),
    );
  });

  testWidgets('capture request details at 304', (tester) async {
    await _pump(
      tester,
      ApprovedBuyerRequestDetailsPage(
        accent: const Color(0xff1917ff),
        requestTitle: 'iPad Air, 5th gen or newer',
        budget: r'$350 - $480',
        onBack: () {},
        onNotifications: () {},
        onOffers: () {},
        includeAppChrome: true,
      ),
      size: const Size(304, 844),
    );
    await _scrollRequestToTop(tester);

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/request-details-corrected-304.png',
      ),
    );
  });

  testWidgets('capture Request Details paired cards at phone widths', (
    tester,
  ) async {
    for (final width in <double>[304, 320, 360, 390, 430]) {
      await _pump(
        tester,
        ApprovedBuyerRequestDetailsPage(
          accent: const Color(0xff1917ff),
          requestTitle: 'iPad Air, 5th gen or newer',
          budget: r'$350 - $480',
          onBack: () {},
          onNotifications: () {},
          onOffers: () {},
          includeAppChrome: true,
        ),
        size: Size(width, 844),
      );
      await tester.ensureVisible(find.text('Condition'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '../.codex-local/buyer-targeted/request-details-pairs-${width.toInt()}.png',
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Request Details paired-card render at ${width.toInt()}px',
      );
    }
  });

  testWidgets('capture the scoped Buyer screens at narrow phone widths', (
    tester,
  ) async {
    for (final width in <double>[304, 320]) {
      final suffix = width.toInt();
      await _pump(
        tester,
        ApprovedRequestFlowPage(
          accent: const Color(0xff1917ff),
          requestTitle: '',
          budget: '',
          onTitleChanged: (_) {},
          onBudgetChanged: (_) {},
          onBack: () {},
          onNotifications: () {},
          onSubmit: () {},
          includeAppChrome: true,
        ),
        size: Size(width, 844),
      );
      await _scrollRequestToTop(tester);
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '../.codex-local/buyer-targeted/product-current-$suffix.png',
        ),
      );

      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await _scrollRequestToTop(tester);
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '../.codex-local/buyer-targeted/location-current-$suffix.png',
        ),
      );

      await _pump(
        tester,
        _BuyerShell(
          selected: ApprovedBuyerNavSelection.hocatrends,
          child: ApprovedHocatrendsPickedSellersPage(
            onBack: () {},
            onChatSeller: () {},
            onNotifications: () {},
          ),
        ),
        size: Size(width, 844),
      );
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '../.codex-local/buyer-targeted/picked-sellers-current-$suffix.png',
        ),
      );
    }
  });

  testWidgets('unselected home address uses an empty radio', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: ApprovedLocationRequestStep(
            useHomeAddress: false,
            onUseHomeAddressChanged: (_) {},
            onBack: () {},
            onSubmit: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('approved-location-radio-unselected')),
      findsOneWidget,
    );
  });

  testWidgets('capture picked sellers at 390', (tester) async {
    await _pump(
      tester,
      _BuyerShell(
        selected: ApprovedBuyerNavSelection.hocatrends,
        child: ApprovedHocatrendsPickedSellersPage(
          onBack: () {},
          onChatSeller: () {},
          onNotifications: () {},
        ),
      ),
    );

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/picked-sellers-current-390.png',
      ),
    );
  });

  testWidgets('capture picked sellers at 304', (tester) async {
    await _pump(
      tester,
      _BuyerShell(
        selected: ApprovedBuyerNavSelection.hocatrends,
        child: ApprovedHocatrendsPickedSellersPage(
          onBack: () {},
          onChatSeller: () {},
          onNotifications: () {},
        ),
      ),
      size: const Size(304, 844),
    );

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/picked-sellers-corrected-304.png',
      ),
    );
  });

  testWidgets('capture edit profile at 390', (tester) async {
    await _pump(
      tester,
      _BuyerShell(
        selected: ApprovedBuyerNavSelection.more,
        child: BuyerProfileEditPage(
          name: 'Maya Chen',
          onNameChanged: (_) {},
          onDone: () {},
        ),
      ),
    );

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../.codex-local/buyer-targeted/edit-profile-current-390.png',
      ),
    );
  });

  testWidgets('edit profile fits supported widths', (tester) async {
    for (final width in <double>[320, 360, 390, 430, 768, 980]) {
      await _pump(
        tester,
        _BuyerShell(
          selected: ApprovedBuyerNavSelection.more,
          child: BuyerProfileEditPage(
            name: 'Maya Chen',
            onNameChanged: (_) {},
            onDone: () {},
          ),
        ),
        size: Size(width, 844),
      );
      expect(tester.takeException(), isNull, reason: 'Edit Profile at $width');
      expect(find.text('Save profile').hitTestable(), findsOneWidget);
    }
  });
}

Future<void> _scrollRequestToTop(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('approved-request-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = _proofSize,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: _ProjectFileAssetBundle(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Nunito',
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
        ),
        home: RepaintBoundary(key: _captureKey, child: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

class _ProjectFileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith('assets/')) return rootBundle.load(key);
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _BuyerShell extends StatelessWidget {
  const _BuyerShell({required this.selected, required this.child});

  final ApprovedBuyerNavSelection selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 56),
          children: [child],
        ),
      ),
      bottomNavigationBar: BuyerBottomNavigation(
        selected: selected,
        callbacks: ApprovedBuyerNavigation(
          onHome: () {},
          onHocatrends: () {},
          onOffers: () {},
          onChats: () {},
          onMore: () {},
        ),
      ),
    );
  }
}
