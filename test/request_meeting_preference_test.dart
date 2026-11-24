import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/features/meetings/request_meeting_preference.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/approved/confirm_offered_meeting_sheet.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'test_fonts.dart';
import 'visual_proof_capture.dart';

MarketplaceRequest request({bool preferred = true, bool home = false, String? unit, String street = '100 Example Street'}) => MarketplaceRequest(
  id: 'request', buyerUserId: 'buyer', buyerProfileId: 'profile', status: RequestStatus.active,
  stamp: RecordStamp(revision: 1, createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)),
  draft: RequestDraft(kind: RequestKind.product, title: 'Test request', condition: ProductCondition.used,
    location: home ? RequestLocation.homeAddress(preferMeetHere: preferred,
      coordinates: RequestCoordinates(latitude: 41.88, longitude: -87.63))
      : RequestLocation.custom(preferMeetHere: preferred,
        address: PostalAddress(line1: street, line2: unit, city: 'Chicago', state: 'IL'),
        coordinates: RequestCoordinates(latitude: 41.88, longitude: -87.63))));
void main() {
  setUpAll(() async {
    await loadHocalistTestFonts();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  String? review(MarketplaceRequest r, {String user='buyer', String id='request',
      String? address, double? lat, double? lng}) => preferredPlaceToReview(
    request:r, requestId:id, buyerUserId:user, proposedAddress:address, latitude:lat, longitude:lng);
  test('only this request owner receives the location warning', () {
    expect(review(request(),address:'200 Other Street'), contains('100 Example Street'));
    expect(review(request(preferred:false)),isNull);
    expect(review(request(),user:'seller'),isNull);
    expect(review(request(),id:'another-request'),isNull);
  });
  test('same full address or tightly matched pin avoids false warnings', () {
    expect(review(request(),address:'100 EXAMPLE Street, Chicago IL'),isNull);
    expect(review(request(),lat:41.880001,lng:-87.63),isNull);
    expect(review(request(),lat:41.89,lng:-87.63),isNotNull);
    expect(review(request()),isNotNull,reason:'Unknown location is not assumed to match');
    expect(review(request(unit:'Suite 2'),lat:41.88,lng:-87.63),isNotNull);
    expect(review(request(home:true),lat:41.89,lng:-87.63),contains('home address'));
    expect(review(request(street:'10 桜町'),address:'10 松町, Chicago, IL'),isNotNull,
      reason:'Different non-Latin street names must not normalize to the same address');
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0,360.0,390.0,430.0]) {
      for (final scale in [1.0,1.15,1.3,1.6]) {
        testWidgets('preference and warning fit $platform $width/$scale', (t) async {
          t.view.physicalSize=Size(width,900); t.view.devicePixelRatio=1;
          addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
          bool selected=false; bool? result;
          Widget app(Widget body) => MaterialApp(theme:HocalistTheme.light.copyWith(platform:platform),
            builder:(c,child)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:child!),
            home:Scaffold(body:body));
          await t.pumpWidget(app(StatefulBuilder(builder:(c,set)=>SingleChildScrollView(child:
            ApprovedLocationRequestStep(useHomeAddress:true,onUseHomeAddressChanged:(_){},onBack:(){},onSubmit:(){},
              preferMeetHere:selected,onPreferMeetHereChanged:(v)=>set(()=>selected=v))))));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('I’d prefer to meet here'));
          await t.tap(find.text('I’d prefer to meet here')); await t.pumpAndSettle();
          expect(selected,isTrue); expect(t.takeException(),isNull);
          await t.tap(find.text('I’d prefer to meet here')); await t.pumpAndSettle(); expect(selected,isFalse);
          await t.pumpWidget(app(Builder(builder:(c)=>TextButton(child:const Text('Open'),onPressed:() async {
            result=await confirmOfferedMeeting(c,title:'Test request',time:'Mon, Nov 23 · 3:00 PM',timezone:'America/Chicago',
              place:'200 Other Street, Chicago, IL',preferredPlace:'100 Example Street, Chicago, IL');
          }))));
          await t.tap(find.text('Open'));await t.pumpAndSettle();
          expect(find.text('Check the meeting place'),findsOneWidget);
          expect(find.text('You preferred: 100 Example Street, Chicago, IL'),findsOneWidget);
          expect(t.takeException(),isNull);
          if(const bool.fromEnvironment('HOCALIST_PREFERENCE_CAPTURE') && platform==TargetPlatform.android &&
              [320.0,390.0].contains(width) && [1.0,1.6].contains(scale)) {
            await writeProofImage(t,find.byType(BuyerModalSheet),'meeting-preference-$width-$scale.png');
          }
          await t.ensureVisible(find.text('Cancel'));await t.tap(find.text('Cancel'));await t.pumpAndSettle();expect(result,isFalse);
          await t.tap(find.text('Open'));await t.pumpAndSettle();
          await t.ensureVisible(find.text('Confirm meeting'));await t.tap(find.text('Confirm meeting'));await t.pumpAndSettle();
          expect(result,isTrue);expect(t.takeException(),isNull);
        });
      }
    }
  }
}
