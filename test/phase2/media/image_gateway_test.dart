import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hocalist/data/phase2/media/image_gateway.dart';
import '../accounts/support/supabase_http_backend.dart';

void main() {
  test('upload errors provide safe stage-specific copy', () {
    expect(
      photoUploadFailureMessage(StateError('invalid_image')),
      contains('format'),
    );
    expect(
      photoUploadFailureMessage(StateError('session_changed')),
      contains('session'),
    );
    expect(
      photoUploadFailureMessage(TimeoutException('private detail')),
      contains('timed out'),
    );
    expect(
      photoUploadFailureMessage(StateError('private token')),
      isNot(contains('private token')),
    );
  });
  test('media keys match the endpoint UUID contract and are unique', () {
    final keys = List.generate(30, (_) => newMediaUploadKey());
    expect(keys.toSet(), hasLength(keys.length));
    for (final key in keys) {
      expect(
        key,
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
    }
  });

  test('prefixed marketplace keys cannot dispatch a media upload', () async {
    final backend = SyntheticAccountBackend();
    final client = buildSyntheticSupabaseClient(backend.client());
    addTearDown(client.dispose);
    var dispatched = false;
    final gateway = ImageGateway(
      client,
      post: (url, {headers, body}) async {
        dispatched = true;
        return http.Response('{}', 400);
      },
    );
    await expectLater(
      gateway.upload(
        Uint8List.fromList([255, 216]),
        'avatar-media-1234567890abcdef1234567890abcdef',
        'profile',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          'invalid_upload_key',
        ),
      ),
    );
    expect(dispatched, false);
  });
  for (final upload in [true, false]) {
    test(
      '${upload ? 'upload' : 'read'} refreshes before media dispatch and keeps its token pinned',
      () async {
        final backend = SyntheticAccountBackend();
        final client = buildSyntheticSupabaseClient(backend.client());
        addTearDown(client.dispose);
        await client.auth.setInitialSession(
          jsonEncode(backend.issueSession(syntheticUserA)),
        );
        final old = client.auth.currentSession!.accessToken;
        client.auth.currentSession!.expiresAt = 1;
        final gateway = ImageGateway(
          client,
          post: (url, {headers, body}) async {
            expect(
              headers!['Authorization'],
              'Bearer ${client.auth.currentSession!.accessToken}',
            );
            expect(headers['Authorization'], isNot('Bearer $old'));
            expect(url.path.endsWith('/hocalist-media'), true);
            if (upload) expect(headers['x-media-purpose'], 'profile');
            return upload
                ? http.Response(
                    '{"id":"11111111-1111-4111-8111-111111111111"}',
                    200,
                  )
                : http.Response.bytes([1, 2, 3], 200);
          },
        );
        if (upload) {
          expect(
            await gateway.upload(
              Uint8List.fromList([1, 2, 3]),
              newMediaUploadKey(),
              'profile',
            ),
            '11111111-1111-4111-8111-111111111111',
          );
        } else {
          expect(await gateway.read('image'), [1, 2, 3]);
        }
        expect(
          backend.requests.where(
            (r) => r.url.queryParameters['grant_type'] == 'refresh_token',
          ),
          hasLength(1),
        );
      },
    );
  }

  test(
    'replacement identity discards a completed upload acknowledgement',
    () async {
      final backend = SyntheticAccountBackend();
      final client = buildSyntheticSupabaseClient(backend.client());
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(backend.issueSession(syntheticUserA)),
      );
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final gateway = ImageGateway(
        client,
        post: (url, {headers, body}) {
          started.complete();
          return response.future;
        },
      );
      final result = gateway.upload(
        Uint8List.fromList([1]),
        newMediaUploadKey(),
        'profile',
      );
      await started.future;
      await client.auth.signInWithPassword(
        email: 'user-b@example.com',
        password: 'synthetic-password',
      );
      response.complete(
        http.Response('{"id":"11111111-1111-4111-8111-111111111111"}', 200),
      );
      await expectLater(
        result,
        throwsA(
          isA<StateError>().having((e) => e.message, 'code', 'session_changed'),
        ),
      );
    },
  );
}
