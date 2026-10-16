/// Chat adapter backed by the reviewed draft-010 RPCs.
///
/// Implements the `ConversationRepository` reads and text operations that the
/// SQL foundation supports today. Identity comes from the injected session;
/// caller-supplied user ids are checked against it, never trusted. Opening a
/// conversation and attachments are deliberately unavailable and return
/// explicit typed failures instead of pretending success.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/communication_completion.dart';
import '../../../domain/phase2/conversations.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/repositories.dart';
import 'chat_codecs.dart';
import 'chat_error_mapper.dart';
import 'chat_session.dart';
import 'chat_transport.dart';

class ChatDataAdapter
    implements ConversationRepository, ConversationSafetyRepository {
  ChatDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const ChatErrorMapper(),
  });

  static const String schema = 'hocalist';
  static const String inboxFunction = 'chat_inbox';
  static const String conversationFunction = 'chat_conversation';
  static const String messagesFunction = 'chat_messages';
  static const String sendFunction = 'chat_send';
  static const String sendAttachmentFunction = 'chat_send_attachment';
  static const String markReadFunction = 'chat_mark_read';
  static const String muteFunction = 'chat_set_muted';
  static const String blockStateFunction = 'chat_block_state';
  static const String blockFunction = 'chat_block';
  static const String unblockFunction = 'chat_unblock';
  static const String searchFunction = 'chat_search';
  static const String searchInboxFunction = 'chat_search_inbox';

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  final ChatTransport transport;
  final ChatSession session;
  final ChatErrorMapper errorMapper;

  String? _captureIdentity() => session.currentUserId;

  bool _isStillCurrent(String userId) => session.currentUserId == userId;

  Future<RepositoryResult<Map<String, Object?>>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.callChatRpc(
      ChatRpcCall(schema: schema, function: function, params: params),
    );
    if (!_isStillCurrent(userId)) return _failure(_staleSession);
    return switch (response) {
      ChatTransportData(:final data) => _decode(function, data),
      ChatTransportError() => RepositoryFailureResult(
        errorMapper.map(response, operation: function),
      ),
    };
  }

  RepositoryResult<Map<String, Object?>> _decode(
    String function,
    Object? data,
  ) {
    try {
      return RepositorySuccess(decodeObject(data, function));
    } on ChatDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  RepositoryResult<T> _failure<T>(RepositoryError error) =>
      RepositoryFailureResult(error);

  RepositoryError _identityMismatch(String field) =>
      PermissionDeniedError(action: 'identity_mismatch', entityType: field);

  static const RepositoryError _openUnavailable = PermissionDeniedError(
    action: 'conversation_open_unavailable',
    entityType: 'conversation',
  );

  @override
  Future<RepositoryResult<PageSlice<ConversationSummary>>> fetchInbox({
    required String userId,
    PageQuery page = PageQuery.standard,
  }) async {
    if (userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    final result = await _call(inboxFunction, {
      'p_page_size': page.limit,
      if (page.cursor != null) 'p_cursor': page.cursor,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeInboxPage(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: inboxFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<Conversation>> fetchConversation({
    required String conversationId,
  }) async {
    final result = await _call(conversationFunction, {
      'p_conversation': conversationId,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeConversationJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: conversationFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<PageSlice<ConversationMessage>>> fetchMessages({
    required String conversationId,
    PageQuery page = PageQuery.standard,
    String? beforeMessageId,
  }) async {
    final result = await _call(messagesFunction, {
      'p_conversation': conversationId,
      'p_page_size': page.limit,
      'p_before_message': beforeMessageId ?? page.cursor,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeMessagePage(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: messagesFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<ConversationMessage>> sendMessage(
    SendMessageCommand command,
  ) async {
    if (command.senderUserId != _captureIdentity()) {
      return _failure(_identityMismatch('senderUserId'));
    }
    final attachments = command.attachmentMediaIds;
    final function = attachments.isEmpty
        ? sendFunction
        : sendAttachmentFunction;
    final result = await _call(function, {
      'p_conversation': command.conversationId,
      'p_key': command.clientMessageId,
      'p_text': command.text,
      if (attachments.isNotEmpty) 'p_media_ids': attachments,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeMessageJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(operation: function, detail: error.detail),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<ConversationMember>> markConversationRead(
    MarkConversationReadCommand command,
  ) async {
    if (command.userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    final result = await _call(markReadFunction, {
      'p_conversation': command.conversationId,
      'p_last_read': command.lastReadMessageId,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeMemberJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: markReadFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<ConversationMember>> setConversationMuted(
    SetConversationMutedCommand command,
  ) async {
    if (command.userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    // Mute is naturally idempotent; the command's key is intentionally not
    // sent because the server operation has no duplicate side effect.
    final result = await _call(muteFunction, {
      'p_conversation': command.conversationId,
      'p_muted': command.isMuted,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeMemberJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: muteFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<Conversation>> openTargetedRequestConversation(
    OpenTargetedRequestConversationCommand command,
  ) async {
    if (command.buyerUserId != _captureIdentity()) {
      return _failure(_identityMismatch('buyerUserId'));
    }
    // Conversation opening is deliberately unavailable to clients in this
    // batch; eligibility records and the reviewed opening command do not
    // exist yet. No request is issued.
    return _failure(_openUnavailable);
  }

  @override
  Future<RepositoryResult<Conversation>> openDiscoveryEnquiry(
    OpenDiscoveryEnquiryCommand command,
  ) async {
    if (command.initiatedByUserId != _captureIdentity()) {
      return _failure(_identityMismatch('initiatedByUserId'));
    }
    return _failure(_openUnavailable);
  }

  // -------------------------------------------------------------------------
  // ConversationSafetyRepository (150/151): block state and server search.
  // -------------------------------------------------------------------------

  @override
  Future<RepositoryResult<ConversationBlockState>> fetchBlockState({
    required String conversationId,
    required String userId,
  }) async {
    if (userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    final result = await _call(blockStateFunction, {
      'p_conversation': conversationId,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeBlockStateJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: blockStateFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<ConversationBlockState>> blockConversation(
    BlockConversationCommand command,
  ) async {
    if (command.userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    // Blocking is naturally idempotent: the server keeps at most one active
    // block per direction, so no command key is sent and a retry cannot create
    // a second record.
    final result = await _call(blockFunction, {
      'p_conversation': command.conversationId,
      if (command.reasonCode != null) 'p_reason': command.reasonCode,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeBlockStateJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: blockFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<ConversationBlockState>> unblockConversation(
    UnblockConversationCommand command,
  ) async {
    if (command.userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    final result = await _call(unblockFunction, {
      'p_conversation': command.conversationId,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeBlockStateJson(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: unblockFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<PageSlice<ChatSearchHit>>> searchMessages({
    required String userId,
    required String query,
    PageQuery page = PageQuery.standard,
    String? conversationId,
  }) async {
    if (userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    final trimmed = query.trim();
    if (trimmed.length < 2 || trimmed.length > 64) {
      return _failure(
        const ValidationError(
          issues: [
            ValidationIssue(
              field: 'query',
              code: ValidationCodes.outOfRange,
              message: 'Search needs between 2 and 64 characters.',
            ),
          ],
          debugMessage: 'chat search query out of range',
        ),
      );
    }
    final result = await _call(searchFunction, {
      'p_query': trimmed,
      'p_page_size': page.limit,
      'p_cursor': page.cursor,
      'p_conversation': conversationId,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(
            decodeSearchPage(json, viewerUserId: userId),
          );
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: searchFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }

  @override
  Future<RepositoryResult<PageSlice<ConversationSummary>>> searchConversations({
    required String userId,
    required String query,
    PageQuery page = PageQuery.standard,
  }) async {
    if (userId != _captureIdentity()) {
      return _failure(_identityMismatch('userId'));
    }
    final trimmed = query.trim();
    if (trimmed.length < 2 || trimmed.length > 64) {
      return _failure(
        const ValidationError(
          issues: [
            ValidationIssue(
              field: 'query',
              code: ValidationCodes.outOfRange,
              message: 'Search needs between 2 and 64 characters.',
            ),
          ],
          debugMessage: 'chat inbox search query out of range',
        ),
      );
    }
    final result = await _call(searchInboxFunction, {
      'p_query': trimmed,
      'p_page_size': page.limit,
      'p_cursor': page.cursor,
    });
    return result.when(
      success: (json) {
        try {
          return RepositorySuccess(decodeInboxPage(json));
        } on ChatDecodeException catch (error) {
          return _failure(
            MalformedResponseError(
              operation: searchInboxFunction,
              detail: error.detail,
            ),
          );
        }
      },
      failure: RepositoryFailureResult.new,
    );
  }
}

extension on RepositoryResult<Map<String, Object?>> {
  RepositoryResult<T> when<T>({
    required RepositoryResult<T> Function(Map<String, Object?> json) success,
    required RepositoryResult<T> Function(RepositoryError error) failure,
  }) {
    return switch (this) {
      RepositorySuccess<Map<String, Object?>>(:final value) => success(value),
      RepositoryFailureResult<Map<String, Object?>>(:final error) => failure(
        error,
      ),
    };
  }
}
