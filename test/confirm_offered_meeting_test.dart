import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/confirm_offered_meeting_sheet.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'test_fonts.dart';
import 'visual_proof_capture.dart';

void main() {
  setUpAll(() async {
    await loadHocalistTestFonts();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        testWidgets('stored meeting confirmation $platform $width/$scale', (t) async {
          t.view.devicePixelRatio = 1; t.view.physicalSize = Size(width, 850);
          addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
          bool? result;
          await t.pumpWidget(MaterialApp(theme: HocalistTheme.light.copyWith(platform: platform),
            builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () async {
              result = await confirmOfferedMeeting(c, title: 'iPad Air 5th Gen (64GB)',
                time: 'Mon, Nov 23 · 3:00 PM', timezone: 'America/Chicago',
                place: '1127 Wilshire Boulevard, Los Angeles, CA 90017');
            }, child: const Text('Open'))))));
          await t.tap(find.text('Open')); await t.pumpAndSettle();
          expect(find.text('Mon, Nov 23 · 3:00 PM'), findsOneWidget);
          expect(find.text('America/Chicago'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DatePickerDialog), findsNothing);
          expect(t.takeException(), isNull);
          if (const bool.fromEnvironment('HOCALIST_MEETING_ACCEPT_CAPTURE') &&
              platform == TargetPlatform.android && [320.0,390.0].contains(width) && [1.0,1.6].contains(scale)) {
            await writeProofImage(t, find.byType(BuyerModalSheet), 'confirm-offered-$width-$scale.png');
          }
          await t.ensureVisible(find.text('Cancel'));
          await t.tap(find.text('Cancel')); await t.pumpAndSettle();
          expect(result, isFalse);
          await t.tap(find.text('Open')); await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('buyer-modal-sheet-close'))); await t.pumpAndSettle();
          expect(result, isFalse);
          await t.tap(find.text('Open')); await t.pumpAndSettle();
          await t.ensureVisible(find.text('Confirm meeting'));
          await t.tap(find.text('Confirm meeting')); await t.pumpAndSettle();
          expect(result, isTrue); expect(t.takeException(), isNull);
        });
      }
    }
  }
  for (final seller in [false, true]) {
    for (final past in [false, true]) {
      testWidgets('chat acceptance stays scoped seller=$seller past=$past', (t) async {
        t.view.devicePixelRatio=1; t.view.physicalSize=const Size(390,1200);
        addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
        var accepted=0, options=0; String? explored;
        const deal = ApprovedDealView(offerId:'offer-1', title:'Stored seller offer',
          priceLabel:r'$650', statusLabel:'Selected', actionLabel:'Accept offer and meet');
        await t.pumpWidget(MaterialApp(theme:HocalistTheme.light, home:Scaffold(body:
          RepaintBoundary(key: const Key('chat-proof'), child: ApprovedConversationBody(
            onBack:(){}, onPrimary:()=>accepted++, onMeetingOptions:()=>options++,
            onCall:(){},onMore:(){},onRequestChange:(){},onChangeLocation:(){},
            onAttach:(){},onSend:(_){},onLearnMore:(){}, viewerIsSeller:seller,
            primaryLabel:'Accept offer and meet', realEntries:const [],
            realContactName:'Test counterpart', realDeals:past?const []:const [deal],
            previousDeals:past?const [deal]:const [], selectedDealId:'offer-1', entryOfferId:'offer-1',
            onOpenRealDeal:(id)=>explored=id,
          )))));
        await t.pumpAndSettle();
        final accept=find.widgetWithText(BuyerPrimaryButton,'Accept offer and meet');
        if(!seller && !past) {
          expect(accept,findsOneWidget);
          await t.ensureVisible(accept); await t.longPress(accept); await t.pumpAndSettle();
          expect(options,1);expect(accepted,0);
          await t.tap(accept);expect(accepted,1);
          if (const bool.fromEnvironment('HOCALIST_MEETING_ACCEPT_CAPTURE')) {
            await writeProofImage(t,find.byKey(const Key('chat-proof')),'chat-meeting-accept.png');
          }
        } else {expect(accept,findsNothing);}
        await t.ensureVisible(find.text('Explore deal').first);
        await t.tap(find.text('Explore deal').first); await t.pumpAndSettle();
        expect(explored,'offer-1');expect(t.takeException(),isNull);
      });
    }
  }
  testWidgets('disabled shared button cannot tap or long press', (t) async {
    var options=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body: BuyerPrimaryButton(
      label:'Busy',onPressed:null,onLongPress:()=>options++))));
    await t.longPress(find.text('Busy'));await t.tap(find.text('Busy'));
    expect(options,0);
  });
}
