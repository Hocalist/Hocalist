import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/components/hocalist_section_tabs.dart';
import 'package:hocalist/features/discovery/buyer_profile_visibility_editor.dart';
import 'package:hocalist/data/phase2/discovery/discovery_backends.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';
import 'package:hocalist/features/seller/seller_schedule_controls.dart';
import 'test_fonts.dart';

class _Consent implements BuyerConsentBackend {
  final keys = <String>[];
  final intents = <BuyerPublicProfileConsent>[];
  BuyerPublicProfileConsent current = const BuyerPublicProfileConsent(
    isPublic: false,
    showDisplayName: false,
    showArea: false,
    showCategories: false,
    revision: 1,
  );
  @override
  Future<BuyerPublicProfileConsent> loadConsent() async => current;
  @override
  Future<BuyerPublicProfileConsent> setConsent({
    required BuyerPublicProfileConsent consent,
    required String operationKey,
  }) async {
    keys.add(operationKey);
    intents.add(consent);
    if (keys.length == 1) throw Exception('response lost');
    return current = consent;
  }

  @override
  Future<PublicBuyerProfile> loadPublicProfile(String profileId) =>
      throw UnimplementedError();
}

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets('real schedule disables past dates but permits the minimum day', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedReplicaScope(
            metrics: ApprovedReplicaMetrics.resolve(
              availableWidth: 390,
              textScaler: TextScaler.noScaling,
            ),
            child: SellerScheduleCalendar(
              keyPrefix: 'auditCalendar',
              selectedDate: DateTime(2026, 10, 16),
              displayedMonth: DateTime(2026, 10),
              earliestDate: DateTime(2026, 10, 16),
              onSelected: (date) => selected = date,
              onDisplayedMonthChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('auditCalendarDay15')));
    expect(selected, isNull);
    await tester.tap(find.byKey(const Key('auditCalendarDay16')));
    expect(selected, DateTime(2026, 10, 16));
  });
  testWidgets('custom role buttons expose their named button semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BuyerPrimaryButton(label: 'Confirm meeting', onPressed: () {}),
              SellerPrimaryButton(label: 'Edit profile', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    for (final label in ['Confirm meeting', 'Edit profile']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
    }
    handle.dispose();
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('visibility fits $width at $scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const capture = Key('visibility-capture');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Nunito'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: capture,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: BuyerProfileVisibilityEditor(backend: _Consent()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('HOCALIST_AUDIT_CAPTURE')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '.codex-local/audit-fixes/visibility-$width-$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
  testWidgets('settings selection survives remount and stays identity scoped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    Widget page(String identity) => MaterialApp(
      home: Scaffold(
        body: HocalistTabPersistenceScope(
          namespace: identity,
          child: HocalistSectionTabs(
            persistenceId: 'settings',
            accent: Colors.blue,
            sections: const {
              'Security': [Text('Security body')],
              'Notifications': [Text('Notification body')],
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(page('buyer-A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-tab-Notifications')));
    await tester.pumpAndSettle();
    expect(find.text('Notification body').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('buyer-A'));
    await tester.pumpAndSettle();
    expect(find.text('Notification body').hitTestable(), findsOneWidget);
    await tester.pumpWidget(page('seller-B'));
    await tester.pumpAndSettle();
    expect(find.text('Security body').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'visibility defaults private and ambiguous retry freezes key and choices',
    (tester) async {
      final backend = _Consent();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuyerProfileVisibilityEditor(backend: backend),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save visibility'));
      await tester.tap(find.text('Save visibility'));
      await tester.pumpAndSettle();
      expect(backend.keys, hasLength(1));
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.ensureVisible(find.text('Retry visibility save'));
      await tester.tap(find.text('Retry visibility save'));
      await tester.pumpAndSettle();
      expect(backend.keys, hasLength(2));
      expect(backend.keys[0], backend.keys[1]);
      expect(identical(backend.intents[0], backend.intents[1]), isTrue);
      expect(backend.current.isPublic, isTrue);
      expect(backend.current.showArea, isFalse);
    },
  );
}
