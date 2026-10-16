import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hocalist/data/phase2/providers/hocalist_push_service.dart';
import 'package:hocalist/features/account/device_push_settings.dart';

class FakePush extends HocalistPushService {
  FakePush()
    : super(
        SupabaseClient(
          'https://example.test',
          'public-test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  bool enabled = false;
  int enables = 0;
  Completer<void>? pending;
  @override
  bool get supported => true;
  @override
  Future<void> start() async {}
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> enable() async {
    enables++;
    await pending?.future;
    enabled = true;
  }

  @override
  Future<void> disableConsent() async {
    enabled = false;
  }
}

void main() {
  testWidgets('only explicit click enables, waits for ack, then disables', (
    tester,
  ) async {
    final service = FakePush();
    service.pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicePushSettings(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.enables, 0);
    await tester.tap(find.text('Enable on this phone'));
    await tester.pump();
    expect(find.text('Updating…'), findsOneWidget);
    expect(find.text('Permission enabled on this phone.'), findsNothing);
    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(service.enables, 1);
    expect(find.text('Permission enabled on this phone.'), findsOneWidget);
    await tester.tap(find.text('Turn off on this phone'));
    await tester.pumpAndSettle();
    expect(service.enabled, isFalse);
  });
  testWidgets('failure is visible and no false success', (tester) async {
    final service = FakePush()..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicePushSettings(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable on this phone'));
    await tester.pump();
    service.pending!.completeError(StateError('private failure'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not update device notifications'),
      findsOneWidget,
    );
    expect(find.textContaining('private failure'), findsNothing);
    expect(service.enabled, isFalse);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('device control fits $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: DevicePushSettings(service: FakePush()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Enable on this phone'), findsOneWidget);
      });
    }
  }
}
