/// Communications-completion domain contracts.
///
/// Package-specific additions for the chat safety (block), server search and
/// call lifecycle work. These types are intentionally separate from the
/// coordinator-owned `conversations.dart`, `repositories.dart` and
/// `notifications.dart` so the shared contracts stay unchanged; the chat data
/// adapter implements both this interface and the existing
/// `ConversationRepository`.
///
/// Rules preserved here:
/// - Block state and search results are server-owned; clients never infer
///   authorization from a hidden control.
/// - Call state is server-owned with an explicit terminal flag; clients never
///   decide a terminal state locally.
library;

import 'common.dart';
import 'conversations.dart';
import 'failures.dart';
import 'notification_destination.dart';
import 'notifications.dart';

/// Server call states. `unknown` covers a future server state without
/// pretending it is one of the known terminals.
enum CallLifecycleState {
  ringing,
  accepted,
  declined,
  cancelled,
  ended,
  missed,
  unknown,
}

bool _isTerminal(CallLifecycleState state) =>
    state != CallLifecycleState.ringing && state != CallLifecycleState.accepted;

/// One authoritative call projection from the `call_status` RPC.
class CallSessionStatus {
  CallSessionStatus({
    required String id,
    required String conversationId,
    required String callerUserId,
    required String calleeUserId,
    required this.state,
    required DateTime createdAt,
    required DateTime expiresAt,
    required DateTime serverNow,
    required this.enabled,
    required this.settingsRevision,
    bool? isTerminal,
  }) : id = requireNonBlank(id, 'id'),
       conversationId = requireNonBlank(conversationId, 'conversationId'),
       callerUserId = requireNonBlank(callerUserId, 'callerUserId'),
       calleeUserId = requireNonBlank(calleeUserId, 'calleeUserId'),
       createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc(),
       serverNow = serverNow.toUtc(),
       isTerminal = isTerminal ?? _isTerminal(state) {
    if (settingsRevision < 0) {
      throw ArgumentError.value(
        settingsRevision,
        'settingsRevision',
        'must not be negative',
      );
    }
  }

  final String id;
  final String conversationId;
  final String callerUserId;
  final String calleeUserId;
  final CallLifecycleState state;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime serverNow;

  /// Admin switch state at read time. False means calls are off and any active
  /// call was already ended server-side.
  final bool enabled;
  final int settingsRevision;

  /// Server-reported terminal state. Callers never compute this from local
  /// timers; an unknown future state stays nonterminal unless the server says
  /// otherwise.
  final bool isTerminal;

  /// Remaining server time before an automatic timeout; never negative.
  Duration get remaining {
    final left = expiresAt.difference(serverNow);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  String toString() =>
      'CallSessionStatus($id, ${state.name}, terminal: $isTerminal, enabled: $enabled)';
}

/// One server-ordered call signal delivered to the other participant.
class CallSignalEnvelope {
  const CallSignalEnvelope({
    required this.sequence,
    required this.kind,
    required this.payload,
  });

  final int sequence;
  final String kind;
  final Map<String, Object?> payload;
}

/// Read result for [CallSessionStatus] plus signals after the cursor.
class CallStatusSnapshot {
  CallStatusSnapshot({
    required this.call,
    List<CallSignalEnvelope> signals = const [],
  }) : signals = List<CallSignalEnvelope>.unmodifiable(signals);

  final CallSessionStatus call;
  final List<CallSignalEnvelope> signals;
}

/// Per-viewer block state for one conversation.
///
/// `isBlockedByMe` is only ever true for the member who recorded the block.
/// `blockedByCounterpart` lets the blocked member render an honest
/// "messages are unavailable" state without exposing who blocked them or why.
class ConversationBlockState {
  const ConversationBlockState({
    required this.conversationId,
    required this.isBlockedByMe,
    required this.blockedByCounterpart,
    required this.conversationStatus,
    required this.canMessage,
  });

  final String conversationId;
  final bool isBlockedByMe;
  final bool blockedByCounterpart;
  final ConversationStatus conversationStatus;
  final bool canMessage;

  bool get hasActiveBlock => isBlockedByMe || blockedByCounterpart;

  ConversationBlockState copyWith({
    bool? isBlockedByMe,
    bool? blockedByCounterpart,
    ConversationStatus? conversationStatus,
    bool? canMessage,
  }) => ConversationBlockState(
    conversationId: conversationId,
    isBlockedByMe: isBlockedByMe ?? this.isBlockedByMe,
    blockedByCounterpart: blockedByCounterpart ?? this.blockedByCounterpart,
    conversationStatus: conversationStatus ?? this.conversationStatus,
    canMessage: canMessage ?? this.canMessage,
  );

  @override
  String toString() =>
      'ConversationBlockState($conversationId, byMe: $isBlockedByMe, '
      'blockedByCounterpart: $blockedByCounterpart, canMessage: $canMessage)';
}

/// One server-side message search hit with the conversation context needed to
/// render a result row and open the conversation.
class ChatSearchHit {
  ChatSearchHit({
    required this.message,
    required String conversationId,
    required this.origin,
    required this.conversationStatus,
    required String counterpartDisplayName,
    this.senderDisplayName,
  }) : conversationId = requireNonBlank(conversationId, 'conversationId'),
       counterpartDisplayName = requireNonBlank(
         counterpartDisplayName,
         'counterpartDisplayName',
       );

  final ConversationMessage message;
  final String conversationId;
  final ConversationOrigin origin;
  final ConversationStatus conversationStatus;
  final String counterpartDisplayName;
  final String? senderDisplayName;

  @override
  String toString() =>
      'ChatSearchHit(${message.id}, conversation: $conversationId)';
}

/// Command for recording the caller's own block in one conversation.
class BlockConversationCommand {
  BlockConversationCommand({
    required String conversationId,
    required String userId,
    this.reasonCode,
    required String idempotencyKey,
  }) : conversationId = requireNonBlank(conversationId, 'conversationId'),
       userId = requireNonBlank(userId, 'userId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (reasonCode != null &&
        !const {
          'safety',
          'harassment',
          'spam',
          'deal_dispute',
          'other',
        }.contains(reasonCode)) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'is not a reviewed reason',
      );
    }
  }

  final String conversationId;
  final String userId;
  final String? reasonCode;
  final String idempotencyKey;
}

/// Unblock command for the caller's own active block.
class UnblockConversationCommand {
  UnblockConversationCommand({
    required String conversationId,
    required String userId,
    required String idempotencyKey,
  }) : conversationId = requireNonBlank(conversationId, 'conversationId'),
       userId = requireNonBlank(userId, 'userId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final String conversationId;
  final String userId;
  final String idempotencyKey;
}

final RegExp _callEventUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The reviewed call-event navigation contract shared with the notification
/// producers.
///
/// Migration 153 emits call rows as `meeting_update` with a
/// `hocalist://chat/<conversationId>` deep link and a payload carrying
/// `call_id` (plus `conversation_id`). This helper recognizes exactly that
/// shape so a call tap opens the conversation where the call happened. Any
/// other kind/URL combination, a missing/malformed call id, a non-chat host or
/// a mismatched payload conversation stays unrecognized instead of guessing.
NotificationDestination? callEventDestination(NotificationInboxItem item) {
  if (_callEventCallId(item) == null) return null;
  final uri = _callEventUri(item);
  if (uri == null) return null;
  return NotificationDestination(
    NotificationDestinationKind.chat,
    uri.pathSegments.single,
  );
}

/// The validated call id for a producer-shaped call notification, or null.
/// Used for tests and diagnostics; navigation does not need it.
String? callEventCallId(NotificationInboxItem item) => _callEventCallId(item);

String? _callEventCallId(NotificationInboxItem item) {
  if (item.kind != 'meeting_update') return null;
  final payload = item.payload;
  final callId = payload?['call_id'];
  if (callId is! String || !_callEventUuid.hasMatch(callId)) return null;
  final payloadConversation = payload?['conversation_id'];
  final uri = _callEventUri(item);
  if (uri == null) return null;
  if (payloadConversation is String &&
      payloadConversation != uri.pathSegments.single) {
    return null;
  }
  return callId;
}

Uri? _callEventUri(NotificationInboxItem item) {
  final uri = Uri.tryParse(item.deepLink ?? '');
  if (uri == null ||
      uri.scheme != 'hocalist' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.host != 'chat' ||
      uri.pathSegments.length != 1 ||
      !_callEventUuid.hasMatch(uri.pathSegments.single)) {
    return null;
  }
  return uri;
}

/// Chat safety and search operations implemented by the chat adapter on top of
/// the existing `ConversationRepository`.
abstract interface class ConversationSafetyRepository {
  /// Block state for the authenticated caller only.
  Future<RepositoryResult<ConversationBlockState>> fetchBlockState({
    required String conversationId,
    required String userId,
  });

  /// Records (or returns) the caller's active block. No deal, credit, meeting,
  /// message or membership row is changed.
  Future<RepositoryResult<ConversationBlockState>> blockConversation(
    BlockConversationCommand command,
  );

  /// Reverses the caller's own active block. Idempotent.
  Future<RepositoryResult<ConversationBlockState>> unblockConversation(
    UnblockConversationCommand command,
  );

  /// Participant-only paged message search, optionally scoped to one
  /// conversation.
  Future<RepositoryResult<PageSlice<ChatSearchHit>>> searchMessages({
    required String userId,
    required String query,
    PageQuery page = PageQuery.standard,
    String? conversationId,
  });

  /// Participant-only paged conversation search over counterpart names.
  Future<RepositoryResult<PageSlice<ConversationSummary>>> searchConversations({
    required String userId,
    required String query,
    PageQuery page = PageQuery.standard,
  });
}
