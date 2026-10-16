// Rendered widget checks for the chat safety UI: block banner, disabled
// composer, unblock/block writes and server-side search. Widget tests only;
// no network, plugin or live data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/seller/approved_seller_chats_page.dart';

const conversationId = '50000000-0000-4000-8000-000000000001';

ConversationBlockState blockState({
  bool byMe = false,
  bool counterpart = false,
  bool canMessage = true,
}) => ConversationBlockState(
  conversationId: conversationId,
  isBlockedByMe: byMe,
  blockedByCounterpart: counterpart,
  conversationStatus: ConversationStatus.open,
  canMessage: canMessage,
);

ChatSearchHit searchHit({String text = 'apple pie'}) => ChatSearchHit(
  message: ChatMessageFactories.text(text),
  conversationId: conversationId,
  origin: ConversationOrigin.targetedRequest,
  conversationStatus: ConversationStatus.open,
  counterpartDisplayName: 'Seller B',
);

class ChatMessageFactories {
  static ConversationMessage text(String value) => ConversationMessage(
    id: '70000000-0000-4000-8000-000000000001',
    conversationId: conversationId,
    senderUserId: 'user-b',
    text: value,
    sentAt: DateTime.utc(2026, 5, 1),
  );
}

ApprovedConversationEntry entry(String text) =>
    ApprovedConversationEntry(isOutgoing: false, time: '9:30 AM', text: text);

Widget conversation({
  ConversationBlockState? state,
  Future<bool> Function(bool blocked)? onBlockChanged,
  Future<PageSlice<ChatSearchHit>> Function(String query, String? cursor)?
  onSearchMessages,
}) => MaterialApp(
  home: Scaffold(
    body: ApprovedConversationBody(
      onBack: () {},
      onPrimary: () {},
      onCall: () {},
      onMore: () {},
      onRequestChange: () {},
      onChangeLocation: () {},
      onAttach: () {},
      onSend: (_) {},
      onLearnMore: () {},
      realEntries: [entry('hello there')],
      onSubmitMessage: (_) async => true,
      blockState: state,
      blockWritePending: false,
      onBlockChanged: onBlockChanged,
      onSearchMessages: onSearchMessages,
    ),
  ),
);

Future<void> pumpConversation(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a block banner renders and the composer stays disabled', (
    tester,
  ) async {
    await pumpConversation(
      tester,
      conversation(state: blockState(counterpart: true, canMessage: false)),
    );

    expect(find.byKey(const Key('approvedChatBlockedNotice')), findsOneWidget);
    expect(find.text('Messaging is unavailable'), findsWidgets);
    final field = tester.widget<TextField>(
      find.byKey(const Key('approved-chat-message')),
    );
    expect(field.enabled, isFalse);
    final send = tester.widget<IconButton>(
      find.byKey(const Key('approved-chat-send')),
    );
    expect(send.onPressed, isNull);
    // The blocked member never gets an unblock action pointing at the other.
    expect(find.byKey(const Key('approvedChatUnblockAction')), findsNothing);
  });

  testWidgets('blocked-by-me shows Unblock and writes through', (tester) async {
    final writes = <bool>[];
    await pumpConversation(
      tester,
      conversation(
        state: blockState(byMe: true, canMessage: false),
        onBlockChanged: (blocked) async {
          writes.add(blocked);
          return true;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('approvedChatUnblockAction')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('approved-unblock-conversation-sheet')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('approved-unblock-conversation-sheet')),
        matching: find.text('Unblock'),
      ),
    );
    await tester.pumpAndSettle();

    expect(writes, [false]);
    expect(find.textContaining('You unblocked seller.'), findsOneWidget);
  });

  testWidgets('the conversation menu records a block through the contract', (
    tester,
  ) async {
    final writes = <bool>[];
    await pumpConversation(
      tester,
      conversation(
        state: blockState(canMessage: true),
        onBlockChanged: (blocked) async {
          writes.add(blocked);
          return true;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('approved-chat-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block seller'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('approved-block-conversation-sheet')),
        matching: find.text('Block'),
      ),
    );
    await tester.pumpAndSettle();

    expect(writes, [true]);
    expect(find.textContaining('You blocked seller.'), findsOneWidget);
  });

  testWidgets('a failed block write stays on the sheet with a retry message', (
    tester,
  ) async {
    await pumpConversation(
      tester,
      conversation(
        state: blockState(canMessage: true),
        onBlockChanged: (_) async => false,
      ),
    );

    await tester.tap(find.byKey(const Key('approved-chat-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block seller'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('approved-block-conversation-sheet')),
        matching: find.text('Block'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approved-block-write-error')), findsOneWidget);
    expect(
      find.byKey(const Key('approved-block-conversation-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('server search renders paged results and the empty state', (
    tester,
  ) async {
    final queries = <String>[];
    var calls = 0;
    await pumpConversation(
      tester,
      conversation(
        state: blockState(),
        onSearchMessages: (query, cursor) async {
          queries.add(query);
          calls += 1;
          if (query == 'zz') {
            return PageSlice<ChatSearchHit>(items: const []);
          }
          return PageSlice<ChatSearchHit>(items: [searchHit()]);
        },
      ),
    );

    await tester.tap(find.byKey(const Key('approved-chat-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search conversation'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('approved-conversation-search-field')),
      'apple',
    );
    await tester.tap(find.text('Search messages').last);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(queries, ['apple']);
    expect(find.text('apple pie'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('approved-conversation-search-field')),
      'zz',
    );
    await tester.tap(find.text('Search messages').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('approvedConversationSearchEmpty')),
      findsOneWidget,
    );
  });

  testWidgets('a server search failure offers a retry', (tester) async {
    var calls = 0;
    await pumpConversation(
      tester,
      conversation(
        state: blockState(),
        onSearchMessages: (query, cursor) async {
          calls += 1;
          if (calls == 1) throw StateError('offline');
          return PageSlice<ChatSearchHit>(items: [searchHit()]);
        },
      ),
    );

    await tester.tap(find.byKey(const Key('approved-chat-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search conversation'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('approved-conversation-search-field')),
      'apple',
    );
    await tester.tap(find.text('Search messages').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('approvedConversationSearchError')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('approvedConversationSearchRetry')));
    await tester.pumpAndSettle();
    expect(find.text('apple pie'), findsOneWidget);
  });

  testWidgets('seller inbox search uses the server rows when provided', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerChatsPage(
            onOpenConversation: () {},
            realThreads: const [],
            onSearchConversations: (query) async {
              queries.add(query);
              if (query == 'nomatch') {
                return PageSlice<ConversationSummary>(items: const []);
              }
              return PageSlice<ConversationSummary>(
                items: [
                  ConversationSummary(
                    conversation: Conversation(
                      id: conversationId,
                      origin: ConversationOrigin.targetedRequest,
                      members: [
                        ConversationMember(
                          userId: 'user-a',
                          profileId: '10000000-0000-4000-8000-00000000000a',
                          role: HocalistRole.buyer,
                          joinedAt: DateTime.utc(2026, 5, 1),
                        ),
                        ConversationMember(
                          userId: 'user-b',
                          profileId: '10000000-0000-4000-8000-00000000000b',
                          role: HocalistRole.seller,
                          joinedAt: DateTime.utc(2026, 5, 1),
                        ),
                      ],
                      status: ConversationStatus.open,
                      stamp: RecordStamp(
                        revision: 1,
                        createdAt: DateTime.utc(2026, 5, 1),
                        updatedAt: DateTime.utc(2026, 5, 1),
                      ),
                      requestId: '60000000-0000-4000-8000-000000000001',
                    ),
                    counterpartDisplayName: 'Maya R.',
                    latestMessage: ChatMessageFactories.text('hello'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('sellerChatsSearch')), 'maya');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(queries, ['maya']);
    expect(find.text('Maya R.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sellerChatsSearch')),
      'nomatch',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerChatsEmpty')), findsOneWidget);
    expect(find.text('No matching conversations'), findsOneWidget);
    expect(find.byKey(const Key('sellerChatsClearSearch')), findsOneWidget);
  });
}
