import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'test_fonts.dart';
void main(){
 setUpAll(loadHocalistTestFonts);
 testWidgets('buyer welcome uses the buyer initials instead of a sample portrait',(tester)async{
  for(final entry in [('Po Testbuyer','PT'),('Maya','M'),('  ','?')]) {
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:ApprovedBuyerBenefitsPage(name:entry.$1,onClose:(){},onFinish:(){}))));
   await tester.pumpAndSettle();
   final avatar=find.byKey(const ValueKey('approved-benefits-avatar'));
   expect(find.descendant(of:avatar,matching:find.text(entry.$2)),findsOneWidget);
   expect(find.descendant(of:avatar,matching:find.byType(Image)),findsNothing);
   expect(tester.takeException(),isNull);
  }
 });
}
