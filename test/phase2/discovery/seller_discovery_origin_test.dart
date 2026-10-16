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
  const Harness({required this.onSave, this.initial, super.key});

  final Future<SellerDiscoveryOrigin> Function(
    SellerDiscoveryOriginInput input,
    String operationKey,
  )
  onSave;
  final SellerDiscoveryOrigin? initial;

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
  testWidgets('the Leads screen opens the manual area editor and saves', (
    tester,
  ) async {
    final calls = <(SellerDiscoveryOriginInput, String)>[];
    await tester.pumpWidget(
      Harness(
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
    expect(find.text('Set your discovery area'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sellerDiscoveryAreaBar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerDiscoveryOriginSheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('sellerDiscoveryOriginArea')),
      'Yonkers, NY',
    );
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.$1.areaLabel, 'Yonkers, NY');
    expect(calls.single.$1.radiusMiles, 25);
    expect(calls.single.$2, startsWith('discovery-origin-'));
    expect(
      find.text('Discovery area: Yonkers, NY · within 25 mi'),
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
        initial: savedOrigin(),
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
    await tester.tap(find.byKey(const Key('sellerDiscoveryAreaBar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerDiscoveryOriginError')),
      findsOneWidget,
    );
    expect(find.textContaining('Retry to check safely'), findsOneWidget);

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
        initial: savedOrigin(),
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
    await tester.tap(find.byKey(const Key('sellerDiscoveryAreaBar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sellerDiscoveryOriginArea')),
      'Mount Vernon, NY',
    );
    await tester.tap(find.byKey(const Key('sellerDiscoveryOriginSave')));
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(keys[0], isNot(keys[1]));
    expect(
      find.text('Discovery area: Mount Vernon, NY · within 25 mi'),
      findsOneWidget,
    );
  });

  testWidgets('an existing picked location is disclosed before replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness(
        initial: savedOrigin(coordinates: true),
        onSave: (input, key) async =>
            savedOrigin(area: input.areaLabel, radius: input.radiusMiles),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerDiscoveryAreaBar')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerDiscoveryOriginCoordinateNotice')),
      findsOneWidget,
    );
  });
}

