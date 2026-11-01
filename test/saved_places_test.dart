import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/saved_places_backend.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/features/approved/place_capture_sheet.dart';
import 'package:hocalist/features/approved/saved_places_sheet.dart';

const office = PlaceCaptureResult(
  label: 'Office',
  address: '100 Example St, Example City',
  postalAddress: PostalAddress(
    line1: '100 Example St',
    line2: 'Suite 2',
    city: 'Example City',
  ),
  latitude: 40,
  longitude: -74,
  timezoneId: 'America/New_York',
  source: PlaceCaptureSource.manual,
);
const pickup = PlaceCaptureResult(
  label: 'Pickup',
  address: '200 Example St, Example City',
  postalAddress: PostalAddress(line1: '200 Example St', city: 'Example City'),
  source: PlaceCaptureSource.manual,
);

class FakePlaces implements SavedPlacesRepository {
  List<SavedPlace> rows = [
    const SavedPlace(id: '1', name: 'Office', place: office),
    const SavedPlace(id: '2', name: 'Pickup', place: pickup),
  ];
  int saves = 0;
  bool failSave = false;
  bool fail = false;
  @override
  Future<List<SavedPlace>> load() async {
    if (fail) throw StateError('offline');
    return rows;
  }

  @override
  Future<void> save(PlaceCaptureResult p, String n, {String? id}) async {
    if (failSave) throw StateError('save unavailable');
    saves++;
    rows = [...rows.where((p) => p.id != id), SavedPlace(id: id ?? 'new-$saves', name: n, place: p)];
  }

  @override
  Future<void> remove(String id) async {
    rows = rows.where((p) => p.id != id).toList();
  }
}

void main() {
  testWidgets('saved-place capture uses saved-place wording', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: PlaceCaptureSheet(savingPlace: true))));
    await t.pumpAndSettle();
    expect(find.text('Add saved place'), findsOneWidget);
    expect(find.text('Save place'), findsOneWidget);
    expect(find.text('Choose the meeting place'), findsNothing);
    expect(find.text('Confirm meeting place'), findsNothing);
  });

  testWidgets('manager saves immediately and reads the place back without a second confirmation', (t) async {
    final repo = FakePlaces()..rows = [];
    Widget manager() => MaterialApp(home: Scaffold(body: SavedPlacesSheet(
      repository: repo, manage: true, capture: (_) async => pickup)));
    await t.pumpWidget(manager()); await t.pumpAndSettle();
    await t.tap(find.text('Add a place')); await t.pumpAndSettle();
    expect(repo.saves, 1); expect(find.text('Pickup'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(manager()); await t.pumpAndSettle();
    expect(find.text('Pickup'), findsOneWidget); expect(repo.saves, 1);
  });
  testWidgets('failed manager save shows an error and can be retried', (t) async {
    final repo = FakePlaces()..rows = []..failSave = true;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SavedPlacesSheet(
      repository: repo, manage: true, capture: (_) async => pickup))));
    await t.pumpAndSettle(); await t.tap(find.text('Add a place')); await t.pumpAndSettle();
    expect(find.textContaining('This place could not be saved.'), findsOneWidget);
    expect(repo.saves, 0);
    repo.failSave = false;
    await t.tap(find.text('Add a place')); await t.pumpAndSettle();
    expect(repo.saves, 1); expect(find.text('Pickup'), findsOneWidget);
  });

  for (final width in [320.0, 430.0]) {
    testWidgets('saved places fit width $width with enlarged text', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = Size(width, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SavedPlacesSheet(
              repository: FakePlaces(),
              capture: (_) async => null,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Use this place'), findsOneWidget);
    });
  }
  testWidgets('explicit save writes once after confirmation', (t) async {
    final repo = FakePlaces();
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => savePlaceForNextTime(c, repo, office),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(repo.saves, 0);
    await t.enterText(find.byType(TextField), 'Office');
    await t.tap(find.text('Save place').last);
    await t.pumpAndSettle();
    expect(repo.saves, 1);
  });
  test(
    'address snapshot round trip keeps apartment, coordinates and timezone',
    () {
      final decoded = SavedPlace.decode({
        'id': '1',
        'name': 'Office',
        'place': SavedPlace.encode(office),
      });
      expect(decoded.place.postalAddress!.line2, 'Suite 2');
      expect(decoded.place.latitude, 40);
      expect(decoded.place.longitude, -74);
      expect(decoded.place.timezoneId, 'America/New_York');
    },
  );
  testWidgets(
    'choosing another saved place replaces selection without a write',
    (t) async {
      final repo = FakePlaces();
      SavedPlaceChoice? chosen;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showSavedPlacesSheet(
                    context: c,
                    repository: repo,
                    capture: (_) async => null,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.tap(find.text('Office'));
      await t.pump();
      await t.tap(find.text('Pickup'));
      await t.pump();
      await t.tap(find.text('Use this place'));
      await t.pumpAndSettle();
      expect(chosen!.place.address, pickup.address);
      expect(repo.saves, 0);
    },
  );
  testWidgets('seller primary card is business, not home', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedPlacesSheet(
            repository: FakePlaces(),
            capture: (_) async => null,
            primary: office,
            primaryLabel: 'Business / service location',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Business / service location'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('new address defaults to use once; saving is explicit', (
    t,
  ) async {
    final repo = FakePlaces();
    SavedPlaceChoice? chosen;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await showSavedPlacesSheet(
                  context: c,
                  repository: repo,
                  capture: (_) async => pickup,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Use a different address'));
    await t.tap(find.text('Use a different address'));
    await t.pumpAndSettle();
    expect(
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    await t.tap(find.text('Use this address'));
    await t.pumpAndSettle();
    expect(repo.saves, 0);
    expect(chosen!.place.address, pickup.address);
  });
  testWidgets('save confirmation cancellation makes no write', (t) async {
    final repo = FakePlaces();
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => savePlaceForNextTime(c, repo, office),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(repo.saves, 0);
  });
  testWidgets('failed list stays recoverable and never claims it is empty', (
    t,
  ) async {
    final repo = FakePlaces()..fail = true;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedPlacesSheet(repository: repo, capture: (_) async => null),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text('Save a place to choose it quickly next time.'),
      findsNothing,
    );
    repo.fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Office'), findsOneWidget);
  });
  testWidgets('manager removes only after confirmation', (t) async {
    final repo = FakePlaces();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedPlacesSheet(
            repository: repo,
            capture: (_) async => null,
            manage: true,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove').first);
    await t.pumpAndSettle();
    expect(repo.rows.length, 2);
    await t.tap(find.text('Keep place'));
    await t.pumpAndSettle();
    expect(repo.rows.length, 2);
    await t.tap(find.byTooltip('Remove').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove place'));
    await t.pumpAndSettle();
    expect(repo.rows.length, 1);
    expect(repo.rows.single.id, '2');
  });
}

