import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/discovery/discovery_adapter.dart';
import 'package:hocalist/data/phase2/discovery/discovery_backends.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/features/seller/seller_customers_page.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'phase2/marketplace/support/marketplace_fakes.dart';
import 'test_fonts.dart';
import 'package:hocalist/features/commercial/credit_wallet_panel.dart';
void main(){
 setUpAll(loadHocalistTestFonts);
 for(final failure in ['contacts_plan_required','permission_denied','network']) {
 testWidgets('customer access handles $failure accurately',(tester)async{
  tester.view.devicePixelRatio=1;tester.view.physicalSize=const Size(320,900);
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final transport=FakeMarketplaceTransport()..handler=(_)=>MarketplaceTransportError(kind:failure=='network'?MarketplaceTransportErrorKind.connectivity:MarketplaceTransportErrorKind.server,code:'42501',message:failure);
  final backend=Phase2DiscoveryBackend(adapter:DiscoveryDataAdapter(transport:transport,session:FakeMarketplaceSession(sellerId)),identity:()=>sellerId);
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:SellerCustomersPage(load:backend.loadCustomers,save:(_,__,___)async{},history:(_)async=>throw StateError('unused'),onBack:(){},onUpgrade:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Scaffold(body:ApprovedSellerBillingPage(focusUpgrade:true,realContent:const CreditWalletPanel(),onBack:(){},onPayment:(){})))))))));
  await tester.pumpAndSettle();
  if(failure=='contacts_plan_required') {
   expect(find.text('Retry'),findsNothing);expect(find.text('Upgrade plan'),findsOneWidget);
   await tester.tap(find.byKey(const Key('customersUpgradePlan')));await tester.pumpAndSettle();
   expect(find.text('Plans & credits'),findsOneWidget);expect(find.text('Continue to upgrade'),findsNothing);expect(find.text('CURRENT PLAN'),findsOneWidget);
  } else {expect(find.text('Upgrade plan'),findsNothing);expect(find.text('Retry'),findsOneWidget);}
  expect(tester.takeException(),isNull);
 });
 }
}
