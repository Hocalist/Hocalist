// Capture-only rendered proof for the chat block/search UI. These tests stay
// out of the default suite; run explicitly with
//   flutter test --dart-define=HOCALIST_VISUAL_CAPTURE=true --update-goldens \
//     test/phase2/chat/chat_safety_visual_capture_test.dart
// Captures land under ignored .codex-local/proof/communications/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/seller/approved_seller_chats_page.dart';

import '../../test_fonts.dart';

const conversationId = '50000000-0000-4000-8000-000000000001';
const _captureKey = ValueKey('communications-capture');
const bool _captureEnabled = bool.fromEnvironment('HOCALIST_VISUAL_CAPTURE');

const _goldenRoot = '../../../.codex-local/proof/communications';

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

ConversationMessage message(String text, {bool mine = false}) =>
    ConversationMessage(
      id: '70000000-0000-4000-8000-000000000001',
      conversationId: conversationId,
      senderUserId: mine ? 'user-a' : 'user-b',
      text: text,
      sentAt: DateTime.utc(2026, 5, 1),
    );

ChatSearchHit hit(String text) => ChatSearchHit(
  message: message(text),
  conversationId: conversationId,
  origin: ConversationOrigin.targetedRequest,
  conversationStatus: ConversationStatus.open,
  counterpartDisplayName: 'Seller B',
);

Widget conversation({
  required ConversationBlockState state,
  Future<bool> Function(bool blocked)? onBlockChanged,
  Future<PageSlice<ChatSearchHit>> Function(String query, String? cursor)?
  onSearchMessages,
}) => MaterialApp(
  home: Scaffold(
    body: KeyedSubtree(
      key: _captureKey,
      child: ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        realEntries: [
          ApprovedConversationEntry(
            isOutgoing: false,
            time: '9:30 AM',
            text: 'Hi! The iPad is in perfect condition like we discussed.',
          ),
          ApprovedConversationEntry(
            isOutgoing: true,
            time: '9:31 AM',
            text: 'Looks good! I’m ready to move forward.',
          ),
        ],
        onSubmitMessage: (_) async => true,
        blockState: state,
        onBlockChanged: onBlockChanged,
        onSearchMessages: onSearchMessages,
      ),
    ),
  ),
);

Future<void> pumpSurface(
  WidgetTester tester,
  Widget child, {
  required double width,
  double height = 1200,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        devicePixelRatio: 1,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  if (!_captureEnabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadHocalistTestFonts);

  testWidgets('blocked by counterpart at phone widths', (tester) async {
    for (final width in <double>[320, 360, 390, 430]) {
      await pumpSurface(
        tester,
        conversation(state: blockState(counterpart: true, canMessage: false)),
        width: width,
      );
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '$_goldenRoot/blocked-blockedByCounterpart-${width.toInt()}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('blocked by me with unblock action', (tester) async {
    await pumpSurface(
      tester,
      conversation(
        state: blockState(byMe: true, canMessage: false),
        onBlockChanged: (_) async => true,
      ),
      width: 390,
    );
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('$_goldenRoot/blocked-byMe-390.png'),
    );
  });

  testWidgets('block confirmation sheet', (tester) async {
    await pumpSurface(
      tester,
      conversation(state: blockState(), onBlockChanged: (_) async => true),
      width: 390,
    );
    await tester.tap(find.byKey(const Key('approved-chat-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block seller'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('approved-block-conversation-sheet')),
      matchesGoldenFile('$_goldenRoot/block-confirmation-390.png'),
    );
  });

  testWidgets('server search results and empty states', (tester) async {
    await pumpSurface(
      tester,
      conversation(
        state: blockState(),
        onSearchMessages: (query, cursor) async => PageSlice<ChatSearchHit>(
          items: [hit('apple pie recipe'), hit('I have apples')],
        ),
      ),
      width: 390,
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
    await expectLater(
      find.byKey(const ValueKey('approved-search-conversation-sheet')),
      matchesGoldenFile('$_goldenRoot/search-results-390.png'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('approved-conversation-search-field')),
      'zz',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('approved-search-conversation-sheet')),
      matchesGoldenFile('$_goldenRoot/search-empty-390.png'),
    );
  });

  testWidgets('block banner at scaled text', (tester) async {
    for (final scale in <double>[1.15, 1.3, 1.6]) {
      await pumpSurface(
        tester,
        conversation(state: blockState(counterpart: true, canMessage: false)),
        width: 390,
        textScale: scale,
      );
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile(
          '$_goldenRoot/blocked-textscale-${scale.toStringAsFixed(2)}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('seller inbox server search states', (tester) async {
    await pumpSurface(
      tester,
      MaterialApp(
        home: Scaffold(
          body: KeyedSubtree(
            key: _captureKey,
            child: ApprovedSellerChatsPage(
              onOpenConversation: () {},
              realThreads: const [],
              onSearchConversations: (query) async =>
                  PageSlice<ConversationSummary>(
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
                        latestMessage: message('See you at the mall entrance.'),
                      ),
                    ],
                  ),
            ),
          ),
        ),
      ),
      width: 390,
    );
    await tester.enterText(find.byKey(const Key('sellerChatsSearch')), 'maya');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('$_goldenRoot/seller-search-results-390.png'),
    );
  });
}
