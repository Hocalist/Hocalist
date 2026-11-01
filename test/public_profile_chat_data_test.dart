import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/profiles/profile_pages.dart';
import 'package:hocalist/features/profiles/profile_request_card.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/domain/phase2/money.dart';
void main() {
  testWidgets('seller read failure hides cached name and listings', (t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:SellerPublicProfileView(
      name:'Cached seller',onBack:(){},load:()async=>throw Exception('offline'),
      listings:const Text('Seller listings'),onOpenChat:(){},
    ))));
    await t.pumpAndSettle();
    expect(find.text('Cached seller'),findsNothing);
    expect(find.text('Seller listings'),findsNothing);
    expect(find.text('Try again'),findsOneWidget);
    expect(find.text('Back to chat'),findsOneWidget);
  });
  for(final width in [320.0,430.0]) {
    testWidgets('authorized chat request fits $width at large text', (t) async {
      t.view.physicalSize=Size(width,900);t.view.devicePixelRatio=1;
      addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(size:Size(width,900),textScaler:TextScaler.linear(1.6)),
        child:Scaffold(body:SingleChildScrollView(child:ProfileRequestCard(load:()async=>SellerLeadProjection(
          requestId:'request-b',kind:RequestKind.product,title:'Actual chat request',description:'Real description',
          buyerProfileId:'buyer-b',buyerDisplayName:'Buyer B',requestRevision:1,
          budget:MoneyRange(minimum:Money(minorUnits:10000,currencyCode:'USD'),maximum:Money(minorUnits:15000,currencyCode:'USD')),
          preferredMeetupLabel:'Public place',lastCompletedItemLabel:'October 2026',
        )))))));
      await t.pumpAndSettle();
      expect(find.text('Actual chat request'),findsOneWidget);
      expect(find.text(r'$100 – $150'),findsOneWidget);
      expect(find.text('Public place'),findsOneWidget);
      expect(t.takeException(),isNull);
    });
  }
  testWidgets('no authorized request does not create sample content', (t)async{
    await t.pumpWidget(MaterialApp(home:Scaffold(body:ProfileRequestCard(load:()async=>null))));
    await t.pumpAndSettle();expect(find.text('Request in this chat'),findsNothing);
  });
}
