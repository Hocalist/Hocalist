// Live-update boundary tests: signals only trigger an authoritative refetch,
// are fenced by identity and watch generation, and collapse duplicates. Fakes
// only.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_live_updates.dart';

import 'support/chat_fakes.dart';

void main() {
  late FakeChatSession session;
  late FakeChatChangeSource source;
  late ChatLiveUpdates updates;

  setUp(() {
    session = FakeChatSession('user-a');
    source = FakeChatChangeSource();
    updates = ChatLiveUpdates(
      source: source,
      session: session,
      debounce: const Duration(milliseconds: 10),
    );
  });

  test('a change signal triggers one refetch after the debounce', () async {
    var refetches = 0;
    updates.watch(
      conversationId: 'conversation-1',
      refetch: (fence) async {
        refetches += 1;
      },
    );

    source.emit('conversation-1');
    source.emit('conversation-1');
    source.emit('conversation-1');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(refetches, 1, reason: 'duplicate signals collapse');
  });

  test('signals for other conversations are ignored', () async {
    var refetches = 0;
    updates.watch(
      conversationId: 'conversation-1',
      refetch: (fence) async {
        refetches += 1;
      },
    );

    source.emit('conversation-2');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(refetches, 0);
  });

  test(
    'identity replacement stops delivery to the previous identity',
    () async {
      var refetches = 0;
      updates.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          refetches += 1;
        },
      );

      session.replaceWith('user-b');
      source.emit('conversation-1');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(refetches, 0);
    },
  );

  test('identity replacement after a signal but before expiry cancels the '
      'pending refetch', () async {
    var refetches = 0;
    final fence = updates.watch(
      conversationId: 'conversation-1',
      refetch: (fence) async {
        refetches += 1;
      },
    );

    source.emit('conversation-1');
    session.replaceWith('user-b');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(refetches, 0, reason: 'the timer callback re-checks identity');
    expect(fence.isActive, isFalse);
  });

  test(
    'stop cancels a pending refetch and dispose closes the source',
    () async {
      var refetches = 0;
      final fence = updates.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          refetches += 1;
        },
      );
      source.emit('conversation-1');
      updates.stop();
      expect(fence.isActive, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(refetches, 0);

      await updates.dispose();
      expect(source.disposed, isTrue);
    },
  );

  test(
    're-watch while a refetch is pending invalidates the old watch',
    () async {
      var first = 0;
      var second = 0;
      final fenceA = updates.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          first += 1;
        },
      );
      source.emit('conversation-1');
      final fenceB = updates.watch(
        conversationId: 'conversation-2',
        refetch: (fence) async {
          second += 1;
        },
      );

      expect(fenceA.isActive, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(first, 0, reason: 'the replaced watch must not refetch');

      source.emit('conversation-2');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(second, 1);
      expect(fenceB.isActive, isTrue);
    },
  );

  test('dispose invalidates pending work and the fence', () async {
    var refetches = 0;
    final fence = updates.watch(
      conversationId: 'conversation-1',
      refetch: (fence) async {
        refetches += 1;
      },
    );
    source.emit('conversation-1');
    await updates.dispose();

    expect(fence.isActive, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(refetches, 0);
    expect(source.disposed, isTrue);
  });

  test('a consuming controller rejects a stale in-flight result', () async {
    final gate = Completer<void>();
    ChatWatchFence? observed;
    var applied = false;
    updates.watch(
      conversationId: 'conversation-1',
      refetch: (fence) async {
        observed = fence;
        await gate.future;
        if (fence.isActive) applied = true;
      },
    );

    source.emit('conversation-1');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(observed, isNotNull);
    expect(observed!.isActive, isTrue);

    session.replaceWith('user-b');
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(applied, isFalse, reason: 'the result belongs to the old identity');
    expect(observed!.isActive, isFalse);
  });

  test('a failing refetch does not surface an unhandled error', () async {
    updates.watch(
      conversationId: 'conversation-1',
      refetch: (fence) async => throw StateError('offline'),
    );
    source.emit('conversation-1');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // Reaching this point without an unhandled exception is the assertion.
    expect(true, isTrue);
  });

  group('connection lifecycle', () {
    late FakeChatChangeConnection connection;
    late ChatLiveUpdates lifecycle;

    setUp(() {
      connection = FakeChatChangeConnection();
      lifecycle = ChatLiveUpdates(
        source: connection,
        session: session,
        debounce: const Duration(milliseconds: 10),
      );
    });

    tearDown(() async {
      await lifecycle.dispose();
    });

    test('a drop marks offline and a reconnect refetches once', () async {
      var refetches = 0;
      lifecycle.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          refetches += 1;
        },
      );
      expect(lifecycle.isOffline, isFalse);

      connection.setConnection(ChatChangeConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(lifecycle.isOffline, isTrue);
      expect(refetches, 0);

      connection.setConnection(ChatChangeConnectionState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(lifecycle.isOffline, isFalse);
      expect(refetches, 1, reason: 'recovery runs one authoritative refetch');

      connection.setConnection(ChatChangeConnectionState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(refetches, 1, reason: 'an unchanged connected state is ignored');
    });

    test('reconnect of the previous identity never refetches', () async {
      var refetches = 0;
      lifecycle.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          refetches += 1;
        },
      );
      connection.setConnection(ChatChangeConnectionState.disconnected);
      session.replaceWith('user-b');
      connection.setConnection(ChatChangeConnectionState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(refetches, 0, reason: 'the fence belongs to the old identity');
    });

    test(
      'sessionRefreshed refetches while the identity is unchanged',
      () async {
        var refetches = 0;
        lifecycle.watch(
          conversationId: 'conversation-1',
          refetch: (fence) async {
            refetches += 1;
          },
        );
        lifecycle.sessionRefreshed();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(refetches, 1);

        session.replaceWith('user-b');
        lifecycle.sessionRefreshed();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          refetches,
          1,
          reason: 'a refresh for the old identity is ignored',
        );
      },
    );

    test('refetchNow works as the offline fallback', () async {
      var refetches = 0;
      lifecycle.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          refetches += 1;
        },
      );
      lifecycle.refetchNow();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(refetches, 1);
    });

    test('reconnect delegates to the source', () async {
      await lifecycle.reconnect();
      expect(connection.reconnectCalls, 1);
    });

    test('a slow refetch does not overlap with a queued one', () async {
      final gate = Completer<void>();
      var running = 0;
      var maxRunning = 0;
      lifecycle.watch(
        conversationId: 'conversation-1',
        refetch: (fence) async {
          running += 1;
          maxRunning = running > maxRunning ? running : maxRunning;
          await gate.future;
          running -= 1;
        },
      );
      connection.emit('conversation-1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      connection.emit('conversation-1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(maxRunning, 1, reason: 'refetches never overlap');
    });

    test(
      'a new watch refetches after an older in-flight watch finishes',
      () async {
        final oldRun = Completer<void>();
        final oldStarted = Completer<void>();
        var oldReads = 0;
        var newReads = 0;
        lifecycle.watch(
          conversationId: 'old',
          refetch: (fence) async {
            oldReads += 1;
            if (!oldStarted.isCompleted) oldStarted.complete();
            await oldRun.future;
          },
        );
        connection.emit('old');
        await oldStarted.future;

        lifecycle.watch(
          conversationId: 'new',
          refetch: (fence) async {
            newReads += 1;
          },
        );
        connection.emit('new');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        oldRun.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(oldReads, 1);
        expect(newReads, 1, reason: 'the new watch queue survives the old run');
      },
    );

    test('stop and dispose discard a queued new watch', () async {
      final oldRun = Completer<void>();
      final oldStarted = Completer<void>();
      var newReads = 0;
      lifecycle.watch(
        conversationId: 'old',
        refetch: (fence) async {
          if (!oldStarted.isCompleted) oldStarted.complete();
          await oldRun.future;
        },
      );
      connection.emit('old');
      await oldStarted.future;
      lifecycle.watch(
        conversationId: 'new',
        refetch: (fence) async {
          newReads += 1;
        },
      );
      connection.emit('new');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      lifecycle.stop();
      oldRun.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(newReads, 0, reason: 'a stopped watch must not refetch');
    });

    test('an identity change discards a queued new watch', () async {
      final oldRun = Completer<void>();
      final oldStarted = Completer<void>();
      var reads = 0;
      lifecycle.watch(
        conversationId: 'old',
        refetch: (fence) async {
          if (!oldStarted.isCompleted) oldStarted.complete();
          await oldRun.future;
        },
      );
      connection.emit('old');
      await oldStarted.future;
      lifecycle.watch(
        conversationId: 'new',
        refetch: (fence) async {
          reads += 1;
        },
      );
      connection.emit('new');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      session.replaceWith('user-b');
      oldRun.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads, 0, reason: 'the queued fence belongs to the old identity');
    });
  });
}
