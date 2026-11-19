import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hocalist/data/phase2/providers/contact_verification_service.dart';
import 'support/supabase_http_backend.dart';

void main() {
  late SyntheticAccountBackend backend;
  late SupabaseClient client;
  late ContactVerificationService service;
  late List<http.Request> calls;
  String? confirmedPhone;
  bool failCode = false;
  Completer<void>? hold;
  setUp(() async {
    backend = SyntheticAccountBackend();
    calls = [];
    confirmedPhone = null;
    failCode = false;
    hold = null;
    final base = backend.client();
    client = buildSyntheticSupabaseClient(
      MockClient((r) async {
        calls.add(r);
        if (r.url.path.endsWith('/verify')) {
          if (failCode) {
            return http.Response(jsonEncode({'code': 'otp_expired'}), 403);
          }
          final body = jsonDecode(r.body) as Map;
          expect(body['type'], 'phone_change');
          confirmedPhone = body['phone'] as String;
          return http.Response(
            jsonEncode(backend.issueSession(syntheticUserA)),
            200,
          );
        }
        if (r.url.path.endsWith('/resend')) return http.Response('{}', 200);
        if (r.url.path.endsWith('/user') && r.method == 'PUT' && hold != null) {
          await hold!.future;
        }
        final copy = http.Request(r.method, r.url)
          ..headers.addAll(r.headers)
          ..bodyBytes = r.bodyBytes;
        final streamed = await base.send(copy);
        final response = await http.Response.fromStream(streamed);
        if (r.url.path.endsWith('/user') &&
            r.method == 'GET' &&
            response.statusCode == 200 &&
            confirmedPhone != null) {
          final user = jsonDecode(response.body) as Map;
          user['phone'] = confirmedPhone!.replaceAll('+', '');
          user['phone_confirmed_at'] = '2026-10-31T00:00:00Z';
          return http.Response(jsonEncode(user), 200);
        }
        return response;
      }),
    );
    await client.auth.signInWithPassword(
      email: 'user-a@example.com',
      password: 'synthetic',
    );
    service = ContactVerificationService(client);
    calls.clear();
  });
  tearDown(() async {
    await client.dispose();
  });
  test('existing confirmed contacts require no duplicate code', () async {
    confirmedPhone = '+12025550123';
    expect(await service.sendPhone(confirmedPhone!), true);
    await service.resendEmail();
    expect(calls.every((r) => r.method == 'GET'), true);
  });
  test(
    'phone uses signed-in account update then phone_change, never signup',
    () async {
      final token = client.auth.currentSession!.accessToken;
      expect(await service.sendPhone('+12025550123'), false);
      final update = calls.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(update.body)['phone'], '+12025550123');
      expect(
        update.headers['Authorization'] ?? update.headers['authorization'],
        'Bearer $token',
      );
      expect(await service.confirmPhone('+12025550123', '123456'), true);
      expect(client.auth.currentSession!.accessToken, token);
      expect(client.auth.currentUser!.id, syntheticUserA);
      expect(calls.any((r) => r.url.path.endsWith('/otp')), false);
    },
  );
  test('wrong or expired code stays unverified', () async {
    await service.sendPhone('+12025550123');
    failCode = true;
    await expectLater(
      service.confirmPhone('+12025550123', '000000'),
      throwsA(isA<ContactVerificationFailure>()),
    );
    expect(confirmedPhone, isNull);
  });
  test('cannot confirm a different number from the requested one', () async {
    await service.sendPhone('+12025550123');
    calls.clear();
    await expectLater(
      service.confirmPhone('+12025550124', '123456'),
      throwsA(isA<ContactVerificationFailure>()),
    );
    expect(calls, isEmpty);
  });
  test('invalid numbers do not send messages', () async {
    await expectLater(
      service.sendPhone('555'),
      throwsA(isA<ContactVerificationFailure>()),
    );
    expect(calls, isEmpty);
  });
  test(
    'late account update cannot replace a newly signed-in account',
    () async {
      hold = Completer<void>();
      final pending = service.sendPhone('+12025550123');
      final checked = expectLater(
        pending,
        throwsA(isA<ContactVerificationFailure>()),
      );
      while (!calls.any((r) => r.method == 'PUT')) {
        await Future<void>.delayed(Duration.zero);
      }
      await client.auth.signInWithPassword(
        email: 'user-b@example.com',
        password: 'synthetic',
      );
      hold!.complete();
      await checked;
      expect(client.auth.currentUser!.id, syntheticUserB);
    },
  );
  test('unconfirmed email resend uses current account email only', () async {
    backend.emailConfirmed = false;
    await service.resendEmail();
    final body = jsonDecode(
      calls.singleWhere((r) => r.url.path.endsWith('/resend')).body,
    );
    expect(body['type'], 'signup');
    expect(body['email'], '$syntheticUserA@example.com');
  });
  test('signed-out account cannot start verification', () async {
    await client.auth.signOut();
    calls.clear();
    await expectLater(
      service.sendPhone('+12025550123'),
      throwsA(isA<ContactVerificationFailure>()),
    );
    expect(calls, isEmpty);
  });
}
