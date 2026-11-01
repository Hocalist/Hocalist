import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/saved_places_backend.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/features/approved/place_capture_sheet.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/approved/request_saved_addresses.dart';
import 'test_fonts.dart';

const address = PostalAddress(line1: '100 Example Street', line2: 'Suite 2',
  city: 'Chicago', state: 'IL', postalCode: '60606', country: 'US');
const place = PlaceCaptureResult(label: 'Office', address: '100 Example Street, Suite 2, Chicago, IL 60606',
  postalAddress: address, source: PlaceCaptureSource.manual);
class Places implements SavedPlacesRepository {
  List<SavedPlace> rows = [];
  int saves = 0;
  bool fail = false;
  @override Future<List<SavedPlace>> load() async {
    if (fail) throw StateError('offline');
    return rows;
  }
  @override Future<void> save(PlaceCaptureResult place, String name, {String? id}) async {
    saves++;
    rows.add(SavedPlace(id: '$saves', name: name, place: place));
  }
  @override Future<void> remove(String id) async {}
}
void main() {
  setUpAll(() async {
    await loadHocalistTestFonts();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('automatic saves reuse normalized addresses and preserve apartment differences', () async {
    final repo = Places();
    await rememberRequestAddress(repo, place);
    await rememberRequestAddress(repo, place);
    await rememberRequestAddress(repo, const PlaceCaptureResult(label: 'same', address: 'same',
      postalAddress: PostalAddress(line1: ' 100 EXAMPLE   Street ', line2: 'suite 2',
        city: 'CHICAGO', state: 'il', postalCode: '60606', country: 'us'), source: PlaceCaptureSource.manual));
    expect(repo.saves, 1);
    await rememberRequestAddress(repo, const PlaceCaptureResult(label: 'other', address: 'other',
      postalAddress: PostalAddress(line1: '100 Example Street', line2: 'Suite 3',
        city: 'Chicago', state: 'IL', postalCode: '60606', country: 'US'), source: PlaceCaptureSource.manual));
    expect(repo.saves, 2);
  });
  for (final hasSaved in [false, true]) {
    testWidgets('request picker exists only with saved addresses: $hasSaved', (t) async {
      t.view.physicalSize = const Size(430, 1000); t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      final repo = Places();
      if (hasSaved) repo.rows.add(const SavedPlace(id: 'office', name: 'Office', place: place));
      await t.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Nunito'), home: Scaffold(body: SingleChildScrollView(child: ApprovedRequestFlowPage(
        accent: Colors.blue, requestTitle: 'Desk', budget: '', onTitleChanged: (_) {}, onBudgetChanged: (_) {},
        onBack: () {}, onNotifications: () {}, onSubmit: () {}, savedAddresses: repo,
      )))));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Continue')); await t.tap(find.text('Continue')); await t.pumpAndSettle();
      expect(find.text('Use my home address'), findsOneWidget);
      await t.ensureVisible(find.text('Enter a different address'));
      await t.tap(find.text('Enter a different address')); await t.pumpAndSettle();
      expect(find.text('Save this address for next time'), findsNothing);
      expect(find.text('Choose from saved places'), hasSaved ? findsOneWidget : findsNothing);
      if (hasSaved) {
        await t.ensureVisible(find.text('Choose from saved places'));
        await t.tap(find.text('Choose from saved places')); await t.pumpAndSettle();
        await t.tap(find.text('Office')); await t.pumpAndSettle();
        expect(find.text('100 Example Street'), findsWidgets);
        expect(find.text('Suite 2'), findsWidgets);
        expect(find.text('Chicago'), findsWidgets);
        expect(find.text('60606'), findsWidgets);
        expect(repo.saves, 0);
      } else {
        final street = find.byKey(const ValueKey('approved-request-address-street-address'));
        await t.ensureVisible(street); await t.enterText(street, '100 Example Street');
        FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle();
        expect(repo.saves, 0, reason: 'Do not save partial input');
        final city = find.byKey(const ValueKey('approved-request-address-city'));
        await t.ensureVisible(city); await t.enterText(city, 'Chicago');
        final state = find.byKey(const ValueKey('approved-request-address-state'));
        await t.ensureVisible(state); await t.tap(state); await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Illinois'), 150, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable))); await Scrollable.ensureVisible(t.element(find.text('Illinois')), alignment: 0.3); await t.pumpAndSettle(); await t.tap(find.text('Illinois')); await t.pumpAndSettle();
        final zip = find.byKey(const ValueKey('approved-request-address-zip-code'));
        await t.ensureVisible(zip); await t.enterText(zip, '60606');
        FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle();
        expect(repo.saves, 1);
        expect(find.text('Choose from saved places'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final width in [320.0, 430.0]) {
    testWidgets('saved address popup fits $width at enlarged text', (t) async {
      t.view.physicalSize = Size(width, 850); t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      PlaceCaptureResult? selected;
      await t.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Nunito'), builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
        home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () async {
          selected = await chooseRequestSavedAddress(c, [const SavedPlace(id: 'office', name: 'Office', place: place)]);
        }, child: const Text('Open'))))));
      await t.tap(find.text('Open')); await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_REQUEST_ADDRESSES')) {
        await t.runAsync(() async {
        final boundary = t.binding.renderView;
        final layer = boundary.debugLayer! as OffsetLayer;
        final image = await layer.toImage(Offset.zero & Size(width, 850));
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('output/saved-address-$width.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await t.tap(find.text('Office')); await t.pumpAndSettle();
      expect(selected, place);
    });
  }
}





