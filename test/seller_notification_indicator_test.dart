import 'package:hocalist/theme/approved_interface_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/notification_indicator.dart';
import 'package:hocalist/features/seller/seller_app_shell.dart';
import 'test_fonts.dart';
void main() {
 setUpAll(loadHocalistTestFonts);
 testWidgets('seller unread dot follows count including cleared and unknown states', (tester) async {
  for (final count in <int?>[null,0,2,0,1,null]) {
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:NotificationIndicatorScope(unreadCount:count,child:SellerAppHeader(onNotifications:(){})))));
   await tester.pumpAndSettle();
   expect(find.byKey(const Key('sellerNotificationUnreadDot')), (count ?? 0)>0 ? findsOneWidget : findsNothing);
   expect(find.byKey(const Key('sellerNotifications')),findsOneWidget);
  }
 });
 testWidgets('unscoped seller header does not invent unread notifications', (tester) async {
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SellerAppHeader(onNotifications:(){}))));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('sellerNotificationUnreadDot')),findsNothing);
 });
 testWidgets('buyer uses seller bell and unread state never clips the icon', (tester) async {
   for (final count in <int?>[null, 0, 2, 0]) {
     await tester.pumpWidget(MaterialApp(home: Scaffold(body: NotificationIndicatorScope(
       unreadCount: count, child: const NotificationArtwork(child: ApprovedInterfaceIcon(
         asset: 'assets/approved_onboarding_home/notification.png', size: 32))))));
     expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
     expect(find.byKey(const Key('buyerNotificationUnreadDot')), (count ?? 0) > 0 ? findsOneWidget : findsNothing);
     expect(find.descendant(of: find.byType(NotificationArtwork), matching: find.byType(ClipPath)), findsNothing);
   }
 });
}

