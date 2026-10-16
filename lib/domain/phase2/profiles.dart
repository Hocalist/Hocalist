/// Buyer and seller profile contracts for Phase 2.
///
/// Identity model: a Hocalist profile is linked to a real authenticated
/// identity (`userId`) plus a Hocalist membership. Role, membership status,
/// verification state and plan access are server-owned and read-only here;
/// profile update commands cannot grant admin, verified or paid privileges
/// (SEC-03).
///
/// Private fields (email, phone, exact address) live on the private profile
/// record and are excluded from [PublicProfileProjection] by construction
/// (SEC-06).
library;

import 'common.dart';

enum HocalistRole { buyer, seller }

enum MembershipStatus { pending, active, restricted, disabled }

enum VerificationState {
  notStarted,
  submitted,
  pendingReview,
  actionRequired,
  verified,
  rejected,
}

/// Server-owned link between an authenticated identity and one Hocalist role.
///
/// The SQL draft stores one membership per identity and role
/// (`UNIQUE (user_id, role)`), so an identity can hold a buyer membership and a
/// seller membership at the same time. Always read a membership by its own
/// [membershipId] or by an explicit [role]; never by user id alone and never
/// by picking the first row.
///
/// There is deliberately no `copyWith`: clients never assign membership state.
class MembershipRecord {
  MembershipRecord({
    required String membershipId,
    required String userId,
    required this.role,
    required this.status,
    required this.stamp,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId'),
       userId = requireNonBlank(userId, 'userId');

  /// Membership row id. This is also the domain profile id used by
  /// [BuyerProfile.id] and [SellerProfile.id].
  final String membershipId;

  /// Supabase Auth identity identifier (project-wide, shared with Postaneur).
  final String userId;

  final HocalistRole role;
  final MembershipStatus status;

  /// Server-owned revision and timestamps from the membership row.
  final RecordStamp stamp;

  @override
  String toString() =>
      'MembershipRecord($membershipId, role: ${role.name}, '
      'status: ${status.name}, revision: ${stamp.revision})';
}

/// Server-owned privileges and entitlements for one membership.
///
/// Scope is the membership, not the account: a buyer and seller membership on
/// one identity can carry different verification or plan state. [planCode] and
/// [planLabel] are opaque here; seller subscription, credit and earned-benefit
/// policy is a separate future contract and is not modelled.
class MembershipPrivileges {
  MembershipPrivileges({
    required String membershipId,
    required this.role,
    required this.isPlatformAdmin,
    required this.identityVerification,
    required this.businessVerification,
    this.planCode,
    this.planLabel,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId');

  /// Membership row id this privilege snapshot belongs to.
  final String membershipId;

  /// Role of the scoped membership.
  final HocalistRole role;

  final bool isPlatformAdmin;
  final VerificationState identityVerification;
  final VerificationState businessVerification;

  /// Opaque server plan identifier, for example a seller plan code.
  final String? planCode;

  /// Display label for the current plan, supplied by the backend.
  final String? planLabel;

  @override
  String toString() =>
      'MembershipPrivileges($membershipId, ${role.name}, '
      'admin: $isPlatformAdmin, '
      'identity: ${identityVerification.name}, '
      'business: ${businessVerification.name}, plan: $planCode)';
}

/// Private contact and address values composed for the owner's profile read.
///
/// [email] comes from Supabase Auth and is read-only; it is not a writable
/// contact column. Phone and address values map to the identity-scoped
/// `hocalist.profile_contacts` row and are updated through the account
/// contact boundary (`AccountRepository`/`UpdateContactCommand`), not through
/// profile commands.
class PrivateContactDetails {
  const PrivateContactDetails({
    this.email,
    this.phone,
    this.address = const PostalAddress(),
  });

  /// Account email. Changing it requires account verification, so it is not
  /// part of any profile update command.
  final String? email;

  final String? phone;
  final PostalAddress address;

  @override
  bool operator ==(Object other) =>
      other is PrivateContactDetails &&
      other.email == email &&
      other.phone == phone &&
      other.address == address;

  @override
  int get hashCode => Object.hash(email, phone, address);

  /// Redacted on purpose: contacts and addresses must not reach logs or
  /// error reporting. Presence flags keep debugging useful.
  @override
  String toString() =>
      'PrivateContactDetails(email: ${isBlank(email) ? 'absent' : 'present'}, '
      'phone: ${isBlank(phone) ? 'absent' : 'present'}, '
      'address: ${address.isEmpty ? 'absent' : 'present'})';
}

/// Server-derived reputation aggregate. Integer sums avoid stored floats.
class ReputationSummary {
  ReputationSummary({
    required int ratingSum,
    required int ratingCount,
    required int completedDeals,
    int? responseRatePercent,
  }) : ratingSum = ratingSum,
       ratingCount = ratingCount,
       completedDeals = completedDeals,
       responseRatePercent = responseRatePercent {
    if (ratingSum < 0 || ratingCount < 0 || completedDeals < 0) {
      throw ArgumentError('reputation counters must not be negative');
    }
    if (ratingCount == 0 && ratingSum != 0) {
      throw ArgumentError('ratingSum requires at least one rating');
    }
    if (responseRatePercent != null &&
        (responseRatePercent < 0 || responseRatePercent > 100)) {
      throw ArgumentError.value(
        responseRatePercent,
        'responseRatePercent',
        'must be between 0 and 100',
      );
    }
  }

  static const ReputationSummary empty = ReputationSummary._empty();

  const ReputationSummary._empty()
    : ratingSum = 0,
      ratingCount = 0,
      completedDeals = 0,
      responseRatePercent = null;

  final int ratingSum;
  final int ratingCount;
  final int completedDeals;
  final int? responseRatePercent;

  /// Average rating for display, derived from the stored integer sum.
  double? get averageRating =>
      ratingCount == 0 ? null : ratingSum / ratingCount;

  @override
  bool operator ==(Object other) =>
      other is ReputationSummary &&
      other.ratingSum == ratingSum &&
      other.ratingCount == ratingCount &&
      other.completedDeals == completedDeals &&
      other.responseRatePercent == responseRatePercent;

  @override
  int get hashCode =>
      Object.hash(ratingSum, ratingCount, completedDeals, responseRatePercent);

  @override
  String toString() =>
      'ReputationSummary(ratingSum: $ratingSum, ratingCount: $ratingCount, '
      'completedDeals: $completedDeals)';
}

/// The public view of a profile shown to the other marketplace side.
///
/// Contains no email, phone, exact address or verification documents. Exact
/// meeting addresses are shared through the meeting contract instead.
class PublicProfileProjection {
  PublicProfileProjection({
    required String profileId,
    required String userId,
    required this.role,
    required String displayName,
    String? profilePhotoMediaId,
    this.areaLabel,
    this.bio,
    List<String> categoryLabels = const [],
    this.serviceRadiusMiles,
    this.pickupAvailability,
    this.reputation = ReputationSummary.empty,
    this.verificationState = VerificationState.notStarted,
  }) : profileId = requireNonBlank(profileId, 'profileId'),
       userId = requireNonBlank(userId, 'userId'),
       displayName = requireNonBlank(displayName, 'displayName'),
       profilePhotoMediaId = optionalNonBlank(
         profilePhotoMediaId,
         'profilePhotoMediaId',
       ),
       categoryLabels = List<String>.unmodifiable(categoryLabels) {
    if (serviceRadiusMiles != null && serviceRadiusMiles! < 0) {
      throw ArgumentError.value(
        serviceRadiusMiles,
        'serviceRadiusMiles',
        'must not be negative',
      );
    }
  }

  final String profileId;
  final String userId;
  final HocalistRole role;
  final String displayName;
  final String? profilePhotoMediaId;

  /// Approximate area only, for example `Yonkers, NY`.
  final String? areaLabel;

  /// Public profile note.
  final String? bio;

  final List<String> categoryLabels;
  final int? serviceRadiusMiles;
  final String? pickupAvailability;
  final ReputationSummary reputation;
  final VerificationState verificationState;

  @override
  String toString() =>
      'PublicProfileProjection($profileId, ${role.name}, $displayName, '
      'area: $areaLabel, verification: ${verificationState.name})';
}

/// Private buyer profile record.
class BuyerProfile {
  BuyerProfile({
    required String id,
    required String userId,
    required String displayName,
    String? profilePhotoMediaId,
    this.homeAreaLabel,
    this.preferredMeetupType,
    this.profileNote,
    this.contact = const PrivateContactDetails(),
    required this.stamp,
  }) : id = requireNonBlank(id, 'id'),
       userId = requireNonBlank(userId, 'userId'),
       displayName = requireNonBlank(displayName, 'displayName'),
       profilePhotoMediaId = optionalNonBlank(
         profilePhotoMediaId,
         'profilePhotoMediaId',
       );

  final String id;
  final String userId;
  final String displayName;
  final String? profilePhotoMediaId;

  /// Approximate public area, for example `Yonkers, NY`.
  final String? homeAreaLabel;

  final String? preferredMeetupType;
  final String? profileNote;
  final PrivateContactDetails contact;
  final RecordStamp stamp;

  BuyerProfile copyWith({
    String? displayName,
    String? profilePhotoMediaId,
    bool clearProfilePhoto = false,
    String? homeAreaLabel,
    String? preferredMeetupType,
    String? profileNote,
    PrivateContactDetails? contact,
    RecordStamp? stamp,
  }) {
    if (clearProfilePhoto && profilePhotoMediaId != null) {
      throw ArgumentError(
        'profilePhotoMediaId and clearProfilePhoto are mutually exclusive',
      );
    }
    return BuyerProfile(
      id: id,
      userId: userId,
      displayName: displayName ?? this.displayName,
      profilePhotoMediaId: clearProfilePhoto
          ? null
          : (profilePhotoMediaId ?? this.profilePhotoMediaId),
      homeAreaLabel: homeAreaLabel ?? this.homeAreaLabel,
      preferredMeetupType: preferredMeetupType ?? this.preferredMeetupType,
      profileNote: profileNote ?? this.profileNote,
      contact: contact ?? this.contact,
      stamp: stamp ?? this.stamp,
    );
  }

  PublicProfileProjection toPublicProjection() {
    return PublicProfileProjection(
      profileId: id,
      userId: userId,
      role: HocalistRole.buyer,
      displayName: displayName,
      profilePhotoMediaId: profilePhotoMediaId,
      areaLabel: homeAreaLabel,
      bio: profileNote,
    );
  }

  @override
  String toString() => 'BuyerProfile($id, $displayName, area: $homeAreaLabel)';
}

/// Private seller profile record.
class SellerProfile {
  SellerProfile({
    required String id,
    required String userId,
    required String displayName,
    String? profilePhotoMediaId,
    List<String> categoryLabels = const [],
    this.serviceAreaLabel,
    this.serviceRadiusMiles,
    this.pickupAvailability,
    this.profileNote,
    this.contact = const PrivateContactDetails(),
    required this.stamp,
  }) : id = requireNonBlank(id, 'id'),
       userId = requireNonBlank(userId, 'userId'),
       displayName = requireNonBlank(displayName, 'displayName'),
       profilePhotoMediaId = optionalNonBlank(
         profilePhotoMediaId,
         'profilePhotoMediaId',
       ),
       categoryLabels = List<String>.unmodifiable(categoryLabels) {
    if (serviceRadiusMiles != null && serviceRadiusMiles! < 0) {
      throw ArgumentError.value(
        serviceRadiusMiles,
        'serviceRadiusMiles',
        'must not be negative',
      );
    }
  }

  final String id;
  final String userId;
  final String displayName;
  final String? profilePhotoMediaId;
  final List<String> categoryLabels;
  final String? serviceAreaLabel;
  final int? serviceRadiusMiles;
  final String? pickupAvailability;
  final String? profileNote;
  final PrivateContactDetails contact;
  final RecordStamp stamp;

  SellerProfile copyWith({
    String? displayName,
    String? profilePhotoMediaId,
    bool clearProfilePhoto = false,
    List<String>? categoryLabels,
    String? serviceAreaLabel,
    int? serviceRadiusMiles,
    String? pickupAvailability,
    String? profileNote,
    PrivateContactDetails? contact,
    RecordStamp? stamp,
  }) {
    if (clearProfilePhoto && profilePhotoMediaId != null) {
      throw ArgumentError(
        'profilePhotoMediaId and clearProfilePhoto are mutually exclusive',
      );
    }
    return SellerProfile(
      id: id,
      userId: userId,
      displayName: displayName ?? this.displayName,
      profilePhotoMediaId: clearProfilePhoto
          ? null
          : (profilePhotoMediaId ?? this.profilePhotoMediaId),
      categoryLabels: categoryLabels ?? this.categoryLabels,
      serviceAreaLabel: serviceAreaLabel ?? this.serviceAreaLabel,
      serviceRadiusMiles: serviceRadiusMiles ?? this.serviceRadiusMiles,
      pickupAvailability: pickupAvailability ?? this.pickupAvailability,
      profileNote: profileNote ?? this.profileNote,
      contact: contact ?? this.contact,
      stamp: stamp ?? this.stamp,
    );
  }

  PublicProfileProjection toPublicProjection() {
    return PublicProfileProjection(
      profileId: id,
      userId: userId,
      role: HocalistRole.seller,
      displayName: displayName,
      profilePhotoMediaId: profilePhotoMediaId,
      areaLabel: serviceAreaLabel,
      bio: profileNote,
      categoryLabels: categoryLabels,
      serviceRadiusMiles: serviceRadiusMiles,
      pickupAvailability: pickupAvailability,
    );
  }

  @override
  String toString() =>
      'SellerProfile($id, $displayName, area: $serviceAreaLabel)';
}

/// Account-level notification preferences. Device permission and token state
/// is separate and lives with the notification service contract (SEC-15).
class NotificationPreferences {
  const NotificationPreferences({
    this.offers = true,
    this.messages = true,
    this.deals = true,
    this.leads = true,
    this.safety = true,
  });

  static const NotificationPreferences defaults = NotificationPreferences();

  final bool offers;
  final bool messages;
  final bool deals;

  /// Lead and lead-update alerts. Only sent to a server that exposes the
  /// `leads` preference; older servers keep their previous payload.
  final bool leads;
  final bool safety;

  NotificationPreferences copyWith({
    bool? offers,
    bool? messages,
    bool? deals,
    bool? leads,
    bool? safety,
  }) {
    return NotificationPreferences(
      offers: offers ?? this.offers,
      messages: messages ?? this.messages,
      deals: deals ?? this.deals,
      leads: leads ?? this.leads,
      safety: safety ?? this.safety,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.offers == offers &&
      other.messages == messages &&
      other.deals == deals &&
      other.leads == leads &&
      other.safety == safety;

  @override
  int get hashCode => Object.hash(offers, messages, deals, leads, safety);

  @override
  String toString() =>
      'NotificationPreferences(offers: $offers, messages: $messages, '
      'deals: $deals, leads: $leads, safety: $safety)';
}

/// Complete buyer profile update for the future full profile contract.
///
/// Carries the editable role-profile field values. Contact values are
/// deliberately excluded: the SQL draft stores contacts per identity with
/// their own revision, so they use [UpdateContactCommand] instead of being
/// bundled under the profile revision.
class UpdateBuyerProfileCommand {
  UpdateBuyerProfileCommand({
    required String profileId,
    required this.expectedRevision,
    required String displayName,
    String? profilePhotoMediaId,
    this.clearProfilePhoto = false,
    this.homeAreaLabel,
    this.preferredMeetupType,
    this.profileNote,
    required String idempotencyKey,
  }) : profileId = requireNonBlank(profileId, 'profileId'),
       displayName = requireNonBlank(displayName, 'displayName'),
       profilePhotoMediaId = optionalNonBlank(
         profilePhotoMediaId,
         'profilePhotoMediaId',
       ),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    if (clearProfilePhoto && profilePhotoMediaId != null) {
      throw ArgumentError(
        'clearProfilePhoto and profilePhotoMediaId are mutually exclusive',
      );
    }
  }

  final String profileId;
  final int expectedRevision;
  final String displayName;
  final String? profilePhotoMediaId;
  final bool clearProfilePhoto;
  final String? homeAreaLabel;
  final String? preferredMeetupType;
  final String? profileNote;
  final String idempotencyKey;
}

/// Complete seller profile update. Carries every editable field value.
class UpdateSellerProfileCommand {
  UpdateSellerProfileCommand({
    required String profileId,
    required this.expectedRevision,
    required String displayName,
    String? profilePhotoMediaId,
    this.clearProfilePhoto = false,
    List<String> categoryLabels = const [],
    this.serviceAreaLabel,
    this.serviceRadiusMiles,
    this.pickupAvailability,
    this.profileNote,
    required String idempotencyKey,
  }) : profileId = requireNonBlank(profileId, 'profileId'),
       displayName = requireNonBlank(displayName, 'displayName'),
       profilePhotoMediaId = optionalNonBlank(
         profilePhotoMediaId,
         'profilePhotoMediaId',
       ),
       categoryLabels = List<String>.unmodifiable(categoryLabels),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    if (clearProfilePhoto && profilePhotoMediaId != null) {
      throw ArgumentError(
        'clearProfilePhoto and profilePhotoMediaId are mutually exclusive',
      );
    }
    if (serviceRadiusMiles != null && serviceRadiusMiles! < 0) {
      throw ArgumentError.value(
        serviceRadiusMiles,
        'serviceRadiusMiles',
        'must not be negative',
      );
    }
  }

  final String profileId;
  final int expectedRevision;
  final String displayName;
  final String? profilePhotoMediaId;
  final bool clearProfilePhoto;
  final List<String> categoryLabels;
  final String? serviceAreaLabel;
  final int? serviceRadiusMiles;
  final String? pickupAvailability;
  final String? profileNote;
  final String idempotencyKey;
}

/// Complete account-level notification preference update.
class UpdateNotificationPreferencesCommand {
  UpdateNotificationPreferencesCommand({
    required String userId,
    required this.preferences,
    required String idempotencyKey,
  }) : userId = requireNonBlank(userId, 'userId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final String userId;
  final NotificationPreferences preferences;
  final String idempotencyKey;
}
