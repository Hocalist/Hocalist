/// Narrow account data-layer contracts for the reviewed SQL drafts.
///
/// These operations cover only what `hocalist.memberships`,
/// `hocalist.role_profiles`, `hocalist.profile_contacts` and
/// `hocalist.account_command` support today: membership and role-profile
/// reads, identity-scoped contact reads, and the `onboard`, `profile.update`
/// and `contact.update` commands.
///
/// This is intentionally **not** a complete `ProfileRepository`. Media,
/// catalogue categories, notification preferences, public projections and
/// server-derived privileges are not implemented and must not be invented.
///
/// Identity always comes from the injected session; method parameters never
/// carry a caller identity, and a caller id is never proof of authorization.
/// RLS remains authoritative even though the adapter re-checks returned ids as
/// defense in depth.
library;

import 'account_contacts.dart';
import 'common.dart';
import 'failures.dart';
import 'patch.dart';
import 'profiles.dart';

/// Maximum lengths and ranges from the `role_profiles` table checks and the
/// `profile.update` command validation.
const int accountDisplayNameMaxLength = 200;
const int accountAreaLabelMaxLength = 200;
const int accountProfileNoteMaxLength = 2000;
const int accountPreferredMeetupTypeMaxLength = 100;
const int accountPickupAvailabilityMaxLength = 500;
const int accountServiceRadiusMax = 99999999;

/// Draft-aligned role-profile read record.
///
/// Contains exactly the columns of `hocalist.role_profiles`. Fields absent
/// from the draft (seller category labels, contacts, media) are not
/// manufactured here; the future full profile contract composes them.
class AccountRoleProfile {
  AccountRoleProfile({
    required String membershipId,
    required String userId,
    required this.role,
    required String displayName,
    this.areaLabel,
    this.profileNote,
    this.preferredMeetupType,
    this.serviceRadiusMiles,
    this.pickupAvailability,
    required this.stamp,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId'),
       userId = requireNonBlank(userId, 'userId'),
       displayName = requireNonBlank(displayName, 'displayName') {
    _requireDisplayName(displayName);
    _requireMaxLength(areaLabel, accountAreaLabelMaxLength, 'areaLabel');
    _requireMaxLength(profileNote, accountProfileNoteMaxLength, 'profileNote');
    _requireMaxLength(
      preferredMeetupType,
      accountPreferredMeetupTypeMaxLength,
      'preferredMeetupType',
    );
    _requireMaxLength(
      pickupAvailability,
      accountPickupAvailabilityMaxLength,
      'pickupAvailability',
    );
    if (serviceRadiusMiles != null &&
        (serviceRadiusMiles! < 0 ||
            serviceRadiusMiles! > accountServiceRadiusMax)) {
      throw ArgumentError.value(
        serviceRadiusMiles,
        'serviceRadiusMiles',
        'must be between 0 and $accountServiceRadiusMax',
      );
    }
  }

  /// Role-profile row id; equals the membership id per the SQL draft.
  final String membershipId;

  /// Auth identity id resolved through the matching membership.
  final String userId;

  final HocalistRole role;
  final String displayName;

  /// Maps to `role_profiles.area_label` for both roles.
  final String? areaLabel;

  final String? profileNote;
  final String? preferredMeetupType;

  /// Seller-only; the server rejects this on buyer profiles.
  final int? serviceRadiusMiles;

  /// Seller-only; the server rejects this on buyer profiles.
  final String? pickupAvailability;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  @override
  String toString() =>
      'AccountRoleProfile($membershipId, ${role.name}, revision: '
      '${stamp.revision})';
}

/// `onboard` command: create an ordinary active membership plus its profile.
class OnboardCommand {
  OnboardCommand({
    required this.role,
    required String displayName,
    required String idempotencyKey,
  }) : displayName = displayName.trim(),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    _requireDisplayName(displayName);
  }

  final HocalistRole role;
  final String displayName;
  final String idempotencyKey;
}

/// Minimal `onboard` acknowledgement from the RPC.
class OnboardResult {
  OnboardResult({
    required String membershipId,
    required this.role,
    required this.revision,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId') {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  /// RPC `profile_id`; the created membership id.
  final String membershipId;

  final HocalistRole role;
  final int revision;

  @override
  String toString() =>
      'OnboardResult($membershipId, ${role.name}, revision: $revision)';
}

/// `profile.update` command with patch semantics for optional fields.
///
/// `display_name` is required and always sent; the SQL validates it after
/// trimming and stores the trimmed value. The five optional fields support
/// keep/set/clear. `service_radius_miles` and `pickup_availability` are
/// seller-only on the server.
class UpdateRoleProfileCommand {
  UpdateRoleProfileCommand({
    required String profileId,
    required this.expectedRevision,
    required String displayName,
    this.areaLabel = const PatchKeep<String>(),
    this.profileNote = const PatchKeep<String>(),
    this.preferredMeetupType = const PatchKeep<String>(),
    this.serviceRadiusMiles = const PatchKeep<int>(),
    this.pickupAvailability = const PatchKeep<String>(),
    required String idempotencyKey,
  }) : profileId = requireNonBlank(profileId, 'profileId'),
       displayName = displayName.trim(),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    _requireDisplayName(displayName);
    _validatePatchLength(areaLabel, accountAreaLabelMaxLength, 'areaLabel');
    _validatePatchLength(
      profileNote,
      accountProfileNoteMaxLength,
      'profileNote',
    );
    _validatePatchLength(
      preferredMeetupType,
      accountPreferredMeetupTypeMaxLength,
      'preferredMeetupType',
    );
    _validatePatchLength(
      pickupAvailability,
      accountPickupAvailabilityMaxLength,
      'pickupAvailability',
    );
    if (serviceRadiusMiles is PatchSet<int>) {
      final radius = (serviceRadiusMiles as PatchSet<int>).value;
      if (radius < 0 || radius > accountServiceRadiusMax) {
        throw ArgumentError.value(
          radius,
          'serviceRadiusMiles',
          'must be between 0 and $accountServiceRadiusMax',
        );
      }
    }
  }

  final String profileId;
  final int expectedRevision;
  final String displayName;
  final Patch<String> areaLabel;
  final Patch<String> profileNote;
  final Patch<String> preferredMeetupType;
  final Patch<int> serviceRadiusMiles;
  final Patch<String> pickupAvailability;
  final String idempotencyKey;
}

/// Minimal `profile.update` acknowledgement from the RPC.
class RoleProfileUpdateResult {
  RoleProfileUpdateResult({required String profileId, required this.revision})
    : profileId = requireNonBlank(profileId, 'profileId') {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final String profileId;
  final int revision;

  @override
  String toString() =>
      'RoleProfileUpdateResult($profileId, revision: $revision)';
}

/// Account operations backed by the reviewed SQL drafts.
///
/// Partial by design: only the three account tables and the three RPC
/// operations are covered. Identity comes from the session boundary.
abstract interface class AccountRepository {
  /// All memberships for the authenticated identity, ordered by role.
  ///
  /// Empty when the identity has no membership yet. Hidden or pending rows
  /// are still returned by RLS for status UI; the server decides.
  Future<RepositoryResult<List<MembershipRecord>>> fetchMemberships();

  /// The membership for one explicit role, or [NotFoundError] when absent.
  Future<RepositoryResult<MembershipRecord>> fetchMembership({
    required HocalistRole role,
  });

  /// The role profile for one explicit role.
  ///
  /// Returns [NotFoundError] when RLS hides the row (missing, pending,
  /// restricted or disabled membership).
  Future<RepositoryResult<AccountRoleProfile>> fetchRoleProfile({
    required HocalistRole role,
  });

  /// The identity's private contact row.
  ///
  /// Returns [NotFoundError] when the identity has no readable contact row.
  Future<RepositoryResult<PrivateContactRecord>> fetchPrivateContact();

  /// Creates an ordinary active membership plus its role profile.
  Future<RepositoryResult<OnboardResult>> onboard(OnboardCommand command);

  /// Patches the caller's own role profile at an expected revision.
  Future<RepositoryResult<RoleProfileUpdateResult>> updateRoleProfile(
    UpdateRoleProfileCommand command,
  );

  /// Patches the caller's shared contact row at its own expected revision.
  Future<RepositoryResult<ContactUpdateResult>> updateContact(
    UpdateContactCommand command,
  );
}

void _requireDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > accountDisplayNameMaxLength) {
    throw ArgumentError.value(
      '[redacted]',
      'displayName',
      'must be between 1 and $accountDisplayNameMaxLength characters',
    );
  }
}

void _requireMaxLength(String? value, int max, String field) {
  if (value != null && value.length > max) {
    throw ArgumentError.value(
      '[redacted]',
      field,
      'must be at most $max characters',
    );
  }
}

void _validatePatchLength(Patch<String> patch, int max, String field) {
  if (patch is PatchSet<String>) {
    _requireMaxLength(patch.value, max, field);
  }
}
