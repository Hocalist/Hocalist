// Real-SDK account auth gateway tests over an injected HTTP transport.
//
// Proves the recovery latch across genuine GoTrue event sequences
// (passwordRecovery -> tokenRefreshed -> userUpdated) and that password
// confirmation cannot clobber or resurrect the signed-in session. No network
// or credential is used.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/providers/supabase_account_auth_gateway.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_http_backend.dart';

void main() {
  late SyntheticAccountBackend backend;
  late SupabaseClient client;
  late SupabaseAccountAuthGateway gateway;

  setUp(() {
    backend = SyntheticAccountBackend();
    client = buildSyntheticSupabaseClient(backend.client());
    gateway = SupabaseAccountAuthGateway(
      client,
      publishableKey: syntheticPublishableKey,
    );
  });

  tearDown(() async {
    await gateway.dispose();
  });

  Uri recoveryLink(String userId) {
    final session = backend.issueSession(userId);
    return Uri.parse(
      'com.hocalist.app://login-callback/'
      '#access_token=${session['access_token']}'
      '&expires_in=3600'
      '&refresh_token=${session['refresh_token']}'
      '&token_type=bearer'
      '&type=recovery',
    );
  }

  test(
    'an unconfirmed email session cannot enter through login or restoration',
    () async {
      backend.emailConfirmed = false;
      await client.auth.getSessionFromUrl(recoveryLink(syntheticUserA));
      await pumpEventQueue();
      expect(gateway.currentIdentity.isSignedIn, isFalse);
      await expectLater(
        gateway.logInWithEmail(
          email: '$syntheticUserA@example.com',
          password: 'test-password',
        ),
        throwsA(isA<AccountAuthException>()),
      );
      expect(gateway.currentIdentity.isSignedIn, isFalse);
      expect(client.auth.currentSession, isNull);
    },
  );

  test('a recovery session stays latched across a token refresh', () async {
    final snapshots = <AuthIdentitySnapshot>[];
    final subscription = gateway.identityChanges.listen(snapshots.add);

    await client.auth.getSessionFromUrl(recoveryLink(syntheticUserA));
    await pumpEventQueue();
    expect(gateway.currentIdentity.recovery, isTrue);
    expect(snapshots.last.recovery, isTrue);

    await client.auth.refreshSession();
    await pumpEventQueue();
    expect(gateway.currentIdentity.recovery, isTrue);
    expect(snapshots.last.recovery, isTrue);

    await gateway.updatePassword(password: 'new-password-1');
    await pumpEventQueue();
    expect(gateway.currentIdentity.recovery, isFalse);
    expect(snapshots.last.recovery, isFalse);

    await client.auth.refreshSession();
    await pumpEventQueue();
    expect(gateway.currentIdentity.recovery, isFalse);
    await subscription.cancel();
  });

  test('a late subscriber still receives the latched recovery state', () async {
    await client.auth.getSessionFromUrl(recoveryLink(syntheticUserA));
    await pumpEventQueue();

    final late = <AuthIdentitySnapshot>[];
    final subscription = gateway.identityChanges.listen(late.add);
    await pumpEventQueue();

    expect(late, isNotEmpty);
    expect(late.first.userId, syntheticUserA);
    expect(late.first.recovery, isTrue);
    await subscription.cancel();
  });

  test('an identity replacement clears the recovery latch', () async {
    await client.auth.getSessionFromUrl(recoveryLink(syntheticUserA));
    await pumpEventQueue();
    expect(gateway.currentIdentity.recovery, isTrue);

    await client.auth.signInWithPassword(
      email: 'user-b@example.com',
      password: 'synthetic-password',
    );
    await pumpEventQueue();

    expect(gateway.currentIdentity.userId, syntheticUserB);
    expect(gateway.currentIdentity.recovery, isFalse);
  });

  test('a sign-out clears the recovery latch', () async {
    await client.auth.getSessionFromUrl(recoveryLink(syntheticUserA));
    await pumpEventQueue();

    await client.auth.signOut();
    await pumpEventQueue();

    expect(gateway.currentIdentity.isSignedIn, isFalse);
    expect(gateway.currentIdentity.recovery, isFalse);
  });

  test('an email change stays pending on the identity snapshot', () async {
    await client.auth.signInWithPassword(
      email: 'user-a@example.com',
      password: 'synthetic-password',
    );
    await gateway.requestEmailChange(newEmail: 'new@example.com');
    await pumpEventQueue();

    expect(gateway.currentIdentity.pendingEmailChange, 'new@example.com');
    expect(gateway.currentIdentity.email, '$syntheticUserA@example.com');
  });

  test('requestPasswordReset sends the provider recovery email', () async {
    await gateway.requestPasswordReset(email: 'user-a@example.com');

    expect(
      backend.requests.any((request) => request.url.path == '/auth/v1/recover'),
      isTrue,
    );
  });

  test('password confirmation never replaces the signed-in session', () async {
    await client.auth.signInWithPassword(
      email: 'user-a@example.com',
      password: 'synthetic-password',
    );
    final before = client.auth.currentSession!;

    await gateway.confirmPassword(password: 'synthetic-password');

    final after = client.auth.currentSession!;
    expect(after.user.id, syntheticUserA);
    expect(after.accessToken, before.accessToken);
    expect(after.refreshToken, before.refreshToken);
    final passwordGrants = backend.requests
        .where(
          (request) =>
              request.url.path == '/auth/v1/token' &&
              request.url.queryParameters['grant_type'] == 'password',
        )
        .length;
    expect(passwordGrants, 2);
  });

  test(
    'a wrong password maps safely and leaves the session in place',
    () async {
      await client.auth.signInWithPassword(
        email: 'user-a@example.com',
        password: 'synthetic-password',
      );
      final before = client.auth.currentSession!;

      await expectLater(
        gateway.confirmPassword(password: 'wrong-password'),
        throwsA(
          isA<AccountAuthException>().having(
            (error) => error.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      expect(client.auth.currentSession!.accessToken, before.accessToken);
    },
  );
}
