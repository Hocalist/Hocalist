/// Conversation, member and message contracts for Phase 2.
///
/// A conversation is a participant-owned record linked by IDs to its members,
/// optional request/offer/listing subject and its messages. Messages are a
/// separate ordered collection; the conversation does not store one
/// "latest message" field.
///
/// Origin distinguishes a targeted-request deal conversation from Store and
/// Hocatrends discovery enquiries. Chargeability, rewards and block/mute
/// enforcement remain server policy (SEC-11) and are not inferred here.
library;

import 'common.dart';
import 'media_reference.dart';
import 'profiles.dart';

/// Why a conversation exists.
enum ConversationOrigin {
  /// Opened from a buyer request after the buyer selects a seller offer.
  /// Targeting-fee and reward policy applies to this origin server-side.
  targetedRequest,

  /// Opened from a seller Store listing. No targeting fee or buyer reward.
  storeListing,

  /// Opened from Hocatrends discovery. No targeting fee or buyer reward.
  hocatrendsEnquiry,
}

enum ConversationStatus { open, closed }

enum MessageKind { text, attachment, systemNotice }

/// One participant in a conversation. Mute and read markers are per member.
class ConversationMember {
  ConversationMember({
    required String userId,
    required String profileId,
    required this.role,
    required DateTime joinedAt,
    this.isMuted = false,
    this.lastReadMessageId,
    DateTime? lastReadAt,
  }) : userId = requireNonBlank(userId, 'userId'),
       profileId = requireNonBlank(profileId, 'profileId'),
       joinedAt = joinedAt.toUtc(),
       lastReadAt = lastReadAt?.toUtc();

  final String userId;
  final String profileId;
  final HocalistRole role;
  final DateTime joinedAt;

  /// Per-member chat mute. Critical deal and safety alerts are separate.
  final bool isMuted;

  /// Highest message this member has read, for unread counts.
  final String? lastReadMessageId;

  final DateTime? lastReadAt;

  ConversationMember copyWith({
    bool? isMuted,
    String? lastReadMessageId,
    DateTime? lastReadAt,
  }) {
    return ConversationMember(
      userId: userId,
      profileId: profileId,
      role: role,
      joinedAt: joinedAt,
      isMuted: isMuted ?? this.isMuted,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  @override
  String toString() =>
      'ConversationMember($profileId, ${role.name}, muted: $isMuted)';
}

/// One persisted message. [clientMessageId] lets a retried send deduplicate.
class ConversationMessage {
  ConversationMessage({
    required String id,
    required String conversationId,
    required String senderUserId,
    this.kind = MessageKind.text,
    this.text = '',
    List<MediaReference> attachments = const [],
    required DateTime sentAt,
    this.clientMessageId,
  }) : id = requireNonBlank(id, 'id'),
       conversationId = requireNonBlank(conversationId, 'conversationId'),
       senderUserId = requireNonBlank(senderUserId, 'senderUserId'),
       attachments = List<MediaReference>.unmodifiable(attachments),
       sentAt = sentAt.toUtc() {
    if (text.trim().isEmpty && attachments.isEmpty) {
      throw ArgumentError(
        'a message must carry text or at least one attachment',
      );
    }
    if (text.length > 4000) {
      throw ArgumentError.value(
        text.length,
        'text',
        'must be at most 4000 characters',
      );
    }
    if (kind == MessageKind.systemNotice && attachments.isNotEmpty) {
      throw ArgumentError('a system notice cannot carry attachments');
    }
  }

  final String id;
  final String conversationId;
  final String senderUserId;
  final MessageKind kind;
  final String text;
  final List<MediaReference> attachments;
  final DateTime sentAt;

  /// Client-generated deduplication key, echoed by the server when present.
  final String? clientMessageId;

  @override
  String toString() =>
      'ConversationMessage($id, conversation: $conversationId, '
      'kind: ${kind.name}, attachments: ${attachments.length})';
}

/// A conversation record. Messages are read separately so history can be
/// paginated instead of reduced to a single latest slot.
class Conversation {
  Conversation({
    required String id,
    required this.origin,
    required List<ConversationMember> members,
    required this.status,
    required this.stamp,
    this.requestId,
    this.offerId,
    this.listingId,
    this.discoveryTopicId,
  }) : id = requireNonBlank(id, 'id'),
       members = List<ConversationMember>.unmodifiable(members) {
    if (members.isEmpty) {
      throw ArgumentError.value(
        members,
        'members',
        'a conversation needs at least one member',
      );
    }
    _validateSubject();
  }

  final String id;
  final ConversationOrigin origin;
  final List<ConversationMember> members;
  final ConversationStatus status;

  /// Targeted-request conversations only.
  final String? requestId;

  /// Targeted-request conversations only, once an offer is selected.
  final String? offerId;

  /// Store listing conversations only.
  final String? listingId;

  /// Hocatrends enquiry conversations only.
  final String? discoveryTopicId;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  /// True for deal-scoped conversations. Fee policy is still server-owned.
  bool get isDealScoped => origin == ConversationOrigin.targetedRequest;

  ConversationMember? memberFor(String userId) {
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    return null;
  }

  void _validateSubject() {
    switch (origin) {
      case ConversationOrigin.targetedRequest:
        requireNonBlank(requestId ?? '', 'requestId');
        if (listingId != null || discoveryTopicId != null) {
          throw ArgumentError(
            'a targeted-request conversation cannot link a listing or topic',
          );
        }
      case ConversationOrigin.storeListing:
        requireNonBlank(listingId ?? '', 'listingId');
        if (requestId != null || offerId != null || discoveryTopicId != null) {
          throw ArgumentError(
            'a store-listing conversation cannot link a request, offer or '
            'discovery topic',
          );
        }
      case ConversationOrigin.hocatrendsEnquiry:
        requireNonBlank(discoveryTopicId ?? '', 'discoveryTopicId');
        if (requestId != null || offerId != null || listingId != null) {
          throw ArgumentError(
            'a Hocatrends enquiry cannot link a request, offer or listing',
          );
        }
    }
  }

  @override
  String toString() =>
      'Conversation($id, ${origin.name}, members: ${members.length}, '
      'status: ${status.name})';
}

/// Inbox read model for one conversation, scoped to the viewer.
class ConversationSummary {
  ConversationSummary({
    required this.conversation,
    required String counterpartDisplayName,
    this.counterpartProfileId,
    this.latestMessage,
    this.unreadCount = 0,
  }) : counterpartDisplayName = requireNonBlank(
         counterpartDisplayName,
         'counterpartDisplayName',
       ) {
    if (unreadCount < 0) {
      throw ArgumentError.value(
        unreadCount,
        'unreadCount',
        'must not be negative',
      );
    }
    final profileId = counterpartProfileId;
    if (profileId != null &&
        !conversation.members.any((member) => member.profileId == profileId)) {
      throw ArgumentError.value(
        profileId,
        'counterpartProfileId',
        'must reference a member of this conversation',
      );
    }
  }

  final Conversation conversation;
  final String counterpartDisplayName;
  final String? counterpartProfileId;

  /// Server-provided preview for the inbox row. Full history is paged from
  /// [ConversationRepository.fetchMessages].
  final ConversationMessage? latestMessage;

  final int unreadCount;

  @override
  String toString() =>
      'ConversationSummary(${conversation.id}, $counterpartDisplayName, '
      'unread: $unreadCount)';
}

/// Opens or returns the deal conversation for a selected offer.
class OpenTargetedRequestConversationCommand {
  OpenTargetedRequestConversationCommand({
    required String requestId,
    required String offerId,
    required String buyerUserId,
    required String idempotencyKey,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       offerId = requireNonBlank(offerId, 'offerId'),
       buyerUserId = requireNonBlank(buyerUserId, 'buyerUserId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final String requestId;
  final String offerId;
  final String buyerUserId;
  final String idempotencyKey;
}

/// Opens a Store or Hocatrends enquiry conversation.
///
/// [origin] must be [ConversationOrigin.storeListing] or
/// [ConversationOrigin.hocatrendsEnquiry]; targeted-request chats use
/// [OpenTargetedRequestConversationCommand].
///
/// A Hocatrends enquiry targets one seller through [sellerProfileId]. The field
/// is validated whenever supplied and is kept optional so every existing
/// construction stays source-compatible; the enquiry-opening command that
/// consumes it requires the seller before issuing a request.
class OpenDiscoveryEnquiryCommand {
  OpenDiscoveryEnquiryCommand({
    required this.origin,
    required String subjectId,
    required String initiatedByUserId,
    required String idempotencyKey,
    String? sellerProfileId,
  }) : subjectId = requireNonBlank(subjectId, 'subjectId'),
       initiatedByUserId = requireNonBlank(
         initiatedByUserId,
         'initiatedByUserId',
       ),
       sellerProfileId = optionalNonBlank(sellerProfileId, 'sellerProfileId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (origin == ConversationOrigin.targetedRequest) {
      throw ArgumentError.value(
        origin,
        'origin',
        'targeted-request conversations need the offer-based command',
      );
    }
  }

  final ConversationOrigin origin;
  final String subjectId;
  final String initiatedByUserId;

  /// Seller membership id targeted by a Hocatrends enquiry. Optional for
  /// compatibility; non-blank whenever supplied.
  final String? sellerProfileId;

  final String idempotencyKey;
}

/// Sends one message. [clientMessageId] makes retries safe.
class SendMessageCommand {
  SendMessageCommand({
    required String conversationId,
    required String senderUserId,
    this.text = '',
    List<String> attachmentMediaIds = const [],
    required String clientMessageId,
  }) : conversationId = requireNonBlank(conversationId, 'conversationId'),
       senderUserId = requireNonBlank(senderUserId, 'senderUserId'),
       attachmentMediaIds = requireNonBlankIds(
         attachmentMediaIds,
         'attachmentMediaIds',
       ),
       clientMessageId = requireNonBlank(clientMessageId, 'clientMessageId') {
    if (text.trim().isEmpty && attachmentMediaIds.isEmpty) {
      throw ArgumentError(
        'a send command must carry text or at least one attachment id',
      );
    }
  }

  final String conversationId;
  final String senderUserId;
  final String text;
  final List<String> attachmentMediaIds;

  /// Client-generated deduplication key for the send.
  final String clientMessageId;
}

/// Marks everything up to [lastReadMessageId] as read for one member.
class MarkConversationReadCommand {
  MarkConversationReadCommand({
    required String conversationId,
    required String userId,
    required String lastReadMessageId,
  }) : conversationId = requireNonBlank(conversationId, 'conversationId'),
       userId = requireNonBlank(userId, 'userId'),
       lastReadMessageId = requireNonBlank(
         lastReadMessageId,
         'lastReadMessageId',
       );

  final String conversationId;
  final String userId;
  final String lastReadMessageId;
}

/// Sets the per-member mute flag. Blocking and reporting remain separate
/// safety workflows with server policy.
class SetConversationMutedCommand {
  SetConversationMutedCommand({
    required String conversationId,
    required String userId,
    required this.isMuted,
    required String idempotencyKey,
  }) : conversationId = requireNonBlank(conversationId, 'conversationId'),
       userId = requireNonBlank(userId, 'userId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final String conversationId;
  final String userId;
  final bool isMuted;
  final String idempotencyKey;
}
