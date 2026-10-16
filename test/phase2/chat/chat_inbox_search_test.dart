// Focused tests for the debounced, generation-fenced inbox search controller.
// Fakes only; no network, SDK or plugin use.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_inbox_search.dart';
import 'package:hocalist/data/phase2/chat/chat_safety_coordinator.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/conversations.dart';
import 'package:hocalist/domain/phase2/profiles.dart';

ConversationSummary summary(String name, {int unread = 0}) =>
    ConversationSummary(
      conversation: Conversation(
        id: '50000000-0000-4000-8000-000000000001',
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
  late List<String> queries;
  late Map<String, Completer<PageSlice<ConversationSummary>>> pending;
  late ChatInboxSearchController controller;

  setUp(() {
    queries = <String>[];
    pending = <String, Completer<PageSlice<ConversationSummary>>>{};
    controller = ChatInboxSearchController(
      debounce: const Duration(milliseconds: 20),
      search: (query) {
        queries.add(query);
        final completer = Completer<PageSlice<ConversationSummary>>();
        pending[query] = completer;
        return completer.future;
      },
    );
  });

  tearDown(() => controller.dispose());

  test('safe backend capability failure reaches the inbox', () async {
    controller.updateQuery('lamp');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    pending['lamp']!.completeError(
      const ChatSafetyException(
        'backend_unavailable',
        'Search has not been enabled on the server yet.',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.error, 'Search has not been enabled on the server yet.');
    expect(controller.loading, isFalse);
  });

  test('a short query never reaches the server', () async {
    controller.updateQuery('m');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(queries, isEmpty);
    expect(controller.isSearching, isFalse);
    expect(controller.results, isEmpty);
  });

  test(
    'a query debounces into one request with loading then results',
    () async {
      controller.updateQuery('maya');
      expect(controller.loading, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(queries, ['maya']);
      expect(controller.loading, isTrue);

      pending['maya']!.complete(
        PageSlice<ConversationSummary>(items: [summary('Maya R.', unread: 2)]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.loading, isFalse);
      expect(controller.results.single.counterpartDisplayName, 'Maya R.');
      expect(controller.hasCompleted, isTrue);
      expect(controller.error, isNull);
    },
  );

  test('a newer query discards an older in-flight response', () async {
    controller.updateQuery('maya');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    controller.updateQuery('alicia');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(queries, ['maya', 'alicia']);

    pending['maya']!.complete(
      PageSlice<ConversationSummary>(items: [summary('Maya R.')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.results, isEmpty, reason: 'the stale page is discarded');

    pending['alicia']!.complete(
      PageSlice<ConversationSummary>(items: [summary('Alicia C.')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.results.single.counterpartDisplayName, 'Alicia C.');
  });

  test('a failure reports an error and retry re-runs the query', () async {
    controller.updateQuery('maya');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    pending['maya']!.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.error, isNotNull);
    expect(controller.results, isEmpty);

    final retry = controller.retry();
    expect(controller.loading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(queries, ['maya', 'maya']);
    pending['maya']!.complete(
      PageSlice<ConversationSummary>(items: [summary('Maya R.')]),
    );
    await retry;
    expect(controller.error, isNull);
    expect(controller.results, hasLength(1));
  });

  test('clear resets without another request', () async {
    controller.updateQuery('maya');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    pending['maya']!.complete(
      PageSlice<ConversationSummary>(items: [summary('Maya R.')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.results, hasLength(1));

    controller.clear();
    expect(controller.results, isEmpty);
    expect(controller.loading, isFalse);
    expect(controller.isSearching, isFalse);
    expect(queries, ['maya']);
  });

  test('dispose cancels a pending debounce and stale completion', () async {
    final local = ChatInboxSearchController(
      debounce: const Duration(milliseconds: 20),
      search: (query) {
        queries.add(query);
        return Future<PageSlice<ConversationSummary>>.value(
          PageSlice<ConversationSummary>(items: const []),
        );
      },
    );
    local.updateQuery('maya');
    local.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(queries, isEmpty, reason: 'the debounce timer was cancelled');
  });

  test('a missing search callback is reported as unavailable', () {
    final local = ChatInboxSearchController(search: null);
    local.updateQuery('maya');
    expect(local.isAvailable, isFalse);
    expect(local.isSearching, isFalse);
    expect(local.loading, isFalse);
    local.dispose();
  });
}
