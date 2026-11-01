import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/credit_wallet_panel.dart';
import 'package:hocalist/features/commercial/seller_subscription_panel.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'phase2/commercial/support/commercial_payloads.dart';
import 'test_fonts.dart';
void main(){
 setUpAll(loadHocalistTestFonts);
 for(final width in [320.0,430.0]) {
 testWidgets('upgrade selects Plans and reveals existing button after loading at $width',(tester)async{
  tester.view.devicePixelRatio=1;tester.view.physicalSize=Size(width,740);
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final plan=Completer<SellerEntitlementView>();
  await tester.pumpWidget(MaterialApp(theme:ThemeData(fontFamily:'Nunito'),home:Scaffold(body:SingleChildScrollView(child:Column(children:[
   const SizedBox(height:100),
   CreditWalletPanel(initialSection:'Plans',load:()async=>CreditWalletView.fromJson(creditWalletJson()),additionalSections:{'Plans':[
    SellerSubscriptionPanel(focusManagePlans:true,loadEntitlement:()=>plan.future),
   ]}),
  ])))));
  await tester.pump();
  expect(find.text('Loading your plan…'),findsOneWidget);
  plan.complete(SellerEntitlementView.fromJson(entitlementJson(effectivePlan:'free',effectiveSource:'free',calendarConfigured:true)));
  await tester.pumpAndSettle();
  expect(find.text('Compare and manage plans').hitTestable(),findsOneWidget);
  expect(find.text('Continue to upgrade'),findsNothing);
  expect(tester.takeException(),isNull);
 });
 }
}
