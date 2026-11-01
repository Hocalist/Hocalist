import 'package:hocalist/data/phase2/maps/places_contract.dart';
// Seller discovery-origin manual fallback: reachable from the approved Leads
// screen, one operation key per intent, safe ambiguous retry.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/discovery/discovery_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_leads_backend.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';

class FakePagedLeads implements MarketplacePagedLeadsBackend {
  @override
  Future<DiscoveryLeadPage> loadLeadPage({
    required DiscoveryLeadFilter filter,
    String? cursor,
    int limit = 20,
  }) async => DiscoveryLeadPage(items: const [], sort: filter.sort);
}

class Harness extends StatefulWidget {
  const Harness({required this.onSave, this.initial, this.onLocationSettings, this.loadLocation, super.key});

  final Future<SellerDiscoveryOrigin> Function(
    SellerDiscoveryOriginInput input,
    String operationKey,
  )
  onSave;
  final SellerDiscoveryOrigin? initial;
  final VoidCallback? onLocationSettings;
  final Future<SellerDiscoveryOrigin> Function()? loadLocation;

  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  SellerDiscoveryOrigin? _origin;

  @override
  void initState() {
    super.initState();
    _origin = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ApprovedSellerLeadsPage(
          sellerName: 'Northside Tech',
          leads: const [],
          leadPaging: FakePagedLeads(),
          discoveryOrigin: _origin,
          onOpenLocationSettings: widget.onLocationSettings,
          onLoadSearchLocation: widget.loadLocation,
          onSearchLocations: (area) async => [PlaceSuggestion(placeId: area, label: area)],
          onSelectSearchLocation: (place) async => SellerDiscoveryOriginInput(areaLabel: place.label, latitude: 40, longitude: -73),
          onSaveDiscoveryOrigin: widget.onSave,
          onDiscoveryOriginSaved: (saved) => setState(() => _origin = saved),
        ),
      ),
    );
  }
}

SellerDiscoveryOrigin savedOrigin({
  String? area = 'Yonkers, NY',
  int radius = 25,
  bool coordinates = false,
}) => SellerDiscoveryOrigin(
  configured: true,
  areaLabel: area,
  radiusMiles: radius,
  coordinatesPresent: coordinates,
  revision: 1,
);

void main() {
 testWidgets('popup loads current saved location instead of stale missing state',(tester)async{
  await tester.pumpWidget(Harness(loadLocation:()async=>savedOrigin(coordinates:true,radius:17),onSave:(i,k)async=>savedOrigin()));
  await tester.pumpAndSettle();await tester.tap(find.text('Location').first);await tester.pumpAndSettle();
  await tester.tap(find.text('Choose location…').last);await tester.pumpAndSettle();
  expect(find.text('Within 17 miles'),findsOneWidget);expect(find.text('Set location first'),findsNothing);
  expect(find.byKey(const Key('sellerDiscoveryAddLocation')),findsNothing);
 });
 testWidgets('a typed search place enables radius without a business location', (tester) async {
  SellerDiscoveryOriginInput? submitted;
  await tester.pumpWidget(Harness(onSave:(input,key)async{submitted=input;return savedOrigin(coordinates:true);}));
  await tester.pumpAndSettle();await tester.tap(find.text('Location').first);await tester.pumpAndSettle();
  await tester.tap(find.text('Choose location…').last);await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('sellerDiscoveryOriginArea')),'Albany, NY');
  await tester.pump(const Duration(milliseconds:350));await tester.pumpAndSettle();
  expect(find.text('Use this location'),findsNothing);
  await tester.tap(find.byKey(const ValueKey('sellerSearchPlace-Albany, NY')));await tester.pumpAndSettle();
  expect(find.text('Set location first'),findsNothing);
  await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
  await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));await tester.pumpAndSettle();
  expect(submitted?.areaLabel,'Albany, NY');expect(submitted?.latitude,40);
 });
 testWidgets('missing location blocks radius and links to profile settings', (tester) async {
  var opened=false; var saves=0;
  await tester.pumpWidget(Harness(onLocationSettings:()=>opened=true,onSave:(input,key)async{ saves++; return savedOrigin(); }));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('sellerClosestOriginNotice')),findsNothing);
  await tester.tap(find.text('Location').first); await tester.pumpAndSettle();
  await tester.tap(find.text('Choose location…').last); await tester.pumpAndSettle();
  final radius=find.byKey(const Key('sellerDiscoveryOriginRadius'));
  expect(tester.widget<AbsorbPointer>(find.ancestor(of:radius,matching:find.byType(AbsorbPointer)).first).absorbing,isTrue);
  await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));await tester.pumpAndSettle();
  expect(saves,0);
  expect(find.text('Set location first'),findsOneWidget);
  expect(find.byKey(const Key('sellerDiscoveryOriginSelected')),findsNothing);
  expect(tester.widget<TextField>(find.byKey(const Key('sellerDiscoveryOriginArea'))).enabled,isTrue);
  await tester.tap(find.byKey(const Key('sellerDiscoveryAddLocation')));await tester.pumpAndSettle();
  expect(opened,isTrue);expect(find.byKey(const Key('sellerDiscoveryOriginSheet')),findsNothing);
 });
 testWidgets('removing search area retains chip on failure and retries the same clear intent', (tester) async {
  final keys=<String>[];
  await tester.pumpWidget(Harness(initial:savedOrigin(),onSave:(input,key)async{
   keys.add(key);expect(input.areaLabel,isNull);expect(input.latitude,isNull);
   if(keys.length==1) throw StateError('network');
   return savedOrigin(area:null);
  }));await tester.pumpAndSettle();
  final chip=find.byKey(const Key('sellerActiveFilter-area'));
  expect(chip,findsOneWidget);
  tester.widget<InputChip>(chip).onDeleted!();await tester.pumpAndSettle();
  expect(chip,findsOneWidget);
  tester.widget<InputChip>(chip).onDeleted!();await tester.pumpAndSettle();
  expect(chip,findsNothing);expect(keys[0],keys[1]);
 });

  testWidgets('the Leads screen opens the manual area editor and saves', (
    tester,
  ) async {
    final calls = <(SellerDiscoveryOriginInput, String)>[];
    await tester.pumpWidget(
      Harness(
        initial: savedOrigin(coordinates: true),
        onSave: (input, key) async {
          calls.add((input, key));
          return savedOrigin(
            area: input.areaLabel,
            radius: input.radiusMiles,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set your search area'), findsNothing);

    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose location…').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerDiscoveryOriginSheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('sellerDiscoveryOriginArea')),
      'Yonkers, NY',
    );
    await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.$1.areaLabel, 'Yonkers, NY');
    expect(calls.single.$1.radiusMiles, 25);
    expect(calls.single.$2, startsWith('discovery-origin-'));
    expect(
      find.byKey(const Key('sellerDiscoveryOriginSavedNotice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sellerDiscoveryOriginSavedNotice')),
      findsOneWidget,
    );
  });

  testWidgets('an uncertain save retries with the same operation key', (
    tester,
  ) async {
    final keys = <String>[];
    var attempts = 0;
    await tester.pumpWidget(
      Harness(
        initial: savedOrigin(coordinates: true),
        onSave: (input, key) async {
          keys.add(key);
          attempts += 1;
          if (attempts == 1) {
            throw const StoreBackendException('The area change could not be confirmed.', ambiguous: true);
          }
          return savedOrigin(area: input.areaLabel, radius: input.radiusMiles);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose location…').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerDiscoveryOriginError')),
      findsOneWidget,
    );
    expect(find.textContaining('Retry to check safely'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(keys[0], keys[1], reason: 'the retry keeps the intent key');
  });

  testWidgets('a changed area after a definitive failure uses a new key', (
    tester,
  ) async {
    final keys = <String>[];
    await tester.pumpWidget(
      Harness(
        initial: savedOrigin(coordinates: true),
        onSave: (input, key) async {
          keys.add(key);
          if (keys.length == 1) {
            throw const StoreBackendException('The area change was rejected.');
          }
          return savedOrigin(area: input.areaLabel, radius: input.radiusMiles);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose location…').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sellerDiscoveryOriginArea')),
      'Mount Vernon, NY',
    );
    await tester.pump(const Duration(milliseconds:350));await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sellerSearchPlace-Mount Vernon, NY')));
    await tester.tap(find.byKey(const ValueKey('sellerSearchPlace-Mount Vernon, NY')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(keys[0], isNot(keys[1]));
    expect(
      find.byKey(const Key('sellerDiscoveryOriginSavedNotice')),
      findsOneWidget,
    );
  });

  testWidgets('an existing location retains the sellers exact saved radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness(
        initial: savedOrigin(coordinates: true, radius: 17),
        onSave: (input, key) async =>
            savedOrigin(area: input.areaLabel, radius: input.radiusMiles),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose location…').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Within 17 miles'),
      findsOneWidget,
    );
  });
}

