// Focused adapter and codec tests for the chat data layer. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_adapter.dart';
import 'package:hocalist/data/phase2/chat/chat_codecs.dart';
import 'package:hocalist/data/phase2/chat/chat_transport.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/failures.dart';

import 'support/chat_fakes.dart';

const conversationId = '50000000-0000-4000-8000-000000000001';

void main() {
  group('chat codecs', () {
    test('decode a conversation, member, message and inbox item', () {
      final conversation = decodeConversationJson(conversationJson());
      expect(conversation.id, conversationId);
      expect(conversation.origin, ConversationOrigin.targetedRequest);
      expect(conversation.status, ConversationStatus.open);
      expect(conversation.requestId, '60000000-0000-4000-8000-000000000001');
      expect(conversation.members, hasLength(2));
      expect(conversation.stamp.revision, 1);

      final message = decodeMessageJson(messageJson());
      expect(message.text, 'Synthetic message');
      expect(message.kind, MessageKind.text);
      expect(message.clientMessageId, 'key-1');
      expect(message.sentAt.isUtc, isTrue);

      final summary = decodeInboxItemJson(inboxItemJson());
      expect(summary.counterpartDisplayName, 'Seller B');
      expect(summary.unreadCount, 2);
      expect(summary.latestMessage?.text, 'Synthetic message');
    });

    test('decode paged messages and inbox cursors', () {
      final page = decodeMessagePage(<String, Object?>{
        'items': [messageJson(seq: 1), messageJson(seq: 2, id: 'm2')],
        'next_cursor': 'm1',
      });
      expect(page.items.map((message) => message.text), [
        'Synthetic message',
        'Synthetic message',
      ]);
      expect(page.nextCursor, 'm1');

      final inbox = decodeInboxPage(<String, Object?>{
        'items': [inboxItemJson()],
        'next_cursor': null,
      });
      expect(inbox.items.single.conversation.id, conversationId);
      expect(inbox.nextCursor, isNull);
    });

    test('reject malformed chat payloads with safe details', () {
      expect(
        () => decodeConversationJson(conversationJson()..['revision'] = 0),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'conversation.revision',
          ),
        ),
      );
      expect(
        () => decodeConversationJson(
          conversationJson()..['origin'] = 'unknown_origin',
        ),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'conversation.origin',
          ),
        ),
      );
      expect(
        () => decodeMessageJson(
          messageJson()..['sent_at'] = '2026-02-30T00:00:00+00:00',
        ),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'message.sent_at',
          ),
        ),
      );
      expect(
        () => decodeMessageJson(messageJson()..['text'] = '   '),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'message.text',
          ),
        ),
      );
      expect(
        () => decodeMessageJson(messageJson()..['kind'] = 'attachment'),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'message.attachment_media_ids',
          ),
        ),
      );
      expect(
        () => decodeMessageJson(messageJson()..['kind'] = 'unsupported'),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'message.kind',
          ),
        ),
      );
      expect(
        () => decodeInboxItemJson(inboxItemJson()..['unread_count'] = -1),
        throwsA(
          isA<ChatDecodeException>().having(
            (e) => e.detail,
            'detail',
            'inbox.unread_count',
          ),
        ),
      );
    });
  });

  group('chat adapter', () {
    late FakeChatSession session;
    late FakeChatTransport transport;
    late ChatDataAdapter adapter;

    setUp(() {
      session = FakeChatSession('user-a');
      transport = FakeChatTransport();
      adapter = ChatDataAdapter(transport: transport, session: session);
    });

    test(
      'inbox uses explicit paging parameters and decodes the page',
      () async {
        transport.handler = (_) => ChatTransportData(<String, Object?>{
          'items': [inboxItemJson()],
          'next_cursor': '1.50000000-0000-4000-8000-000000000001',
        });
        final result = await adapter.fetchInbox(
          userId: 'user-a',
          page: PageQuery(
            limit: 25,
            cursor: '4.50000000-0000-4000-8000-000000000001',
          ),
        );
        expect(result.isSuccess, isTrue);
        final page = result.valueOrNull!;
        expect(page.items.single.unreadCount, 2);
        expect(page.nextCursor, '1.50000000-0000-4000-8000-000000000001');
        expect(transport.calls.single.function, ChatDataAdapter.inboxFunction);
        expect(transport.calls.single.params, {
          'p_page_size': 25,
          'p_cursor': '4.50000000-0000-4000-8000-000000000001',
        });
      },
    );

    test('messages page uses beforeMessageId and decodes the cursor', () async {
      transport.handler = (_) => ChatTransportData(<String, Object?>{
        'items': [messageJson()],
        'next_cursor': null,
      });
      final result = await adapter.fetchMessages(
        conversationId: conversationId,
        page: PageQuery(limit: 30),
        beforeMessageId: '70000000-0000-4000-8000-0000000000ff',
      );
      expect(result.isSuccess, isTrue);
      expect(transport.calls.single.params, {
        'p_conversation': conversationId,
        'p_page_size': 30,
        'p_before_message': '70000000-0000-4000-8000-0000000000ff',
      });
    });

    test('caller-supplied identity must match the session', () async {
      final inbox = await adapter.fetchInbox(userId: 'user-b');
      expect(inbox.isFailure, isTrue);
      expect(
        (inbox.errorOrNull! as PermissionDeniedError).action,
        'identity_mismatch',
      );
      final send = await adapter.sendMessage(
        SendMessageCommand(
          conversationId: conversationId,
          senderUserId: 'user-b',
          text: 'forged',
          clientMessageId: 'key',
        ),
      );
      expect(send.isFailure, isTrue);
      final read = await adapter.markConversationRead(
        MarkConversationReadCommand(
          conversationId: conversationId,
          userId: 'user-b',
          lastReadMessageId: 'm',
        ),
      );
      expect(read.isFailure, isTrue);
      final mute = await adapter.setConversationMuted(
        SetConversationMutedCommand(
          conversationId: conversationId,
          userId: 'user-b',
          isMuted: true,
          idempotencyKey: 'key',
        ),
      );
      expect(mute.isFailure, isTrue);
      expect(transport.calls, isEmpty, reason: 'no request for a forged id');
    });

    test('attachment sends use the attachment RPC with media ids', () async {
      transport.handler = (_) => ChatTransportData(
        messageJson(
          kind: 'attachment',
          text: '',
          attachmentMediaIds: const [
            '50000000-0000-4000-8000-00000000000a',
          ],
        ),
      );
      final result = await adapter.sendMessage(
        SendMessageCommand(
          conversationId: conversationId,
          senderUserId: 'user-a',
          text: 'with file',
          attachmentMediaIds: const [
            '50000000-0000-4000-8000-00000000000a',
          ],
          clientMessageId: 'key',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.kind, MessageKind.attachment);
      expect(result.valueOrNull!.attachments, hasLength(1));
      expect(
        transport.calls.single.function,
        ChatDataAdapter.sendAttachmentFunction,
      );
      expect(transport.calls.single.params, {
        'p_conversation': conversationId,
        'p_key': 'key',
        'p_text': 'with file',
        'p_media_ids': const ['50000000-0000-4000-8000-00000000000a'],
      });
    });

    test(
      'opening conversations is explicitly unavailable without a request',
      () async {
        final targeted = await adapter.openTargetedRequestConversation(
          OpenTargetedRequestConversationCommand(
            requestId: 'r',
            offerId: 'o',
            buyerUserId: 'user-a',
            idempotencyKey: 'key',
          ),
        );
        expect(targeted.isFailure, isTrue);
        expect(
          (targeted.errorOrNull! as PermissionDeniedError).action,
          'conversation_open_unavailable',
        );
        final discovery = await adapter.openDiscoveryEnquiry(
          OpenDiscoveryEnquiryCommand(
            origin: ConversationOrigin.storeListing,
            subjectId: 'l',
            initiatedByUserId: 'user-a',
            idempotencyKey: 'key',
          ),
        );
        expect(discovery.isFailure, isTrue);
        final forged = await adapter.openDiscoveryEnquiry(
          OpenDiscoveryEnquiryCommand(
            origin: ConversationOrigin.storeListing,
            subjectId: 'l',
            initiatedByUserId: 'user-b',
            idempotencyKey: 'key',
          ),
        );
        expect(
          (forged.errorOrNull! as PermissionDeniedError).action,
          'identity_mismatch',
        );
        expect(transport.calls, isEmpty);
      },
    );

    test('sends keep the caller key and never regenerate it', () async {
      transport.handler = (call) => ChatTransportData(
        messageJson(clientMessageId: call.params['p_key'] as String?),
      );
      final command = SendMessageCommand(
        conversationId: conversationId,
        senderUserId: 'user-a',
        text: 'Retry-safe',
        clientMessageId: 'stable-key',
      );
      await adapter.sendMessage(command);
      await adapter.sendMessage(command);
      expect(transport.calls, hasLength(2));
      for (final call in transport.calls) {
        expect(call.function, ChatDataAdapter.sendFunction);
        expect(call.params['p_key'], 'stable-key');
        expect(call.params['p_text'], 'Retry-safe');
        expect(call.params['p_conversation'], conversationId);
      }
    });

    test('mute sends only the conversation and flag', () async {
      transport.handler = (_) => ChatTransportData(memberJson(isMuted: true));
      final result = await adapter.setConversationMuted(
        SetConversationMutedCommand(
          conversationId: conversationId,
          userId: 'user-a',
          isMuted: true,
          idempotencyKey: 'not-sent',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.isMuted, isTrue);
      expect(transport.calls.single.params, {
        'p_conversation': conversationId,
        'p_muted': true,
      });
    });

    test('in-flight identity replacement discards the result', () async {
      final gate = Future<void>.delayed(const Duration(milliseconds: 5));
      transport.gate = gate;
      transport.handler = (_) => ChatTransportData(<String, Object?>{
        'items': [inboxItemJson()],
        'next_cursor': null,
      });
      final pending = adapter.fetchInbox(userId: 'user-a');
      session.replaceWith('user-b');
      final result = await pending;
      expect(result.isFailure, isTrue);
      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
    });

    test('in-flight identity replacement also fences attachment sends', () async {
      final gate = Future<void>.delayed(const Duration(milliseconds: 5));
      transport.gate = gate;
      transport.handler = (call) => ChatTransportData(
        messageJson(
          kind: 'attachment',
          text: '',
          attachmentMediaIds: const [
            '50000000-0000-4000-8000-00000000000a',
          ],
        ),
      );
      final pending = adapter.sendMessage(
        SendMessageCommand(
          conversationId: conversationId,
          senderUserId: 'user-a',
          text: '',
          attachmentMediaIds: const ['50000000-0000-4000-8000-00000000000a'],
          clientMessageId: 'attachment-key',
        ),
      );
      session.replaceWith('user-b');
      final result = await pending;
      expect(result.isFailure, isTrue);
      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
    });

    test('malformed responses map to MalformedResponseError', () async {
      transport.handler = (_) => const ChatTransportData('not-a-map');
      final result = await adapter.fetchConversation(
        conversationId: conversationId,
      );
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<MalformedResponseError>());
    });

    test('transport failures map through the chat error mapper', () async {
      transport.handler = (_) => const ChatTransportError(
        kind: ChatTransportErrorKind.server,
        code: '42501',
        message: 'conversation_access_denied',
      );
      final result = await adapter.fetchConversation(
        conversationId: conversationId,
      );
      expect(result.isFailure, isTrue);
      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'conversation_access_denied',
      );

      transport.handler = (_) => const ChatTransportError(
        kind: ChatTransportErrorKind.connectivity,
        retryable: true,
      );
      final offline = await adapter.fetchConversation(
        conversationId: conversationId,
      );
      expect(offline.errorOrNull, isA<NetworkError>());

      transport.handler = (_) => const ChatTransportError(
        kind: ChatTransportErrorKind.server,
        message: 'idempotency_conflict',
        code: 'P0001',
      );
      final conflict = await adapter.sendMessage(
        SendMessageCommand(
          conversationId: conversationId,
          senderUserId: 'user-a',
          text: 'x',
          clientMessageId: 'k',
        ),
      );
      expect(
        (conflict.errorOrNull! as ConflictError).conflictCode,
        'idempotency_conflict',
      );
    });
  });
}
