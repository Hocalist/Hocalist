import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Widget tests have no Android host. Default to consent off, just as a
    // fresh installation does. Analytics contract tests install their own
    // channel handler to exercise opt-in, failures, and event delivery.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('hocalist/marketplace_analytics'),
      (call) async => call.method == 'setConsent',
    );
  });
  await testMain();
}
