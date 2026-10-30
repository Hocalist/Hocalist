import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/us_states.dart';
import 'package:hocalist/features/account/private_contact_editor.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'test_fonts.dart';
import 'package:hocalist/data/phase2/maps/places_repository.dart';
import 'package:hocalist/data/phase2/maps/places_transport.dart';

class _ContactPlaces implements PlacesTransport {
  @override
  Future<PlacesTransportResult> autocomplete({required String input,required String sessionToken}) async =>
    const PlacesTransportResult({'suggestions':[{'placeId':'library','label':'TEST Library, Chicago'}]});
  @override
  Future<PlacesTransportResult> details({required String placeId,required String sessionToken}) async =>
    const PlacesTransportResult({'placeId':'library','address':'TEST Library','latitude':41.8,'longitude':-87.6,
      'timezoneId':'America/Chicago','postalAddress':{'line1':'TEST Library','city':'Chicago','state':'IL','postalCode':'60605','country':'US'},'attributions':<Object?>[]});
}

void main() {
  setUpAll(loadHocalistTestFonts);
  test('US reference includes all 50 states and DC', () {
    expect(usStates.length, 51);
    expect(usStates['CA'], 'California');
    expect(usStates['NY'], 'New York');
  });
  testWidgets('US state chooser shows states and returns a code', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedLocationRequestStep(
              useHomeAddress: false,
              onUseHomeAddressChanged: (_) {},
              onBack: () {},
              onSubmit: () {},
              customAddress: PostalAddress(country: 'US'),
              onStateChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Select state'));
    await tester.tap(find.text('Select state'));
    await tester.pumpAndSettle();
    expect(find.text('California'), findsOneWidget);
    await tester.tap(find.text('California'));
    await tester.pumpAndSettle();
    expect(selected, 'CA');
    expect(tester.takeException(), isNull);
  });
  for (final size in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      for (final seller in [false, true]) {
        testWidgets(
          'searched address saves and survives reopening for seller=$seller $size/$scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(size, 900);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            var record = PrivateContactRecord(
              userId: 'test',
              contact: AccountContact(phone: 'unchanged', countryCode: 'US'),
              stamp: RecordStamp(
                revision: 1,
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              ),
            );
            var saves = 0;
            Widget editor() => MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PrivateContactEditor(
                    seller: seller,
                    readCurrent: () => record,
                    places:PlacesRepository(transport:_ContactPlaces()),
                    onSave: (command) async {
                      saves++;
                      record = PrivateContactRecord(
                        userId: 'test',
                        contact: AccountContact(
                          phone: command.phone.valueOrNull,
                          addressLine1: command.addressLine1.valueOrNull,
                          city: command.city.valueOrNull,
                          region: command.region.valueOrNull,
                          postalCode: command.postalCode.valueOrNull,
                          countryCode: command.countryCode.valueOrNull,
                        ),
                        stamp: RecordStamp(
                          revision: 2,
                          createdAt: DateTime.utc(2026),
                          updatedAt: DateTime.utc(2026),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
            await tester.pumpWidget(editor());
            expect(find.text('Choose and save address on map'),findsNothing);
            await tester.ensureVisible(find.byKey(const Key('privateContact1')));
            await tester.enterText(find.byKey(const Key('privateContact1')),'TEST Library');
            await tester.pump(const Duration(milliseconds:400));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(const ValueKey('contactAddress-library')));
            await tester.tap(find.byKey(const ValueKey('contactAddress-library')));
            await tester.pumpAndSettle();
            expect(saves,0);
            await tester.ensureVisible(find.text('Save contact details'));
            await tester.tap(find.text('Save contact details'));
            await tester.pumpAndSettle();
            expect(saves, 1);
            expect(record.contact.addressLine1, 'TEST Library');
            expect(record.contact.region, 'IL');
            expect(record.contact.phone, 'unchanged');
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(editor());
            await tester.pumpAndSettle();
            expect(find.text('TEST Library'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
