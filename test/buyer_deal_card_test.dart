import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/buyer_deal_card.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'test_fonts.dart';
import 'visual_proof_capture.dart';

void main() {
  setUpAll(() async {
    await loadHocalistTestFonts();
    if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE')) {
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  final seller = SynchronousFuture(const BuyerDealSeller(verified: true,
    rating: 4.9, reviewCount: 128, sales: 42));
  Future<void> pump(WidgetTester t, double width, double scale, TargetPlatform platform,
      {VoidCallback? chat, VoidCallback? decline, VoidCallback? accept, VoidCallback? options,
      VisualDensity density = VisualDensity.standard, String message = 'Includes the original charger. Payment at the meeting.',
      List<String> photos = const ['test-product']}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1300);
    await t.pumpWidget(MaterialApp(theme: HocalistTheme.light.copyWith(platform: platform, visualDensity: density),
      home: MediaQuery(data: MediaQueryData(size: Size(width, 1300), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12),
          child: RepaintBoundary(key: const Key('deal-proof'), child: BuyerDealCard(
            sellerName: 'Jonathan Sanchez', sellerProfileId: 'seller', loadSeller: (_) => seller,
            title: 'iPad Air 5th Gen (64GB)', price: r'$650',
            meeting: 'Mon, Nov 23 · 3:00 PM', place: 'Business address',
            message: message,
            photos: photos,
            readImage: (_) => SynchronousFuture(File('assets/approved_offers_chat/chat-ipad.png').readAsBytesSync()),
            onChat: chat ?? () {}, onDecline: decline ?? () {}, onAccept: accept, onOptions: options,
          ))))))));
    await t.pumpAndSettle();
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        testWidgets('deal card fits $platform $width at $scale', (t) async {
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await pump(t, width, scale, platform);
          expect(t.takeException(), isNull);
          expect(find.text('Confirmed sales'), findsOneWidget);
          final salesText = t.widget<Text>(find.text('Confirmed sales'));
          final word = TextPainter(text: TextSpan(text: 'Confirmed', style: salesText.style),
            textDirection: TextDirection.ltr, textScaler: TextScaler.linear(scale))..layout();
          expect(t.getSize(find.text('Confirmed sales')).width, greaterThanOrEqualTo(word.width));
          expect(find.text('Verified seller'), findsOneWidget);
          expect(find.text('Available'), findsOneWidget);
          if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE')) {
            if (platform == TargetPlatform.android && scale == 1) {
              await writeProofImage(t, find.byKey(const Key('deal-proof')), 'buyer-deal-${width.toInt()}.png');
            }
          }
        });
      }
    }
  }
  testWidgets('home facts never split unavailable across lines at larger text sizes', (t) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        await pump(t, width, scale, TargetPlatform.android, accept: () {});
        if (scale <= 1.15) {
          final top = t.getTopLeft(find.text('Meet-up')).dy;
          expect(t.getTopLeft(find.text('Available')).dy, closeTo(top, .1));
          expect(t.getTopLeft(find.text('Distance')).dy, closeTo(top, .1),
            reason: 'The approved three-column row must stay intact at $width / $scale');
        }
        final paragraph = t.renderObject<RenderParagraph>(find.text('Unavailable'));
        expect(paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 11)),
          hasLength(1), reason: 'Unavailable must remain a whole word at $width / $scale');
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE') &&
            ((width == 390 && [1.0, 1.15, 1.3].contains(scale)) || (width == 320 && [1.0, 1.6].contains(scale)))) {
          await writeProofImage(t, find.byKey(const Key('deal-proof')),
            'buyer-home-facts-${width.toInt()}-$scale.png');
        }
      }
    }
  });
  testWidgets('paired actions have equal height with compact desktop density', (t) async {
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    await pump(t, 613, 1, TargetPlatform.windows, density: VisualDensity.compact, photos: ['first','extra']);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(BuyerPrimaryButton)).height,
      t.getSize(find.byType(OutlinedButton)).height);
    expect(t.getCenter(find.text('Chat with seller')).dy,
      closeTo(t.getCenter(find.text('Decline offer')).dy, .5));
    if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE')) {
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(find.text('More details')));
      await t.pump(const Duration(milliseconds: 250));
      await writeProofImage(t, find.byKey(const Key('deal-proof')), 'buyer-deal-hover-613.png');
      await mouse.removePointer();
    }
  });
  testWidgets('details hide without extras but remain available for additional photos', (t) async {
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    await pump(t,390,1,TargetPlatform.android,message:'   ');
    expect(find.text('More details'),findsNothing);
    expect(find.text('No message included.'),findsNothing);
    await pump(t,390,1,TargetPlatform.android,message:'',photos:['first','extra']);
    await t.tap(find.text('More details')); await t.pumpAndSettle();
    expect(find.text('Your request'),findsNothing);
    expect(find.text('Seller’s message'),findsNothing);
    expect(find.bySemanticsLabel('Open photo preview'),findsNWidgets(2));
  });
  testWidgets('details expand in place and chat and decline stay distinct', (t) async {
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    var chats=0, declines=0;
    await pump(t,390,1,TargetPlatform.android,chat:()=>chats++,decline:()=>declines++, photos:['first','extra']);
    expect(find.textContaining('Includes the original'),findsNothing);
    await t.tap(find.text('More details')); await t.pumpAndSettle();
    expect(find.textContaining('Includes the original'),findsNothing);
    expect(find.text('iPad Air 5th Gen (64GB)'),findsOneWidget);
    expect(find.text('Business address'),findsOneWidget);
    await t.tap(find.text('Chat with seller')); await t.tap(find.text('Decline offer'));
    expect(chats,1); expect(declines,1);
  });
  testWidgets('missing photo has a neutral thumbnail without message or reschedule details', (t) async {
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    await pump(t,320,1.6,TargetPlatform.android,photos:[]);
    expect(find.bySemanticsLabel('No photo uploaded'),findsOneWidget);
    expect(find.text('More details'),findsNothing);
    expect(find.text('Reschedule'),findsNothing);
    expect(find.textContaining('Includes the original'),findsNothing);
    expect(t.takeException(),isNull);
    if (const bool.fromEnvironment('HOCALIST_BUYER_DEAL_CAPTURE')) {
      await writeProofImage(t,find.byKey(const Key('deal-proof')),'buyer-no-photo-final.png');
    }
  });
  testWidgets('long press opens options without accepting and duplicate dots are absent', (t) async {
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    var accepted=0, options=0;
    await pump(t,360,1,TargetPlatform.android,accept:()=>accepted++,options:()=>options++);
    await t.longPress(find.text('Accept offer and meet')); await t.pumpAndSettle();
    expect(options,1); expect(accepted,0);
    expect(find.byTooltip('Reschedule or decline offer'), findsNothing);
    await t.tap(find.text('Accept offer and meet')); expect(accepted,1);
  });
}
