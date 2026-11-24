import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/marketplace_analytics.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/analytics_consent_setting.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';

import 'phase2/account/account_test_fakes.dart';
import 'phase2/marketplace/requests_backend_test.dart' as requests;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hocalist/marketplace_analytics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late bool consent;
  late List<MethodCall> events;
  late bool failChannel;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    consent = false;
    failChannel = false;
    events = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (failChannel) throw PlatformException(code: 'unavailable');
      if (call.method == 'getConsent') return consent;
      if (call.method == 'setConsent') {
        consent = call.arguments as bool;
        return true;
      }
      events.add(call);
      return consent;
    });
  });
  tearDown(() async {
    await pumpEventQueue();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'off by default; opting in and revoking governs both event types',
    () async {
      final analytics = MarketplaceAnalytics();
      await analytics.buyerRequestSubmitted('request-1');
      await analytics.sellerProfileCreated('seller-1');
      expect(events, isEmpty);
      await analytics.setConsent(true);
      await analytics.buyerRequestSubmitted('request-2');
      await analytics.sellerProfileCreated('seller-2');
      expect(events.map((e) => e.method), [
        'buyer_request_submitted',
        'seller_signup_completed',
      ]);
      expect(events.every((e) => e.arguments == null), isTrue);
      await analytics.setConsent(false);
      await analytics.buyerRequestSubmitted('request-3');
      expect(events, hasLength(2));
    },
  );

  test(
    'concurrent retries and tracker recreation never count a record twice',
    () async {
      consent = true;
      final analytics = MarketplaceAnalytics();
      await Future.wait(
        List.generate(
          5,
          (_) => analytics.buyerRequestSubmitted('same-request'),
        ),
      );
      await MarketplaceAnalytics().buyerRequestSubmitted('same-request');
      await analytics.sellerProfileCreated('same-seller');
      await MarketplaceAnalytics().sellerProfileCreated('same-seller');
      expect(events, hasLength(2));
    },
  );

  test('unsupported platforms and tracking failures are harmless', () async {
    consent = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await MarketplaceAnalytics().buyerRequestSubmitted('ios');
    expect(events, isEmpty);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    failChannel = true;
    await MarketplaceAnalytics().sellerProfileCreated('failure');
    expect(events, isEmpty);
  });

  test(
    'buyer event follows committed creation, not a failure, edit or reload',
    () async {
      consent = true;
      final pending = Completer<MarketplaceRequest>();
      final backend = requests.FakeRequestsBackend()
        ..onCreate = (_, _) => pending.future;
      final repository = LocalMarketplaceRepository(requestsBackend: backend);
      addTearDown(repository.dispose);
      final posting = repository.createBuyerRequest(
        draft: requests.draft(),
        operationKey: 'create',
      );
      await pumpEventQueue();
      expect(events, isEmpty);
      pending.complete(requests.request());
      expect((await posting).request, isNotNull);
      await pumpEventQueue();
      expect(events.single.method, 'buyer_request_submitted');
      backend.onCreate = (_, _) async =>
          throw const StoreBackendException('Not saved');
      await repository.createBuyerRequest(
        draft: requests.draft(),
        operationKey: 'fail',
      );
      await repository.updateBuyerRequest(
        requestId: requests.request().id,
        expectedRevision: 1,
        draft: requests.draft(),
        operationKey: 'edit',
      );
      await repository.refreshBuyerRequests();
      await pumpEventQueue();
      expect(events, hasLength(1));
      failChannel = true;
      backend.onCreate = (_, _) async => requests.request();
      expect(
        (await repository.createBuyerRequest(
          draft: requests.draft(),
          operationKey: 'retry',
        )).request,
        isNotNull,
      );
    },
  );

  test(
    'seller signup is logged once; existing-role switch and edits are not signup',
    () async {
      consent = true;
      final auth = FakeAuthGateway()
        ..signIn(
          const AuthIdentitySnapshot(
            userId: 'user-a',
            email: 'test@example.invalid',
          ),
        );
      final accounts = FakeAccountRepository();
      final controller = HocalistAccountController(
        auth: auth,
        accounts: accounts,
        initialRole: HocalistRole.seller,
      );
      addTearDown(() async {
        controller.dispose();
        await auth.dispose();
      });
      await controller.start();
      expect(controller.phase, AccountAccessPhase.onboarding);
      var created = false;
      accounts.onboardHandler = (command) {
        created = true;
        return RepositorySuccess(
          OnboardResult(
            membershipId: 'seller-1',
            role: command.role,
            revision: 1,
          ),
        );
      };
      accounts.membershipHandler = (role) => created
          ? RepositorySuccess(membership(id: 'seller-1', role: role))
          : const RepositoryFailureResult(
              NotFoundError(entityType: 'membership', entityId: 'seller'),
            );
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      await controller.onboardSelectedRole(displayName: 'Test seller');
      await pumpEventQueue();
      expect(events.single.method, 'seller_signup_completed');
      await controller.updateDisplayName('Edited seller');
      controller.selectRole(HocalistRole.buyer);
      await pumpEventQueue();
      controller.selectRole(HocalistRole.seller);
      await pumpEventQueue();
      await controller.refresh();
      expect(events, hasLength(1));
    },
  );

  test(
    'failed signup and an existing-membership conflict do not log signup',
    () async {
      consent = true;
      final auth = FakeAuthGateway()
        ..signIn(const AuthIdentitySnapshot(userId: 'user-a'));
      final accounts = FakeAccountRepository();
      final controller = HocalistAccountController(
        auth: auth,
        accounts: accounts,
        initialRole: HocalistRole.seller,
      );
      addTearDown(() async {
        controller.dispose();
        await auth.dispose();
      });
      await controller.start();
      accounts.onboardHandler = (_) =>
          const RepositoryFailureResult(NetworkError());
      await expectLater(
        controller.onboardSelectedRole(displayName: 'Test'),
        throwsA(isA<AccountActionException>()),
      );
      accounts.onboardHandler = (_) => const RepositoryFailureResult(
        ConflictError(conflictCode: 'membership_exists'),
      );
      await controller.onboardSelectedRole(displayName: 'Test');
      await pumpEventQueue();
      expect(events, isEmpty);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('consent fits $width at scale $scale and can be revoked', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: AnalyticsConsentSetting(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('analytics-consent-switch'));
        expect(tester.widget<Switch>(toggle).value, isFalse);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(consent, isTrue);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(consent, isFalse);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
