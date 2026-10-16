/// Asynchronous repository contracts for the Phase 2 marketplace.
///
/// These interfaces describe what the existing buyer and seller screens need
/// to read and change. They contain no network, database, provider or cache
/// implementation and they do not decide server policy.
///
/// Rules these contracts preserve:
/// - Commands carry complete editable field values plus the identifiers and
///   expected revisions needed for stale-write and idempotency handling.
/// - Server-owned results (status, revision, timestamps, verification,
///   completion, PIN outcomes) are returned, never accepted from clients.
/// - A client-side validation check is advisory; the server re-validates and
///   authorization is enforced by RLS/API policy (SEC-03, SEC-05, SEC-08).
/// - Failures are typed so screens can show retry, conflict, not-found and
///   permission-denied states without parsing strings.
library;

import 'catalogue.dart';
import 'common.dart';
import 'conversations.dart';
import 'failures.dart';
import 'meetings.dart';
import 'offers.dart';
import 'profiles.dart';
import 'requests.dart';
import 'store_listings.dart';

/// Profile, membership and preference reads and updates.
///
/// Supports signup/profile screens, buyer and seller edit-profile pages,
/// settings, public profile pages and notification preferences.
///
/// Membership scope rules (draft SQL: one membership per identity and role):
/// - Read the collection with [fetchMemberships] to render role/status UI.
/// - Read one role explicitly with [fetchMembership]; never pick the first
///   list row and never treat a user id as a role.
/// - Privileges are scoped to one [MembershipRecord.membershipId].
/// - The authenticated session supplies identity; caller-provided ids are
///   never proof of authorization (SEC-03).
///
/// This is the full future contract. The SQL-draft-backed subset (membership
/// and role-profile reads, identity-scoped contacts, `onboard`,
/// `profile.update`, `contact.update`) is implemented by `AccountRepository`
/// in `accounts.dart`; contact reads/writes live there, not here, because the
/// draft stores contacts per identity with their own revision.
abstract interface class ProfileRepository {
  /// All memberships for the authenticated identity, ordered by role.
  ///
  /// Returns every status (pending/active/restricted/disabled) so status UI
  /// can render restrictions. Empty when the identity has no Hocalist
  /// membership yet.
  Future<RepositoryResult<List<MembershipRecord>>> fetchMemberships({
    required String userId,
  });

  /// The membership for one explicit role, or [NotFoundError] when the
  /// identity has no membership for that role.
  Future<RepositoryResult<MembershipRecord>> fetchMembership({
    required String userId,
    required HocalistRole role,
  });

  /// Server-owned privileges for one membership, including admin flag,
  /// verification and plan access.
  Future<RepositoryResult<MembershipPrivileges>> fetchMembershipPrivileges({
    required String membershipId,
  });

  /// Private buyer profile, including contact details for the owner only.
  ///
  /// The method name fixes the role, so [userId] resolves to at most one
  /// buyer membership. [BuyerProfile.id] is that membership id; the server
  /// returns [NotFoundError] or [PermissionDeniedError] for a missing or
  /// non-active buyer membership.
  Future<RepositoryResult<BuyerProfile>> fetchBuyerProfile({
    required String userId,
  });

  /// Private seller profile, including contact details for the owner only.
  ///
  /// The method name fixes the role, so [userId] resolves to at most one
  /// seller membership. [SellerProfile.id] is that membership id; the server
  /// returns [NotFoundError] or [PermissionDeniedError] for a missing or
  /// non-active seller membership.
  Future<RepositoryResult<SellerProfile>> fetchSellerProfile({
    required String userId,
  });

  /// Public projection of a profile. Never includes private contacts,
  /// addresses or verification documents (SEC-06).
  Future<RepositoryResult<PublicProfileProjection>> fetchPublicProfile({
    required String profileId,
  });

  Future<RepositoryResult<BuyerProfile>> updateBuyerProfile(
    UpdateBuyerProfileCommand command,
  );

  Future<RepositoryResult<SellerProfile>> updateSellerProfile(
    UpdateSellerProfileCommand command,
  );

  Future<RepositoryResult<NotificationPreferences>>
  fetchNotificationPreferences({required String userId});

  Future<RepositoryResult<NotificationPreferences>>
  updateNotificationPreferences(UpdateNotificationPreferencesCommand command);
}

/// Buyer request reads and commands.
///
/// Supports the buyer dashboard, request detail/edit, create-request flow and
/// deal recovery.
abstract interface class RequestRepository {
  /// Buyer-owned requests, newest first, bounded by [page].
  Future<RepositoryResult<PageSlice<MarketplaceRequest>>> fetchBuyerRequests({
    required String buyerUserId,
    RequestStatus? status,
    PageQuery page = PageQuery.standard,
  });

  Future<RepositoryResult<MarketplaceRequest>> fetchRequest({
    required String requestId,
  });

  /// Seller-visible lead projections for the Leads screen.
  ///
  /// Returns [SellerLeadProjection] rows that exclude the buyer's exact
  /// address, contact details and every other seller's offers. Eligibility,
  /// filtering, ranking and visibility are server policy; the query only
  /// carries the seller's selected filters. A null [query] means the default
  /// unfiltered page.
  Future<RepositoryResult<PageSlice<SellerLeadProjection>>> fetchSellerLeads({
    required String sellerUserId,
    SellerLeadQuery? query,
  });

  Future<RepositoryResult<MarketplaceRequest>> createRequest(
    CreateRequestCommand command,
  );

  Future<RepositoryResult<MarketplaceRequest>> updateRequest(
    UpdateRequestCommand command,
  );

  Future<RepositoryResult<MarketplaceRequest>> closeRequest(
    CloseRequestCommand command,
  );

  /// Reopens a request. Backup-seller and reservation policy stays server-side
  /// and is an unresolved decision, not a client rule.
  Future<RepositoryResult<MarketplaceRequest>> reopenRequest(
    ReopenRequestCommand command,
  );
}

/// Seller offer reads and commands.
///
/// Supports the seller leads/offer sheet, offer history and detail, the buyer
/// offers-received list and the buyer offer detail.
abstract interface class OfferRepository {
  /// Every offer for one request, so concurrent sellers are all visible.
  Future<RepositoryResult<PageSlice<Offer>>> fetchRequestOffers({
    required String requestId,
    PageQuery page = PageQuery.standard,
  });

  /// Every offer sent by one seller, with status and revision history.
  Future<RepositoryResult<PageSlice<Offer>>> fetchSellerOffers({
    required String sellerUserId,
    PageQuery page = PageQuery.standard,
  });

  Future<RepositoryResult<Offer>> fetchOffer({required String offerId});

  Future<RepositoryResult<Offer>> submitOffer(SubmitOfferCommand command);

  Future<RepositoryResult<Offer>> reviseOffer(ReviseOfferCommand command);

  Future<RepositoryResult<Offer>> withdrawOffer(WithdrawOfferCommand command);

  /// Buyer selects an offer revision. Stale or duplicate selections return a
  /// [ConflictError] rather than creating a second accepted deal silently.
  /// Several offers may be selected; each keeps its own conversation/meeting.
  Future<RepositoryResult<Offer>> selectOffer(SelectOfferCommand command);

  /// Buyer designates one already accepted offer as the final purchase. Only
  /// the designated seller can complete the request PIN, and the server
  /// enforces at most one successful purchase per request.
  Future<RepositoryResult<Offer>> selectPurchaseOffer(
    SelectPurchaseCommand command,
  );
}

/// Conversation, member and message reads and commands.
///
/// Supports buyer and seller chat lists and the shared conversation body,
/// including search, mute and read markers.
abstract interface class ConversationRepository {
  /// Participant-owned inbox rows for one user, bounded by [page].
  Future<RepositoryResult<PageSlice<ConversationSummary>>> fetchInbox({
    required String userId,
    PageQuery page = PageQuery.standard,
  });

  Future<RepositoryResult<Conversation>> fetchConversation({
    required String conversationId,
  });

  /// Paged message history, oldest-to-newest within the page.
  Future<RepositoryResult<PageSlice<ConversationMessage>>> fetchMessages({
    required String conversationId,
    PageQuery page = PageQuery.standard,
    String? beforeMessageId,
  });

  Future<RepositoryResult<ConversationMessage>> sendMessage(
    SendMessageCommand command,
  );

  Future<RepositoryResult<ConversationMember>> markConversationRead(
    MarkConversationReadCommand command,
  );

  Future<RepositoryResult<ConversationMember>> setConversationMuted(
    SetConversationMutedCommand command,
  );

  /// Opens (or returns) the deal conversation for a selected request offer.
  Future<RepositoryResult<Conversation>> openTargetedRequestConversation(
    OpenTargetedRequestConversationCommand command,
  );

  /// Opens a Store or Hocatrends enquiry conversation without deal fees.
  Future<RepositoryResult<Conversation>> openDiscoveryEnquiry(
    OpenDiscoveryEnquiryCommand command,
  );
}

/// Meeting, reschedule and PIN commands.
///
/// Supports the buyer meeting-details screen, the seller meets list, the
/// reschedule dialog and the seller PIN entry sheet.
abstract interface class MeetingRepository {
  /// Meetings visible to one participant, optionally filtered by status.
  Future<RepositoryResult<PageSlice<Meeting>>> fetchMeetingsForParticipant({
    required String userId,
    MeetingStatus? status,
    PageQuery page = PageQuery.standard,
  });

  Future<RepositoryResult<Meeting>> fetchMeeting({required String meetingId});

  Future<RepositoryResult<Meeting>> confirmMeeting(
    ConfirmMeetingCommand command,
  );

  Future<RepositoryResult<Meeting>> proposeReschedule(
    ProposeRescheduleCommand command,
  );

  Future<RepositoryResult<Meeting>> respondToReschedule(
    RespondToRescheduleCommand command,
  );

  Future<RepositoryResult<Meeting>> cancelMeeting(CancelMeetingCommand command);

  /// Returns the buyer's display PIN for one accepted meeting.
  ///
  /// Restricted to the authenticated buyer participant. The returned
  /// [BuyerPinDisplay] is transient: the client must not persist, cache or
  /// log it, and the code is never part of general meeting reads. The server
  /// re-checks participation, accepted schedule, PIN status and expiry on
  /// every call. PIN generation and validation are not implemented here.
  Future<RepositoryResult<BuyerPinDisplay>> fetchBuyerPinForMeeting({
    required String meetingId,
    required String buyerUserId,
  });

  /// Submits the buyer-shown PIN for server verification.
  ///
  /// The server binds the PIN to the request and eligible seller, enforces
  /// attempt limits and expiry, and records one successful verification.
  /// Opening a review or success screen never completes the deal (SEC-12,
  /// SEC-13).
  Future<RepositoryResult<PinVerificationOutcome>> submitPin(
    SubmitPinCommand command,
  );
}

/// Admin-managed catalogue reads and commands.
///
/// Ordinary app reads return active entries. [includeRetired] is honored only
/// for authorized admin callers; retired entries stay readable so historical
/// requests and listings keep their category meaning.
abstract interface class CatalogueRepository {
  /// Categories for the request and Store forms.
  Future<RepositoryResult<PageSlice<CatalogueCategory>>> fetchCategories({
    CatalogueScope? scope,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  });

  /// Option groups inside one category, ordered by `sortOrder`.
  Future<RepositoryResult<PageSlice<CatalogueOptionGroup>>> fetchOptionGroups({
    required String categoryId,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  });

  /// Options inside one option group, ordered by `sortOrder`.
  Future<RepositoryResult<PageSlice<CatalogueOption>>> fetchOptions({
    required String groupId,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  });

  /// Admin-managed locations for request and Store forms.
  ///
  /// Ordinary reads return active locations. [includeRetired] is honored only
  /// for authorized admin callers.
  Future<RepositoryResult<PageSlice<LocationEntry>>> fetchLocations({
    String? countryCode,
    bool includeRetired = false,
    PageQuery page = PageQuery.standard,
  });

  Future<RepositoryResult<CatalogueCategory>> createCategory(
    CreateCatalogueCategoryCommand command,
  );

  Future<RepositoryResult<CatalogueCategory>> updateCategory(
    UpdateCatalogueCategoryCommand command,
  );

  Future<RepositoryResult<CatalogueOptionGroup>> createOptionGroup(
    CreateCatalogueOptionGroupCommand command,
  );

  Future<RepositoryResult<CatalogueOptionGroup>> updateOptionGroup(
    UpdateCatalogueOptionGroupCommand command,
  );

  Future<RepositoryResult<CatalogueOption>> createOption(
    CreateCatalogueOptionCommand command,
  );

  Future<RepositoryResult<CatalogueOption>> updateOption(
    UpdateCatalogueOptionCommand command,
  );

  /// Activates or retires a category, option group or option.
  Future<RepositoryResult<CatalogueEntryStatusResult>> setEntryStatus(
    SetCatalogueEntryStatusCommand command,
  );
}

/// Seller Store listing reads and commands.
///
/// Ownership, publication, moderation and plan-limit checks are server
/// decisions. Public reads only ever return published and approved listings.
abstract interface class StoreListingRepository {
  /// Owner listings for the Store manager, filtered and paged server-side.
  Future<RepositoryResult<PageSlice<StoreListing>>> fetchSellerListings({
    required String sellerUserId,
    ListingKind? kind,
    ListingStatus? status,
    String? query,
    PageQuery page = PageQuery.standard,
  });

  /// One owner listing. Returns [NotFoundError] for another seller's listing.
  Future<RepositoryResult<StoreListing>> fetchStoreListing({
    required String listingId,
  });

  /// Server-derived counts for the Store manager summary card.
  Future<RepositoryResult<StoreListingSummary>> fetchSellerStoreSummary({
    required String sellerUserId,
  });

  /// Published listings for one seller's public store.
  Future<RepositoryResult<PageSlice<PublicStoreListing>>>
  fetchPublicSellerListings({
    required String sellerProfileId,
    ListingKind? kind,
    PageQuery page = PageQuery.standard,
  });

  /// One published listing projection for a buyer-facing detail view.
  Future<RepositoryResult<PublicStoreListing>> fetchPublicStoreListing({
    required String listingId,
  });

  /// Creates a listing. A plan limit returns [LimitExceededError].
  Future<RepositoryResult<StoreListing>> createStoreListing(
    CreateStoreListingCommand command,
  );

  /// Replaces all editable listing values at an expected revision.
  Future<RepositoryResult<StoreListing>> updateStoreListing(
    UpdateStoreListingCommand command,
  );

  /// Publishes or pauses a listing. The server owns the resulting status and
  /// may return a moderation or limit failure instead.
  Future<RepositoryResult<StoreListing>> setStoreListingPublication(
    SetStoreListingPublicationCommand command,
  );

  /// Archives a listing without deleting its history.
  Future<RepositoryResult<StoreListing>> archiveStoreListing(
    ArchiveStoreListingCommand command,
  );

  /// Creates a draft copy. A plan limit returns [LimitExceededError].
  Future<RepositoryResult<StoreListing>> duplicateStoreListing(
    DuplicateStoreListingCommand command,
  );
}
