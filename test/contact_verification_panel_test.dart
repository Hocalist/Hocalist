import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hocalist/features/account/contact_verification_panel.dart';
import 'package:hocalist/data/phase2/providers/contact_verification_service.dart';
import 'test_fonts.dart';

class FakeContacts implements ContactVerificationGateway {
  @override Future<void> resendEmail() async {}
  bool verified = false;
  int sends = 0, confirms = 0;
  @override
  Future<User> load() async => User(
    id: 'controlled',
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    appMetadata: const <String, dynamic>{},
    userMetadata: const <String, dynamic>{},
    email: 'test@example.com',
    emailConfirmedAt: '2026-01-01T00:00:00Z',
    phoneConfirmedAt: verified ? '2026-01-01T00:00:00Z' : null,
    phone: verified ? '12025550123' : null,
  );
  @override
  Future<bool> sendPhone(String phone) async {
    sends++;
    return verified;
  }

  @override
  Future<bool> confirmPhone(String phone, String code) async {
    confirms++;
    verified = true;
    return true;
  }
}

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('existing seller phone verification fits $width at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeContacts();

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1600),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ContactVerificationPanel(
                      service: service,
                      onChanged: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Send confirmation email'), findsNothing);
        await tester.enterText(
          find.byKey(const Key('verification-phone')),
          '+12025550123',
        );
        await tester.ensureVisible(find.text('Send code'));
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
        expect(service.sends, 1);
        await tester.enterText(
          find.byKey(const Key('verification-phone-code')),
          '123456',
        );
        await tester.ensureVisible(find.text('Verify phone'));
        await tester.tap(find.text('Verify phone'));
        await tester.pumpAndSettle();
        expect(service.confirms, 1);
        expect(find.text('Phone verified.'), findsOneWidget);
        expect(find.byKey(const Key('verification-phone-code')), findsNothing);
        expect(find.text('Send code'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
