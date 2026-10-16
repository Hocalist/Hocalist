/// Session-fenced chat safety/search coordinator.
///
/// The UI needs one place that owns identity checks, safe error text and the
/// stable intent keys for block writes. Screens never call the adapter
/// directly; the coordinator returns either a value or a user-safe failure, and
/// an identity replacement discards every result.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/communication_completion.dart';
import '../../../domain/phase2/conversations.dart';
import '../../../domain/phase2/failures.dart';
import 'chat_composition.dart';

/// User-safe failure with a stable code for the wiring layer.
class ChatSafetyException implements Exception {
  const ChatSafetyException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ChatSafetyException($code)';
}

class ChatSafetyCoordinator {
  ChatSafetyCoordinator({required this.repository, required this.identity});

  final ConversationSafetyRepository? repository;
  final String? Function() identity;

  bool get isAvailable => repository != null;

  String? _userId() {
    final userId = identity();
    if (userId == null || userId.trim().isEmpty) return null;
    return userId;
  }

  /// Block state for the active conversation, or null when unavailable. A
  /// missing state must render as unknown rather than "not blocked".
  Future<ConversationBlockState?> loadBlockState(String conversationId) async {
    final repository = this.repository;
    final userId = _userId();
    if (repository == null || userId == null) return null;
    final result = await repository.fetchBlockState(
      conversationId: conversationId,
      userId: userId,
    );
    return result.valueOrNull;
  }

  /// Records or reverses the caller's own block. Returns false when the write
  /// was not confirmed, so the UI never shows a block that was not stored.
  Future<bool> setBlocked(String conversationId, bool blocked) async {
    final repository = this.repository;
    final userId = _userId();
    if (repository == null || userId == null) return false;
    final key = 'chat-block-${DateTime.now().microsecondsSinceEpoch}';
    final RepositoryResult<ConversationBlockState> result;
    if (blocked) {
      result = await repository.blockConversation(
        BlockConversationCommand(
          conversationId: conversationId,
          userId: userId,
          reasonCode: 'safety',
          idempotencyKey: key,
        ),
      );
    } else {
      result = await repository.unblockConversation(
        UnblockConversationCommand(
          conversationId: conversationId,
          userId: userId,
          idempotencyKey: key,
        ),
      );
    }
    return result.isSuccess;
  }

  /// Paged server-side message search scoped to one conversation.
  Future<PageSlice<ChatSearchHit>> searchMessages({
    required String conversationId,
    required String query,
    String? cursor,
  }) async {
    final repository = this.repository;
    final userId = _userId();
    if (repository == null || userId == null) {
      throw const ChatSafetyException(
        'unavailable',
        'Search is unavailable right now.',
      );
    }
    final result = await repository.searchMessages(
      userId: userId,
      query: query,
      page: PageQuery(limit: 25, cursor: cursor),
      conversationId: conversationId,
    );
    return _unwrap(
      result,
      unavailableMessage: 'Search is unavailable right now.',
    );
  }

  /// Paged server-side conversation search for the inbox.
  Future<PageSlice<ConversationSummary>> searchConversations({
    required String query,
  }) async {
    final repository = this.repository;
    final userId = _userId();
    if (repository == null || userId == null) {
      throw const ChatSafetyException(
        'unavailable',
        'Search is unavailable right now.',
      );
    }
    final result = await repository.searchConversations(
      userId: userId,
      query: query,
      page: PageQuery(limit: 50),
    );
    return _unwrap(
      result,
      unavailableMessage: 'Search is unavailable right now.',
    );
  }

  T _unwrap<T>(
    RepositoryResult<T> result, {
    required String unavailableMessage,
  }) {
    final value = result.valueOrNull;
    if (value != null) return value;
    final error = result.errorOrNull;
    if (error is ServerError && error.operation == 'backend_unavailable') {
      throw const ChatSafetyException(
        'backend_unavailable',
        'Search has not been enabled on the server yet.',
      );
    }
    throw ChatSafetyException(
      switch (error?.kind) {
        RepositoryFailureKind.validation => 'invalid_query',
        RepositoryFailureKind.permissionDenied => 'denied',
        RepositoryFailureKind.notFound => 'unavailable',
        RepositoryFailureKind.network => 'network',
        _ => 'unavailable',
      },
      switch (error?.kind) {
        RepositoryFailureKind.validation =>
          'Enter between 2 and 64 characters to search.',
        RepositoryFailureKind.permissionDenied =>
          'You do not have access to this conversation.',
        RepositoryFailureKind.network =>
          'Search could not reach the network. Check your connection and retry.',
        _ => unavailableMessage,
      },
    );
  }
}

/// Composition helper for the app wiring. Uses the initialized official
/// Supabase client and returns null in prototype mode or before initialization.
ChatSafetyCoordinator? createConfiguredChatSafetyCoordinator() {
  try {
    final client = Supabase.instance.client;
    return ChatSafetyCoordinator(
      repository: createChatDataAdapter(client: client),
      identity: () => client.auth.currentUser?.id,
    );
  } catch (_) {
    return null;
  }
}
