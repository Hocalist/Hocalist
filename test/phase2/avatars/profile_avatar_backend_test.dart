// Focused tests for the profile avatar seam. Fakes only; no SDK or network.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/avatars/profile_avatar_backend.dart';

class _Rpc {
  _Rpc({this.result, this.error});

  Map<String, Object?>? result;
  Object? error;
  final List<({String function, Map<String, Object?> params})> calls = [];

  Future<Map<String, Object?>> call(
    String function,
    Map<String, Object?> params,
  ) async {
    calls.add((function: function, params: params));
    final failure = error;
    if (failure != null) throw failure;
    return result ?? const <String, Object?>{};
  }
}

Map<String, Object?> _reference({
  String membershipId = '10000000-0000-4000-8000-00000000000a',
  String? mediaId = '50000000-0000-4000-8000-00000000000a',
  int revision = 4,
}) => <String, Object?>{
  'membership_id': membershipId,
  'image_media_id': mediaId,
  'revision': revision,
};

void main() {
  const membershipId = '10000000-0000-4000-8000-00000000000a';

  test('loadMemberAvatar sends the membership and decodes the reference',
      () async {
    final rpc = _Rpc(result: _reference());
    final backend = Phase2ProfileAvatarBackend(
      rpc: rpc.call,
      identity: () => 'user-a',
    );
    final reference = await backend.loadMemberAvatar(membershipId);
    expect(reference.membershipId, membershipId);
    expect(reference.imageMediaId, '50000000-0000-4000-8000-00000000000a');
    expect(reference.revision, 4);
    expect(rpc.calls.single.function, 'member_avatar');
    expect(rpc.calls.single.params, {'p_membership': membershipId});
  });

  test('updateAvatar sends role, key, revision and media id unchanged',
      () async {
    final rpc = _Rpc(result: _reference(mediaId: null, revision: 5));
    final backend = Phase2ProfileAvatarBackend(
      rpc: rpc.call,
      identity: () => 'user-a',
    );
    final reference = await backend.updateAvatar(
      role: 'seller',
      operationKey: 'avatar-key-1',
      expectedRevision: 4,
      mediaId: null,
    );
    expect(reference.imageMediaId, isNull);
    expect(reference.revision, 5);
    expect(rpc.calls.single.function, 'profile_avatar_update');
    expect(rpc.calls.single.params, {
      'p_role': 'seller',
      'p_key': 'avatar-key-1',
      'p_expected_revision': 4,
      'p_media_id': null,
    });
  });

  test('a retry reuses the caller operation key', () async {
    final rpc = _Rpc(result: _reference());
    final backend = Phase2ProfileAvatarBackend(
      rpc: rpc.call,
      identity: () => 'user-a',
    );
    await backend.updateAvatar(
      role: 'buyer',
      operationKey: 'avatar-key-2',
      expectedRevision: 1,
      mediaId: '50000000-0000-4000-8000-00000000000a',
    );
    await backend.updateAvatar(
      role: 'buyer',
      operationKey: 'avatar-key-2',
      expectedRevision: 1,
      mediaId: '50000000-0000-4000-8000-00000000000a',
    );
    expect(rpc.calls, hasLength(2));
    expect(
      rpc.calls.map((call) => call.params['p_key']).toSet(),
      {'avatar-key-2'},
    );
  });

  test('revision and idempotency conflicts map to typed outcomes', () async {
    final rpc = _Rpc(
      error: const ProfileAvatarRpcException(
        'revision_conflict',
        code: 'P0001',
        statusCode: 400,
      ),
    );
    final backend = Phase2ProfileAvatarBackend(
      rpc: rpc.call,
      identity: () => 'user-a',
    );
    await expectLater(
      backend.updateAvatar(
        role: 'buyer',
        operationKey: 'k',
        expectedRevision: 1,
        mediaId: null,
      ),
      throwsA(isA<ProfileAvatarConflictException>()),
    );

    rpc.error = const ProfileAvatarRpcException(
      'idempotency_conflict',
      code: 'P0001',
      statusCode: 400,
    );
    await expectLater(
      backend.updateAvatar(
        role: 'buyer',
        operationKey: 'k',
        expectedRevision: 1,
        mediaId: null,
      ),
      throwsA(
        isA<ProfileAvatarUnavailableException>().having(
          (error) => error.outcomeUncertain,
          'outcomeUncertain',
          isFalse,
        ),
      ),
    );
  });

  test('a transport failure is uncertain and keeps the key for retry',
      () async {
    final rpc = _Rpc(error: StateError('offline'));
    final backend = Phase2ProfileAvatarBackend(
      rpc: rpc.call,
      identity: () => 'user-a',
    );
    await expectLater(
      backend.updateAvatar(
        role: 'buyer',
        operationKey: 'k',
        expectedRevision: 2,
        mediaId: '50000000-0000-4000-8000-00000000000a',
      ),
      throwsA(
        isA<ProfileAvatarUnavailableException>().having(
          (error) => error.outcomeUncertain,
          'outcomeUncertain',
          isTrue,
        ),
      ),
    );
  });

  test('the session fence discards a result after an identity change',
      () async {
    var identity = 'user-a';
    final rpc = _Rpc(result: _reference());
    final backend = Phase2ProfileAvatarBackend(
      rpc: (function, params) async {
        identity = 'user-b';
        return rpc.call(function, params);
      },
      identity: () => identity,
    );
    await expectLater(
      backend.loadMemberAvatar(membershipId),
      throwsA(
        isA<ProfileAvatarUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('session changed'),
        ),
      ),
    );
  });

  test('a signed-out call never reaches the transport', () async {
    final rpc = _Rpc(result: _reference());
    final backend = Phase2ProfileAvatarBackend(
      rpc: rpc.call,
      identity: () => null,
    );
    await expectLater(
      backend.loadMemberAvatar(membershipId),
      throwsA(isA<ProfileAvatarUnavailableException>()),
    );
    expect(rpc.calls, isEmpty);
  });

  test('a malformed response is rejected without exposing values', () async {
    for (final payload in [
      <String, Object?>{},
      {'membership_id': membershipId, 'revision': 0, 'image_media_id': null},
      {'membership_id': 5, 'revision': 1, 'image_media_id': null},
      {'membership_id': membershipId, 'revision': 1, 'image_media_id': 7},
    ]) {
      final rpc = _Rpc(result: payload);
      final backend = Phase2ProfileAvatarBackend(
        rpc: rpc.call,
        identity: () => 'user-a',
      );
      await expectLater(
        backend.loadMemberAvatar(membershipId),
        throwsA(isA<ProfileAvatarUnavailableException>()),
        reason: payload.toString(),
      );
    }
  });
}
