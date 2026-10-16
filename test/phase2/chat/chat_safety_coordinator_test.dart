// Focused tests for the session-fenced chat safety coordinator: identity
// fencing, block writes and safe search failures. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_adapter.dart';
import 'package:hocalist/data/phase2/chat/chat_safety_coordinator.dart';
import 'package:hocalist/data/phase2/chat/chat_transport.dart';

import 'support/chat_fakes.dart';

const conversationId = '50000000-0000-4000-8000-000000000001';

Map<String, Object?> blockStateJson({
  bool byMe = true,
  bool canMessage = false,
}) => <String, Object?>{
  'conversation_id': conversationId,
  'is_blocked_by_me': byMe,
  'blocked_by_counterpart': !byMe,
  'conversation_status': 'open',
  'can_message': canMessage,
};

void main() {
  const userId = 'user-a';
  late FakeChatTransport transport;
  late FakeChatSession session;
  late ChatSafetyCoordinator coordinator;

  setUp(() {
    transport = FakeChatTransport();
    session = FakeChatSession(userId);
    coordinator = ChatSafetyCoordinator(
      repository: ChatDataAdapter(transport: transport, session: session),
      identity: () => session.currentUserId,
    );
  });

  test(
    'missing deployed search is not reported as a connection failure',
    () async {
      transport.handler = (_) => const ChatTransportError(
        kind: ChatTransportErrorKind.server,
        code: 'PGRST202',
        statusCode: 404,
        message: 'Sensitive raw provider detail',
      );
      await expectLater(
        coordinator.searchConversations(query: 'lamp'),
        throwsA(
          isA<ChatSafetyException>()
              .having((e) => e.code, 'code', 'backend_unavailable')
              .having(
                (e) => e.message,
                'message',
                'Search has not been enabled on the server yet.',
              ),
        ),
      );
    },
  );

  test('loadBlockState returns the decoded state', () async {
    transport.handler = (_) => ChatTransportData(blockStateJson());
    final state = await coordinator.loadBlockState(conversationId);
    expect(state, isNotNull);
    expect(state!.isBlockedByMe, isTrue);
    expect(state.canMessage, isFalse);
  });

  test('block and unblock report only a confirmed write', () async {
    transport.handler = (_) => ChatTransportData(blockStateJson());
    expect(await coordinator.setBlocked(conversationId, true), isTrue);
    expect(transport.calls.last.function, 'chat_block');

    transport.handler = (_) =>
        ChatTransportData(blockStateJson(byMe: false, canMessage: true));
    expect(await coordinator.setBlocked(conversationId, false), isTrue);
    expect(transport.calls.last.function, 'chat_unblock');
  });

  test('an unconfirmed block write reports false', () async {
    transport.handler = (_) => const ChatTransportError(
      kind: ChatTransportErrorKind.connectivity,
      retryable: true,
    );
    expect(await coordinator.setBlocked(conversationId, true), isFalse);
  });

  test('signed-out calls fail closed without a transport call', () async {
    session.replaceWith(null);
    expect(await coordinator.loadBlockState(conversationId), isNull);
    expect(await coordinator.setBlocked(conversationId, true), isFalse);
    await expectLater(
      coordinator.searchMessages(
        conversationId: conversationId,
        query: 'apples',
      ),
      throwsA(isA<ChatSafetyException>()),
    );
    expect(transport.calls, isEmpty);
  });

  test('search maps validation and denial failures to safe text', () async {
    transport.handler = (_) => const ChatTransportError(
      kind: ChatTransportErrorKind.server,
      code: '42501',
      message: 'conversation_blocked',
      statusCode: 403,
    );
    try {
      await coordinator.searchMessages(
        conversationId: conversationId,
        query: 'apples',
      );
      fail('expected a denial');
    } on ChatSafetyException catch (error) {
      expect(error.code, 'denied');
      expect(error.message, 'You do not have access to this conversation.');
    }

    transport.handler = (_) => const ChatTransportError(
      kind: ChatTransportErrorKind.connectivity,
      retryable: true,
    );
    try {
      await coordinator.searchConversations(query: 'apples');
      fail('expected a network failure');
    } on ChatSafetyException catch (error) {
      expect(error.code, 'network');
    }
  });

  test('a paged search returns the server page with its cursor', () async {
    transport.handler = (_) => ChatTransportData(<String, Object?>{
      'items': [
        <String, Object?>{
          'message': messageJson(text: 'apple pie'),
          'conversation_id': conversationId,
          'conversation_origin': 'targeted_request',
          'conversation_status': 'open',
          'counterpart_display_name': 'Seller B',
        },
      ],
      'next_cursor': '9.50000000-0000-4000-8000-000000000001',
    });
    final page = await coordinator.searchMessages(
      conversationId: conversationId,
      query: 'apple',
      cursor: '7.50000000-0000-4000-8000-000000000001',
    );
    expect(page.items.single.message.text, 'apple pie');
    expect(page.nextCursor, isNotNull);
    expect(
      transport.calls.single.params['p_cursor'],
      '7.50000000-0000-4000-8000-000000000001',
    );
    expect(transport.calls.single.params['p_page_size'], 25);
  });
}
