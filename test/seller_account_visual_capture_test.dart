import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';

import 'test_fonts.dart';

const _captureKey = ValueKey('seller-account-capture');
const _proofSize = Size(390, 844);

/// Capture-only comparisons against mutable `output/` goldens. They stay out of
/// the default suite so `flutter test` never depends on local capture state;
/// run explicitly with
/// `flutter test --dart-define=HOCALIST_VISUAL_CAPTURE=true`.
const bool _captureEnabled = bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE');

void main() {
  if (!_captureEnabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadHocalistTestFonts);

  testWidgets('capture Seller More identity card at 390', (tester) async {
    await _pump(
      tester,
      ApprovedSellerMorePage(
        sellerName: 'Northside Tech',
        onProfile: () {},
        onEditProfile: () {},
        onSettings: () {},
        onNotifications: () {},
        onAccessibility: () {},
        onSafety: () {},
        onHelp: () {},
        onLogout: () {},
      ),
    );

    await expectLater(
      find.byKey(const Key('sellerMoreIdentityCard')),
      matchesGoldenFile(
        '../output/seller-account-redesign-2026-08-09/seller-more-card-390.png',
      ),
    );
  });

  testWidgets('capture Seller Edit Profile at 390', (tester) async {
    await _pump(
      tester,
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 56),
        child: ApprovedSellerEditProfilePage(
          name: 'Northside Tech',
          onNameChanged: (_) {},
          onBack: () {},
          onDone: () {},
        ),
      ),
    );

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile(
        '../output/seller-account-redesign-2026-08-09/seller-edit-profile-390.png',
      ),
    );
  });
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _proofSize;
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
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2915f4)),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: _captureKey,
            child: ColoredBox(color: Colors.white, child: page),
          ),
        ),
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
