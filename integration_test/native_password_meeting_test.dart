// Explicit live-account proof. Credentials arrive once over an adb-reversed
// loopback channel and are never compiled into the application or printed.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hocalist/main.dart' as app;
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('controlled buyer password sign-in reaches the real dashboard',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hocalist.auth.selected_role', 'buyer');
    await app.main();
    await Supabase.instance.client.auth.signOut();
    Future<void> until(Finder finder, {int seconds = 60}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(finder, findsWidgets);
    }
    await until(find.byKey(const ValueKey('real-account-buyer')));
    final client = HttpClient();
    Map<String, dynamic> input;
    try {
      final request = await client.getUrl(Uri.parse(
          'http://127.0.0.1:43198/native-meeting-test'));
      final response = await request.close();
      expect(response.statusCode, 200);
      input = jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
    final loginRow = find.byKey(const ValueKey('approved-account-login-row'));
    await tester.ensureVisible(loginRow);
    await tester.tap(find.descendant(of: loginRow, matching: find.text('Log in')));
    await tester.pump(const Duration(milliseconds: 400));
    Finder field(String key) => find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(TextField));
    final email = field('approved-account-email-field');
    final password = field('approved-account-password-field');
    await tester.ensureVisible(email);
    await tester.enterText(email, input['buyerEmail'] as String);
    await tester.ensureVisible(password);
    await tester.enterText(password, input['password'] as String);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    final submit = find.byKey(const ValueKey('approved-account-primary-action'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await until(find.byType(ApprovedBuyerHomePage), seconds: 90);
    expect(Supabase.instance.client.auth.currentUser?.email, input['buyerEmail']);
    input.clear();
    expect(tester.takeException(), isNull);
    debugPrint('NATIVE_BUYER_PASSWORD_DASHBOARD_PASSED');
  }, skip: !const bool.fromEnvironment('NATIVE_LIVE_PASSWORD_TEST'));
}
