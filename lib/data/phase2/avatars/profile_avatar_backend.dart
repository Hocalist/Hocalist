/// Real-mode profile avatar seam.
///
/// Wraps the reviewed `member_avatar` reference read and the revisioned,
/// idempotent `profile_avatar_update` command with the same session fence used
/// by the other configured backends: the identity is captured once, re-checked
/// after every dispatch, and no request is sent for a signed-out session.
///
/// Deployment gate: [createConfiguredProfileAvatarBackend] returns null unless
/// `enabled` is true, so the photo UI stays visibly unavailable until the
/// `101_profile_avatar` migration is deployed. Tests inject an [rpc] fake.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/phase2/profile_avatar.dart';

/// Transport-level failure carrying the PostgREST code for outcome mapping.
class ProfileAvatarRpcException implements Exception {
  const ProfileAvatarRpcException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'ProfileAvatarRpcException($code: $message)';
}

/// The avatar write hit a stale revision; the caller should reload and retry.
class ProfileAvatarConflictException implements Exception {
  const ProfileAvatarConflictException();
}

/// The change could not be applied or confirmed. [outcomeUncertain] means the
/// same operation key must be retried instead of composing a new change.
class ProfileAvatarUnavailableException implements Exception {
  const ProfileAvatarUnavailableException(
    this.message, {
    this.outcomeUncertain = false,
  });

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => 'ProfileAvatarUnavailableException($message)';
}

typedef ProfileAvatarRpc =
    Future<Map<String, Object?>> Function(
      String function,
      Map<String, Object?> params,
    );

abstract interface class ProfileAvatarBackend {
  Future<ProfileAvatarReference> loadMemberAvatar(String membershipId);

  Future<ProfileAvatarReference> updateAvatar({
    required String role,
    required String operationKey,
    required int expectedRevision,
    required String? mediaId,
  });
}

class Phase2ProfileAvatarBackend implements ProfileAvatarBackend {
  Phase2ProfileAvatarBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String referenceFunction = 'member_avatar';
  static const String updateFunction = 'profile_avatar_update';
  static const Set<String> allowedFunctions = {
    referenceFunction,
    updateFunction,
  };

  final ProfileAvatarRpc rpc;
  final String? Function() identity;

  @override
  Future<ProfileAvatarReference> loadMemberAvatar(String membershipId) async {
    final data = await _call(referenceFunction, {
      'p_membership': membershipId,
    });
    return _decode(data);
  }

  @override
  Future<ProfileAvatarReference> updateAvatar({
    required String role,
    required String operationKey,
    required int expectedRevision,
    required String? mediaId,
  }) async {
    final data = await _call(updateFunction, {
      'p_role': role,
      'p_key': operationKey,
      'p_expected_revision': expectedRevision,
      'p_media_id': mediaId,
    });
    return _decode(data);
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const ProfileAvatarUnavailableException(
        'Photo changes are unavailable.',
      );
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const ProfileAvatarUnavailableException(
        'Sign in to change your photo.',
      );
    }
    try {
      final data = await rpc(function, params);
      if (identity() != captured) {
        throw const ProfileAvatarUnavailableException(
          'Your session changed. Sign in again.',
        );
      }
      return data;
    } on ProfileAvatarRpcException catch (error) {
      if (error.code == 'P0001' && error.message.contains('revision_conflict')) {
        throw const ProfileAvatarConflictException();
      }
      if (error.code == 'P0001' &&
          error.message.contains('idempotency_conflict')) {
        throw const ProfileAvatarUnavailableException(
          'This change conflicts with an earlier attempt. Please try again.',
        );
      }
      throw ProfileAvatarUnavailableException(
        error.message,
        outcomeUncertain:
            error.statusCode == null || error.statusCode! >= 500,
      );
    } on ProfileAvatarUnavailableException {
      rethrow;
    } catch (_) {
      throw const ProfileAvatarUnavailableException(
        'Your photo change could not be confirmed. Retry to check it safely.',
        outcomeUncertain: true,
      );
    }
  }

  ProfileAvatarReference _decode(Map<String, Object?> row) {
    final membershipId = row['membership_id'];
    final revision = row['revision'];
    final mediaId = row['image_media_id'];
    if (membershipId is! String ||
        revision is! int ||
        revision < 1 ||
        (mediaId != null && mediaId is! String)) {
      throw const ProfileAvatarUnavailableException(
        'The avatar response was invalid.',
      );
    }
    try {
      return ProfileAvatarReference(
        membershipId: membershipId,
        imageMediaId: mediaId as String?,
        revision: revision,
      );
    } on ArgumentError {
      throw const ProfileAvatarUnavailableException(
        'The avatar response was invalid.',
      );
    }
  }
}

/// Set true only after the reviewed `101_profile_avatar` migration is deployed.
const bool kProfileAvatarsEnabled = bool.fromEnvironment('HOCALIST_PROFILE_AVATARS');

/// Composes the avatar backend for a configured Supabase session. Returns null
/// in prototype mode, before Supabase initialization, or while the feature flag
/// is off so the UI keeps its honest unavailable state.
ProfileAvatarBackend? createConfiguredProfileAvatarBackend({
  bool enabled = kProfileAvatarsEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2ProfileAvatarBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2ProfileAvatarBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const ProfileAvatarUnavailableException(
              'The avatar response was invalid.',
            );
          }
          return Map<String, Object?>.from(data);
        } on PostgrestException catch (error) {
          throw ProfileAvatarRpcException(
            error.message,
            code: error.code,
            statusCode: error.code == null ? null : 400,
          );
        }
      },
    );
  } catch (_) {
    return null;
  }
}
