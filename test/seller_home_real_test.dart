import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'test_fonts.dart';

const realLead = SellerLeadView(
  requestId: 'request-1',
  requestRevision: 1,
  name: 'Buyer',
  initials: 'B',
  city: 'Yonkers, NY',
  distance: '—',
  request: 'Used laptop',
  description: 'A working laptop',
  budget: r'$300 - $500',
  match: 0,
  purchases: 0,
  lastPurchase: '—',
  meeting: 'Public place',
  avatarColor: Colors.white,
  initialColor: Colors.blue,
);

Future<void> pumpHome(
  WidgetTester tester, {
  List<SellerLeadView> leads = const [realLead],
  bool loading = false,
  String? error,
  VoidCallback? onRetry,
  VoidCallback? onOfferHistory,
  ValueChanged<SellerLeadView>? onOpenLead,
  VoidCallback? onSetupBusiness,
  Future<SellerHomeSummaryView> Function()? loadSummary,
  double width = 390,
  double scale = 1,
  String sellerName = 'Northside Tech',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme:ThemeData(fontFamily:'Nunito'),
      home: Scaffold(
        body: RepaintBoundary(key:const Key('seller-home-capture'),child:ApprovedSellerHomePage(
          onLeads: () {},
          onOpenLead: onOpenLead,
          onSetupBusiness:onSetupBusiness,
          onBrowseRequests: () {},
          onOfferHistory: onOfferHistory,
          sellerName: sellerName,
          loadSummary:loadSummary,
          realLeads: leads,
          leadsLoading: loading,
          leadsError: error,
          onRefreshLeads: onRetry,
        )),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadHocalistTestFonts();
    if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE')) {
      final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')); await icons.load();
    }
  });
  for (final width in [320.0,390.0,528.0]) {
    testWidgets('greeting keeps wave attached to the final name word at $width',(tester)async{
      await pumpHome(tester,width:width,sellerName:'Po SellerTesting2');
      final finder=find.textContaining('SellerTesting2!');
      final paragraph=tester.renderObject<RenderParagraph>(finder);
      final text=paragraph.text.toPlainText();
      final start=text.indexOf('SellerTesting2!');
      final boxes=paragraph.getBoxesForSelection(TextSelection(baseOffset:start,extentOffset:text.length));
      expect(boxes,isNotEmpty);
      expect(boxes.every((box)=>(box.top-boxes.first.top).abs()<1),isTrue);
    });
  }
  testWidgets('missing recommendation details provide a Store setup route',(tester)async{
    var opened=0;
    await pumpHome(tester,onSetupBusiness:()=>opened++);
    await tester.ensureVisible(find.text('Set up your Store'));
    await tester.tap(find.text('Set up your Store'));
    expect(opened,1);
  });
  testWidgets('recent lead tap carries the exact request identity', (
    tester,
  ) async {
    SellerLeadView? opened;
    await pumpHome(tester, onOpenLead: (lead) => opened = lead);
    await tester.ensureVisible(find.text('Used laptop').first);
    await tester.tap(find.text('Used laptop').first);
    await tester.pump();
    expect(opened?.requestId, 'request-1');
  });
  testWidgets(
    'real seller profile never fills an unavailable email with demo data',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: ApprovedSellerEditProfilePage(
            name: 'Northside Tech',
            onNameChanged: (_) {},
            onBack: () {},
            onDone: () {},
            contactEditor: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('northside.tech@example.com'), findsNothing);
    },
  );

  testWidgets('real seller More shows only the supplied account email', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedSellerMorePage(
          sellerName: 'Northside Tech',
          sellerEmail: 'seller@example.com',
          onProfile: () {},
          onEditProfile: () {},
          onSettings: () {},
          onNotifications: () {},
          onAccessibility: () {},
          onSafety: () {},
          onHelp: () {},
          onLogout: () {},
        ),
      ),
    );
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('northside.tech@example.com'), findsNothing);
  });

  testWidgets('seller edit profile keeps the placeholder photo without an id', (
    tester,
  ) async {
    SellerProfilePhotoAction? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerEditProfilePage(
            name: 'Northside Tech',
            onNameChanged: (_) {},
            onBack: () {},
            onDone: () {},
            onProfilePhotoAction: (value) => action = value,
            contactEditor: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('sellerEditProfilePhotoAction')),
      findsOneWidget,
    );
    expect(find.text('N'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerEditProfileChangePhoto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove current photo'));
    await tester.pumpAndSettle();
    expect(action, SellerProfilePhotoAction.remove);
  });

  testWidgets('real seller home displays only sourced lead facts', (
    tester,
  ) async {
    var historyOpens = 0;
    await pumpHome(tester, onOfferHistory: () => historyOpens++);
    expect(find.textContaining('Northside Tech'), findsOneWidget);
    expect(find.byKey(const Key('sellerHomeAvatar')),findsOneWidget);
    expect(find.text('Leads targeted'),findsOneWidget);
    expect(find.text('Deals closed'),findsOneWidget);
    expect(find.text('Used laptop'), findsOneWidget);
    expect(find.text('Yonkers, NY'), findsOneWidget);
    expect(find.text(r'$300 - $500'), findsOneWidget);
    expect(find.text('56'), findsNothing);
    expect(find.text('12'), findsNothing);
    expect(find.textContaining('Alex'), findsNothing);
    expect(find.text('Pressure Washing'), findsNothing);
    expect(find.text('This month'), findsNothing);
    expect(find.byKey(const Key('sellerAccountHealth')), findsOneWidget);
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.text('Recommended leads for you'), findsOneWidget);
    expect(find.byKey(const Key('sellerHomeRecommendedEmpty')), findsOneWidget);
    await tester.tap(find.text('View offers'));
    expect(historyOpens, 1);
  });

  testWidgets('real seller home shows retry instead of sample leads', (
    tester,
  ) async {
    var retries = 0;
    await pumpHome(
      tester,
      leads: const [],
      error: 'Could not load requests.',
      onRetry: () => retries++,
    );
    expect(find.text('Could not load requests.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(find.text('PS5 Console'), findsNothing);
  });

  testWidgets('monthly metrics use complete server totals rather than loaded cards',(tester) async {
    await pumpHome(tester,loadSummary:()async=>SellerHomeSummaryView(
      leadsTargeted:147,dealsClosed:9,monthStart:DateTime.utc(2026,10),monthEnd:DateTime.utc(2026,11),timezone:'UTC'));
    expect(find.text('147'),findsOneWidget); expect(find.text('9'),findsOneWidget);
    expect(find.text('This month (UTC)'),findsNWidgets(2));
    expect(find.text('Available leads'),findsNothing);expect(find.text('Offers sent'),findsNothing);
  });
  testWidgets('failed monthly totals do not substitute offer counts',(tester) async {
    await pumpHome(tester,loadSummary:()async=>throw StateError('offline'));
    expect(find.text('Unavailable'),findsNWidgets(2)); expect(find.text('—'),findsNWidgets(2));
  });
  for (final width in [320.0,360.0,390.0,430.0]) {
    for (final scale in [1.0,1.15,1.3,1.6]) {
      testWidgets('real seller home fits $width at scale $scale', (
        tester,
      ) async {
        await pumpHome(tester, width: width, scale: scale,loadSummary:()async=>SellerHomeSummaryView(
          leadsTargeted:147,dealsClosed:9,monthStart:DateTime.utc(2026,10),monthEnd:DateTime.utc(2026,11),timezone:'UTC'));
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE') && scale==1.0 && (width==320 || width==390)) {
          final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('seller-home-capture')));
          await tester.runAsync(()async{
            final image=await boundary.toImage(); final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('.codex-local/seller-home-restored-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
      });
    }
  }
}
