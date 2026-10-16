// Widget coverage for the Buyer inbox server search added by the screens.dart
// integration patch. Runs only after the patch is applied.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/main.dart' show BuyerChatsPage;

const conversationId = '50000000-0000-4000-8000-000000000001';

ConversationSummary summary(String name, {int unread = 0}) =>
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
      counterpartDisplayName: name,
      unreadCount: unread,
    );

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<PageSlice<ConversationSummary>> Function(String) search,
  }) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerChatsPage(
            onBack: () {},
            onOpenChat: () {},
            onOffers: () {},
            realThreads: const [],
            onOpenThread: (_) {},
            onSearchConversations: search,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('server rows render, filter-empty and failure retry work', (
    tester,
  ) async {
    final queries = <String>[];
    var failNext = false;
    await pumpPage(
      tester,
      search: (query) async {
        queries.add(query);
        if (failNext) {
          failNext = false;
          throw StateError('offline');
        }
        if (query == 'zz') {
          return PageSlice<ConversationSummary>(items: const []);
        }
        return PageSlice<ConversationSummary>(
          items: [summary('Maya R.', unread: 2)],
        );
      },
    );

    await tester.enterText(find.byKey(const Key('buyerChatsSearch')), 'maya');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(queries, ['maya']);
    expect(find.text('Maya R.'), findsOneWidget);

    // A filtered zero is distinct from an inbox with no conversations.
    await tester.enterText(find.byKey(const Key('buyerChatsSearch')), 'zz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buyerChatsFilteredEmpty')), findsOneWidget);
    expect(find.text('No matching conversations'), findsOneWidget);

    // A failure shows a retry that re-runs the same query.
    failNext = true;
    await tester.enterText(find.byKey(const Key('buyerChatsSearch')), 'maya');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buyerChatsSearchError')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Maya R.'), findsOneWidget);
    expect(queries.where((query) => query == 'maya'), hasLength(3));
    expect(tester.takeException(), isNull);
  });
}
