/// Role-profile avatar contracts.
///
/// A membership's avatar is a reference to one ready, profile-purpose media
/// asset owned by the same user. The server owns the reference revision and
/// applies the same cross-role restriction fence the account commands use.
library;

import 'common.dart';

/// One authoritative avatar reference read.
class ProfileAvatarReference {
  ProfileAvatarReference({
    required String membershipId,
    String? imageMediaId,
    required this.revision,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId'),
       imageMediaId = optionalNonBlank(imageMediaId, 'imageMediaId') {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final String membershipId;

  /// Null means the member has no avatar (cleared or never set).
  final String? imageMediaId;

  /// Role-profile revision the reference was read at.
  final int revision;

  @override
  String toString() =>
      'ProfileAvatarReference($membershipId, revision: $revision, '
      'hasImage: ${imageMediaId != null})';
}

/// Outcome of one avatar update, safe to show in the photo editor.
class ProfileAvatarUpdateResult {
  const ProfileAvatarUpdateResult.success(this.reference)
    : error = null,
      conflict = false,
      outcomeUncertain = false;

  const ProfileAvatarUpdateResult.conflict()
    : reference = null,
      error = null,
      conflict = true,
      outcomeUncertain = false;

  const ProfileAvatarUpdateResult.failure(
    this.error, {
    this.outcomeUncertain = false,
  }) : reference = null,
       conflict = false;

  final ProfileAvatarReference? reference;
  final String? error;
  final bool conflict;

  /// True when the outcome is unknown and the caller should retry the same
  /// operation key instead of composing a new change.
  final bool outcomeUncertain;

  bool get isSuccess => reference != null;
}
