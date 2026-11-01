import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/reviews/buyer_reviews_backend.dart';
import 'package:hocalist/features/profiles/buyer_reviews_section.dart';
import 'package:hocalist/features/discovery/buyer_public_profile_page.dart';
import 'package:hocalist/domain/phase2/discovery.dart';

class FakeReviews implements BuyerReviewsRepository {
 bool reviewed=false,failSubmit=false;int calls=0;final keys=<String>[];final offsets=<int>[];
 int rating=0;String body='';
 @override Future<BuyerReviewsPageData> load({int offset=0})async{
  offsets.add(offset);
  return BuyerReviewsPageData(available:true,count:reviewed?1:0,sum:reviewed?rating:0,hasMore:false,
    items:reviewed?[BuyerReviewEntry(id:'review',rating:rating,body:body,seller:'Test seller',createdAt:DateTime(2026,11,1))]:[],
    purchases:reviewed?[]:[BuyerReviewPurchase(id:'sale',title:'Confirmed test purchase',date:DateTime(2026,10,30))]);
 }
 @override Future<void> submit(String key,String outcomeId,int score,String comment)async{keys.add(key);calls++;if(failSubmit)throw Exception('network');reviewed=true;rating=score;body=comment;}
 @override Future<void> report(String reviewId,String reason)async{}
}
void main(){
 Future<void> pump(WidgetTester t,Widget child,{double width=390,double scale=1})async{
  t.view.physicalSize=Size(width,1000);t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(size:Size(width,1000),textScaler:TextScaler.linear(scale)),child:Scaffold(body:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(16),child:child))))));await t.pumpAndSettle();
 }
 testWidgets('eligible seller opens new editor, publishes and sees stored review', (t)async{
  final repo=FakeReviews();await pump(t,BuyerReviewsSection(repository:repo));
  await t.tap(find.text('Review buyer'));await t.pumpAndSettle();
  await t.tap(find.byTooltip('4 stars'));await t.enterText(find.byType(TextField),'Clear communication.');
  await t.ensureVisible(find.text('Publish review'));await t.tap(find.text('Publish review'));await t.pumpAndSettle();
  expect(repo.calls,1);expect(repo.rating,4);expect(repo.body,'Clear communication.');expect(find.text('Clear communication.'),findsOneWidget);expect(find.text('Review buyer'),findsNothing);
 });
 testWidgets('ambiguous retry keeps same key, rating and comment', (t)async{
  final repo=FakeReviews()..failSubmit=true;await pump(t,BuyerReviewEditor(repository:repo,purchases:[BuyerReviewPurchase(id:'sale',title:'Test',date:DateTime(2026))]));
  await t.tap(find.byTooltip('1 star'));await t.enterText(find.byType(TextField),'Comment');await t.tap(find.text('Publish review'));await t.pumpAndSettle();
  expect(t.widget<TextField>(find.byType(TextField)).enabled,false);
  await t.tap(find.text('Retry review'));await t.pumpAndSettle();expect(repo.keys.length,2);expect(repo.keys[0],repo.keys[1]);
 });
 for(final embedded in [false,true]){
  testWidgets('same reviews on buyer chat page and preview embedded=$embedded; privacy cannot hide rating', (t)async{
   final repo=FakeReviews()..reviewed=true..rating=1..body='Actual seller feedback';
   await pump(t,BuyerPublicProfilePage(embedded:embedded,onBack:(){},load:()async=>const PublicBuyerProfile(available:false),reviews:repo));
   expect(find.text('Actual seller feedback'),findsOneWidget);expect(find.text('1.0'),findsOneWidget);expect(find.text('This profile is private'),findsOneWidget);
  });
 }
 for(final width in [320.0,360.0,390.0,430.0])for(final scale in [1.0,1.15,1.3,1.6]){
  testWidgets('review form fits $width/$scale',(t)async{
   final repo=FakeReviews();await pump(t,BuyerReviewEditor(repository:repo,purchases:[BuyerReviewPurchase(id:'sale',title:'Long confirmed purchase title',date:DateTime(2026))]),width:width,scale:scale);
   expect(t.takeException(),isNull);
  });
 }
}
