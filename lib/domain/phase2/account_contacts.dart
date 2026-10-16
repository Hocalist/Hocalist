/// Identity-scoped private contact contracts for the account layer.
///
/// Mirrors `hocalist.profile_contacts` from the reviewed SQL draft:
/// one row per Auth identity (shared by the identity's roles), its own
/// `revision`, nullable address components, and a two-letter `country_code`.
///
/// Auth email is separate and is never written here. A saved phone string is
/// unverified contact data, not a verified Auth phone. Nothing in this file
/// reads or writes the Auth session.
library;

import 'common.dart';
import 'patch.dart';

/// Maximum lengths from the `profile_contacts` table checks.
const int accountPhoneMaxLength = 40;
const int accountAddressLineMaxLength = 300;
const int accountCityMaxLength = 150;
const int accountRegionMaxLength = 150;
const int accountPostalCodeMaxLength = 40;

final RegExp _countryCodePattern = RegExp(r'^[A-Z]{2}$');

/// Draft-aligned private contact values. Every field is optional.
class AccountContact {
  factory AccountContact({
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? region,
    String? postalCode,
    String? countryCode,
  }) {
    _requireMaxLength(phone, accountPhoneMaxLength, 'phone');
    _requireMaxLength(
      addressLine1,
      accountAddressLineMaxLength,
      'addressLine1',
    );
    _requireMaxLength(
      addressLine2,
      accountAddressLineMaxLength,
      'addressLine2',
    );
    _requireMaxLength(city, accountCityMaxLength, 'city');
    _requireMaxLength(region, accountRegionMaxLength, 'region');
    _requireMaxLength(postalCode, accountPostalCodeMaxLength, 'postalCode');
    _requireCountryCode(countryCode);
    return AccountContact._(
      phone: phone,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      region: region,
      postalCode: postalCode,
      countryCode: countryCode,
    );
  }

  const AccountContact._({
    this.phone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.region,
    this.postalCode,
    this.countryCode,
  });

  final String? phone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? region;
  final String? postalCode;

  /// ISO-style two-letter code, or null when unknown.
  final String? countryCode;

  bool get isEmpty =>
      isBlank(phone) &&
      isBlank(addressLine1) &&
      isBlank(addressLine2) &&
      isBlank(city) &&
      isBlank(region) &&
      isBlank(postalCode) &&
      isBlank(countryCode);

  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) =>
      other is AccountContact &&
      other.phone == phone &&
      other.addressLine1 == addressLine1 &&
      other.addressLine2 == addressLine2 &&
      other.city == city &&
      other.region == region &&
      other.postalCode == postalCode &&
      other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(
    phone,
    addressLine1,
    addressLine2,
    city,
    region,
    postalCode,
    countryCode,
  );

  /// Redacted on purpose: contacts must not reach logs or error reporting.
  @override
  String toString() =>
      'AccountContact(phone: ${isBlank(phone) ? 'absent' : 'present'}, '
      'address: ${isBlank(addressLine1) && isBlank(addressLine2) && isBlank(city) && isBlank(region) && isBlank(postalCode) && isBlank(countryCode) ? 'absent' : 'present'})';
}

/// A private contact row with its own server revision and timestamps.
class PrivateContactRecord {
  PrivateContactRecord({
    required String userId,
    required this.contact,
    required this.stamp,
  }) : userId = requireNonBlank(userId, 'userId');

  /// Auth identity id that owns this contact row.
  final String userId;

  final AccountContact contact;

  /// Server-owned revision and timestamps from `profile_contacts`.
  final RecordStamp stamp;

  PrivateContactRecord copyWith({AccountContact? contact, RecordStamp? stamp}) {
    return PrivateContactRecord(
      userId: userId,
      contact: contact ?? this.contact,
      stamp: stamp ?? this.stamp,
    );
  }

  @override
  String toString() =>
      'PrivateContactRecord($userId, revision: ${stamp.revision})';
}

/// Patch-style contact update matching `contact.update`.
///
/// Omitted fields keep their value; [PatchClear] sends JSON null; [PatchSet]
/// sends a value. The server owns the resulting revision and never returns
/// contact values in the acknowledgement.
class UpdateContactCommand {
  UpdateContactCommand({
    required this.expectedRevision,
    this.phone = const PatchKeep<String>(),
    this.addressLine1 = const PatchKeep<String>(),
    this.addressLine2 = const PatchKeep<String>(),
    this.city = const PatchKeep<String>(),
    this.region = const PatchKeep<String>(),
    this.postalCode = const PatchKeep<String>(),
    this.countryCode = const PatchKeep<String>(),
    required String idempotencyKey,
  }) : idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    _validatePatchLength(phone, accountPhoneMaxLength, 'phone');
    _validatePatchLength(
      addressLine1,
      accountAddressLineMaxLength,
      'addressLine1',
    );
    _validatePatchLength(
      addressLine2,
      accountAddressLineMaxLength,
      'addressLine2',
    );
    _validatePatchLength(city, accountCityMaxLength, 'city');
    _validatePatchLength(region, accountRegionMaxLength, 'region');
    _validatePatchLength(postalCode, accountPostalCodeMaxLength, 'postalCode');
    if (countryCode is PatchSet<String>) {
      _requireCountryCode((countryCode as PatchSet<String>).value);
    }
  }

  final int expectedRevision;
  final Patch<String> phone;
  final Patch<String> addressLine1;
  final Patch<String> addressLine2;
  final Patch<String> city;
  final Patch<String> region;
  final Patch<String> postalCode;
  final Patch<String> countryCode;
  final String idempotencyKey;
}

/// Minimal `contact.update` acknowledgement: revision only, no contact data.
class ContactUpdateResult {
  ContactUpdateResult({required this.revision}) {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final int revision;

  @override
  String toString() => 'ContactUpdateResult(revision: $revision)';
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

void _requireCountryCode(String? value) {
  if (value != null && !_countryCodePattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'countryCode',
      'must be two uppercase letters',
    );
  }
}

void _validatePatchLength(Patch<String> patch, int max, String field) {
  if (patch is PatchSet<String>) {
    _requireMaxLength(patch.value, max, field);
  }
}
