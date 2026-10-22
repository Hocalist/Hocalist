import '../domain/phase2/category_answers.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/phase2/conversations.dart';
import '../domain/phase2/common.dart';
import '../domain/phase2/notifications.dart';
import '../domain/phase2/offers.dart';
import '../domain/phase2/profiles.dart';
import '../domain/phase2/requests.dart';
import 'phase2/meetings/meeting_adapter.dart';
import 'phase2/meetings/meeting_codecs.dart';
import 'phase2/marketplace/marketplace_requests_backend.dart';
import 'phase2/marketplace/request_reopen_intent.dart';

/// Backend seam for the seller Leads list.
abstract interface class MarketplaceLeadsBackend {
  Future<List<SellerLeadProjection>> loadLeads();
}

/// Backend seam for real seller offers.
abstract interface class MarketplaceOffersBackend {
  /// Valid named IANA zones supplied by the server for scheduling.
  Future<List<String>> loadTimezones();

  Future<Offer> submitOffer({
    required String requestId,
    required OfferTerms terms,
    required String operationKey,
  });
}

/// Backend seam for real buyer requests.
///
/// Implementations map the approved create/edit form to the marketplace
/// request RPCs. Server-owned status, revision and timestamps are returned,
/// never guessed; every write carries a client-owned operation key so a
/// retried submit stays one intent.
abstract interface class MarketplaceRequestsBackend {
  /// Active catalogue categories for the request form, including retired
  /// entries so an existing request keeps its meaning.
  Future<List<CatalogueCategoryOption>> loadCategories();

  /// Buyer-owned requests, newest first.
  Future<List<MarketplaceRequest>> loadBuyerRequests();

  Future<MarketplaceRequest> createRequest({
    required RequestDraft draft,
    required String operationKey,
  });

  Future<MarketplaceRequest> updateRequest({
    required String requestId,
    required int expectedRevision,
    required RequestDraft draft,
    required String operationKey,
  });

  Future<MarketplaceRequest> closeRequest({
    required String requestId,
    required int expectedRevision,
    required String operationKey,
  });
}

/// Outcome of one real request create/update, safe to show in the form.
class RequestSubmissionResult {
  const RequestSubmissionResult.success(this.request)
    : error = null,
      outcomeUncertain = false;

  const RequestSubmissionResult.failure(
    this.error, {
    this.outcomeUncertain = false,
  }) : request = null;

  final MarketplaceRequest? request;
  final String? error;

  /// True when the network or server outcome is unknown and the request may
  /// have been committed. The caller must retry with the original payload and
  /// operation key, or discard the intent before changing anything.
  final bool outcomeUncertain;

  bool get isSuccess => request != null;
}

/// Backend seam for the buyer offers list and selection.
///
/// The buyer only chooses an offer revision; the server decides eligibility,
/// opens the permitted conversation and owns the resulting status.
abstract interface class MarketplaceBuyerOffersBackend {
  Future<List<Offer>> loadRequestOffers(String requestId);

  /// Selects one offer revision and returns the authoritative offer plus the
  /// conversation opened for it, when the server has one.
  Future<OfferSelectionOutcome> selectOffer({
    required String offerId,
    required String revisionId,
    required int expectedOfferRevision,
    required String operationKey,
  });

  /// Designates one already accepted offer as the buyer's final purchase. Only
  /// that seller can complete the request PIN.
  Future<Offer> selectPurchaseSeller({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  });
}

/// Authoritative result of selecting one offer revision.
class OfferSelectionOutcome {
  const OfferSelectionOutcome({required this.offer, this.conversationId});

  final Offer offer;
  final String? conversationId;
}

/// Outcome of one real offer selection, safe to show on the buyer screens.
class BuyerOfferSelectionResult {
  const BuyerOfferSelectionResult.success(this.offer, {this.conversationId})
    : error = null,
      outcomeUncertain = false;

  const BuyerOfferSelectionResult.failure(
    this.error, {
    this.outcomeUncertain = false,
  }) : offer = null,
       conversationId = null;

  final Offer? offer;
  final String? conversationId;
  final String? error;

  /// True when the network or server outcome is unknown and the selection may
  /// have committed. Retry with the same operation key and payload.
  final bool outcomeUncertain;

  bool get isSuccess => offer != null;
}

/// Outcome of designating the final purchase seller for one request.
class BuyerPurchaseSelectionResult {
  const BuyerPurchaseSelectionResult.success(this.offer)
    : error = null,
      outcomeUncertain = false;

  const BuyerPurchaseSelectionResult.failure(
    this.error, {
    this.outcomeUncertain = false,
  }) : offer = null;

  final Offer? offer;
  final String? error;

  /// True when the outcome is unknown and may have committed; retry with the
  /// same operation key and payload.
  final bool outcomeUncertain;

  bool get isSuccess => offer != null;
}

/// Backend seam for the participant meeting and reschedule foundation.
///
/// PIN issuance and verification are deliberately absent: that transition
/// stays gated on the owner's PIN policy decision.
abstract interface class MarketplaceMeetingsBackend {
  Future<MeetingPageView> loadMeetings({
    String? status,
    String? cursor,
    int limit,
  });

  Future<MeetingView> loadMeeting(String meetingId);

  Future<MeetingView> proposeMeeting({
    required String conversationId,
    required MeetingScheduleInput input,
    required String operationKey,
  });

  Future<MeetingView> respondToMeeting({
    required String meetingId,
    required bool accept,
    required int expectedRevision,
    required String operationKey,
  });

  Future<MeetingView> proposeReschedule({
    required String meetingId,
    required MeetingScheduleInput input,
    required int expectedRevision,
    required String operationKey,
  });

  Future<MeetingView> cancelMeeting({
    required String meetingId,
    required int expectedRevision,
    required String operationKey,
  });
}

/// Outcome of one real meeting action, safe to show on the meeting screens.
class MeetingActionResult {
  const MeetingActionResult.success(this.meeting)
    : error = null,
      outcomeUncertain = false;

  const MeetingActionResult.failure(this.error, {this.outcomeUncertain = false})
    : meeting = null;

  final MeetingView? meeting;
  final String? error;
  final bool outcomeUncertain;

  bool get isSuccess => meeting != null;
}

/// Backend seam for the notification inbox and preferences.
abstract interface class MarketplaceNotificationsBackend {
  Future<NotificationInboxPage> loadInbox({String? cursor, int limit});

  Future<void> markRead(String notificationId);

  Future<int> markAllRead();

  Future<NotificationPreferencesRecord> loadPreferences();

  Future<NotificationPreferencesRecord> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  });
}

/// Outcome of one real notification preference write.
class NotificationPreferencesResult {
  const NotificationPreferencesResult.success(this.record)
    : error = null,
      outcomeUncertain = false;

  const NotificationPreferencesResult.failure(
    this.error, {
    this.outcomeUncertain = false,
  }) : record = null;

  final NotificationPreferencesRecord? record;
  final String? error;
  final bool outcomeUncertain;

  bool get isSuccess => record != null;
}

/// Backend seam for the participant chat inbox and thread.
///
/// The server authorizes participation and owns delivery, read markers and
/// mute state; this seam only carries identifiers and user-safe errors.
abstract interface class MarketplaceChatRequestBackend {
  Future<SellerLeadProjection?> loadConversationRequest(String conversationId);
}

abstract interface class MarketplacePagedChatBackend {
  Future<PageSlice<ConversationMessage>> loadMessagePage(
    String conversationId,
    String? cursor,
  );
}

abstract interface class MarketplaceChatBackend {
  Future<Offer?> loadMeetingOffer(String conversationId);
  Future<List<ConversationSummary>> loadInbox();

  Future<List<ConversationMessage>> loadMessages(String conversationId);

  Future<ConversationMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientMessageId,
  });

  Future<ConversationMember> markRead({
    required String conversationId,
    required String messageId,
  });

  Future<ConversationMember> setMuted({
    required String conversationId,
    required bool muted,
  });
}

/// Optional extension of the chat backend for authorized image attachments.
/// Older chat backends that do not implement it keep attachments visibly
/// unavailable instead of pretending to send. `chatAttachmentsEnabled` is
/// false until the reviewed attachment RPC is deployed.
abstract interface class MarketplaceChatAttachmentBackend {
  bool get chatAttachmentsEnabled;

  Future<ConversationMessage> sendAttachment({
    required String conversationId,
    required String text,
    required List<String> mediaIds,
    required String clientMessageId,
  });
}

/// Backend seam for the seller's own offers: history reads and withdrawal.
abstract interface class MarketplaceSellerOffersBackend {
  Future<List<Offer>> loadSellerOffers();

  Future<Offer> withdrawOffer({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  });
}

/// Optional server revision capability; older prototype/test backends stay valid.
abstract interface class MarketplaceSellerOffersRevisionBackend {
  Future<Offer> reviseOffer({
    required String offerId,
    required int expectedOfferRevision,
    required OfferTerms terms,
    required String operationKey,
  });
}

/// Outcome of one real seller offer action, safe to show on the seller pages.
class SellerOfferActionResult {
  const SellerOfferActionResult.success(this.offer)
    : error = null,
      outcomeUncertain = false;

  const SellerOfferActionResult.failure(
    this.error, {
    this.outcomeUncertain = false,
  }) : offer = null;

  final Offer? offer;
  final String? error;
  final bool outcomeUncertain;

  bool get isSuccess => offer != null;
}

/// Outcome of one real message send, safe to show in the composer.
class ChatSendResult {
  const ChatSendResult.success(this.message)
    : error = null,
      outcomeUncertain = false;

  const ChatSendResult.failure(this.error, {this.outcomeUncertain = false})
    : message = null;

  final ConversationMessage? message;
  final String? error;

  /// True when the outcome is unknown and the send may have committed. Retry
  /// with the same client message id instead of composing a new message.
  final bool outcomeUncertain;

  bool get isSuccess => message != null;
}

/// Outcome of one real offer submission, safe to show in the offer sheet.
class OfferSubmissionResult {
  const OfferSubmissionResult.success(this.offer)
    : error = null,
      ambiguousTime = false,
      outcomeUncertain = false;

  const OfferSubmissionResult.failure(
    this.error, {
    this.ambiguousTime = false,
    this.outcomeUncertain = false,
  }) : offer = null;

  final Offer? offer;
  final String? error;

  /// True when the chosen local time repeats and an occurrence must be picked.
  /// This is a definitive server rejection: nothing was committed, so choosing
  /// the occurrence corrects the same submission.
  final bool ambiguousTime;

  /// True when the network or server outcome is unknown and the offer may have
  /// committed. The caller must retry with the original payload and operation
  /// key, or discard the intent before changing anything.
  final bool outcomeUncertain;

  bool get isSuccess => offer != null;
}

/// Backend seam for the seller Store manager.
///
/// The approved screens keep their synchronous surface; when a backend is
/// attached the repository keeps an optimistic cache and delegates persistence
/// to this interface. Implementations must be identity-aware and must never
/// trust caller-supplied ownership.
abstract interface class MarketplaceStoreBackend {
  Future<List<LocalStoreListing>> loadListings();

  /// Catalogue categories for the Store editor, including retired entries so
  /// a legacy listing keeps its meaning. Empty in prototype mode.
  Future<List<StoreCategoryOption>> loadCategories();

  /// Creates or updates a listing using [listing.revision] as the expected
  /// authoritative revision. [operationKey] is a client-owned idempotency key
  /// that must stay identical across retries of the same intent.
  Future<StoreWriteResult> saveListing(
    LocalStoreListing listing, {
    required String operationKey,
  });

  Future<StoreWriteResult> setListingStatus(
    String listingId,
    LocalListingStatus status, {
    required String operationKey,
    required int expectedRevision,
  });

  Future<StoreWriteResult> duplicateListing(
    String listingId, {
    required String operationKey,
  });

  Future<void> archiveListing(
    String listingId, {
    required String operationKey,
    required int expectedRevision,
  });
}

/// One admin-managed catalogue category as a form needs it.
///
/// The label is a display snapshot; [id] is the identity sent to the server.
class CatalogueCategoryOption {
  const CatalogueCategoryOption({
    required this.id,
    required this.label,
    required this.scope,
    required this.status,
  });

  final String id;
  final String label;

  /// Wire scope: `product`, `service` or `both`.
  final String scope;
  final String status;

  bool get isActive => status == 'active';

  bool get supportsProduct => scope != 'service';

  bool get supportsService => scope != 'product';
}

/// Store-form name for the shared catalogue option value.
typedef StoreCategoryOption = CatalogueCategoryOption;

/// Result of one Store write. [warning] reports a partial success such as a
/// saved listing whose publication change did not apply; the row is persisted
/// but the change is incomplete.
class StoreWriteResult {
  const StoreWriteResult({required this.listing, this.warning});

  final LocalStoreListing listing;
  final String? warning;
}

/// User-safe Store backend failure. Never carries server payloads.
///
/// [ambiguous] marks an outcome that may have committed (timeout, connection
/// loss, server error). Callers must retry with the same operation key and
/// payload instead of starting a new intent.
class StoreBackendException implements Exception {
  const StoreBackendException(
    this.message, {
    this.ambiguous = false,
    this.code,
  });

  final String message;
  final bool ambiguous;

  /// Stable machine code for a typed failure such as `ambiguous_local_time`.
  final String? code;

  @override
  String toString() =>
      'StoreBackendException($message, ambiguous: $ambiguous, code: $code)';
}

enum LocalOfferStatus { sent, selected, meetingConfirmed, completed }

enum LocalListingKind { product, service }

enum LocalListingStatus { active, draft, paused }

@immutable
class LocalStoreListing {
  const LocalStoreListing({
    required this.id,
    required this.kind,
    required this.title,
    required this.priceLabel,
    required this.description,
    required this.category,
    required this.serviceArea,
    required this.availability,
    required this.status,
    this.categoryId,
    this.categoryAnswers = const [],
    this.revision = 0,
    this.pendingReview = false,
    this.rejected = false,
    this.pendingSync = false,
    this.imageAsset,
    this.imageCount = 0,
    this.imageMediaIds = const [],
  });

  factory LocalStoreListing.fromJson(Map<String, Object?> json) {
    return LocalStoreListing(
      id: json['id']! as String,
      kind: LocalListingKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => LocalListingKind.product,
      ),
      title: json['title']! as String,
      priceLabel: json['priceLabel']! as String,
      description: (json['description'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'Other',
      serviceArea: (json['serviceArea'] as String?) ?? '',
      availability: (json['availability'] as String?) ?? '',
      status: LocalListingStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => LocalListingStatus.draft,
      ),
      categoryId: json['categoryId'] as String?,
      categoryAnswers: CategoryAnswer.decode(json['categoryAnswers']),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      pendingReview: (json['pendingReview'] as bool?) ?? false,
      rejected: (json['rejected'] as bool?) ?? false,
      pendingSync: (json['pendingSync'] as bool?) ?? false,
      imageAsset: json['imageAsset'] as String?,
      imageCount: (json['imageCount'] as num?)?.toInt() ?? 0,
      imageMediaIds: List<String>.unmodifiable(
        (json['imageMediaIds'] as List?)?.cast<String>() ?? const <String>[],
      ),
    );
  }

  final String id;
  final LocalListingKind kind;
  final String title;
  final String priceLabel;
  final String description;

  /// Category display snapshot. A label is never an identity.
  final String category;

  /// Authoritative catalogue category id in real mode, or null for legacy
  /// free-text prototype records. Never derived from the label.
  final String? categoryId;
  final List<CategoryAnswer> categoryAnswers;

  /// Authoritative server revision in real mode; 0 when unknown.
  final int revision;

  /// True while the server moderation decision is still pending. A pending
  /// listing is not publicly visible even when its status is active.
  final bool pendingReview;

  /// Rejected listings remain private even when publication was requested.
  final bool rejected;

  /// True while a real-mode write is still in flight or its outcome is
  /// ambiguous. Pending rows are never described as persisted.
  final bool pendingSync;

  final String serviceArea;
  final String availability;
  final LocalListingStatus status;
  final String? imageAsset;
  final int imageCount;
  final List<String> imageMediaIds;

  /// True only when the server has approved the listing and it is active.
  bool get isPubliclyVisible =>
      status == LocalListingStatus.active && !pendingReview && !rejected;

  LocalStoreListing copyWith({
    String? id,
    LocalListingKind? kind,
    String? title,
    String? priceLabel,
    String? description,
    String? category,
    String? categoryId,
    List<CategoryAnswer>? categoryAnswers,
    int? revision,
    bool? pendingReview,
    bool? rejected,
    bool? pendingSync,
    String? serviceArea,
    String? availability,
    LocalListingStatus? status,
    String? imageAsset,
    int? imageCount,
    List<String>? imageMediaIds,
  }) {
    return LocalStoreListing(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      priceLabel: priceLabel ?? this.priceLabel,
      description: description ?? this.description,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      categoryAnswers: categoryAnswers ?? this.categoryAnswers,
      revision: revision ?? this.revision,
      pendingReview: pendingReview ?? this.pendingReview,
      rejected: rejected ?? this.rejected,
      pendingSync: pendingSync ?? this.pendingSync,
      serviceArea: serviceArea ?? this.serviceArea,
      availability: availability ?? this.availability,
      status: status ?? this.status,
      imageAsset: imageAsset ?? this.imageAsset,
      imageCount: imageCount ?? this.imageCount,
      imageMediaIds: imageMediaIds ?? this.imageMediaIds,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'priceLabel': priceLabel,
    'description': description,
    'category': category,
    'categoryId': categoryId,
    'categoryAnswers': categoryAnswers.map((a) => a.toJson()).toList(),
    'revision': revision,
    'pendingReview': pendingReview,
    'rejected': rejected,
    'pendingSync': pendingSync,
    'serviceArea': serviceArea,
    'availability': availability,
    'status': status.name,
    'imageAsset': imageAsset,
    'imageCount': imageCount,
    'imageMediaIds': imageMediaIds,
  };
}

@immutable
class LocalRequestRecord {
  const LocalRequestRecord({
    required this.id,
    required this.buyerName,
    required this.title,
    required this.budget,
  });

  final String id;
  final String buyerName;
  final String title;
  final String budget;
}

@immutable
class LocalOfferRecord {
  const LocalOfferRecord({
    required this.id,
    required this.requestId,
    required this.buyerName,
    required this.sellerName,
    required this.requestTitle,
    required this.price,
    required this.location,
    required this.meetingDate,
    required this.meetingTime,
    required this.message,
    required this.imageNames,
    required this.status,
  });

  factory LocalOfferRecord.fromJson(Map<String, Object?> json) {
    return LocalOfferRecord(
      id: json['id']! as String,
      requestId: json['requestId']! as String,
      buyerName: json['buyerName']! as String,
      sellerName: json['sellerName']! as String,
      requestTitle: json['requestTitle']! as String,
      price: json['price']! as String,
      location: json['location']! as String,
      meetingDate: json['meetingDate']! as String,
      meetingTime: json['meetingTime']! as String,
      message: json['message']! as String,
      imageNames: (json['imageNames']! as List<Object?>).cast<String>(),
      status: LocalOfferStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => LocalOfferStatus.sent,
      ),
    );
  }

  final String id;
  final String requestId;
  final String buyerName;
  final String sellerName;
  final String requestTitle;
  final String price;
  final String location;
  final String meetingDate;
  final String meetingTime;
  final String message;
  final List<String> imageNames;
  final LocalOfferStatus status;

  LocalOfferRecord copyWith({LocalOfferStatus? status}) {
    return LocalOfferRecord(
      id: id,
      requestId: requestId,
      buyerName: buyerName,
      sellerName: sellerName,
      requestTitle: requestTitle,
      price: price,
      location: location,
      meetingDate: meetingDate,
      meetingTime: meetingTime,
      message: message,
      imageNames: imageNames,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'requestId': requestId,
    'buyerName': buyerName,
    'sellerName': sellerName,
    'requestTitle': requestTitle,
    'price': price,
    'location': location,
    'meetingDate': meetingDate,
    'meetingTime': meetingTime,
    'message': message,
    'imageNames': imageNames,
    'status': status.name,
  };
}

@immutable
class LocalChatEntry {
  const LocalChatEntry({
    required this.id,
    required this.senderIsSeller,
    required this.sentAtLabel,
    this.text = '',
    this.attachmentLabel,
    this.attachmentIsImage = false,
  });

  factory LocalChatEntry.fromJson(Map<String, Object?> json) {
    return LocalChatEntry(
      id: json['id']! as String,
      senderIsSeller: json['senderIsSeller']! as bool,
      sentAtLabel: json['sentAtLabel']! as String,
      text: (json['text'] as String?) ?? '',
      attachmentLabel: json['attachmentLabel'] as String?,
      attachmentIsImage: (json['attachmentIsImage'] as bool?) ?? false,
    );
  }

  final String id;
  final bool senderIsSeller;
  final String sentAtLabel;
  final String text;
  final String? attachmentLabel;
  final bool attachmentIsImage;

  Map<String, Object?> toJson() => {
    'id': id,
    'senderIsSeller': senderIsSeller,
    'sentAtLabel': sentAtLabel,
    'text': text,
    'attachmentLabel': attachmentLabel,
    'attachmentIsImage': attachmentIsImage,
  };
}

/// Replaceable local data seam for the frontend-only prototype.
///
/// Upgraded Buyer and Seller routes read the same records from here so a local
/// action remains consistent until the real Supabase repositories are wired.
class LocalMarketplaceRepository extends ChangeNotifier {
  LocalMarketplaceRepository({
    this.request = const LocalRequestRecord(
      id: 'request-ipad-air',
      buyerName: 'Maya Chen',
      title: 'iPad Air, 5th gen or newer',
      budget: r'$350 - $480',
    ),
    List<LocalStoreListing>? storeListings,
    this.storeBackend,
    this.leadsBackend,
    this.offersBackend,
    this.requestsBackend,
    this.buyerOffersBackend,
    this.chatBackend,
    this.sellerOffersBackend,
    this.notificationsBackend,
    this.meetingsBackend,
  }) : _storeListings = List<LocalStoreListing>.of(
         storeBackend == null
             ? (storeListings ?? _defaultStoreListings)
             : const <LocalStoreListing>[],
       );

  static const List<LocalStoreListing> _defaultStoreListings = [
    LocalStoreListing(
      id: 'listing-ipad-air',
      kind: LocalListingKind.product,
      title: 'iPad Air 5th Gen 64GB',
      priceLabel: r'$650',
      description: 'Excellent condition with charger included.',
      category: 'Electronics',
      serviceArea: 'Yonkers, NY',
      availability: 'Available today',
      status: LocalListingStatus.active,
      imageAsset: 'assets/approved_seller/chat/chat-ipad.png',
      imageCount: 3,
    ),
    LocalStoreListing(
      id: 'listing-pressure-washing',
      kind: LocalListingKind.service,
      title: 'Pressure washing',
      priceLabel: r'From $120',
      description: 'Driveways, patios, and exterior surfaces.',
      category: 'Home services',
      serviceArea: 'Within 15 miles',
      availability: 'Next opening: Friday',
      status: LocalListingStatus.paused,
      imageAsset: 'assets/approved_seller/home-pressure-washing.png',
      imageCount: 4,
    ),
  ];

  final LocalRequestRecord request;
  LocalOfferRecord? _latestOffer;
  final List<LocalChatEntry> _conversationEntries = <LocalChatEntry>[];
  final List<LocalStoreListing> _storeListings;
  int _sequence = 0;
  int _listingSequence = 2;

  /// When set, Store reads and writes go through the real backend instead of
  /// the local prototype data. The approved screens keep their synchronous
  /// surface; pending changes are optimistic and revert on failure.
  final MarketplaceStoreBackend? storeBackend;

  /// When set, the seller Leads list loads real buyer requests.
  final MarketplaceLeadsBackend? leadsBackend;

  /// When set, the seller offer form submits real offers.
  final MarketplaceOffersBackend? offersBackend;

  /// When set, buyer request create/edit reads and writes go through the real
  /// backend instead of the local prototype state.
  final MarketplaceRequestsBackend? requestsBackend;

  /// When set, the buyer offers list and selection use the real backend.
  final MarketplaceBuyerOffersBackend? buyerOffersBackend;

  /// When set, the chat inbox and thread use the real backend.
  final MarketplaceChatBackend? chatBackend;

  /// When set, the seller offer history and withdrawal use the real backend.
  final MarketplaceSellerOffersBackend? sellerOffersBackend;

  /// When set, the notification inbox and preferences use the real backend.
  final MarketplaceNotificationsBackend? notificationsBackend;

  /// When set, meetings and reschedules use the real backend.
  final MarketplaceMeetingsBackend? meetingsBackend;

  List<MeetingView> _meetings = const <MeetingView>[];
  bool _meetingsLoading = false;
  String? _meetingsError;
  int _meetingsToken = 0;
  MeetingView? _meetingDetail;
  int _meetingDetailToken = 0;
  String? _meetingsCursor;
  String? _meetingsStatus;
  bool get meetingsHasMore => _meetingsCursor != null;

  List<MeetingView> get meetings => List<MeetingView>.unmodifiable(_meetings);

  bool get meetingsLoading => _meetingsLoading;

  String? get meetingsError => _meetingsError;

  MeetingView? get meetingDetail => _meetingDetail;

  bool get isMeetingsBacked => meetingsBackend != null;

  void clearMeetingDetail() {
    ++_meetingDetailToken;
    _meetingDetail = null;
    _notifyStore();
  }

  /// Loads the participant meetings, newest first.
  Future<void> refreshMeetings({String? status}) async {
    final backend = meetingsBackend;
    if (backend == null) return;
    final token = ++_meetingsToken;
    _meetingsLoading = true;
    _meetingsError = null;
    _meetingsStatus = status;
    _notifyStore();
    try {
      final page = await backend.loadMeetings(status: status, limit: 50);
      if (_disposed || token != _meetingsToken) return;
      _meetings = page.items;
      _meetingsCursor = page.nextCursor;
    } catch (error) {
      if (_disposed || token != _meetingsToken) return;
      _meetingsError = error is StoreBackendException
          ? error.message
          : 'Could not load meetings. Pull to retry.';
    } finally {
      if (!_disposed && token == _meetingsToken) {
        _meetingsLoading = false;
        _notifyStore();
      }
    }
  }

  Future<void> loadMoreMeetings() async {
    final backend = meetingsBackend;
    final cursor = _meetingsCursor;
    if (backend == null || cursor == null || _meetingsLoading) return;
    final token = ++_meetingsToken;
    _meetingsLoading = true;
    _meetingsError = null;
    _notifyStore();
    try {
      final page = await backend.loadMeetings(
        status: _meetingsStatus,
        cursor: cursor,
        limit: 50,
      );
      if (_disposed || token != _meetingsToken) return;
      final existing = {for (final item in _meetings) item.meetingId: item};
      for (final item in page.items) {
        existing.putIfAbsent(item.meetingId, () => item);
      }
      _meetings = List.unmodifiable(existing.values);
      _meetingsCursor = page.nextCursor == cursor ? null : page.nextCursor;
    } catch (error) {
      if (!_disposed && token == _meetingsToken) {
        _meetingsError = error is StoreBackendException
            ? error.message
            : 'Could not load more meetings. Try again.';
      }
    } finally {
      if (!_disposed && token == _meetingsToken) {
        _meetingsLoading = false;
        _notifyStore();
      }
    }
  }

  /// Loads one meeting for the detail screen.
  Future<MeetingView?> loadMeeting(String meetingId) async {
    final backend = meetingsBackend;
    if (backend == null) return null;
    final token = ++_meetingDetailToken;
    _meetingDetail = null;
    _meetingsError = null;
    _notifyStore();
    try {
      final meeting = await backend.loadMeeting(meetingId);
      if (_disposed || token != _meetingDetailToken) return null;
      _meetingDetail = meeting;
      return meeting;
    } catch (error) {
      if (!_disposed && token == _meetingDetailToken) {
        _meetingsError = error is StoreBackendException
            ? error.message
            : 'Could not load this meeting. Try again.';
      }
      return null;
    } finally {
      _notifyStore();
    }
  }

  Future<MeetingActionResult> proposeMeeting({
    required String conversationId,
    required MeetingScheduleInput input,
    required String operationKey,
  }) {
    return _runMeetingAction(
      () => meetingsBackend!.proposeMeeting(
        conversationId: conversationId,
        input: input,
        operationKey: operationKey,
      ),
    );
  }

  Future<MeetingActionResult> respondToMeeting({
    required String meetingId,
    required bool accept,
    required int expectedRevision,
    required String operationKey,
  }) {
    return _runMeetingAction(
      () => meetingsBackend!.respondToMeeting(
        meetingId: meetingId,
        accept: accept,
        expectedRevision: expectedRevision,
        operationKey: operationKey,
      ),
    );
  }

  Future<MeetingActionResult> proposeMeetingReschedule({
    required String meetingId,
    required MeetingScheduleInput input,
    required int expectedRevision,
    required String operationKey,
  }) {
    return _runMeetingAction(
      () => meetingsBackend!.proposeReschedule(
        meetingId: meetingId,
        input: input,
        expectedRevision: expectedRevision,
        operationKey: operationKey,
      ),
    );
  }

  Future<MeetingActionResult> cancelMeeting({
    required String meetingId,
    required int expectedRevision,
    required String operationKey,
  }) {
    return _runMeetingAction(
      () => meetingsBackend!.cancelMeeting(
        meetingId: meetingId,
        expectedRevision: expectedRevision,
        operationKey: operationKey,
      ),
    );
  }

  Future<MeetingActionResult> _runMeetingAction(
    Future<MeetingView> Function() action,
  ) async {
    if (meetingsBackend == null) {
      throw const StoreBackendException('Meetings are unavailable.');
    }
    try {
      final meeting = await action();
      if (!_disposed) {
        ++_meetingsToken;
        ++_meetingDetailToken;
        _meetingsLoading = false;
        _meetingDetail = meeting;
        final next = List<MeetingView>.of(_meetings);
        final index = next.indexWhere(
          (row) => row.meetingId == meeting.meetingId,
        );
        if (index < 0) {
          next.insert(0, meeting);
        } else {
          next[index] = meeting;
        }
        _meetings = List<MeetingView>.unmodifiable(next);
      }
      return MeetingActionResult.success(meeting);
    } on StoreBackendException catch (error) {
      return MeetingActionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    } finally {
      _notifyStore();
    }
  }

  List<NotificationInboxItem> _notifications = const <NotificationInboxItem>[];
  bool _notificationsLoading = false;
  bool _notificationsLoadingMore = false;
  String? _notificationsError;
  String? _notificationsCursor;
  int _notificationsUnread = 0;
  int _notificationsToken = 0;
  NotificationPreferencesRecord? _notificationPreferences;
  bool _notificationPreferencesLoading = false;
  String? _notificationPreferencesError;

  List<NotificationInboxItem> get notifications =>
      List<NotificationInboxItem>.unmodifiable(_notifications);

  bool get notificationsLoading => _notificationsLoading;

  bool get notificationsLoadingMore => _notificationsLoadingMore;

  String? get notificationsError => _notificationsError;

  bool get notificationsHasMore => _notificationsCursor != null;

  int get notificationsUnreadCount => _notificationsUnread;

  NotificationPreferencesRecord? get notificationPreferences =>
      _notificationPreferences;

  bool get notificationPreferencesLoading => _notificationPreferencesLoading;

  String? get notificationPreferencesError => _notificationPreferencesError;

  bool get isNotificationsBacked => notificationsBackend != null;

  /// Loads the first inbox page. No-op without a backend; overlapping refreshes
  /// are versioned and a disposed repository applies nothing.
  Future<void> refreshNotifications() async {
    final backend = notificationsBackend;
    if (backend == null) return;
    final token = ++_notificationsToken;
    _notificationsLoading = true;
    _notificationsError = null;
    _notifyStore();
    try {
      final page = await backend.loadInbox(limit: 50);
      if (_disposed || token != _notificationsToken) return;
      _notifications = page.items;
      _notificationsCursor = page.nextCursor;
      _notificationsUnread = page.unreadCount;
    } catch (error) {
      if (_disposed || token != _notificationsToken) return;
      _notificationsError = error is StoreBackendException
          ? error.message
          : 'Could not load notifications. Pull to retry.';
    } finally {
      if (!_disposed && token == _notificationsToken) {
        _notificationsLoading = false;
        _notifyStore();
      }
    }
  }

  /// Loads the next inbox page using the server cursor.
  Future<void> loadMoreNotifications() async {
    final backend = notificationsBackend;
    final cursor = _notificationsCursor;
    if (backend == null || cursor == null || _notificationsLoadingMore) return;
    final token = _notificationsToken;
    _notificationsLoadingMore = true;
    _notifyStore();
    try {
      final page = await backend.loadInbox(cursor: cursor, limit: 50);
      if (_disposed || token != _notificationsToken) return;
      _notifications = <NotificationInboxItem>[
        ..._notifications,
        ...page.items,
      ];
      _notificationsCursor = page.nextCursor;
      _notificationsUnread = page.unreadCount;
    } catch (error) {
      if (_disposed || token != _notificationsToken) return;
      _notificationsError = error is StoreBackendException
          ? error.message
          : 'Could not load more notifications.';
    } finally {
      if (!_disposed && token == _notificationsToken) {
        _notificationsLoadingMore = false;
        _notifyStore();
      }
    }
  }

  /// Marks one notification read. The local row updates only after the server
  /// acknowledges the marker.
  Future<bool> markNotificationRead(String notificationId) async {
    final backend = notificationsBackend;
    if (backend == null) return false;
    try {
      await backend.markRead(notificationId);
      if (_disposed) return false;
      final now = DateTime.now().toUtc();
      _notifications = _notifications
          .map(
            (item) => item.id == notificationId
                ? NotificationInboxItem(
                    id: item.id,
                    kind: item.kind,
                    title: item.title,
                    body: item.body,
                    deepLink: item.deepLink,
                    sourceId: item.sourceId,
                    payload: item.payload,
                    readAt: item.readAt ?? now,
                    createdAt: item.createdAt,
                  )
                : item,
          )
          .toList(growable: false);
      if (_notificationsUnread > 0) _notificationsUnread -= 1;
      return true;
    } on StoreBackendException {
      return false;
    } finally {
      _notifyStore();
    }
  }

  /// Marks every unread notification read and reconciles the unread total.
  Future<int> markAllNotificationsRead() async {
    final backend = notificationsBackend;
    if (backend == null) return 0;
    try {
      final marked = await backend.markAllRead();
      if (_disposed) return 0;
      final now = DateTime.now().toUtc();
      _notifications = _notifications
          .map(
            (item) => item.isUnread
                ? NotificationInboxItem(
                    id: item.id,
                    kind: item.kind,
                    title: item.title,
                    body: item.body,
                    deepLink: item.deepLink,
                    sourceId: item.sourceId,
                    payload: item.payload,
                    readAt: now,
                    createdAt: item.createdAt,
                  )
                : item,
          )
          .toList(growable: false);
      _notificationsUnread = 0;
      return marked;
    } on StoreBackendException {
      return 0;
    } finally {
      _notifyStore();
    }
  }

  /// Loads the caller's notification preferences.
  Future<void> refreshNotificationPreferences() async {
    final backend = notificationsBackend;
    if (backend == null) return;
    _notificationPreferencesLoading = true;
    _notifyStore();
    try {
      final record = await backend.loadPreferences();
      if (_disposed) return;
      _notificationPreferences = record;
      _notificationPreferencesError = null;
    } catch (error) {
      if (_disposed) return;
      _notificationPreferencesError = error is StoreBackendException
          ? error.message
          : 'Could not load notification preferences.';
    } finally {
      if (!_disposed) {
        _notificationPreferencesLoading = false;
        _notifyStore();
      }
    }
  }

  /// Replaces the editable preferences at their expected revision.
  Future<NotificationPreferencesResult> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final backend = notificationsBackend;
    final current = _notificationPreferences;
    if (backend == null || current == null) {
      throw const StoreBackendException(
        'Notification preferences are unavailable.',
      );
    }
    try {
      final record = await backend.updatePreferences(
        preferences: preferences,
        expectedRevision: current.revision,
        includeLeads: current.supportsLeads,
      );
      if (!_disposed) _notificationPreferences = record;
      return NotificationPreferencesResult.success(record);
    } on StoreBackendException catch (error) {
      return NotificationPreferencesResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    } finally {
      _notifyStore();
    }
  }

  List<Offer> _sellerOffers = const <Offer>[];
  bool _sellerOffersLoading = false;
  String? _sellerOffersError;
  int _sellerOffersToken = 0;

  List<Offer> get sellerOffers => List<Offer>.unmodifiable(_sellerOffers);

  bool get sellerOffersLoading => _sellerOffersLoading;

  String? get sellerOffersError => _sellerOffersError;

  bool get isSellerOffersBacked => sellerOffersBackend != null;

  /// Loads the seller's own offers. No-op without a backend.
  Future<void> refreshSellerOffers() async {
    final backend = sellerOffersBackend;
    if (backend == null) return;
    final token = ++_sellerOffersToken;
    _sellerOffersLoading = true;
    _sellerOffersError = null;
    _notifyStore();
    try {
      final offers = await backend.loadSellerOffers();
      if (_disposed || token != _sellerOffersToken) return;
      _sellerOffers = offers;
    } catch (error) {
      if (_disposed || token != _sellerOffersToken) return;
      _sellerOffersError = error is StoreBackendException
          ? error.message
          : 'Could not load your offers. Pull to retry.';
    } finally {
      if (!_disposed && token == _sellerOffersToken) {
        _sellerOffersLoading = false;
        _notifyStore();
      }
    }
  }

  /// Withdraws one seller offer at its expected revision.
  Future<SellerOfferActionResult> withdrawSellerOffer({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  }) async {
    final backend = sellerOffersBackend;
    if (backend == null) {
      throw const StoreBackendException('Offer changes are unavailable.');
    }
    try {
      final offer = await backend.withdrawOffer(
        offerId: offerId,
        expectedOfferRevision: expectedOfferRevision,
        operationKey: operationKey,
      );
      final next = List<Offer>.of(_sellerOffers);
      final index = next.indexWhere((row) => row.id == offer.id);
      if (index < 0) {
        next.insert(0, offer);
      } else {
        next[index] = offer;
      }
      _sellerOffers = List<Offer>.unmodifiable(next);
      _notifyStore();
      return SellerOfferActionResult.success(offer);
    } on StoreBackendException catch (error) {
      return SellerOfferActionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  Future<SellerOfferActionResult> reviseSellerOffer({
    required String offerId,
    required int expectedOfferRevision,
    required OfferTerms terms,
    required String operationKey,
  }) async {
    final backend = sellerOffersBackend;
    if (backend is! MarketplaceSellerOffersRevisionBackend) {
      return const SellerOfferActionResult.failure(
        'Offer editing is unavailable.',
      );
    }
    try {
      final offer = await (backend as MarketplaceSellerOffersRevisionBackend)
          .reviseOffer(
            offerId: offerId,
            expectedOfferRevision: expectedOfferRevision,
            terms: terms,
            operationKey: operationKey,
          );
      final next = List<Offer>.of(_sellerOffers);
      final index = next.indexWhere((row) => row.id == offer.id);
      if (index < 0) {
        next.insert(0, offer);
      } else {
        next[index] = offer;
      }
      _sellerOffers = List<Offer>.unmodifiable(next);
      _notifyStore();
      return SellerOfferActionResult.success(offer);
    } on StoreBackendException catch (error) {
      return SellerOfferActionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  List<ConversationSummary> _chatInbox = const <ConversationSummary>[];
  bool _chatInboxLoading = false;
  String? _chatInboxError;
  int _chatInboxToken = 0;
  String? _activeConversationId;
  List<ConversationMessage> _chatMessages = const <ConversationMessage>[];
  bool _chatMessagesLoading = false;
  String? _chatMessagesError;
  int _chatMessagesToken = 0;
  bool _chatMuted = false;
  bool _chatSending = false;
  final Map<String, ({String text, String key})> _pendingChatSends = {};
  final Map<String, ({String text, List<String> mediaIds, String key})>
  _pendingChatAttachments = {};

  List<ConversationSummary> get chatInbox =>
      List<ConversationSummary>.unmodifiable(_chatInbox);

  bool get chatInboxLoading => _chatInboxLoading;

  String? get chatInboxError => _chatInboxError;

  String? get activeConversationId => _activeConversationId;

  List<ConversationMessage> get chatMessages =>
      List<ConversationMessage>.unmodifiable(_chatMessages);

  bool get chatMessagesLoading => _chatMessagesLoading;

  String? get chatMessagesError => _chatMessagesError;

  bool get chatMuted => _chatMuted;

  bool get chatSending => _chatSending;
  String? get unconfirmedChatText =>
      _pendingChatSends[_activeConversationId]?.text;

  bool get isChatBacked => chatBackend != null;

  /// True when the composed chat backend also accepts authorized image
  /// attachments. The picker stays unavailable until this is true.
  bool get chatAttachmentsSupported {
    final backend = chatBackend;
    if (backend is MarketplaceChatAttachmentBackend) {
      return (backend as MarketplaceChatAttachmentBackend)
          .chatAttachmentsEnabled;
    }
    return false;
  }

  List<String> get unconfirmedChatAttachmentIds =>
      _pendingChatAttachments[_activeConversationId]?.mediaIds ??
      const <String>[];
  String? _chatHistoryCursor;
  bool _chatOlderLoading = false;
  String? _chatOlderError;
  int _chatOlderToken = 0;
  bool get chatHasOlder => _chatHistoryCursor != null;
  bool _chatPollRunning = false;

  void _clearDeniedChat(String message) {
    ++_chatMessagesToken;
    ++_chatOlderToken;
    _chatMessages = const [];
    _chatHistoryCursor = null;
    _chatMessagesLoading = false;
    _chatOlderLoading = false;
    _chatOlderError = null;
    _chatMessagesError = message;
    _pendingChatSends.remove(_activeConversationId);
    _notifyStore();
  }

  /// Refresh the newest page without discarding explicitly loaded history.
  Future<void> pollChatMessages() async {
    final backend = chatBackend;
    final id = _activeConversationId;
    if (backend is! MarketplacePagedChatBackend ||
        id == null ||
        _chatPollRunning ||
        _chatMessagesLoading ||
        _chatSending) {
      return;
    }
    _chatPollRunning = true;
    final token = _chatMessagesToken;
    try {
      final page = await (backend as MarketplacePagedChatBackend)
          .loadMessagePage(id, null);
      if (_disposed ||
          token != _chatMessagesToken ||
          id != _activeConversationId) {
        return;
      }
      final newIds = page.items.map((row) => row.id).toSet();
      // A full new page with no overlap may hide a gap after a long pause.
      // Restart pagination from the server cursor rather than stitching across it.
      final gap =
          page.nextCursor != null &&
          _chatMessages.isNotEmpty &&
          !_chatMessages.any((row) => newIds.contains(row.id));
      if (gap) {
        ++_chatOlderToken;
        _chatOlderLoading = false;
        _chatOlderError = null;
        _chatHistoryCursor = page.nextCursor;
      }
      _chatMessages = List.unmodifiable([
        if (!gap) ..._chatMessages.where((row) => !newIds.contains(row.id)),
        ...page.items,
      ]);
      _chatMessagesError = null;
      _notifyStore();
    } catch (error) {
      // Preserve already-authorized history on transient refresh failures.
      // Manual refresh retains its explicit error/retry presentation.
      if (!_disposed &&
          token == _chatMessagesToken &&
          id == _activeConversationId &&
          error is StoreBackendException &&
          error.code == 'chat_access_denied') {
        _clearDeniedChat(error.message);
      }
    } finally {
      _chatPollRunning = false;
    }
  }

  bool get chatOlderLoading => _chatOlderLoading;
  String? get chatOlderError => _chatOlderError;

  Future<void> loadOlderChatMessages() async {
    final backend = chatBackend;
    final id = _activeConversationId;
    final cursor = _chatHistoryCursor;
    if (backend is! MarketplacePagedChatBackend ||
        id == null ||
        cursor == null ||
        _chatOlderLoading ||
        _chatMessagesLoading) {
      return;
    }
    final token = ++_chatOlderToken;
    _chatOlderLoading = true;
    _chatOlderError = null;
    _notifyStore();
    try {
      final slice = await (backend as MarketplacePagedChatBackend)
          .loadMessagePage(id, cursor);
      if (_disposed ||
          token != _chatOlderToken ||
          id != _activeConversationId) {
        return;
      }
      if (slice.nextCursor == cursor) {
        throw const StoreBackendException(
          'Could not advance message history. Try again.',
        );
      }
      final existing = _chatMessages.map((row) => row.id).toSet();
      _chatMessages = List.unmodifiable([
        ...slice.items.where((row) => !existing.contains(row.id)),
        ..._chatMessages,
      ]);
      _chatHistoryCursor = slice.nextCursor;
    } catch (error) {
      if (!_disposed && token == _chatOlderToken) {
        if (error is StoreBackendException &&
            error.code == 'chat_access_denied') {
          _clearDeniedChat(error.message);
          return;
        }
        _chatOlderError = 'Could not load older messages. Try again.';
      }
    } finally {
      if (!_disposed && token == _chatOlderToken) {
        _chatOlderLoading = false;
        _notifyStore();
      }
    }
  }

  Future<Offer?> loadActiveConversationOffer() async {
    final conversationId = _activeConversationId;
    final backend = chatBackend;
    if (conversationId == null || backend == null) return null;
    final offer = await backend.loadMeetingOffer(conversationId);
    return !_disposed && _activeConversationId == conversationId ? offer : null;
  }

  int get chatUnreadTotal =>
      _chatInbox.fold(0, (total, row) => total + row.unreadCount);

  /// Loads the participant inbox. No-op without a backend; overlapping
  /// refreshes are versioned and a disposed repository applies nothing.
  Future<void> refreshChatInbox() async {
    final backend = chatBackend;
    if (backend == null) return;
    final token = ++_chatInboxToken;
    _chatInboxLoading = true;
    _chatInboxError = null;
    _notifyStore();
    try {
      final inbox = await backend.loadInbox();
      if (_disposed || token != _chatInboxToken) return;
      _chatInbox = inbox;
    } catch (error) {
      if (_disposed || token != _chatInboxToken) return;
      _chatInboxError = error is StoreBackendException
          ? error.message
          : 'Could not load your conversations. Pull to retry.';
    } finally {
      if (!_disposed && token == _chatInboxToken) {
        _chatInboxLoading = false;
        _notifyStore();
      }
    }
  }

  /// Opens one conversation and loads its history.
  Future<void> openChatConversation(String conversationId) async {
    _activeConversationId = conversationId;
    _chatMessages = const <ConversationMessage>[];
    _chatMuted = false;
    _notifyStore();
    await refreshChatMessages();
  }

  /// Loads the active conversation history, oldest first.
  Future<void> refreshChatMessages() async {
    final backend = chatBackend;
    final conversationId = _activeConversationId;
    if (backend == null || conversationId == null) return;
    final token = ++_chatMessagesToken;
    ++_chatOlderToken;
    _chatOlderLoading = false;
    _chatOlderError = null;
    _chatHistoryCursor = null;
    _chatMessagesLoading = true;
    _chatMessagesError = null;
    _notifyStore();
    try {
      final slice = backend is MarketplacePagedChatBackend
          ? await (backend as MarketplacePagedChatBackend).loadMessagePage(
              conversationId,
              null,
            )
          : null;
      final messages =
          slice?.items ?? await backend.loadMessages(conversationId);
      if (_disposed || token != _chatMessagesToken) return;
      _chatMessages = messages;
      _chatHistoryCursor = slice?.nextCursor;
    } catch (error) {
      if (_disposed || token != _chatMessagesToken) return;
      if (error is StoreBackendException &&
          error.code == 'chat_access_denied') {
        _clearDeniedChat(error.message);
        return;
      }
      _chatMessagesError = error is StoreBackendException
          ? error.message
          : 'Could not load this conversation. Pull to retry.';
    } finally {
      if (!_disposed && token == _chatMessagesToken) {
        _chatMessagesLoading = false;
        _notifyStore();
      }
    }
  }

  /// Sends one message to the active conversation.
  Future<ChatSendResult> sendChatMessage(String text) async {
    final backend = chatBackend;
    final conversationId = _activeConversationId;
    if (backend == null || conversationId == null) {
      throw const StoreBackendException('Chat is unavailable.');
    }
    if (_chatSending) {
      return const ChatSendResult.failure('A message is already being sent.');
    }
    final pending = _pendingChatSends[conversationId];
    if (pending != null && pending.text != text) {
      return const ChatSendResult.failure(
        'Retry the original unconfirmed message before sending a different one.',
        outcomeUncertain: true,
      );
    }
    final intent =
        pending ?? (text: text, key: newStoreOperationKey('chat-send'));
    _pendingChatSends[conversationId] = intent;
    _chatSending = true;
    _notifyStore();
    try {
      final message = await backend.sendMessage(
        conversationId: conversationId,
        text: text,
        clientMessageId: intent.key,
      );
      _pendingChatSends.remove(conversationId);
      if (!_disposed && _activeConversationId == conversationId) {
        ++_chatMessagesToken;
        _chatMessagesLoading = false;
        _chatMessages = List<ConversationMessage>.unmodifiable([
          ..._chatMessages.where((row) => row.id != message.id),
          message,
        ]);
      }
      return ChatSendResult.success(message);
    } on StoreBackendException catch (error) {
      if (!error.ambiguous) _pendingChatSends.remove(conversationId);
      return ChatSendResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    } catch (_) {
      return const ChatSendResult.failure(
        'The message could not be confirmed. Retry the same message.',
        outcomeUncertain: true,
      );
    } finally {
      if (!_disposed) {
        _chatSending = false;
        _notifyStore();
      }
    }
  }

  /// Sends one authorized image attachment message. The intent (text and media
  /// ids) is frozen while the outcome is unknown so a retry reuses the same
  /// client key; a changed intent is refused until the unresolved attempt is
  /// discarded. When [expectedConversationId] no longer matches the active
  /// conversation, the upload is kept with the original conversation instead of
  /// being sent into whichever chat is now open.
  Future<ChatSendResult> sendChatAttachment({
    required String text,
    required List<String> mediaIds,
    String? expectedConversationId,
  }) async {
    final backend = chatBackend;
    final conversationId = _activeConversationId;
    final attachmentBackend = backend is MarketplaceChatAttachmentBackend
        ? backend as MarketplaceChatAttachmentBackend
        : null;
    if (attachmentBackend == null ||
        !attachmentBackend.chatAttachmentsEnabled ||
        conversationId == null) {
      throw const StoreBackendException(
        'Image attachments are not available yet.',
      );
    }
    if (mediaIds.isEmpty) return sendChatMessage(text);
    if (expectedConversationId != null &&
        expectedConversationId != conversationId) {
      if (!_pendingChatAttachments.containsKey(expectedConversationId)) {
        _pendingChatAttachments[expectedConversationId] = (
          text: text,
          mediaIds: List<String>.unmodifiable(mediaIds),
          key: newStoreOperationKey('chat-attachment'),
        );
      }
      _notifyStore();
      return const ChatSendResult.failure(
        'This chat changed. The photo is kept with the original conversation.',
      );
    }
    if (_chatSending) {
      return const ChatSendResult.failure('A message is already being sent.');
    }
    final pending = _pendingChatAttachments[conversationId];
    if (pending != null && !_sameAttachmentIntent(pending, text, mediaIds)) {
      return const ChatSendResult.failure(
        'Retry the original unconfirmed attachments before sending different ones.',
        outcomeUncertain: true,
      );
    }
    final intent =
        pending ??
        (
          text: text,
          mediaIds: List<String>.unmodifiable(mediaIds),
          key: newStoreOperationKey('chat-attachment'),
        );
    _pendingChatAttachments[conversationId] = intent;
    _chatSending = true;
    _notifyStore();
    try {
      final message = await attachmentBackend.sendAttachment(
        conversationId: conversationId,
        text: intent.text,
        mediaIds: intent.mediaIds,
        clientMessageId: intent.key,
      );
      _pendingChatAttachments.remove(conversationId);
      if (!_disposed && _activeConversationId == conversationId) {
        ++_chatMessagesToken;
        _chatMessagesLoading = false;
        _chatMessages = List<ConversationMessage>.unmodifiable([
          ..._chatMessages.where((row) => row.id != message.id),
          message,
        ]);
      }
      return ChatSendResult.success(message);
    } on StoreBackendException catch (error) {
      if (!error.ambiguous) {
        _pendingChatAttachments.remove(conversationId);
      }
      return ChatSendResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    } catch (_) {
      return const ChatSendResult.failure(
        'The attachments could not be confirmed. Retry the same message.',
        outcomeUncertain: true,
      );
    } finally {
      if (!_disposed) {
        _chatSending = false;
        _notifyStore();
      }
    }
  }

  bool _sameAttachmentIntent(
    ({String text, List<String> mediaIds, String key}) intent,
    String text,
    List<String> mediaIds,
  ) {
    if (intent.text != text || intent.mediaIds.length != mediaIds.length) {
      return false;
    }
    for (var index = 0; index < mediaIds.length; index++) {
      if (intent.mediaIds[index] != mediaIds[index]) return false;
    }
    return true;
  }

  /// True while [conversationId] is still the open conversation. Used to fence
  /// a delayed upload before it can be sent.
  bool isActiveConversation(String conversationId) =>
      !_disposed && _activeConversationId == conversationId;

  /// The unconfirmed attachment intent for the active conversation, if any.
  ({String text, List<String> mediaIds})? get pendingChatAttachment {
    final intent = _pendingChatAttachments[_activeConversationId];
    if (intent == null) return null;
    return (text: intent.text, mediaIds: intent.mediaIds);
  }

  bool get hasUnconfirmedChatAttachment =>
      _pendingChatAttachments.containsKey(_activeConversationId);

  /// Retries the retained attachment intent without uploading anything again:
  /// the repository reuses the stored media ids and client key.
  Future<ChatSendResult> retryChatAttachment() async {
    final conversationId = _activeConversationId;
    final intent = _pendingChatAttachments[conversationId];
    if (conversationId == null || intent == null) {
      return const ChatSendResult.failure(
        'There is no unconfirmed photo to retry.',
      );
    }
    return sendChatAttachment(
      text: intent.text,
      mediaIds: intent.mediaIds,
      expectedConversationId: conversationId,
    );
  }

  /// Abandons the unconfirmed attachment intent for the active conversation.
  void discardChatAttachment() {
    final conversationId = _activeConversationId;
    if (conversationId == null) return;
    if (_pendingChatAttachments.remove(conversationId) != null) {
      _notifyStore();
    }
  }

  /// Marks the active conversation read up to [messageId].
  Future<void> markChatRead(String messageId) async {
    final backend = chatBackend;
    final conversationId = _activeConversationId;
    if (backend == null || conversationId == null) return;
    try {
      await backend.markRead(
        conversationId: conversationId,
        messageId: messageId,
      );
      if (_disposed) return;
      _chatInbox = _chatInbox
          .map(
            (row) => row.conversation.id == conversationId
                ? ConversationSummary(
                    conversation: row.conversation,
                    counterpartDisplayName: row.counterpartDisplayName,
                    counterpartProfileId: row.counterpartProfileId,
                    latestMessage: row.latestMessage,
                    unreadCount: 0,
                  )
                : row,
          )
          .toList(growable: false);
    } catch (_) {
      // Read markers are best-effort; the inbox refresh reconciles them.
    } finally {
      _notifyStore();
    }
  }

  /// Persists the per-member mute flag for the active conversation.
  Future<bool> setChatMuted(bool muted) async {
    final backend = chatBackend;
    final conversationId = _activeConversationId;
    if (backend == null || conversationId == null) return false;
    try {
      final member = await backend.setMuted(
        conversationId: conversationId,
        muted: muted,
      );
      if (!_disposed && _activeConversationId == conversationId) {
        _chatMuted = member.isMuted;
      }
      return true;
    } on StoreBackendException {
      return false;
    } finally {
      _notifyStore();
    }
  }

  List<Offer> _buyerOffers = const <Offer>[];
  bool _buyerOffersLoading = false;
  String? _buyerOffersError;
  int _buyerOffersToken = 0;
  String? _buyerOffersRequestId;

  List<Offer> get buyerOffers => List<Offer>.unmodifiable(_buyerOffers);

  bool get buyerOffersLoading => _buyerOffersLoading;

  String? get buyerOffersError => _buyerOffersError;

  String? get buyerOffersRequestId => _buyerOffersRequestId;

  bool get isBuyerOffersBacked => buyerOffersBackend != null;

  /// Loads every offer for one buyer request. No-op without a backend;
  /// overlapping refreshes are versioned and a disposed repository applies
  /// nothing.
  Future<void> refreshBuyerOffers(String requestId) async {
    final backend = buyerOffersBackend;
    if (backend == null) return;
    final token = ++_buyerOffersToken;
    _buyerOffersLoading = true;
    _buyerOffersError = null;
    _buyerOffersRequestId = requestId;
    _notifyStore();
    try {
      final offers = await backend.loadRequestOffers(requestId);
      if (_disposed || token != _buyerOffersToken) return;
      _buyerOffers = offers;
    } catch (error) {
      if (_disposed || token != _buyerOffersToken) return;
      _buyerOffersError = error is StoreBackendException
          ? error.message
          : 'Could not load offers. Pull to retry.';
    } finally {
      if (!_disposed && token == _buyerOffersToken) {
        _buyerOffersLoading = false;
        _notifyStore();
      }
    }
  }

  /// Selects one real offer revision and returns a user-safe outcome.
  Future<BuyerOfferSelectionResult> selectBuyerOffer({
    required String offerId,
    required String revisionId,
    required int expectedOfferRevision,
    required String operationKey,
  }) async {
    final backend = buyerOffersBackend;
    if (backend == null) {
      throw const StoreBackendException('Offer selection is unavailable.');
    }
    try {
      final outcome = await backend.selectOffer(
        offerId: offerId,
        revisionId: revisionId,
        expectedOfferRevision: expectedOfferRevision,
        operationKey: operationKey,
      );
      _replaceBuyerOffer(outcome.offer);
      return BuyerOfferSelectionResult.success(
        outcome.offer,
        conversationId: outcome.conversationId,
      );
    } on StoreBackendException catch (error) {
      return BuyerOfferSelectionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  void _replaceBuyerOffer(Offer offer) {
    final next = List<Offer>.of(_buyerOffers);
    final index = next.indexWhere((row) => row.id == offer.id);
    if (index < 0) {
      next.insert(0, offer);
    } else {
      next[index] = offer;
    }
    _buyerOffers = List<Offer>.unmodifiable(next);
    _notifyStore();
  }

  /// Buyer designates the accepted seller they purchased from. Only that seller
  /// can complete the request PIN; the server owns the one-purchase rule.
  Future<BuyerPurchaseSelectionResult> selectBuyerPurchaseSeller({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  }) async {
    final backend = buyerOffersBackend;
    if (backend == null) {
      throw const StoreBackendException(
        'Choosing your purchase seller is unavailable.',
      );
    }
    try {
      final offer = await backend.selectPurchaseSeller(
        offerId: offerId,
        expectedOfferRevision: expectedOfferRevision,
        operationKey: operationKey,
      );
      _replaceBuyerOffer(offer);
      return BuyerPurchaseSelectionResult.success(offer);
    } on StoreBackendException catch (error) {
      return BuyerPurchaseSelectionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  List<MarketplaceRequest> _buyerRequests = const <MarketplaceRequest>[];
  bool _buyerRequestsLoading = false;
  String? _buyerRequestsError;
  int _buyerRequestsToken = 0;
  List<CatalogueCategoryOption> _requestCategories =
      const <CatalogueCategoryOption>[];
  bool _requestCategoriesLoading = false;
  bool _requestCategoriesLoaded = false;
  String? _requestCategoriesError;

  List<MarketplaceRequest> get buyerRequests =>
      List<MarketplaceRequest>.unmodifiable(_buyerRequests);

  bool get buyerRequestsLoading => _buyerRequestsLoading;

  String? get buyerRequestsError => _buyerRequestsError;

  List<CatalogueCategoryOption> get requestCategories =>
      List<CatalogueCategoryOption>.unmodifiable(_requestCategories);

  bool get requestCategoriesLoaded => _requestCategoriesLoaded;

  bool get requestCategoriesLoading => _requestCategoriesLoading;

  String? get requestCategoriesError => _requestCategoriesError;

  bool get isRequestsBacked => requestsBackend != null;

  /// Loads the buyer's own requests. No-op without a backend; overlapping
  /// refreshes are versioned and a disposed repository applies nothing.
  Future<void> refreshBuyerRequests() async {
    final backend = requestsBackend;
    if (backend == null) return;
    final token = ++_buyerRequestsToken;
    _buyerRequestsLoading = true;
    _buyerRequestsError = null;
    _notifyStore();
    try {
      final requests = await backend.loadBuyerRequests();
      if (_disposed || token != _buyerRequestsToken) return;
      _buyerRequests = requests;
    } catch (error) {
      if (_disposed || token != _buyerRequestsToken) return;
      _buyerRequestsError = error is StoreBackendException
          ? error.message
          : 'Could not load your requests. Pull to retry.';
    } finally {
      if (!_disposed && token == _buyerRequestsToken) {
        _buyerRequestsLoading = false;
        _notifyStore();
      }
    }
  }

  /// Loads the server-provided catalogue categories for the request form.
  Future<void> refreshRequestCategories() async {
    final backend = requestsBackend;
    if (backend == null) return;
    _requestCategoriesLoading = true;
    _notifyStore();
    try {
      final categories = await backend.loadCategories();
      if (_disposed) return;
      _requestCategories = categories;
      _requestCategoriesLoaded = true;
      _requestCategoriesError = null;
    } catch (error) {
      if (_disposed) return;
      _requestCategoriesError = error is StoreBackendException
          ? error.message
          : 'Could not load categories.';
    } finally {
      if (!_disposed) {
        _requestCategoriesLoading = false;
        _notifyStore();
      }
    }
  }

  /// Creates a real request and returns a user-safe outcome. The caller keeps
  /// the same [operationKey] and payload while the outcome is uncertain.
  Future<RequestSubmissionResult> createBuyerRequest({
    required RequestDraft draft,
    required String operationKey,
  }) async {
    final backend = requestsBackend;
    if (backend == null) {
      throw const StoreBackendException('Request posting is unavailable.');
    }
    try {
      final created = await backend.createRequest(
        draft: draft,
        operationKey: operationKey,
      );
      _upsertBuyerRequest(created);
      return RequestSubmissionResult.success(created);
    } on StoreBackendException catch (error) {
      return RequestSubmissionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  /// Updates a real request at its expected revision.
  Future<RequestSubmissionResult> updateBuyerRequest({
    required String requestId,
    required int expectedRevision,
    required RequestDraft draft,
    required String operationKey,
  }) async {
    final backend = requestsBackend;
    if (backend == null) {
      throw const StoreBackendException('Request editing is unavailable.');
    }
    try {
      final updated = await backend.updateRequest(
        requestId: requestId,
        expectedRevision: expectedRevision,
        draft: draft,
        operationKey: operationKey,
      );
      _upsertBuyerRequest(updated);
      return RequestSubmissionResult.success(updated);
    } on StoreBackendException catch (error) {
      return RequestSubmissionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  /// Closes a real request at its expected revision.
  Future<RequestSubmissionResult> closeBuyerRequest({
    required String requestId,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final backend = requestsBackend;
    if (backend == null) {
      throw const StoreBackendException('Request changes are unavailable.');
    }
    try {
      final closed = await backend.closeRequest(
        requestId: requestId,
        expectedRevision: expectedRevision,
        operationKey: operationKey,
      );
      _upsertBuyerRequest(closed);
      return RequestSubmissionResult.success(closed);
    } on StoreBackendException catch (error) {
      return RequestSubmissionResult.failure(
        error.message,
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  void _upsertBuyerRequest(MarketplaceRequest request) {
    final next = List<MarketplaceRequest>.of(_buyerRequests);
    final index = next.indexWhere((row) => row.id == request.id);
    if (index < 0) {
      next.insert(0, request);
    } else {
      next[index] = request;
    }
    _buyerRequests = List<MarketplaceRequest>.unmodifiable(next);
    _notifyStore();
  }

  /// Reopens a real request through the server command and returns its
  /// authoritative revision. The first-acceptance window is preserved. One
  /// unresolved intent retains its request id, expected revision and operation
  /// key so a retry after a lost acknowledgement replays the same intent; a
  /// definitive rejection or an explicit [discardReopenIntent] starts a new one.
  Future<MarketplaceRequest> reopenBuyerRequest({
    required String requestId,
    required int expectedRevision,
  }) {
    final backend = requestsBackend;
    if (backend is! MarketplaceRequestReopenBackend) {
      throw const StoreBackendException(
        'Reopening is unavailable for this account.',
      );
    }
    final MarketplaceRequestReopenBackend reopenBackend =
        backend as MarketplaceRequestReopenBackend;
    final controller = _reopenIntent ??= RequestReopenIntentController(
      reopen:
          ({
            required requestId,
            required expectedRevision,
            required operationKey,
          }) => reopenBackend.reopenRequest(
            requestId: requestId,
            expectedRevision: expectedRevision,
            operationKey: operationKey,
          ),
      apply: (request) {
        if (!_disposed) _upsertBuyerRequest(request);
      },
    );
    return controller.run(
      requestId: requestId,
      expectedRevision: expectedRevision,
    );
  }

  RequestReopenIntentController? _reopenIntent;

  /// Abandons a retained reopen intent whose outcome is unknown, so the next
  /// attempt cannot be mistaken for the discarded one.
  void discardReopenIntent() => _reopenIntent?.discard();

  List<String> _offerTimezones = const <String>[];
  bool _offerTimezonesLoaded = false;
  String? _offerTimezonesError;

  List<String> get offerTimezones => List<String>.unmodifiable(_offerTimezones);

  bool get offerTimezonesLoaded => _offerTimezonesLoaded;

  String? get offerTimezonesError => _offerTimezonesError;

  bool get isOffersBacked => offersBackend != null;

  /// Loads the server-provided named timezones for scheduling.
  Future<void> refreshOfferTimezones() async {
    final backend = offersBackend;
    if (backend == null) return;
    try {
      final zones = await backend.loadTimezones();
      if (_disposed) return;
      _offerTimezones = zones;
      _offerTimezonesLoaded = true;
      _offerTimezonesError = null;
    } catch (error) {
      if (_disposed) return;
      _offerTimezonesError = error is StoreBackendException
          ? error.message
          : 'Could not load meeting timezones.';
    } finally {
      _notifyStore();
    }
  }

  /// Submits a real offer and returns a user-safe outcome. The caller keeps the
  /// same [operationKey] and payload for retries of the same intent; an
  /// uncertain outcome is reported so the caller can reconcile before a
  /// changed payload reuses the key.
  Future<OfferSubmissionResult> submitOfferForRequest({
    required String requestId,
    required OfferTerms terms,
    required String operationKey,
  }) async {
    final backend = offersBackend;
    if (backend == null) {
      throw const StoreBackendException('Offer submission is unavailable.');
    }
    try {
      final offer = await backend.submitOffer(
        requestId: requestId,
        terms: terms,
        operationKey: operationKey,
      );
      return OfferSubmissionResult.success(offer);
    } on StoreBackendException catch (error) {
      return OfferSubmissionResult.failure(
        error.message,
        ambiguousTime: error.code == 'ambiguous_local_time',
        outcomeUncertain: error.ambiguous,
      );
    }
  }

  List<SellerLeadProjection> _sellerLeads = const <SellerLeadProjection>[];
  bool _leadsLoading = false;
  String? _leadsError;
  int _leadsToken = 0;

  List<SellerLeadProjection> get sellerLeads =>
      List<SellerLeadProjection>.unmodifiable(_sellerLeads);

  bool get sellerLeadsLoading => _leadsLoading;

  String? get sellerLeadsError => _leadsError;

  bool get isLeadsBacked => leadsBackend != null;

  /// Loads the seller's leads. No-op without a backend; overlapping refreshes
  /// are versioned and a disposed repository applies nothing.
  Future<void> refreshSellerLeads() async {
    final backend = leadsBackend;
    if (backend == null) return;
    final token = ++_leadsToken;
    _leadsLoading = true;
    _leadsError = null;
    _notifyStore();
    try {
      final leads = await backend.loadLeads();
      if (_disposed || token != _leadsToken) return;
      _sellerLeads = leads;
    } catch (error) {
      if (_disposed || token != _leadsToken) return;
      _leadsError = error is StoreBackendException
          ? error.message
          : 'Could not load buyer requests. Pull to retry.';
    } finally {
      if (!_disposed && token == _leadsToken) {
        _leadsLoading = false;
        _notifyStore();
      }
    }
  }

  bool _storeLoading = false;
  String? _storeError;
  List<StoreCategoryOption> _storeCategories = const <StoreCategoryOption>[];
  bool _disposed = false;
  int _storeGeneration = 0;
  int _refreshToken = 0;
  final Map<String, int> _mutationTokens = <String, int>{};

  bool get storeLoading => _storeLoading;

  /// User-safe message for the last failed Store operation, if any.
  String? get storeError => _storeError;

  /// Catalogue categories for the Store editor in real mode. Empty in
  /// prototype mode.
  List<StoreCategoryOption> get storeCategories =>
      List<StoreCategoryOption>.unmodifiable(_storeCategories);

  bool get isStoreBacked => storeBackend != null;

  bool _leadCategoriesLoading = false;
  String? _leadCategoriesError;
  int _leadCategoriesToken = 0;

  bool get leadCategoriesLoading => _leadCategoriesLoading;

  /// User-safe message when the lead category list failed to load.
  String? get leadCategoriesError => _leadCategoriesError;

  /// Loads the admin-managed catalogue for the Seller lead filters without
  /// touching Store listing state, so a filter failure never replaces the
  /// approved Store screen's error surface.
  Future<void> refreshLeadCategories() async {
    final backend = storeBackend;
    if (backend == null) return;
    final token = ++_leadCategoriesToken;
    _leadCategoriesLoading = true;
    _leadCategoriesError = null;
    _notifyStore();
    try {
      final categories = await backend.loadCategories();
      if (_disposed || token != _leadCategoriesToken) return;
      _storeCategories = categories;
    } catch (error) {
      if (_disposed || token != _leadCategoriesToken) return;
      _leadCategoriesError = error is StoreBackendException
          ? error.message
          : 'Could not load categories.';
    } finally {
      if (!_disposed && token == _leadCategoriesToken) {
        _leadCategoriesLoading = false;
        _notifyStore();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reopenIntent?.dispose();
    _storeGeneration += 1;
    super.dispose();
  }

  void _notifyStore() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Loads the seller's Store and catalogue from the backend. No-op without a
  /// backend. Overlapping refreshes are versioned so an older response can
  /// never replace a newer cache, and a disposed repository applies nothing.
  Future<void> refreshStore() async {
    final backend = storeBackend;
    if (backend == null) return;
    final generation = _storeGeneration;
    final token = ++_refreshToken;
    _storeLoading = true;
    _storeError = null;
    _notifyStore();
    try {
      final listings = await backend.loadListings();
      final categories = await backend.loadCategories();
      if (!_isCurrentRefresh(generation, token)) return;
      _storeListings
        ..clear()
        ..addAll(listings);
      _storeCategories = categories;
    } catch (error) {
      if (!_isCurrentRefresh(generation, token)) return;
      _storeError = _storeMessage(error);
    } finally {
      if (_isCurrentRefresh(generation, token)) {
        _storeLoading = false;
        _notifyStore();
      }
    }
  }

  bool _isCurrentRefresh(int generation, int token) =>
      !_disposed && generation == _storeGeneration && token == _refreshToken;

  int _nextMutationToken(String id) {
    final next = (_mutationTokens[id] ?? 0) + 1;
    _mutationTokens[id] = next;
    return next;
  }

  bool _isCurrentMutation(String id, int token) =>
      !_disposed && _mutationTokens[id] == token;

  void _replaceListing(String id, LocalStoreListing listing) {
    final index = _storeListings.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _storeListings[index] = listing;
    } else {
      _storeListings.insert(0, listing);
    }
  }

  void _removeListing(String id) {
    _storeListings.removeWhere((item) => item.id == id);
  }

  static final math.Random _operationRandom = math.Random.secure();

  /// Opaque, client-owned operation key for one user intent. Allocated once by
  /// the caller and reused for retries of the same intent; never derived from
  /// backend state or payload hashes.
  static String newStoreOperationKey(String prefix) {
    final bytes = List<int>.generate(16, (_) => _operationRandom.nextInt(256));
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-$hex';
  }

  String _storeMessage(Object error) {
    if (error is StoreBackendException) return error.message;
    return 'Your Store change could not be saved. Try again.';
  }

  StoreBackendException _asStoreException(Object error) =>
      error is StoreBackendException
      ? error
      : StoreBackendException(_storeMessage(error));

  LocalOfferRecord? get latestOffer => _latestOffer;
  List<LocalChatEntry> get conversationEntries =>
      List<LocalChatEntry>.unmodifiable(_conversationEntries);
  List<LocalStoreListing> get storeListings =>
      List<LocalStoreListing>.unmodifiable(_storeListings);

  /// Saves a listing. Prototype mode completes immediately; real mode awaits
  /// the authoritative server result and never reports success before it.
  /// [operationKey] identifies one user intent across retries.
  Future<LocalStoreListing> saveStoreListing(
    LocalStoreListing listing, {
    String? operationKey,
  }) async {
    final backend = storeBackend;
    if (backend == null) {
      final index = _storeListings.indexWhere((item) => item.id == listing.id);
      if (index >= 0) {
        _storeListings[index] = listing;
        notifyListeners();
        return listing;
      }
      _listingSequence += 1;
      final saved = listing.copyWith(id: 'local-listing-$_listingSequence');
      _storeListings.insert(0, saved);
      notifyListeners();
      return saved;
    }
    final key = operationKey ?? newStoreOperationKey('store-save');
    final existingIndex = _storeListings.indexWhere(
      (item) => item.id == listing.id,
    );
    final previous = existingIndex >= 0 ? _storeListings[existingIndex] : null;
    final optimistic =
        (existingIndex >= 0 ? listing : listing.copyWith(id: 'pending-$key'))
            .copyWith(pendingSync: true);
    if (existingIndex >= 0) {
      _storeListings[existingIndex] = optimistic;
    } else {
      _storeListings.insert(0, optimistic);
    }
    final token = _nextMutationToken(optimistic.id);
    _storeError = null;
    _notifyStore();
    try {
      final result = await backend.saveListing(listing, operationKey: key);
      if (!_isCurrentMutation(optimistic.id, token)) return optimistic;
      _replaceListing(
        optimistic.id,
        result.listing.copyWith(pendingSync: false),
      );
      _storeError = result.warning;
      return result.listing;
    } catch (error) {
      if (!_isCurrentMutation(optimistic.id, token)) return optimistic;
      if (error is StoreBackendException && error.ambiguous) {
        _storeError = error.message;
        rethrow;
      }
      _removeListing(optimistic.id);
      if (previous != null) _replaceListing(previous.id, previous);
      _storeError = _storeMessage(error);
      throw _asStoreException(error);
    } finally {
      _notifyStore();
    }
  }

  /// Changes publication state. Prototype mode completes immediately; real
  /// mode awaits the server and keeps the previous state on definitive
  /// failure.
  Future<LocalStoreListing> updateStoreListingStatus(
    String id,
    LocalListingStatus status, {
    String? operationKey,
  }) async {
    final backend = storeBackend;
    if (backend == null) {
      final index = _storeListings.indexWhere((item) => item.id == id);
      if (index < 0) {
        throw const StoreBackendException(
          'That listing is no longer available.',
        );
      }
      final updated = _storeListings[index].copyWith(status: status);
      _storeListings[index] = updated;
      notifyListeners();
      return updated;
    }
    final index = _storeListings.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw const StoreBackendException(
        'That listing is no longer in your Store. Refresh and try again.',
      );
    }
    final previous = _storeListings[index];
    if (previous.revision < 1) {
      throw const StoreBackendException(
        'Refresh your Store before changing this listing.',
      );
    }
    final optimistic = previous.copyWith(status: status, pendingSync: true);
    _storeListings[index] = optimistic;
    final token = _nextMutationToken(id);
    _storeError = null;
    _notifyStore();
    try {
      final result = await backend.setListingStatus(
        id,
        status,
        operationKey: operationKey ?? newStoreOperationKey('store-status'),
        expectedRevision: previous.revision,
      );
      if (!_isCurrentMutation(id, token)) return optimistic;
      _replaceListing(id, result.listing.copyWith(pendingSync: false));
      _storeError = result.warning;
      return result.listing;
    } catch (error) {
      if (!_isCurrentMutation(id, token)) return optimistic;
      if (error is StoreBackendException && error.ambiguous) {
        _storeError = error.message;
        rethrow;
      }
      _replaceListing(id, previous);
      _storeError = _storeMessage(error);
      throw _asStoreException(error);
    } finally {
      _notifyStore();
    }
  }

  Future<LocalStoreListing?> duplicateStoreListing(
    String id, {
    String? operationKey,
  }) async {
    final backend = storeBackend;
    if (backend == null) {
      final index = _storeListings.indexWhere((item) => item.id == id);
      if (index < 0) return null;
      _listingSequence += 1;
      final duplicate = _storeListings[index].copyWith(
        id: 'local-listing-$_listingSequence',
        title: '${_storeListings[index].title} copy',
        status: LocalListingStatus.draft,
      );
      _storeListings.insert(0, duplicate);
      notifyListeners();
      return duplicate;
    }
    final index = _storeListings.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw const StoreBackendException(
        'That listing is no longer in your Store. Refresh and try again.',
      );
    }
    final source = _storeListings[index];
    final key = operationKey ?? newStoreOperationKey('store-duplicate');
    final optimistic = source.copyWith(
      id: 'pending-$key',
      title: '${source.title} copy',
      status: LocalListingStatus.draft,
      revision: 0,
      pendingReview: true,
      pendingSync: true,
    );
    _storeListings.insert(0, optimistic);
    final token = _nextMutationToken(optimistic.id);
    _storeError = null;
    _notifyStore();
    try {
      final result = await backend.duplicateListing(id, operationKey: key);
      if (!_isCurrentMutation(optimistic.id, token)) return optimistic;
      _replaceListing(
        optimistic.id,
        result.listing.copyWith(pendingSync: false),
      );
      _storeError = result.warning;
      return result.listing;
    } catch (error) {
      if (!_isCurrentMutation(optimistic.id, token)) return optimistic;
      if (error is StoreBackendException && error.ambiguous) {
        _storeError = error.message;
        rethrow;
      }
      _removeListing(optimistic.id);
      _storeError = _storeMessage(error);
      throw _asStoreException(error);
    } finally {
      _notifyStore();
    }
  }

  Future<void> deleteStoreListing(String id, {String? operationKey}) async {
    final backend = storeBackend;
    if (backend == null) {
      _storeListings.removeWhere((item) => item.id == id);
      notifyListeners();
      return;
    }
    final index = _storeListings.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final previous = _storeListings.removeAt(index);
    if (previous.revision < 1) {
      _storeListings.insert(index.clamp(0, _storeListings.length), previous);
      throw const StoreBackendException(
        'Refresh your Store before deleting this listing.',
      );
    }
    final token = _nextMutationToken(id);
    _storeError = null;
    _notifyStore();
    try {
      await backend.archiveListing(
        id,
        operationKey: operationKey ?? newStoreOperationKey('store-archive'),
        expectedRevision: previous.revision,
      );
      if (!_isCurrentMutation(id, token)) return;
    } catch (error) {
      if (!_isCurrentMutation(id, token)) return;
      final ambiguous = error is StoreBackendException && error.ambiguous;
      _storeListings.insert(
        index.clamp(0, _storeListings.length),
        previous.copyWith(pendingSync: ambiguous),
      );
      _storeError = _storeMessage(error);
      throw _asStoreException(error);
    } finally {
      _notifyStore();
    }
  }

  void submitOffer(LocalOfferRecord offer) {
    _latestOffer = offer;
    notifyListeners();
  }

  void updateOfferStatus(LocalOfferStatus status) {
    final offer = _latestOffer;
    if (offer == null) return;
    _latestOffer = offer.copyWith(status: status);
    notifyListeners();
  }

  LocalChatEntry addConversationEntry({
    required bool senderIsSeller,
    String text = '',
    String? attachmentLabel,
    bool attachmentIsImage = false,
  }) {
    _sequence += 1;
    final entry = LocalChatEntry(
      id: 'local-message-$_sequence',
      senderIsSeller: senderIsSeller,
      sentAtLabel: 'Now',
      text: text,
      attachmentLabel: attachmentLabel,
      attachmentIsImage: attachmentIsImage,
    );
    _conversationEntries.add(entry);
    notifyListeners();
    return entry;
  }

  String encodeSnapshot() {
    return jsonEncode({
      'latestOffer': _latestOffer?.toJson(),
      'conversationEntries': _conversationEntries
          .map((entry) => entry.toJson())
          .toList(),
      'sequence': _sequence,
      'storeListings': _storeListings
          .map((listing) => listing.toJson())
          .toList(),
      'listingSequence': _listingSequence,
    });
  }

  void restoreSnapshot(String? encoded) {
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final offer = decoded['latestOffer'];
      _latestOffer = offer is Map<String, Object?>
          ? LocalOfferRecord.fromJson(offer)
          : null;
      _conversationEntries
        ..clear()
        ..addAll(
          ((decoded['conversationEntries'] as List<Object?>?) ?? const [])
              .whereType<Map<String, Object?>>()
              .map(LocalChatEntry.fromJson),
        );
      _sequence =
          (decoded['sequence'] as num?)?.toInt() ?? _conversationEntries.length;
      final listings = decoded['storeListings'];
      if (listings is List<Object?>) {
        _storeListings
          ..clear()
          ..addAll(
            listings.whereType<Map<String, Object?>>().map(
              LocalStoreListing.fromJson,
            ),
          );
      }
      _listingSequence =
          (decoded['listingSequence'] as num?)?.toInt() ??
          _storeListings.length;
    } on FormatException {
      // Ignore stale prototype snapshots and retain the safe defaults.
    } on TypeError {
      // Ignore snapshots created by an older incompatible local schema.
    }
  }
}
