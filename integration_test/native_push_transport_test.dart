import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Explicit device-only transport probe. Never logs/persists the token, registers
// it with Hocalist, requests OS permission, or sends a notification.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Firebase can obtain and revoke a transport token', (
    tester,
  ) async {
    await Firebase.initializeApp();
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 60),
      );
      expect(token, isNotNull);
      expect(token!.isNotEmpty, isTrue);
    } finally {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 30),
      );
    }
    expect(tester.takeException(), isNull);
  });
}
