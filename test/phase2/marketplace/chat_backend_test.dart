// Chat backend tests: inbox, paged history, send, read and mute mapping plus
// repository caching. Fakes only.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_chat_backend.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/domain/phase2/repositories.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'buyer_offers_backend_test.dart' show selectedOffer;
import 'support/marketplace_fakes.dart' show leadJson;
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';

class MeetingOfferRepository implements OfferRepository {
  Offer value = selectedOffer();
  final List<String> reads = [];
  @override
  Future<RepositoryResult<Offer>> fetchOffer({required String offerId}) async {
    reads.add(offerId);
    return RepositorySuccess(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _conversationId = '60000000-0000-4000-8000-000000000001';
const _viewerId = 'user-a';
const _counterpartId = 'user-b';

ConversationMember _member(
  String userId,
  HocalistRole role, {
  bool muted = false,
}) => ConversationMember(
  userId: userId,
  profileId: role == HocalistRole.buyer
      ? '10000000-0000-4000-8000-00000000000a'
      : '10000000-0000-4000-8000-00000000000b',
  role: role,
  joinedAt: DateTime.utc(2026, 5, 1),
  isMuted: muted,
);

Conversation _conversation({bool muted = false}) => Conversation(
  id: _conversationId,
  origin: ConversationOrigin.targetedRequest,
  members: [
    _member(_viewerId, HocalistRole.buyer, muted: muted),
    _member(_counterpartId, HocalistRole.seller),
  ],
  status: ConversationStatus.open,
  requestId: '30000000-0000-4000-8000-000000000001',
  offerId: '40000000-0000-4000-8000-000000000001',
  stamp: RecordStamp(
    revision: 1,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  ),
);

ConversationMessage _message({
  String id = '70000000-0000-4000-8000-000000000001',
  String senderUserId = _counterpartId,
  String text = 'Hello there.',
  int minute = 0,
}) => ConversationMessage(
  id: id,
  conversationId: _conversationId,
  senderUserId: senderUserId,
  text: text,
  sentAt: DateTime.utc(2026, 5, 1, 9, minute),
);

class FakeConversationRepository implements ConversationRepository {
  final inboxCursors = <String?>[];
  Future<RepositoryResult<PageSlice<ConversationSummary>>> Function()? onInbox;
  Future<RepositoryResult<PageSlice<ConversationMessage>>> Function(
    String? cursor,
  )?
  onMessages;
  Future<RepositoryResult<ConversationMessage>> Function(
    SendMessageCommand command,
  )?
  onSend;
  Future<RepositoryResult<ConversationMember>> Function(
    MarkConversationReadCommand command,
  )?
  onMarkRead;
  Future<RepositoryResult<ConversationMember>> Function(
    SetConversationMutedCommand command,
  )?
  onMute;
  final List<SendMessageCommand> sends = <SendMessageCommand>[];
  final List<MarkConversationReadCommand> reads =
      <MarkConversationReadCommand>[];
  final List<SetConversationMutedCommand> mutes =
      <SetConversationMutedCommand>[];

  @override
  Future<RepositoryResult<PageSlice<ConversationSummary>>> fetchInbox({
    required String userId,
    PageQuery page = PageQuery.standard,
  }) {
    inboxCursors.add(page.cursor);
    return onInbox?.call() ??
        Future.value(
          RepositorySuccess(
            PageSlice<ConversationSummary>(
              items: [
                ConversationSummary(
                  conversation: _conversation(),
                  counterpartDisplayName: 'Seller B',
                  unreadCount: 2,
                ),
              ],
            ),
          ),
        );
  }

  @override
  Future<RepositoryResult<PageSlice<ConversationMessage>>> fetchMessages({
    required String conversationId,
    PageQuery page = PageQuery.standard,
    String? beforeMessageId,
  }) {
    return onMessages?.call(page.cursor ?? beforeMessageId) ??
        Future.value(
          RepositorySuccess(
            PageSlice<ConversationMessage>(items: [_message()]),
          ),
        );
  }

  @override
  Future<RepositoryResult<ConversationMessage>> sendMessage(
    SendMessageCommand command,
  ) {
    sends.add(command);
    return onSend?.call(command) ??
        Future.value(
          RepositorySuccess(
            _message(
              id: '70000000-0000-4000-8000-000000000002',
              text: command.text,
            ),
          ),
        );
  }

  @override
  Future<RepositoryResult<ConversationMember>> markConversationRead(
    MarkConversationReadCommand command,
  ) {
    reads.add(command);
    return onMarkRead?.call(command) ??
        Future.value(RepositorySuccess(_member(_viewerId, HocalistRole.buyer)));
  }

  @override
  Future<RepositoryResult<ConversationMember>> setConversationMuted(
    SetConversationMutedCommand command,
  ) {
    mutes.add(command);
    return onMute?.call(command) ??
        Future.value(
          RepositorySuccess(
            _member(_viewerId, HocalistRole.buyer, muted: command.isMuted),
          ),
        );
  }

  @override
  Future<RepositoryResult<Conversation>> fetchConversation({
    required String conversationId,
  }) => Future.value(RepositorySuccess(_conversation()));

  @override
  Future<RepositoryResult<Conversation>> openTargetedRequestConversation(
    OpenTargetedRequestConversationCommand command,
  ) => Future.value(RepositorySuccess(_conversation()));

  @override
  Future<RepositoryResult<Conversation>> openDiscoveryEnquiry(
    OpenDiscoveryEnquiryCommand command,
  ) => Future.value(RepositorySuccess(_conversation()));
}

void main() {
  test(
    'refresh restarts older pagination when newest page has a gap',
    () async {
      final conversations = FakeConversationRepository();
      var resumed = false;
      final cursors = <String?>[];
      conversations.onMessages = (cursor) async {
        cursors.add(cursor);
        return RepositorySuccess(
          PageSlice(
            items: [_message(id: resumed ? 'new-window' : 'old-window')],
            nextCursor: resumed ? 'gap-cursor' : 'original-cursor',
          ),
        );
      };
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      addTearDown(repository.dispose);
      await repository.openChatConversation(_conversationId);
      resumed = true;
      await repository.pollChatMessages();
      expect(repository.chatMessages.map((row) => row.id), ['new-window']);
      await repository.loadOlderChatMessages();
      expect(cursors.last, 'gap-cursor');
    },
  );
  for (final source in ['poll', 'refresh', 'older']) {
    test(
      '$source denial clears history and fences an older response',
      () async {
        final conversations = FakeConversationRepository();
        final late =
            Completer<RepositoryResult<PageSlice<ConversationMessage>>>();
        var denied = false;
        conversations.onMessages = (cursor) async {
          if (denied) {
            return const RepositoryFailureResult(
              PermissionDeniedError(action: 'read', entityType: 'conversation'),
            );
          }
          if (cursor != null) return late.future;
          return RepositorySuccess(
            PageSlice(
              items: [_message(id: 'recent')],
              nextCursor: 'older',
            ),
          );
        };
        final repository = LocalMarketplaceRepository(
          chatBackend: Phase2MarketplaceChatBackend(
            conversations: conversations,
            currentUserId: _viewerId,
          ),
        );
        addTearDown(repository.dispose);
        await repository.openChatConversation(_conversationId);
        final pending = source == 'older'
            ? null
            : repository.loadOlderChatMessages();
        denied = true;
        if (source == 'poll') await repository.pollChatMessages();
        if (source == 'refresh') await repository.refreshChatMessages();
        if (source == 'older') await repository.loadOlderChatMessages();
        late.complete(
          RepositorySuccess(PageSlice(items: [_message(id: 'private-old')])),
        );
        if (pending != null) await pending;
        expect(repository.chatMessages, isEmpty);
        expect(repository.chatHasOlder, isFalse);
        expect(repository.chatOlderLoading, isFalse);
        expect(repository.chatMessagesError, isNotNull);
      },
    );
  }
  test(
    'foreground refresh preserves older history and clears revoked access',
    () async {
      final conversations = FakeConversationRepository();
      var revision = 0;
      var denied = false;
      conversations.onMessages = (cursor) async {
        if (denied) {
          return const RepositoryFailureResult(
            PermissionDeniedError(action: 'read', entityType: 'conversation'),
          );
        }
        return RepositorySuccess(
          PageSlice(
            items: cursor != null
                ? [_message(id: 'old')]
                : [
                    _message(id: 'recent'),
                    if (revision > 0) _message(id: 'new'),
                  ],
            nextCursor: cursor == null ? 'older' : null,
          ),
        );
      };
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      addTearDown(repository.dispose);
      await repository.openChatConversation(_conversationId);
      await repository.loadOlderChatMessages();
      revision = 1;
      await repository.pollChatMessages();
      expect(repository.chatMessages.map((row) => row.id), [
        'old',
        'recent',
        'new',
      ]);
      denied = true;
      await repository.pollChatMessages();
      expect(repository.chatMessages, isEmpty);
      expect(repository.chatMessagesError, isNotNull);
    },
  );
  test('inbox follows server cursor and refuses a looping cursor', () async {
    final conversations = FakeConversationRepository();
    conversations.onInbox = () async => RepositorySuccess(
      PageSlice(
        items: <ConversationSummary>[],
        nextCursor: conversations.inboxCursors.length == 1 ? 'next' : null,
      ),
    );
    final backend = Phase2MarketplaceChatBackend(
      conversations: conversations,
      currentUserId: _viewerId,
    );
    await backend.loadInbox();
    expect(conversations.inboxCursors, [null, 'next']);
    conversations.onInbox = () async => RepositorySuccess(
      PageSlice(items: <ConversationSummary>[], nextCursor: 'loop'),
    );
    await expectLater(
      backend.loadInbox(),
      throwsA(isA<StoreBackendException>()),
    );
  });
  test('repository loads older pages on demand and preserves order', () async {
    final conversations = FakeConversationRepository();
    final cursors = <String?>[];
    conversations.onMessages = (cursor) async {
      cursors.add(cursor);
      return RepositorySuccess(
        PageSlice(
          items: [_message(id: cursor == null ? 'new' : 'old')],
          nextCursor: cursor == null ? 'older' : null,
        ),
      );
    };
    final repository = LocalMarketplaceRepository(
      chatBackend: Phase2MarketplaceChatBackend(
        conversations: conversations,
        currentUserId: _viewerId,
      ),
    );
    addTearDown(repository.dispose);
    await repository.openChatConversation(_conversationId);
    expect(cursors, [null]);
    expect(repository.chatHasOlder, isTrue);
    await repository.loadOlderChatMessages();
    expect(cursors, [null, 'older']);
    expect(repository.chatMessages.map((row) => row.id), ['old', 'new']);
    expect(repository.chatHasOlder, isFalse);
  });

  test('older page failure preserves messages and cursor for retry', () async {
    final conversations = FakeConversationRepository();
    var fail = true;
    conversations.onMessages = (cursor) async {
      if (cursor != null && fail) throw StateError('offline');
      return RepositorySuccess(
        PageSlice(
          items: [_message(id: cursor == null ? 'new' : 'old')],
          nextCursor: cursor == null ? 'older' : null,
        ),
      );
    };
    final repository = LocalMarketplaceRepository(
      chatBackend: Phase2MarketplaceChatBackend(
        conversations: conversations,
        currentUserId: _viewerId,
      ),
    );
    addTearDown(repository.dispose);
    await repository.openChatConversation(_conversationId);
    await repository.loadOlderChatMessages();
    expect(repository.chatMessages.single.id, 'new');
    expect(repository.chatOlderError, isNotNull);
    expect(repository.chatHasOlder, isTrue);
    fail = false;
    await repository.loadOlderChatMessages();
    expect(repository.chatOlderError, isNull);
    expect(repository.chatMessages, hasLength(2));
  });

  test(
    'late older page cannot restore a previously opened conversation',
    () async {
      final conversations = FakeConversationRepository();
      final pending =
          Completer<RepositoryResult<PageSlice<ConversationMessage>>>();
      conversations.onMessages = (cursor) => cursor == null
          ? Future.value(
              RepositorySuccess(
                PageSlice(
                  items: [_message(id: 'new')],
                  nextCursor: 'older',
                ),
              ),
            )
          : pending.future;
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      addTearDown(repository.dispose);
      await repository.openChatConversation(_conversationId);
      final older = repository.loadOlderChatMessages();
      await repository.openChatConversation('other');
      pending.complete(
        RepositorySuccess(PageSlice(items: [_message(id: 'old')])),
      );
      await older;
      expect(repository.chatMessages, isEmpty);
      expect(repository.chatOlderLoading, isFalse);
    },
  );
  test(
    'chat request uses authorized conversation id and rejects mismatches',
    () async {
      final reads = <String>[];
      final backend = Phase2MarketplaceChatBackend(
        conversations: FakeConversationRepository(),
        currentUserId: _viewerId,
        requestReader: (id) async {
          reads.add(id);
          return RepositorySuccess(decodeLeadJson(leadJson(), 'lead'));
        },
      );
      final request = await backend.loadConversationRequest(_conversationId);
      expect(reads, [request!.requestId]);
      expect(request.areaLabel, 'Yonkers, NY');
      await expectLater(
        backend.loadConversationRequest('other'),
        throwsA(isA<StoreBackendException>()),
      );
      expect(reads, hasLength(1));
    },
  );

  test('chat request discards result after identity replacement', () async {
    var identity = _viewerId;
    final backend = Phase2MarketplaceChatBackend(
      conversations: FakeConversationRepository(),
      currentUserId: _viewerId,
      identity: () => identity,
      requestReader: (id) async {
        identity = 'replacement';
        return RepositorySuccess(decodeLeadJson(leadJson(), 'lead'));
      },
    );
    await expectLater(
      backend.loadConversationRequest(_conversationId),
      throwsA(isA<StoreBackendException>()),
    );
  });

  group('Phase2MarketplaceChatBackend', () {
    test(
      'reloads the authorized accepted offer after losing local screen state',
      () async {
        final offers = MeetingOfferRepository();
        final backend = Phase2MarketplaceChatBackend(
          conversations: FakeConversationRepository(),
          currentUserId: _viewerId,
          offers: offers,
        );
        final loaded = await backend.loadMeetingOffer(_conversationId);
        expect(loaded!.acceptedRevisionId, offers.value.acceptedRevisionId);
        expect(offers.reads, [offers.value.id]);
        offers.value = selectedOffer(conversationId: 'another-conversation');
        await expectLater(
          backend.loadMeetingOffer(_conversationId),
          throwsA(isA<StoreBackendException>()),
        );
      },
    );
    late FakeConversationRepository conversations;
    late Phase2MarketplaceChatBackend backend;

    setUp(() {
      conversations = FakeConversationRepository();
      backend = Phase2MarketplaceChatBackend(
        conversations: conversations,
        currentUserId: _viewerId,
      );
    });

    test('loads the inbox summary', () async {
      final inbox = await backend.loadInbox();
      expect(inbox, hasLength(1));
      expect(inbox.single.counterpartDisplayName, 'Seller B');
      expect(inbox.single.unreadCount, 2);
    });

    test('orders older message pages oldest first', () async {
      var calls = 0;
      conversations.onMessages = (cursor) async {
        calls += 1;
        if (calls == 1) {
          return RepositorySuccess(
            PageSlice<ConversationMessage>(
              items: [
                _message(
                  id: '70000000-0000-4000-8000-000000000010',
                  minute: 10,
                ),
              ],
              nextCursor: 'older-page',
            ),
          );
        }
        return RepositorySuccess(
          PageSlice<ConversationMessage>(
            items: [
              _message(id: '70000000-0000-4000-8000-000000000001', minute: 1),
            ],
          ),
        );
      };
      final messages = await backend.loadMessages(_conversationId);
      expect(calls, 2);
      expect(messages, hasLength(2));
      expect(messages.first.id, '70000000-0000-4000-8000-000000000001');
      expect(messages.last.id, '70000000-0000-4000-8000-000000000010');
    });

    test('sends text with the client message id as the key', () async {
      final message = await backend.sendMessage(
        conversationId: _conversationId,
        text: 'On my way.',
        clientMessageId: 'client-1',
      );
      expect(message.text, 'On my way.');
      expect(conversations.sends.single.clientMessageId, 'client-1');
      expect(conversations.sends.single.senderUserId, _viewerId);
      expect(conversations.sends.single.text, 'On my way.');
    });

    test('maps a definitive send failure', () async {
      conversations.onSend = (command) async => const RepositoryFailureResult(
        ValidationError(
          issues: [
            ValidationIssue(
              field: 'text',
              code: 'invalid',
              message: 'This message could not be sent.',
            ),
          ],
          debugMessage: 'synthetic',
        ),
      );
      await expectLater(
        backend.sendMessage(
          conversationId: _conversationId,
          text: 'x',
          clientMessageId: 'client-2',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.ambiguous,
            'ambiguous',
            isFalse,
          ),
        ),
      );
    });

    test('marks read and persists mute for the current user', () async {
      await backend.markRead(
        conversationId: _conversationId,
        messageId: '70000000-0000-4000-8000-000000000001',
      );
      expect(conversations.reads.single.userId, _viewerId);
      expect(
        conversations.reads.single.lastReadMessageId,
        '70000000-0000-4000-8000-000000000001',
      );

      final member = await backend.setMuted(
        conversationId: _conversationId,
        muted: true,
      );
      expect(member.isMuted, isTrue);
      expect(conversations.mutes.single.userId, _viewerId);
      expect(conversations.mutes.single.isMuted, isTrue);
    });
  });

  group('LocalMarketplaceRepository chat', () {
    test(
      'uncertain retry keeps its message id and refuses changed text',
      () async {
        final conversations = FakeConversationRepository()
          ..onSend = (_) async =>
              const RepositoryFailureResult(NetworkError(retryable: true));
        final repository = LocalMarketplaceRepository(
          chatBackend: Phase2MarketplaceChatBackend(
            conversations: conversations,
            currentUserId: _viewerId,
          ),
        );
        await repository.openChatConversation(_conversationId);
        await repository.sendChatMessage('Original message');
        final changed = await repository.sendChatMessage('Changed message');
        expect(changed.outcomeUncertain, isTrue);
        expect(conversations.sends, hasLength(1));
        conversations.onSend = (_) async =>
            RepositorySuccess(_message(text: 'Original message'));
        expect(
          (await repository.sendChatMessage('Original message')).isSuccess,
          isTrue,
        );
        expect(
          conversations.sends[0].clientMessageId,
          conversations.sends[1].clientMessageId,
        );
        // A concurrent history refresh may already contain the acknowledged row.
        expect(
          repository.chatMessages.where((row) => row.id == _message().id),
          hasLength(1),
        );
        repository.dispose();
      },
    );

    test('late send does not append into another conversation', () async {
      final pending = Completer<RepositoryResult<ConversationMessage>>();
      final conversations = FakeConversationRepository()
        ..onSend = (_) => pending.future;
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      await repository.openChatConversation(_conversationId);
      final send = repository.sendChatMessage('Only for conversation A');
      final duplicate = await repository.sendChatMessage(
        'Only for conversation A',
      );
      expect(duplicate.isSuccess, isFalse);
      expect(conversations.sends, hasLength(1));
      await repository.openChatConversation(
        '60000000-0000-4000-8000-000000000002',
      );
      pending.complete(
        RepositorySuccess(
          _message(id: 'late-message', text: 'Only for conversation A'),
        ),
      );
      await send;
      expect(
        repository.chatMessages.any((row) => row.id == 'late-message'),
        isFalse,
      );
      repository.dispose();
    });
    test('loads the inbox and reports a safe error', () async {
      final conversations = FakeConversationRepository();
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      await repository.refreshChatInbox();
      expect(repository.chatInbox, hasLength(1));
      expect(repository.chatUnreadTotal, 2);

      conversations.onInbox = () async =>
          const RepositoryFailureResult(NetworkError(retryable: true));
      await repository.refreshChatInbox();
      expect(repository.chatInboxError, isNotNull);
      expect(repository.chatInbox, hasLength(1));
    });

    test('opens a conversation, sends and appends the message', () async {
      final conversations = FakeConversationRepository();
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      await repository.openChatConversation(_conversationId);
      expect(repository.chatMessages, hasLength(1));

      final result = await repository.sendChatMessage('See you soon.');
      expect(result.isSuccess, isTrue);
      expect(repository.chatMessages, hasLength(2));
      expect(repository.chatMessages.last.text, 'See you soon.');
      expect(conversations.sends.single.clientMessageId, isNotEmpty);
    });

    test('send reports an uncertain outcome without appending', () async {
      final conversations = FakeConversationRepository()
        ..onSend = (command) async =>
            const RepositoryFailureResult(NetworkError(retryable: true));
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      await repository.openChatConversation(_conversationId);
      final result = await repository.sendChatMessage('Maybe lost.');
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isTrue);
      expect(repository.chatMessages, hasLength(1));
    });

    test('mute persists through the backend', () async {
      final conversations = FakeConversationRepository();
      final repository = LocalMarketplaceRepository(
        chatBackend: Phase2MarketplaceChatBackend(
          conversations: conversations,
          currentUserId: _viewerId,
        ),
      );
      await repository.openChatConversation(_conversationId);
      final applied = await repository.setChatMuted(true);
      expect(applied, isTrue);
      expect(repository.chatMuted, isTrue);
    });
  });
}
