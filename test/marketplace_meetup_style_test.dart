import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';
import 'package:hocalist/theme/marketplace_ui_foundation.dart';
import 'test_fonts.dart';
final now = DateTime.now().toUtc();
final schedule = MeetingScheduleView(sequence: 1,
 date: LocalDate(year: now.year, month: now.month, day: now.day),
 startTime: LocalTime(hour:23,minute:59), timezoneId:'UTC',offsetMinutes:0,
 instant:DateTime.utc(now.year,now.month,now.day,23,59), placeChoice:'custom',
 placeLabel:'City library', placeAddress:'City library', proposedByUserId:'seller',
 status:'accepted',createdAt:now);
final meeting=MeetingView(meetingId:'meeting',conversationId:'chat',requestId:'request',offerId:'offer',
 buyerUserId:'buyer',sellerUserId:'seller',status:'accepted',revision:1,
 acceptedSchedule:schedule,revisions:[schedule],meetingExpiresAt:now.add(const Duration(days:1)));

void main(){
 setUpAll(loadHocalistTestFonts);
 for (final seller in [false, true]) {
   testWidgets('dashboard keeps a locked meetup until today is confirmed (seller=$seller)', (
     tester,
   ) async {
     tester.view.devicePixelRatio = 1;
     tester.view.physicalSize = const Size(320, 900);
     addTearDown(tester.view.resetDevicePixelRatio);
     addTearDown(tester.view.resetPhysicalSize);
     var pinTaps = 0;
     Future<void> showHome({required bool confirmed}) async {
       await tester.pumpWidget(MaterialApp(
         theme: seller ? HocalistTheme.dark : HocalistTheme.light,
         home: MediaQuery(
           data: MediaQueryData(
             size: const Size(320, 900),
             textScaler: TextScaler.linear(1.6),
           ),
           child: Scaffold(
             body: seller
                 ? ApprovedSellerHomePage(
                     onLeads: () {},
                     onBrowseRequests: () {},
                     todayMeetup: confirmed
                         ? TodayMeetupCard(
                             meeting: meeting,
                             seller: true,
                             counterpartName: 'Buyer A',
                             onPin: () => pinTaps++,
                           )
                         : const LockedTodayMeetupCard(seller: true),
                   )
                 : ApprovedBuyerHomePage(
                     name: 'Buyer',
                     requestTitle: '',
                     requestPosted: false,
                     onCreate: () {},
                     onRequestDetails: () {},
                     onOffers: () {},
                     onRecentActivity: () {},
                     onWallet: () {},
                     realMeetings: confirmed ? [meeting] : const [],
                     onShowTodayPurchasePin: (_) => pinTaps++,
                   ),
           ),
         ),
       ));
       await tester.pumpAndSettle();
     }

     final role = seller ? 'seller' : 'buyer';
     final locked = find.byKey(Key('$role-locked-meetup'));
     final active = find.byKey(Key('$role-today-meetup'));
     final pinLabel = seller ? 'Type buyer’s PIN' : 'Show purchase PIN';
     await showHome(confirmed: false);
     expect(locked, findsOneWidget);
     expect(active, findsNothing);
     expect(find.text('No meetup today'), findsOneWidget);
     expect(find.descendant(of: locked, matching: find.byIcon(Icons.lock_outline)), findsOneWidget);
     for (final label in [pinLabel, 'Manage']) {
       final control = find.descendant(
         of: locked,
         matching: find.widgetWithText(TextButton, label),
       );
       expect(tester.widget<TextButton>(control).onPressed, isNull);
     }
     expect(tester.takeException(), isNull);

     await showHome(confirmed: true);
     expect(locked, findsNothing);
     expect(active, findsOneWidget);
     final pin = find.descendant(
       of: active,
       matching: find.widgetWithText(TextButton, pinLabel),
     );
     await tester.ensureVisible(pin);
     await tester.tap(pin);
     expect(pinTaps, 1);
     expect(tester.takeException(), isNull);
   });
 }

 testWidgets('Seller Home uses the same meetup card with a buyer PIN action', (tester) async {
  var opened = false;
  await tester.pumpWidget(MaterialApp(
   theme: HocalistTheme.light,
   home: Scaffold(body: ApprovedSellerHomePage(
    onLeads: () {},
    onBrowseRequests: () {},
    todayMeetup: TodayMeetupCard(
     meeting: meeting,
     seller: true,
     counterpartName: 'Buyer A',
     requestTitle: 'Camera tripod',
     onPin: () => opened = true,
     onOpenManage: () {},
    ),
   )),
  ));
  await tester.pumpAndSettle();
  final card = find.byKey(const Key('seller-today-meetup'));
  final pin = find.descendant(
   of: card, matching: find.widgetWithText(MarketplaceButton, 'Type buyer’s PIN'),
  );
  await tester.ensureVisible(pin);
  await tester.tap(pin);
  expect(opened, isTrue);
  expect(find.descendant(of: card, matching: find.text('Buyer A')), findsOneWidget);
  expect(find.text('Show purchase PIN'), findsNothing);
 });
 for(final platform in [TargetPlatform.android,TargetPlatform.iOS]){
 for(final width in [320.0,360.0,390.0,430.0]){
 for(final scale in [1.0,1.15,1.3,1.6]){
 testWidgets('today meetup retains actions and design $platform $width $scale',(t) async {
  t.view.devicePixelRatio=1;t.view.physicalSize=Size(width,1900);
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  var maps=0,calls=0,chats=0,pins=0;
  await t.pumpWidget(MaterialApp(theme:HocalistTheme.light.copyWith(platform:platform),
   home:MediaQuery(data:MediaQueryData(size:Size(width,1900),textScaler:TextScaler.linear(scale)),
    child:ApprovedBuyerHomePage(name:'Buyer',requestTitle:'',requestPosted:false,
     onCreate:(){},onRequestDetails:(){},onOffers:(){},onRecentActivity:(){},onWallet:(){},
     realRequests:const [],realMeetings:[meeting],homeOffers:const [],
     onShowTodayPurchasePin:(_)=>pins++,onMeetingDirections:(_)=>maps++,
     onMeetingCall:(_)=>calls++,onMeetingMessage:(_)=>chats++,onManageTodayMeetup:(_,__,___){}))));
  await t.pumpAndSettle();
  final card=find.byKey(const Key('buyer-today-meetup'));
  expect(card,findsOneWidget);
  expect(t.widget<Text>(find.text('Your meetup is today')).style?.fontFamily,'Roboto');
  for(final label in ['Maps','Call','Chat','Show purchase PIN','Manage']){
   final button=find.descendant(of:card,matching:find.widgetWithText(MarketplaceButton,label));
   await t.ensureVisible(button);await t.tap(button);await t.pumpAndSettle();
   expect(t.getSize(button).height,greaterThanOrEqualTo(44));
   expect(t.takeException(),isNull);
  }
  expect([maps,calls,chats,pins],[1,1,1,1]);
  expect(find.text('Reschedule meetup'),findsOneWidget);
  expect(find.text('Cancel meetup'),findsOneWidget);
 });
 }}}
}
