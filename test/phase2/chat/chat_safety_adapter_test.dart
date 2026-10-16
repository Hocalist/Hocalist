// Focused tests for the communications-completion chat adapter additions:
// durable block state, block/unblock commands and server-side search. Fakes
// only; no SDK, network or plugin use.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_adapter.dart';
import 'package:hocalist/data/phase2/chat/chat_codecs.dart';
import 'package:hocalist/data/phase2/chat/chat_transport.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/failures.dart';

import 'support/chat_fakes.dart';

const conversationId = '50000000-0000-4000-8000-000000000001';
const userId = 'user-a';

Map<String, Object?> blockStateJson({
  bool byMe = false,
  bool counterpart = false,
  bool canMessage = true,
  String status = 'open',
}) => <String, Object?>{
  'conversation_id': conversationId,
  'is_blocked_by_me': byMe,
  'blocked_by_counterpart': counterpart,
  'conversation_status': status,
  'can_message': canMessage,
};

Map<String, Object?> searchHitJson({String text = 'apple pie'}) =>
    <String, Object?>{
      'message': messageJson(text: text),
      'conversation_id': conversationId,
      'conversation_origin': 'targeted_request',
      'conversation_status': 'open',
      'counterpart_display_name': 'Seller B',
    };

void main() {
  group('block and search codecs', () {
    test('decode a block state', () {
      final state = decodeBlockStateJson(
        blockStateJson(byMe: true, canMessage: false),
      );
      expect(state.conversationId, conversationId);
      expect(state.isBlockedByMe, isTrue);
      expect(state.blockedByCounterpart, isFalse);
      expect(state.conversationStatus, ConversationStatus.open);
      expect(state.canMessage, isFalse);
      expect(state.hasActiveBlock, isTrue);
    });

    test('decode a search page and reject malformed rows', () {
      final page = decodeSearchPage(<String, Object?>{
        'items': [searchHitJson()],
        'next_cursor': '12.50000000-0000-4000-8000-000000000001',
      });
      expect(page.items.single.message.text, 'apple pie');
      expect(page.items.single.origin, ConversationOrigin.targetedRequest);
      expect(page.items.single.counterpartDisplayName, 'Seller B');
      expect(page.nextCursor, isNotNull);

      expect(
        () => decodeSearchPage(<String, Object?>{
          'items': [searchHitJson()..['conversation_origin'] = 'bogus'],
          'next_cursor': null,
        }),
        throwsA(
          isA<ChatDecodeException>().having(
            (error) => error.detail,
            'detail',
            'search.conversation_origin',
          ),
        ),
      );
    });
  });

  group('chat safety adapter', () {
    late FakeChatTransport transport;
    late FakeChatSession session;
    late ChatDataAdapter adapter;

    setUp(() {
      transport = FakeChatTransport();
      session = FakeChatSession(userId);
      adapter = ChatDataAdapter(transport: transport, session: session);
    });

    test('block sends the reviewed wire shape and decodes the state', () async {
      transport.handler = (call) =>
          ChatTransportData(blockStateJson(byMe: true, canMessage: false));
      final result = await adapter.blockConversation(
        BlockConversationCommand(
          conversationId: conversationId,
          userId: userId,
          reasonCode: 'safety',
          idempotencyKey: 'key-1',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.isBlockedByMe, isTrue);
      expect(transport.calls.single.function, 'chat_block');
      expect(transport.calls.single.schema, 'hocalist');
      expect(transport.calls.single.params['p_conversation'], conversationId);
      expect(transport.calls.single.params['p_reason'], 'safety');
    });

    test('a foreign identity is rejected before any transport call', () async {
      final result = await adapter.blockConversation(
        BlockConversationCommand(
          conversationId: conversationId,
          userId: 'someone-else',
          idempotencyKey: 'key-1',
        ),
      );
      expect(result.isFailure, isTrue);
      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'identity_mismatch',
      );
      expect(transport.calls, isEmpty);
    });

    test('unblock and fetchBlockState use the participant RPCs', () async {
      transport.handler = (_) => ChatTransportData(blockStateJson());
      final fetched = await adapter.fetchBlockState(
        conversationId: conversationId,
        userId: userId,
      );
      expect(fetched.isSuccess, isTrue);
      await adapter.unblockConversation(
        UnblockConversationCommand(
          conversationId: conversationId,
          userId: userId,
          idempotencyKey: 'key-2',
        ),
      );
      expect(transport.calls.map((call) => call.function), [
        'chat_block_state',
        'chat_unblock',
      ]);
    });

    test('searchMessages pages with the optional conversation scope', () async {
      transport.handler = (_) => ChatTransportData(<String, Object?>{
        'items': [searchHitJson()],
        'next_cursor': null,
      });
      final result = await adapter.searchMessages(
        userId: userId,
        query: '  apple  ',
        page: PageQuery(limit: 25, cursor: '7.m1'),
        conversationId: conversationId,
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.items.single.message.text, 'apple pie');
      expect(result.valueOrNull!.items.single.senderDisplayName, 'You');
      final call = transport.calls.single;
      expect(call.function, 'chat_search');
      expect(call.params['p_query'], 'apple');
      expect(call.params['p_page_size'], 25);
      expect(call.params['p_cursor'], '7.m1');
      expect(call.params['p_conversation'], conversationId);
    });

    test('a query outside 2..64 characters is rejected locally', () async {
      final short = await adapter.searchMessages(userId: userId, query: ' a ');
      expect(short.isFailure, isTrue);
      expect(short.errorOrNull!.kind, RepositoryFailureKind.validation);
      final long = await adapter.searchMessages(
        userId: userId,
        query: 'x' * 65,
      );
      expect(long.isFailure, isTrue);
      expect(transport.calls, isEmpty);
    });

    test('searchConversations decodes inbox-shaped rows', () async {
      transport.handler = (_) => ChatTransportData(<String, Object?>{
        'items': [inboxItemJson()],
        'next_cursor': null,
      });
      final result = await adapter.searchConversations(
        userId: userId,
        query: 'seller',
      );
      expect(result.isSuccess, isTrue);
      expect(
        result.valueOrNull!.items.single.counterpartDisplayName,
        'Seller B',
      );
      expect(transport.calls.single.function, 'chat_search_inbox');
      expect(transport.calls.single.params['p_query'], 'seller');
    });

    test(
      'a conversation_blocked server error maps to a typed denial',
      () async {
        transport.handler = (_) => const ChatTransportError(
          kind: ChatTransportErrorKind.server,
          code: '42501',
          message: 'conversation_blocked',
          statusCode: 403,
        );
        final result = await adapter.fetchBlockState(
          conversationId: conversationId,
          userId: userId,
        );
        expect(result.isFailure, isTrue);
        final error = result.errorOrNull! as PermissionDeniedError;
        expect(error.action, 'conversation_blocked');
      },
    );

    test(
      'a malformed search payload is reported without payload values',
      () async {
        transport.handler = (_) => const ChatTransportData(<String, Object?>{
          'items': [
            <String, Object?>{'message': 'not-an-object'},
          ],
          'next_cursor': null,
        });
        final result = await adapter.searchMessages(
          userId: userId,
          query: 'apple',
        );
        expect(result.isFailure, isTrue);
        final error = result.errorOrNull! as MalformedResponseError;
        expect(error.operation, 'chat_search');
        expect(error.detail, 'search.message.result');
      },
    );

    test('an identity replacement during a call discards the result', () async {
      final gate = Completer<void>();
      transport.gate = gate.future;
      transport.handler = (_) => ChatTransportData(blockStateJson());
      final pending = adapter.blockConversation(
        BlockConversationCommand(
          conversationId: conversationId,
          userId: userId,
          idempotencyKey: 'key-1',
        ),
      );
      session.replaceWith('user-b');
      gate.complete();
      final result = await pending;
      expect(result.isFailure, isTrue);
      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
    });
  });
}
