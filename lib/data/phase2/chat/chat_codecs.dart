/// Strict decoders for the chat wire shapes from draft 010.
///
/// Every decoder validates required fields, types, enum values, positive
/// revisions/sequences and parseable timestamps. Failures raise
/// [ChatDecodeException] with a safe field path; message text, participant
/// values and server messages are never included.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/communication_completion.dart';
import '../../../domain/phase2/conversations.dart';
import '../../../domain/phase2/media_reference.dart';
import '../../../domain/phase2/profiles.dart';
import '../accounts/timestamptz.dart';

final RegExp _mediaIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

List<MediaReference> _decodeAttachments(
  Map<String, Object?> json,
  String context,
) {
  final raw = json['attachment_media_ids'];
  if (raw == null) return const <MediaReference>[];
  if (raw is! List || raw.length > 4) {
    throw ChatDecodeException('$context.attachment_media_ids');
  }
  final references = <MediaReference>[];
  for (final item in raw) {
    if (item is! String || !_mediaIdPattern.hasMatch(item)) {
      throw ChatDecodeException('$context.attachment_media_ids');
    }
    references.add(
      MediaReference(
        id: item,
        kind: MediaKind.image,
        fileName: 'chat-image-${references.length + 1}.jpg',
        contentType: 'image/jpeg',
      ),
    );
  }
  return references;
}

class ChatDecodeException implements Exception {
  const ChatDecodeException(this.detail);

  final String detail;

  @override
  String toString() => 'ChatDecodeException($detail)';
}

Map<String, Object?> decodeObject(Object? data, String context) {
  if (data is! Map) throw ChatDecodeException('$context.result');
  try {
    return Map<String, Object?>.from(data);
  } on TypeError {
    throw ChatDecodeException('$context.result');
  }
}

List<Map<String, Object?>> decodeObjectList(Object? data, String context) {
  if (data is! List) throw ChatDecodeException('$context.items');
  final rows = <Map<String, Object?>>[];
  for (final entry in data) {
    if (entry is! Map) throw ChatDecodeException('$context.item');
    try {
      rows.add(Map<String, Object?>.from(entry));
    } on TypeError {
      throw ChatDecodeException('$context.item');
    }
  }
  return rows;
}

ConversationMember decodeMemberJson(Map<String, Object?> row) {
  final role = _requireEnum(
    HocalistRole.values,
    _requireString(row, 'role', 'member.role'),
    'member.role',
  );
  return ConversationMember(
    userId: _requireString(row, 'user_id', 'member.user_id'),
    profileId: _requireString(row, 'profile_id', 'member.profile_id'),
    role: role,
    joinedAt: _requireTimestamp(row, 'joined_at', 'member.joined_at'),
    isMuted: _requireBool(row, 'is_muted', 'member.is_muted'),
    lastReadMessageId: _optionalString(row, 'last_read_message_id'),
    lastReadAt: _optionalTimestamp(row, 'last_read_at', 'member.last_read_at'),
  );
}

Conversation decodeConversationJson(Map<String, Object?> json) {
  final members = decodeObjectList(
    json['members'],
    'conversation',
  ).map(decodeMemberJson).toList(growable: false);
  return Conversation(
    id: _requireString(json, 'id', 'conversation.id'),
    origin: _requireEnum(
      ConversationOrigin.values,
      _requireString(json, 'origin', 'conversation.origin'),
      'conversation.origin',
    ),
    members: members,
    status: _requireEnum(
      ConversationStatus.values,
      _requireString(json, 'status', 'conversation.status'),
      'conversation.status',
    ),
    stamp: RecordStamp(
      revision: _requirePositiveInt(json, 'revision', 'conversation.revision'),
      createdAt: _requireTimestamp(
        json,
        'created_at',
        'conversation.created_at',
      ),
      updatedAt: _requireTimestamp(
        json,
        'updated_at',
        'conversation.updated_at',
      ),
    ),
    requestId: _optionalString(json, 'request_id'),
    offerId: _optionalString(json, 'offer_id'),
    listingId: _optionalString(json, 'listing_id'),
    discoveryTopicId: _optionalString(json, 'discovery_topic_id'),
  );
}

ConversationMessage decodeMessageJson(Map<String, Object?> json) {
  final text = _requireString(json, 'text', 'message.text', allowEmpty: true);
  final kind = _requireEnum(
    MessageKind.values,
    _requireString(json, 'kind', 'message.kind'),
    'message.kind',
  );
  if (kind != MessageKind.text &&
      kind != MessageKind.attachment &&
      kind != MessageKind.systemNotice) {
    throw const ChatDecodeException('message.kind');
  }
  final attachments = _decodeAttachments(json, 'message');
  if (kind == MessageKind.attachment && attachments.isEmpty) {
    throw const ChatDecodeException('message.attachment_media_ids');
  }
  if (kind != MessageKind.attachment && attachments.isNotEmpty) {
    throw const ChatDecodeException('message.attachment_media_ids');
  }
  if (text.trim().isEmpty && kind != MessageKind.attachment) {
    throw const ChatDecodeException('message.text');
  }
  return ConversationMessage(
    id: _requireString(json, 'id', 'message.id'),
    conversationId: _requireString(
      json,
      'conversation_id',
      'message.conversation_id',
    ),
    senderUserId: _requireString(
      json,
      'sender_user_id',
      'message.sender_user_id',
    ),
    kind: kind,
    text: text,
    attachments: attachments,
    sentAt: _requireTimestamp(json, 'sent_at', 'message.sent_at'),
    clientMessageId: _optionalString(json, 'client_message_id'),
    offerId: _optionalString(json, 'offer_id'),
    readByCounterpart: json['read_by_counterpart'] == true,
  );
}

ConversationSummary decodeInboxItemJson(Map<String, Object?> json) {
  final conversationJson = decodeObject(
    json['conversation'],
    'inbox.conversation',
  );
  final latestJson = json['latest_message'];
  final ConversationMessage? latest;
  if (latestJson == null) {
    latest = null;
  } else {
    latest = decodeMessageJson(
      decodeObject(latestJson, 'inbox.latest_message'),
    );
  }
  final ConversationSummary summary;
  try {
    summary = ConversationSummary(
      conversation: decodeConversationJson(conversationJson),
      counterpartDisplayName: _requireString(
        json,
        'counterpart_display_name',
        'inbox.counterpart_display_name',
      ),
      counterpartProfileId: _optionalString(json, 'counterpart_profile_id'),
      latestMessage: latest,
      unreadCount: _requireNonNegativeInt(
        json,
        'unread_count',
        'inbox.unread_count',
      ),
    );
  } on ArgumentError {
    throw const ChatDecodeException('inbox.item');
  }
  return summary;
}

PageSlice<ConversationSummary> decodeInboxPage(Map<String, Object?> json) {
  final items = decodeObjectList(
    json['items'],
    'inbox',
  ).map(decodeInboxItemJson).toList(growable: false);
  return PageSlice<ConversationSummary>(
    items: items,
    nextCursor: _optionalString(json, 'next_cursor'),
  );
}

PageSlice<ConversationMessage> decodeMessagePage(Map<String, Object?> json) {
  final items = decodeObjectList(
    json['items'],
    'messages',
  ).map(decodeMessageJson).toList(growable: false);
  return PageSlice<ConversationMessage>(
    items: items,
    nextCursor: _optionalString(json, 'next_cursor'),
  );
}

ConversationBlockState decodeBlockStateJson(Map<String, Object?> json) {
  final status = _requireEnum(
    ConversationStatus.values,
    _requireString(json, 'conversation_status', 'block.conversation_status'),
    'block.conversation_status',
  );
  try {
    return ConversationBlockState(
      conversationId: _requireString(
        json,
        'conversation_id',
        'block.conversation_id',
      ),
      isBlockedByMe: _requireBool(
        json,
        'is_blocked_by_me',
        'block.is_blocked_by_me',
      ),
      blockedByCounterpart: _requireBool(
        json,
        'blocked_by_counterpart',
        'block.blocked_by_counterpart',
      ),
      conversationStatus: status,
      canMessage: _requireBool(json, 'can_message', 'block.can_message'),
    );
  } on ArgumentError {
    throw const ChatDecodeException('block.state');
  }
}

PageSlice<ChatSearchHit> decodeSearchPage(
  Map<String, Object?> json, {
  String? viewerUserId,
}) {
  final items = decodeObjectList(json['items'], 'search')
      .map((row) {
        try {
          return ChatSearchHit(
            senderDisplayName: viewerUserId == null
                ? null
                : decodeObject(
                        row['message'],
                        'search.message',
                      )['sender_user_id'] ==
                      viewerUserId
                ? 'You'
                : _requireString(
                    row,
                    'counterpart_display_name',
                    'search.counterpart_display_name',
                  ),
            message: decodeMessageJson(
              decodeObject(row['message'], 'search.message'),
            ),
            conversationId: _requireString(
              row,
              'conversation_id',
              'search.conversation_id',
            ),
            origin: _requireEnum(
              ConversationOrigin.values,
              _requireString(
                row,
                'conversation_origin',
                'search.conversation_origin',
              ),
              'search.conversation_origin',
            ),
            conversationStatus: _requireEnum(
              ConversationStatus.values,
              _requireString(
                row,
                'conversation_status',
                'search.conversation_status',
              ),
              'search.conversation_status',
            ),
            counterpartDisplayName: _requireString(
              row,
              'counterpart_display_name',
              'search.counterpart_display_name',
            ),
          );
        } on ArgumentError {
          throw const ChatDecodeException('search.item');
        }
      })
      .toList(growable: false);
  return PageSlice<ChatSearchHit>(
    items: items,
    nextCursor: _optionalString(json, 'next_cursor'),
  );
}

String _requireString(
  Map<String, Object?> row,
  String key,
  String context, {
  bool allowEmpty = false,
}) {
  final value = row[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw ChatDecodeException(context);
  }
  return value;
}

String? _optionalString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw ChatDecodeException(key);
  }
  return value;
}

bool _requireBool(Map<String, Object?> row, String key, String context) {
  final value = row[key];
  if (value is! bool) throw ChatDecodeException(context);
  return value;
}

int _requirePositiveInt(Map<String, Object?> row, String key, String context) {
  final value = row[key];
  if (value is! int || value < 1) throw ChatDecodeException(context);
  return value;
}

int _requireNonNegativeInt(
  Map<String, Object?> row,
  String key,
  String context,
) {
  final value = row[key];
  if (value is! int || value < 0) throw ChatDecodeException(context);
  return value;
}

DateTime _requireTimestamp(
  Map<String, Object?> row,
  String key,
  String context,
) {
  final value = row[key];
  if (value is! String) throw ChatDecodeException(context);
  try {
    return parsePostgresTimestamptz(value, context: context);
  } catch (_) {
    throw ChatDecodeException(context);
  }
}

DateTime? _optionalTimestamp(
  Map<String, Object?> row,
  String key,
  String context,
) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String) throw ChatDecodeException(context);
  try {
    return parsePostgresTimestamptz(value, context: context);
  } catch (_) {
    throw ChatDecodeException(context);
  }
}

T _requireEnum<T extends Enum>(List<T> values, String wire, String context) {
  final normalized = wire.replaceAll('_', '');
  for (final value in values) {
    if (value.name.toLowerCase() == normalized.toLowerCase()) return value;
  }
  throw ChatDecodeException(context);
}
