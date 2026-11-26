import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
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
