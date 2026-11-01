import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'test_fonts.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'phase2/marketplace/support/marketplace_fakes.dart';

const enquiryFixtures=[
  ChatEnquiry(id:'store',conversationId:'pair',origin:'store_listing',subjectId:'listing',label:'Refurbished tablet with keyboard'),
  ChatEnquiry(id:'trend',conversationId:'pair',origin:'hocatrends_enquiry',subjectId:'topic',label:'Computers and accessories'),
];
Widget enquiryChat({String? selected='store',ValueChanged<String>? onSelect,bool seller=false})=>Scaffold(
  body:ApprovedConversationBody(
    onBack:(){},onPrimary:(){},onCall:(){},onMore:(){},onRequestChange:(){},onChangeLocation:(){},onAttach:(){},onSend:(_){},onLearnMore:(){},
    viewerIsSeller:seller,realContactName:'Controlled test account',realEntries:const [],
    realDeals:const [ApprovedDealView(offerId:'deal',title:'Previous tablet request',priceLabel:'\$15',statusLabel:'Completed',completed:true)],
    selectedDealId:selected??'deal',enquiries:enquiryFixtures,selectedEnquiryId:selected,onSelectEnquiry:onSelect,
  ),
);
void main(){
  test('closed offer cards do not prompt buyer confirmation or meeting setup', () {
    for (final status in ['declined', 'withdrawn', 'cancelled', 'expired']) {
      final offer = decodeOfferJson(offerJson()..['status'] = status, 'offer');
      final deal = ApprovedDealView.fromSelectedOffer(offer);
      expect(deal.statusLabel, 'Deal closed');
      expect(deal.actionLabel, 'View offer details');
      expect(deal.completed, false);
    }
  });
  testWidgets('Deals opens history when an enquiry has no current deals', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ApprovedConversationBody(
      onBack:(){},onPrimary:(){},onCall:(){},onMore:(){},onRequestChange:(){},
      onChangeLocation:(){},onAttach:(){},onSend:(_){},onLearnMore:(){},
      realEntries: const [], realDeals: const [], enquiries: enquiryFixtures,
      selectedEnquiryId: 'store', onSelectEnquiry: (_) {},
      previousDeals: const [ApprovedDealView(offerId:'past',title:'Past request',
        priceLabel:'15',statusLabel:'Completed',completed:true)],
      onSelectRealDeal: (id) => selected=id,
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    expect(selected, 'past');
    expect(tester.takeException(), isNull);
  });
  setUpAll(loadHocalistTestFonts);
  for (final seller in [false, true]) {
    testWidgets('collapse deals preserves selected note and draft for seller=$seller', (tester) async {
      await tester.pumpWidget(MaterialApp(home: enquiryChat(selected: null, seller: seller)));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('active-deal-deal'));
      final toggle = find.byKey(const Key('chat-toggle-deals'));
      final input = find.byType(TextField).first;
      expect(card, findsOneWidget);
      await tester.enterText(input, 'Keep this draft');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(find.text('Selected deal: Previous tablet request'), findsOneWidget);
      expect(find.byKey(const Key('approved-manage-conversation-deals')), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'Keep this draft');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'Keep this draft');
      expect(tester.takeException(), isNull);
    });
  }
  for(final width in [320.0,360.0,390.0,430.0]) {
    for(final scale in [1.0,1.15,1.3,1.6]) {
      testWidgets('approved enquiry selection fits $width at $scale',(tester) async {
        tester.view.physicalSize=Size(width,844);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        await tester.pumpWidget(MaterialApp(theme:ThemeData(fontFamily:'Nunito'),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home:enquiryChat(onSelect:(id)=>selected=id)));
        await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
        expect(find.text('Selected deal: Previous tablet request'),findsNothing);
        final choice=find.byKey(const ValueKey('enquiry-trend'));
        await tester.ensureVisible(choice);await tester.tap(choice);expect(selected,'trend');
        expect(tester.takeException(),isNull);
      });
    }
  }
  testWidgets('Past opens the completed deal chat directly', (tester) async {
    String? selected = 'current';
    String? enquiry;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, update) => Scaffold(
      body: ApprovedConversationBody(
        onBack:(){},onPrimary:(){},onCall:(){},onMore:(){},onRequestChange:(){},onChangeLocation:(){},onAttach:(){},onSend:(_){},onLearnMore:(){},
        realEntries: const [], realContactName: 'Test seller',
        realDeals: const [ApprovedDealView(offerId:'current',title:'Current request',priceLabel:'15',statusLabel:'Selected')],
        previousDeals: const [ApprovedDealView(offerId:'past',title:'Completed request',priceLabel:'15',statusLabel:'Completed',completed:true)],
        enquiries: enquiryFixtures, selectedDealId: selected, selectedEnquiryId: enquiry,
        onSelectRealDeal: (id) => update(() {selected=id; enquiry=null;}),
        onSelectEnquiry: (id) => update(() {enquiry=id;}),
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Current Deals'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-deal-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('active-deal-past')), findsNothing);
    expect(find.byKey(const Key('chat-past-deals')), findsNothing);
    await tester.tap(find.byKey(const Key('approved-manage-conversation-deals')));
    await tester.pumpAndSettle();
    expect(find.text('Deals in this conversation'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.byKey(const ValueKey('approved-real-deal-row-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('approved-real-previous-row-past')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-past-deals')));
    await tester.pumpAndSettle();
    expect(selected, 'past');
    expect(find.text('Selected deal: Completed request'), findsOneWidget);
    await tester.tap(find.text('Enquiries').first);
    await tester.pumpAndSettle();
    expect(enquiry, 'store');
    expect(find.textContaining('You are messaging about this enquiry'), findsNothing);
    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    expect(enquiry, isNull);
    expect(selected, 'current');
    expect(tester.takeException(), isNull);
  });
  testWidgets('enquiry drafts survive switching enquiry and deal in the same body',(tester) async {
    String? selected='store';late StateSetter update;
    await tester.pumpWidget(MaterialApp(home:StatefulBuilder(builder:(context,setState){update=setState;return enquiryChat(selected:selected);})));await tester.pumpAndSettle();
    final input=find.byType(TextField).first;
    await tester.enterText(input,'Store draft');
    update(()=>selected='trend');await tester.pumpAndSettle();expect(tester.widget<TextField>(input).controller!.text,isEmpty);
    await tester.enterText(input,'Topic draft');
    update(()=>selected=null);await tester.pumpAndSettle();expect(tester.widget<TextField>(input).controller!.text,isEmpty);
    update(()=>selected='store');await tester.pumpAndSettle();expect(tester.widget<TextField>(input).controller!.text,'Store draft');
    update(()=>selected='trend');await tester.pumpAndSettle();expect(tester.widget<TextField>(input).controller!.text,'Topic draft');
  });
}
