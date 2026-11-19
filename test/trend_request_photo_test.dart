import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/features/media/trend_request_photo.dart';
import 'package:hocalist/features/media/private_remote_image.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';

void main() {
  final pixel=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS0cAAAAASUVORK5CYII=');
  HocatrendsSellerResults data(String id, {bool photo=true}) => HocatrendsSellerResults(topicId:id,items:[
    HocatrendsSellerView(sellerProfileId:'seller',displayName:'Exact seller',avatarMediaId:'avatar-is-not-product',offerImageMediaIds:photo?['photo-$id']:[]),
  ]);
  Widget page(String id, Object version, Future<HocatrendsSellerResults> Function(String) load) => MaterialApp(home:Scaffold(body:TrendRequestPhoto(requestId:id,size:80,version:version,load:load,read:(_)async=>pixel)));
  testWidgets('loads exact request photos, caches rebuild and refreshes on new projection',(tester)async{
    final calls=<String>[];
    Future<HocatrendsSellerResults> load(String id)async{calls.add(id);return data(id);}
    await tester.pumpWidget(page('request-a',1,load));await tester.pumpAndSettle();
    expect(calls,['request-a']);
    expect(tester.widget<PrivateRemoteImage>(find.byType(PrivateRemoteImage)).id,'photo-request-a');
    expect(find.byTooltip('Photo from Exact seller'),findsOneWidget);
    await tester.pumpWidget(page('request-a',1,load));await tester.pumpAndSettle();expect(calls.length,1);
    await tester.pumpWidget(page('request-b',1,load));await tester.pumpAndSettle();
    expect(calls,['request-a','request-b']);expect(tester.widget<PrivateRemoteImage>(find.byType(PrivateRemoteImage)).id,'photo-request-b');
    await tester.pumpWidget(page('request-b',2,(id)async=>data(id,photo:false)));await tester.pumpAndSettle();
    expect(find.byType(PrivateRemoteImage),findsNothing);expect(find.text('No seller photos yet'),findsOneWidget);
  });
  testWidgets('no offer photo never substitutes seller avatar',(tester)async{
    await tester.pumpWidget(page('flash',1,(id)async=>data(id,photo:false)));await tester.pumpAndSettle();
    expect(find.byType(PrivateRemoteImage),findsNothing);expect(find.text('No seller photos yet'),findsOneWidget);
  });
  testWidgets('different request result never displays its photo',(tester)async{
    await tester.pumpWidget(page('request-a',1,(_)async=>data('request-b')));await tester.pumpAndSettle();
    expect(find.byType(PrivateRemoteImage),findsNothing);
  });
  testWidgets('main card calls the request photo loader, not the category',(tester)async{
    String? loaded;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ApprovedHocatrendsPage(
      accent:Colors.blue,realMode:true,onSeeSellers:(){},
      trends:HocatrendsProjection(items:const [HocatrendsTopic(requestId:'exact-request',rank:1,categoryId:'different-category',label:'flash',openRequests:1,competingSellers:1,confirmedPurchases:0,participatingBuyers:1,percent:100,competition:'Medium',activityCopy:'1 seller',availableSellers:1)]),
      loadSellerPhotos:(id)async{loaded=id;return data(id,photo:false);},
    )))));
    await tester.pumpAndSettle();expect(loaded,'exact-request');expect(find.text('No seller photos yet'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('failure shows honest unavailable state',(tester)async{
    await tester.pumpWidget(page('request-a',1,(_)async=>throw StateError('Unavailable')));await tester.pumpAndSettle();
    expect(find.text('Photo unavailable'),findsOneWidget);expect(find.byType(PrivateRemoteImage),findsNothing);
  });
}
