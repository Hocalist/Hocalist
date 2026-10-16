/// Account adapter backed by the reviewed SQL drafts.
///
/// Implements the narrow `AccountRepository` boundary: membership and
/// role-profile reads, identity-scoped contact reads, and the `onboard`,
/// `profile.update` and `contact.update` RPC calls. It is intentionally not a
/// complete `ProfileRepository`.
///
/// Identity comes from the injected [AccountSession]; no method takes a
/// caller identity, and returned ids are re-checked against the session as
/// defense in depth while RLS remains authoritative.
///
/// Session fence: every operation captures the session identity once, then
/// re-checks it immediately before and after each transport dispatch. A
/// logout or account replacement during a queued, multi-step or in-flight
/// call discards the work with `PermissionDeniedError(action:
/// 'session_changed')` instead of returning another identity's private data.
/// The concrete transport additionally pins the captured access token on the
/// request, so an account A operation can never be sent with account B's
/// token. A token refresh for the same user keeps the identity stable and is
/// therefore unaffected. The adapter never retries by itself, so a
/// caller-supplied idempotency key is passed through unchanged on a manual
/// retry.
library;

import '../../../domain/phase2/phase2.dart';
import 'account_codecs.dart';
import 'account_error_mapper.dart';
import 'account_session.dart';
import 'account_transport.dart';

class AccountDataAdapter implements AccountRepository {
  AccountDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const AccountErrorMapper(),
  });

  static const String schema = 'hocalist';
  static const String membershipsTable = 'memberships';
  static const String roleProfilesTable = 'role_profiles';
  static const String profileContactsTable = 'profile_contacts';
  static const String accountCommandFunction = 'account_command';

  /// Columns the codecs require; a select never requests more than these.
  static const List<String> membershipColumns = [
    'id',
    'user_id',
    'role',
    'status',
    'revision',
    'created_at',
    'updated_at',
  ];

  static const List<String> roleProfileColumns = [
    'membership_id',
    'display_name',
    'area_label',
    'profile_note',
    'preferred_meetup_type',
    'service_radius_miles',
    'pickup_availability',
    'revision',
    'created_at',
    'updated_at',
  ];

  static const List<String> profileContactColumns = [
    'user_id',
    'phone',
    'address_line1',
    'address_line2',
    'city',
    'region',
    'postal_code',
    'country_code',
    'revision',
    'created_at',
    'updated_at',
  ];

  final AccountTransport transport;
  final AccountSession session;
  final AccountErrorMapper errorMapper;

  @override
  Future<RepositoryResult<List<MembershipRecord>>> fetchMemberships() async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.selectRows(
      AccountTableQuery(
        schema: schema,
        table: membershipsTable,
        columns: membershipColumns,
        filters: [AccountColumnFilter.equals('user_id', userId)],
        orderBy: const ['role'],
      ),
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    return switch (response) {
      AccountTransportData(:final data) => _decodeRows(
        data,
        'memberships.select',
        (rows) {
          final memberships = <MembershipRecord>[];
          final ids = <String>{};
          final roles = <HocalistRole>{};
          for (final row in rows) {
            final membership = decodeMembershipRow(row);
            if (membership.userId != userId) {
              throw const AccountDecodeException(
                'memberships.user_id_mismatch',
              );
            }
            final uniqueId = ids.add(membership.membershipId);
            final uniqueRole = roles.add(membership.role);
            if (!uniqueId || !uniqueRole) {
              throw const AccountDecodeException('memberships.duplicate_rows');
            }
            memberships.add(membership);
          }
          memberships.sort(
            (left, right) => left.role.index.compareTo(right.role.index),
          );
          return List<MembershipRecord>.unmodifiable(memberships);
        },
      ),
      AccountTransportError() => _failure(
        errorMapper.map(response, operation: 'memberships.select'),
      ),
    };
  }

  @override
  Future<RepositoryResult<MembershipRecord>> fetchMembership({
    required HocalistRole role,
  }) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    return _fetchMembershipFor(
      userId,
      role,
      operation: 'memberships.select_one',
    );
  }

  @override
  Future<RepositoryResult<AccountRoleProfile>> fetchRoleProfile({
    required HocalistRole role,
  }) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final membershipResult = await _fetchMembershipFor(
      userId,
      role,
      operation: 'memberships.select_one',
    );
    final membership = membershipResult.valueOrNull;
    if (membership == null) {
      return _failure(
        membershipResult.errorOrNull ??
            const MalformedResponseError(
              operation: 'role_profiles.select',
              detail: 'memberships.missing_result',
            ),
      );
    }
    if (!_isStillCurrent(userId)) return _sessionChanged();
    final response = await transport.selectRows(
      AccountTableQuery(
        schema: schema,
        table: roleProfilesTable,
        columns: roleProfileColumns,
        filters: [
          AccountColumnFilter.equals('membership_id', membership.membershipId),
        ],
      ),
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    switch (response) {
      case AccountTransportError():
        return _failure(
          errorMapper.map(response, operation: 'role_profiles.select'),
        );
      case AccountTransportData(:final data):
        try {
          final rows = decodeRowList(data, 'role_profiles.select');
          if (rows.isEmpty) {
            return _failure(
              NotFoundError(
                entityType: 'role_profile',
                entityId: membership.membershipId,
              ),
            );
          }
          if (rows.length > 1) {
            return _failure(
              const MalformedResponseError(
                operation: 'role_profiles.select',
                detail: 'role_profiles.multiple_rows',
              ),
            );
          }
          final profile = decodeRoleProfileRow(
            rows.single,
            role: role,
            userId: membership.userId,
          );
          if (profile.membershipId != membership.membershipId) {
            return _failure(
              const MalformedResponseError(
                operation: 'role_profiles.select',
                detail: 'role_profiles.membership_mismatch',
              ),
            );
          }
          return RepositorySuccess<AccountRoleProfile>(profile);
        } on AccountDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: 'role_profiles.select',
              detail: error.detail,
            ),
          );
        }
    }
  }

  @override
  Future<RepositoryResult<PrivateContactRecord>> fetchPrivateContact() async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.selectRows(
      AccountTableQuery(
        schema: schema,
        table: profileContactsTable,
        columns: profileContactColumns,
        filters: [AccountColumnFilter.equals('user_id', userId)],
      ),
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    switch (response) {
      case AccountTransportError():
        return _failure(
          errorMapper.map(response, operation: 'profile_contacts.select'),
        );
      case AccountTransportData(:final data):
        try {
          final rows = decodeRowList(data, 'profile_contacts.select');
          if (rows.isEmpty) {
            return _failure(
              NotFoundError(entityType: 'private_contact', entityId: userId),
            );
          }
          if (rows.length > 1) {
            return _failure(
              const MalformedResponseError(
                operation: 'profile_contacts.select',
                detail: 'profile_contacts.multiple_rows',
              ),
            );
          }
          final contact = decodePrivateContactRow(rows.single);
          if (contact.userId != userId) {
            return _failure(
              const MalformedResponseError(
                operation: 'profile_contacts.select',
                detail: 'profile_contacts.identity_mismatch',
              ),
            );
          }
          return RepositorySuccess<PrivateContactRecord>(contact);
        } on AccountDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: 'profile_contacts.select',
              detail: error.detail,
            ),
          );
        }
    }
  }

  @override
  Future<RepositoryResult<OnboardResult>> onboard(
    OnboardCommand command,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.callAccountCommand(
      schema: schema,
      function: accountCommandFunction,
      operation: 'onboard',
      key: command.idempotencyKey,
      input: <String, Object?>{
        'role': command.role.name,
        'display_name': command.displayName,
      },
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    return _decodeResult(response, 'account_command.onboard', (result) {
      final onboard = decodeOnboardResult(result);
      if (onboard.role != command.role) {
        throw const AccountDecodeException(
          'account_command.onboard.role_mismatch',
        );
      }
      return onboard;
    });
  }

  @override
  Future<RepositoryResult<RoleProfileUpdateResult>> updateRoleProfile(
    UpdateRoleProfileCommand command,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final input = <String, Object?>{
      'profile_id': command.profileId,
      'expected_revision': command.expectedRevision,
      'display_name': command.displayName,
    };
    _applyPatch(input, 'area_label', command.areaLabel);
    _applyPatch(input, 'profile_note', command.profileNote);
    _applyPatch(input, 'preferred_meetup_type', command.preferredMeetupType);
    _applyPatch(input, 'service_radius_miles', command.serviceRadiusMiles);
    _applyPatch(input, 'pickup_availability', command.pickupAvailability);
    final response = await transport.callAccountCommand(
      schema: schema,
      function: accountCommandFunction,
      operation: 'profile.update',
      key: command.idempotencyKey,
      input: input,
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    return _decodeResult(response, 'account_command.profile_update', (result) {
      final update = decodeRoleProfileUpdateResult(result);
      if (update.profileId != command.profileId) {
        throw const AccountDecodeException(
          'account_command.profile_update.profile_mismatch',
        );
      }
      return update;
    });
  }

  @override
  Future<RepositoryResult<ContactUpdateResult>> updateContact(
    UpdateContactCommand command,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final input = <String, Object?>{
      'expected_revision': command.expectedRevision,
    };
    _applyPatch(input, 'phone', command.phone);
    _applyPatch(input, 'address_line1', command.addressLine1);
    _applyPatch(input, 'address_line2', command.addressLine2);
    _applyPatch(input, 'city', command.city);
    _applyPatch(input, 'region', command.region);
    _applyPatch(input, 'postal_code', command.postalCode);
    _applyPatch(input, 'country_code', command.countryCode);
    final response = await transport.callAccountCommand(
      schema: schema,
      function: accountCommandFunction,
      operation: 'contact.update',
      key: command.idempotencyKey,
      input: input,
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    return _decodeResult(
      response,
      'account_command.contact_update',
      (result) => decodeContactUpdateResult(result),
    );
  }

  Future<RepositoryResult<MembershipRecord>> _fetchMembershipFor(
    String userId,
    HocalistRole role, {
    required String operation,
  }) async {
    final response = await transport.selectRows(
      AccountTableQuery(
        schema: schema,
        table: membershipsTable,
        columns: membershipColumns,
        filters: [
          AccountColumnFilter.equals('user_id', userId),
          AccountColumnFilter.equals('role', role.name),
        ],
      ),
    );
    if (!_isStillCurrent(userId)) return _sessionChanged();
    switch (response) {
      case AccountTransportError():
        return _failure(errorMapper.map(response, operation: operation));
      case AccountTransportData(:final data):
        try {
          final rows = decodeRowList(data, operation);
          if (rows.isEmpty) {
            return _failure(
              NotFoundError(entityType: 'membership', entityId: role.name),
            );
          }
          if (rows.length > 1) {
            return _failure(
              MalformedResponseError(
                operation: operation,
                detail: 'memberships.multiple_rows',
              ),
            );
          }
          final membership = decodeMembershipRow(rows.single);
          if (membership.userId != userId || membership.role != role) {
            return _failure(
              MalformedResponseError(
                operation: operation,
                detail: 'memberships.identity_mismatch',
              ),
            );
          }
          return RepositorySuccess<MembershipRecord>(membership);
        } on AccountDecodeException catch (error) {
          return _failure(
            MalformedResponseError(operation: operation, detail: error.detail),
          );
        }
    }
  }

  RepositoryResult<T> _decodeRows<T>(
    Object? data,
    String operation,
    T Function(List<Map<String, Object?>> rows) build,
  ) {
    try {
      return RepositorySuccess<T>(build(decodeRowList(data, operation)));
    } on AccountDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: operation, detail: error.detail),
      );
    }
  }

  RepositoryResult<T> _decodeResult<T>(
    AccountTransportResponse response,
    String operation,
    T Function(Map<String, Object?> result) build,
  ) {
    switch (response) {
      case AccountTransportError():
        return _failure(errorMapper.map(response, operation: operation));
      case AccountTransportData(:final data):
        try {
          return RepositorySuccess<T>(
            build(decodeResultObject(data, operation)),
          );
        } on AccountDecodeException catch (error) {
          return _failure(
            MalformedResponseError(operation: operation, detail: error.detail),
          );
        }
    }
  }

  static void _applyPatch<T>(
    Map<String, Object?> target,
    String field,
    Patch<T> patch,
  ) {
    switch (patch) {
      case PatchKeep<T>():
        break;
      case PatchClear<T>():
        target[field] = null;
      case PatchSet<T>(:final value):
        target[field] = value;
    }
  }

  /// Captures the live session identity, or null when signed out.
  String? _captureIdentity() {
    final userId = session.currentUserId;
    if (userId == null || userId.trim().isEmpty) return null;
    return userId;
  }

  /// True while [capturedUserId] is still the live session identity.
  bool _isStillCurrent(String capturedUserId) =>
      session.currentUserId == capturedUserId;

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );

  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  RepositoryFailureResult<T> _failure<T>(RepositoryError error) =>
      RepositoryFailureResult<T>(error);

  RepositoryFailureResult<T> _sessionChanged<T>() => _failure<T>(_staleSession);
}
