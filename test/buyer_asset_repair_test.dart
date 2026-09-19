import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repaired Buyer icons and routed wordmark have alpha', () async {
    const assets = [
      'assets/approved_onboarding_home/faq-store.png',
      'assets/approved_onboarding_home/faq-buyer.png',
      'assets/approved_onboarding_home/faq-target.png',
      'assets/approved_onboarding_home/benefit-medal.png',
      'assets/approved_offers_chat/chat-back.png',
      'assets/approved_offers_chat/chat-safety.png',
      'assets/approved_trends_notifications/activity-chat.png',
      'assets/brand/hocalist-wordmark.png',
    ];

    for (final asset in assets) {
      final bytes = await File(asset).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull, reason: '$asset should decode as RGBA');
      final rgba = data!.buffer.asUint8List();
      final cornerAlphas = [
        rgba[3],
        rgba[frame.image.width * 4 - 1],
        rgba[rgba.length - frame.image.width * 4 + 3],
        rgba[rgba.length - 1],
      ];
      expect(
        cornerAlphas.any((alpha) => alpha == 0),
        isTrue,
        reason: '$asset should have a transparent outer pixel',
      );
    }
  });

  test(
    'Seller chat interface icons have clean transparent outer canvases',
    () async {
      const excludedNames = {
        'actual-chat-426.png',
        'actual-offers-426.png',
        'actual-view-offer-426.png',
        'comparison-contact-sheet.png',
        'chat-ipad.png',
        'john-avatar.png',
        'offer-thumbnail.png',
        'ps5.png',
        'rewards-gift.png',
        'wordmark.png',
      };
      final assets = Directory('assets/approved_seller/chat')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .where((file) => !excludedNames.contains(file.uri.pathSegments.last));

      for (final asset in assets) {
        final bytes = await asset.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(data, isNotNull, reason: '${asset.path} should decode as RGBA');
        final rgba = data!.buffer.asUint8List();
        final width = frame.image.width;
        final cornerOffsets = [
          0,
          width * 4 - 4,
          rgba.length - width * 4,
          rgba.length - 4,
        ];
        for (final offset in cornerOffsets) {
          final red = rgba[offset];
          final green = rgba[offset + 1];
          final blue = rgba[offset + 2];
          final alpha = rgba[offset + 3];
          final maximum = [red, green, blue].reduce((a, b) => a > b ? a : b);
          final minimum = [red, green, blue].reduce((a, b) => a < b ? a : b);
          final screenshotWhite =
              alpha > 0 && minimum >= 238 && maximum - minimum <= 16;
          expect(
            screenshotWhite,
            isFalse,
            reason: '${asset.path} should not reveal a white crop when pressed',
          );
        }
      }
    },
  );

  test('detail PIN icons are clean centred rebuilds', () async {
    const assets = [
      'assets/approved_offers_chat/detail-pin.png',
      'assets/approved_seller/chat/detail-pin.png',
    ];

    for (final asset in assets) {
      final bytes = await File(asset).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(frame.image.width, 128, reason: '$asset uses the shared canvas');
      expect(frame.image.height, 128, reason: '$asset uses the shared canvas');
      expect(data, isNotNull, reason: '$asset should decode as RGBA');

      final rgba = data!.buffer.asUint8List();
      var visiblePixels = 0;
      var strayWhitePixels = 0;
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          final offset = (y * 128 + x) * 4;
          final red = rgba[offset];
          final green = rgba[offset + 1];
          final blue = rgba[offset + 2];
          final alpha = rgba[offset + 3];
          if (alpha > 8) visiblePixels++;
          final intentionalInfoBadge = x >= 70 && y >= 69;
          if (alpha > 8 &&
              red > 245 &&
              green > 245 &&
              blue > 245 &&
              !intentionalInfoBadge) {
            strayWhitePixels++;
          }
        }
      }

      expect(visiblePixels, greaterThan(1500));
      expect(
        strayWhitePixels,
        0,
        reason: '$asset should not retain white screenshot debris',
      );
      expect(rgba[3], 0, reason: '$asset should keep transparent corners');
      expect(
        rgba[rgba.length - 1],
        0,
        reason: '$asset should keep transparent corners',
      );
    }
  });

  testWidgets('Buyer icon slots use rebuilt centred source canvases', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: BuyerAssetIcon(
            asset: 'assets/post_request/kind-service.png',
            slotSize: BuyerIconTokens.card,
          ),
        ),
      ),
    );

    final slot = find.byKey(
      const ValueKey('buyer-icon-slot:assets/post_request/kind-service.png'),
    );
    expect(tester.getSize(slot), const Size.square(BuyerIconTokens.card));
    expect(
      find.descendant(of: slot, matching: find.byType(Transform)),
      findsNothing,
      reason: 'rebuilt Buyer icons should not need overflow scaling',
    );
  });

  test(
    'approved soft-circle icons keep color without outer screenshot debris',
    () async {
      const assets = [
        'assets/approved_onboarding_home/dashboard-trophy.png',
        'assets/approved_onboarding_home/dashboard-calendar.png',
        'assets/approved_onboarding_home/dashboard-clipboard.png',
        'assets/approved_onboarding_home/dashboard-medal.png',
        'assets/approved_onboarding_home/benefit-chat.png',
        'assets/approved_onboarding_home/benefit-location.png',
        'assets/approved_onboarding_home/benefit-medal.png',
        'assets/approved_onboarding_home/benefit-payment-shield.png',
        'assets/approved_onboarding_home/benefit-review-dollar.png',
        'assets/approved_onboarding_home/benefit-reward.png',
        'assets/approved_onboarding_home/benefit-shield.png',
        'assets/approved_onboarding_home/benefit-tag.png',
        'assets/approved_onboarding_home/activity-check.png',
        'assets/approved_onboarding_home/activity-star.png',
      ];

      for (final asset in assets) {
        final bytes = await File(asset).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(data, isNotNull, reason: '$asset should decode as RGBA');
        final rgba = data!.buffer.asUint8List();
        final width = frame.image.width;
        final height = frame.image.height;
        int alphaAt(int x, int y) => rgba[((y * width + x) * 4) + 3];

        expect(alphaAt(0, 0), 0, reason: '$asset should keep a clean corner');
        expect(
          alphaAt(width ~/ 4, height ~/ 2),
          greaterThan(200),
          reason: '$asset should retain its approved soft-circle background',
        );
        expect(
          alphaAt(width - 1, height ~/ 2),
          0,
          reason: '$asset should not retain screenshot pixels past the circle',
        );
      }
    },
  );

  testWidgets('changing routed AppFrame page starts at the top', (
    tester,
  ) async {
    const firstKey = PageStorageKey<String>('app-frame-first');
    const secondKey = PageStorageKey<String>('app-frame-second');

    Widget app(Key key, String title) => MaterialApp(
      home: Scaffold(
        body: AppFrame(
          key: ValueKey(title),
          scrollKey: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 1400),
              const Text('Bottom'),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(firstKey, 'First page'));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(ListView)).position.pixels,
      greaterThan(0),
    );

    await tester.pumpWidget(app(secondKey, 'Second page'));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(find.byType(ListView)).position.pixels,
      0,
    );
    expect(find.text('Second page'), findsOneWidget);
  });
}
