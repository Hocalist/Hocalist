/// Real-mode chat backend: participant inbox, history, send, read and mute.
///
/// Bridges the approved chat screens to the participant-authorized chat RPCs
/// (Task 07 foundation) through the conversation repository. Participation,
/// delivery and mute state stay server-owned; this adapter only maps
/// identifiers, pages and user-safe errors.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/conversations.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/repositories.dart';
import '../../../domain/phase2/offers.dart';
import '../../../domain/phase2/requests.dart';
import '../../local_marketplace_repository.dart';

class Phase2MarketplaceChatBackend
    implements
        MarketplaceChatBackend,
        MarketplaceChatRequestBackend,
        MarketplacePagedChatBackend,
        MarketplaceChatAttachmentBackend {
  Phase2MarketplaceChatBackend({
    required this.conversations,
    required this.currentUserId,
    this.offers,
    this.requestReader,
    this.identity,
    this.attachmentsEnabled = false,
  });

  final ConversationRepository conversations;
  final String currentUserId;
  final OfferRepository? offers;
  final Future<RepositoryResult<SellerLeadProjection>> Function(String)?
  requestReader;
  final String? Function()? identity;

  /// Set true only after the reviewed `chat_send_attachment` RPC is deployed.
  final bool attachmentsEnabled;

  @override
  bool get chatAttachmentsEnabled => attachmentsEnabled;

  @override
  Future<SellerLeadProjection?> loadConversationRequest(
    String conversationId,
  ) async {
    final reader = requestReader;
    if (reader == null) return null;
    void checkIdentity() {
      if (identity != null && identity!() != currentUserId) {
        throw const StoreBackendException(
          'Your session changed. Sign in again.',
        );
      }
    }

    checkIdentity();
    final result = await conversations.fetchConversation(
      conversationId: conversationId,
    );
    if (result.isFailure) {
      throw StoreBackendException(
        _message(result.errorOrNull),
        code:
            result.errorOrNull!.kind ==
                    RepositoryFailureKind.permissionDenied ||
                result.errorOrNull!.kind == RepositoryFailureKind.notFound
            ? 'chat_access_denied'
            : null,
      );
    }
    final conversation = result.valueOrNull!;
    checkIdentity();
    if (conversation.id != conversationId) {
      throw const StoreBackendException('Could not load this request.');
    }
    final requestId = conversation.requestId;
    if (requestId == null) return null;
    final request = await reader(requestId);
    checkIdentity();
    if (request.isFailure) {
      throw const StoreBackendException(
        'This request is no longer available to your account.',
      );
    }
    if (request.valueOrNull?.requestId != requestId) {
      throw const StoreBackendException('Could not load this request.');
    }
    return request.valueOrNull;
  }

  @override
  Future<Offer?> loadMeetingOffer(String conversationId) async {
    final source = offers;
    if (source == null) return null;
    final conversationResult = await conversations.fetchConversation(
      conversationId: conversationId,
    );
    if (conversationResult.isFailure) {
      throw StoreBackendException(_message(conversationResult.errorOrNull!));
    }
    final conversation = conversationResult.valueOrNull!;
    final offerId = conversation.offerId;
    if (conversation.id != conversationId || offerId == null) return null;
    final offerResult = await source.fetchOffer(offerId: offerId);
    if (offerResult.isFailure) {
      throw StoreBackendException(_message(offerResult.errorOrNull!));
    }
    final offer = offerResult.valueOrNull!;
    if (offer.id != offerId ||
        offer.requestId != conversation.requestId ||
        offer.acceptedRevisionId == null ||
        (offer.conversationId != null &&
            offer.conversationId != conversationId)) {
      throw const StoreBackendException(
        'Refresh the conversation before proposing a meeting.',
      );
    }
    return offer;
  }

  @override
  Future<List<ConversationSummary>> loadInbox() async {
    final items = <String, ConversationSummary>{};
    final seen = <String>{};
    String? cursor;
    do {
      final result = await conversations.fetchInbox(
        userId: currentUserId,
        page: PageQuery(limit: 100, cursor: cursor),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        throw StoreBackendException(
          _message(error),
          ambiguous: _isAmbiguous(error),
        );
      }
      final page = result.valueOrNull!;
      for (final item in page.items) {
        items.putIfAbsent(item.conversation.id, () => item);
      }
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw const StoreBackendException(
          'Could not advance your inbox. Try again.',
        );
      }
    } while (cursor != null);
    return List.unmodifiable(items.values);
  }

  @override
  Future<PageSlice<ConversationMessage>> loadMessagePage(
    String conversationId,
    String? cursor,
  ) async {
    if (identity != null && identity!() != currentUserId) {
      throw const StoreBackendException('Your session changed.');
    }
    final result = await conversations.fetchMessages(
      conversationId: conversationId,
      page: PageQuery(limit: 100, cursor: cursor),
    );
    if (identity != null && identity!() != currentUserId) {
      throw const StoreBackendException('Your session changed.');
    }
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        code:
            error.kind == RepositoryFailureKind.permissionDenied ||
                error.kind == RepositoryFailureKind.notFound
            ? 'chat_access_denied'
            : null,
      );
    }
    final page = result.valueOrNull!;
    if (page.items.any((row) => row.conversationId != conversationId)) {
      throw const StoreBackendException('Could not load this conversation.');
    }
    return page;
  }

  @override
  Future<List<ConversationMessage>> loadMessages(String conversationId) async {
    final pages = <List<ConversationMessage>>[];
    String? cursor;
    for (var page = 0; page < 5; page++) {
      final result = await conversations.fetchMessages(
        conversationId: conversationId,
        page: PageQuery(limit: 100, cursor: cursor),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        throw StoreBackendException(
          _message(error),
          ambiguous: _isAmbiguous(error),
        );
      }
      final slice = result.valueOrNull!;
      pages.add(slice.items);
      cursor = slice.nextCursor;
      if (cursor == null) break;
    }
    final ordered = <ConversationMessage>[];
    for (final page in pages.reversed) {
      ordered.addAll(page);
    }
    return ordered;
  }

  @override
  Future<ConversationMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientMessageId,
  }) async {
    final result = await conversations.sendMessage(
      SendMessageCommand(
        conversationId: conversationId,
        senderUserId: currentUserId,
        text: text,
        clientMessageId: clientMessageId,
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<ConversationMessage> sendAttachment({
    required String conversationId,
    required String text,
    required List<String> mediaIds,
    required String clientMessageId,
  }) async {
    if (!attachmentsEnabled) {
      throw const StoreBackendException(
        'Image attachments are not available yet.',
      );
    }
    final result = await conversations.sendMessage(
      SendMessageCommand(
        conversationId: conversationId,
        senderUserId: currentUserId,
        text: text,
        attachmentMediaIds: mediaIds,
        clientMessageId: clientMessageId,
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<ConversationMember> markRead({
    required String conversationId,
    required String messageId,
  }) async {
    final result = await conversations.markConversationRead(
      MarkConversationReadCommand(
        conversationId: conversationId,
        userId: currentUserId,
        lastReadMessageId: messageId,
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<ConversationMember> setMuted({
    required String conversationId,
    required bool muted,
  }) async {
    final result = await conversations.setConversationMuted(
      SetConversationMutedCommand(
        conversationId: conversationId,
        userId: currentUserId,
        isMuted: muted,
        idempotencyKey: LocalMarketplaceRepository.newStoreOperationKey(
          'chat-mute',
        ),
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  bool _isAmbiguous(RepositoryError? error) {
    if (error == null) return false;
    return switch (error.kind) {
      RepositoryFailureKind.network ||
      RepositoryFailureKind.malformedResponse => true,
      RepositoryFailureKind.server =>
        error is ServerError &&
            (error.statusCode == null || error.statusCode! >= 500),
      _ => false,
    };
  }

  String _message(RepositoryError? error) {
    if (error == null) {
      return 'The conversation action could not be completed. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.permissionDenied =>
        'This conversation is unavailable. Your access may have changed.',
      RepositoryFailureKind.notFound => 'This conversation is unavailable.',
      RepositoryFailureKind.conflict =>
        'This conversation changed. Refresh and try again.',
      RepositoryFailureKind.network =>
        'The message could not be confirmed. Retry to check it safely.',
      RepositoryFailureKind.validation =>
        'This message could not be sent. Check it and try again.',
      _ => 'The conversation action could not be completed. Try again.',
    };
  }
}
