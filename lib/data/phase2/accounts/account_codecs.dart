/// Strict decoders for the account wire shapes from drafts 003/004.
///
/// Every decoder validates required fields, types, enum values, positive
/// revisions and parseable timestamps. Failures raise
/// [AccountDecodeException] carrying only a safe field path; response
/// payloads, contact values and server messages are never included.
library;

import '../../../domain/phase2/phase2.dart';
import 'timestamptz.dart';

/// Internal decode failure with a safe detail such as `memberships.role`.
class AccountDecodeException implements Exception {
  const AccountDecodeException(this.detail);

  final String detail;

  @override
  String toString() => 'AccountDecodeException($detail)';
}

/// Validates a table-select payload and returns its rows.
List<Map<String, Object?>> decodeRowList(Object? data, String context) {
  if (data is! List) {
    throw AccountDecodeException('$context.rows');
  }
  final rows = <Map<String, Object?>>[];
  for (final entry in data) {
    if (entry is! Map) {
      throw AccountDecodeException('$context.row');
    }
    try {
      rows.add(Map<String, Object?>.from(entry));
    } on TypeError {
      throw AccountDecodeException('$context.row');
    }
  }
  return rows;
}

/// Validates an RPC payload and returns the JSON object.
Map<String, Object?> decodeResultObject(Object? data, String context) {
  if (data is! Map) {
    throw AccountDecodeException('$context.result');
  }
  try {
    return Map<String, Object?>.from(data);
  } on TypeError {
    throw AccountDecodeException('$context.result');
  }
}

MembershipRecord decodeMembershipRow(Map<String, Object?> row) {
  final id = _requireString(row, 'id', 'memberships.id');
  final userId = _requireString(row, 'user_id', 'memberships.user_id');
  final role = _requireEnum(
    HocalistRole.values,
    _requireString(row, 'role', 'memberships.role'),
    'memberships.role',
  );
  final status = _requireEnum(
    MembershipStatus.values,
    _requireString(row, 'status', 'memberships.status'),
    'memberships.status',
  );
  final revision = _requirePositiveInt(row, 'revision', 'memberships.revision');
  final createdAt = _requireTimestamp(
    row,
    'created_at',
    'memberships.created_at',
  );
  final updatedAt = _requireTimestamp(
    row,
    'updated_at',
    'memberships.updated_at',
  );
  return MembershipRecord(
    membershipId: id,
    userId: userId,
    role: role,
    status: status,
    stamp: RecordStamp(
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
    ),
  );
}

AccountRoleProfile decodeRoleProfileRow(
  Map<String, Object?> row, {
  required HocalistRole role,
  required String userId,
}) {
  final membershipId = _requireString(
    row,
    'membership_id',
    'role_profiles.membership_id',
  );
  final displayName = _requireString(
    row,
    'display_name',
    'role_profiles.display_name',
  );
  final areaLabel = _optionalString(
    row,
    'area_label',
    'role_profiles.area_label',
  );
  final profileNote = _optionalString(
    row,
    'profile_note',
    'role_profiles.profile_note',
  );
  final preferredMeetupType = _optionalString(
    row,
    'preferred_meetup_type',
    'role_profiles.preferred_meetup_type',
  );
  final serviceRadiusMiles = _optionalNonNegativeInt(
    row,
    'service_radius_miles',
    'role_profiles.service_radius_miles',
  );
  final pickupAvailability = _optionalString(
    row,
    'pickup_availability',
    'role_profiles.pickup_availability',
  );
  final revision = _requirePositiveInt(
    row,
    'revision',
    'role_profiles.revision',
  );
  final createdAt = _requireTimestamp(
    row,
    'created_at',
    'role_profiles.created_at',
  );
  final updatedAt = _requireTimestamp(
    row,
    'updated_at',
    'role_profiles.updated_at',
  );
  try {
    return AccountRoleProfile(
      membershipId: membershipId,
      userId: userId,
      role: role,
      displayName: displayName,
      areaLabel: areaLabel,
      profileNote: profileNote,
      preferredMeetupType: preferredMeetupType,
      serviceRadiusMiles: serviceRadiusMiles,
      pickupAvailability: pickupAvailability,
      stamp: RecordStamp(
        revision: revision,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );
  } on ArgumentError {
    throw const AccountDecodeException('role_profiles.field_value');
  }
}

PrivateContactRecord decodePrivateContactRow(Map<String, Object?> row) {
  final userId = _requireString(row, 'user_id', 'profile_contacts.user_id');
  final phone = _optionalString(row, 'phone', 'profile_contacts.phone');
  final addressLine1 = _optionalString(
    row,
    'address_line1',
    'profile_contacts.address_line1',
  );
  final addressLine2 = _optionalString(
    row,
    'address_line2',
    'profile_contacts.address_line2',
  );
  final city = _optionalString(row, 'city', 'profile_contacts.city');
  final region = _optionalString(row, 'region', 'profile_contacts.region');
  final postalCode = _optionalString(
    row,
    'postal_code',
    'profile_contacts.postal_code',
  );
  final countryCode = _optionalString(
    row,
    'country_code',
    'profile_contacts.country_code',
  );
  final revision = _requirePositiveInt(
    row,
    'revision',
    'profile_contacts.revision',
  );
  final createdAt = _requireTimestamp(
    row,
    'created_at',
    'profile_contacts.created_at',
  );
  final updatedAt = _requireTimestamp(
    row,
    'updated_at',
    'profile_contacts.updated_at',
  );
  try {
    return PrivateContactRecord(
      userId: userId,
      contact: AccountContact(
        phone: phone,
        addressLine1: addressLine1,
        addressLine2: addressLine2,
        city: city,
        region: region,
        postalCode: postalCode,
        countryCode: countryCode,
      ),
      stamp: RecordStamp(
        revision: revision,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );
  } on ArgumentError {
    throw const AccountDecodeException('profile_contacts.field_value');
  }
}

OnboardResult decodeOnboardResult(Map<String, Object?> result) {
  final membershipId = _requireString(
    result,
    'profile_id',
    'account_command.onboard.profile_id',
  );
  final role = _requireEnum(
    HocalistRole.values,
    _requireString(result, 'role', 'account_command.onboard.role'),
    'account_command.onboard.role',
  );
  final revision = _requirePositiveInt(
    result,
    'revision',
    'account_command.onboard.revision',
  );
  return OnboardResult(
    membershipId: membershipId,
    role: role,
    revision: revision,
  );
}

RoleProfileUpdateResult decodeRoleProfileUpdateResult(
  Map<String, Object?> result,
) {
  final profileId = _requireString(
    result,
    'profile_id',
    'account_command.profile_update.profile_id',
  );
  final revision = _requirePositiveInt(
    result,
    'revision',
    'account_command.profile_update.revision',
  );
  return RoleProfileUpdateResult(profileId: profileId, revision: revision);
}

ContactUpdateResult decodeContactUpdateResult(Map<String, Object?> result) {
  final revision = _requirePositiveInt(
    result,
    'revision',
    'account_command.contact_update.revision',
  );
  return ContactUpdateResult(revision: revision);
}

String _requireString(Map<String, Object?> row, String field, String context) {
  final value = row[field];
  if (value is! String || value.trim().isEmpty) {
    throw AccountDecodeException(context);
  }
  return value;
}

String? _optionalString(
  Map<String, Object?> row,
  String field,
  String context,
) {
  final value = row[field];
  if (value == null) return null;
  if (value is! String) {
    throw AccountDecodeException(context);
  }
  return value;
}

int _requirePositiveInt(
  Map<String, Object?> row,
  String field,
  String context,
) {
  final value = row[field];
  if (value is! int || value < 1) {
    throw AccountDecodeException(context);
  }
  return value;
}

int? _optionalNonNegativeInt(
  Map<String, Object?> row,
  String field,
  String context,
) {
  final value = row[field];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw AccountDecodeException(context);
  }
  return value;
}

DateTime _requireTimestamp(
  Map<String, Object?> row,
  String field,
  String context,
) {
  final value = row[field];
  if (value is! String) {
    throw AccountDecodeException(context);
  }
  return parsePostgresTimestamptz(value, context: context);
}

T _requireEnum<T extends Enum>(List<T> values, String raw, String context) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw AccountDecodeException(context);
}
