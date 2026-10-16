// Runs the actual configured app on a device. No credentials or provider
// mutations: this proves native initialization and keyboard input/dismissal.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hocalist/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native signed-out entry and keyboard remain operable', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('hocalist.auth.selected_role', 'buyer');
    app.main();
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    final buyer = find.byKey(const ValueKey('real-account-buyer'));
    while (buyer.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      buyer,
      findsOneWidget,
      reason: 'Configured native bootstrap must reach real authentication.',
    );
    expect(tester.takeException(), isNull);
    final email = find.descendant(
      of: find.byKey(const ValueKey('approved-account-email-field')),
      matching: find.byType(TextField),
    );
    expect(email, findsOneWidget);
    await tester.ensureVisible(email);
    await tester.tap(email);
    await tester.enterText(email, 'native-layout@example.invalid');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('native-layout@example.invalid'), findsOneWidget);
    expect(tester.takeException(), isNull);
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    final seller = find.byKey(
      const ValueKey('approved-account-role-I am selling'),
    );
    await tester.ensureVisible(seller);
    await tester.tap(seller);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('real-account-seller')), findsOneWidget);
    final recovery = find.byKey(const ValueKey('real-account-forgot-password'));
    await tester.ensureVisible(recovery);
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);
    await tester.tap(find.text('Back to log in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('real-account-seller')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native push, location and encrypted storage plugins initialize',
    (tester) async {
      await Firebase.initializeApp();
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      expect(settings.authorizationStatus, isA<AuthorizationStatus>());
      // Inspect only: no permission prompt, token registration or push is sent.
      expect(await Geolocator.checkPermission(), isA<LocationPermission>());
      const storage = FlutterSecureStorage();
      const key = 'hocalist.integration.synthetic-storage';
      try {
        await storage.write(key: key, value: 'synthetic-roundtrip');
        expect(await storage.read(key: key), 'synthetic-roundtrip');
      } finally {
        await storage.delete(key: key);
      }
      expect(await storage.read(key: key), isNull);
    },
  );
}
