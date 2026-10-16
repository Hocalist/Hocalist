import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/notifications/push_inbox_router.dart';
import 'package:hocalist/domain/phase2/notifications.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  NotificationInboxItem item([String value = id]) => NotificationInboxItem(
    id: value,
    kind: 'new_message',
    title: 'Message',
    createdAt: DateTime.utc(2026),
  );
  late String? identity;
  late int opens, refreshes, errors, lookups;
  late Future<NotificationInboxItem?> Function(String) lookup;
  late PushInboxRouter router;
  setUp(() {
    identity = 'A';
    opens = 0;
    refreshes = 0;
    errors = 0;
    lookups = 0;
    lookup = (_) async => item();
    router = PushInboxRouter(
      identity: () => identity,
      lookup: (id) {
        lookups++;
        return lookup(id);
      },
      refresh: () async {
        refreshes++;
      },
      open: (_) async {
        opens++;
      },
      unavailable: () {
        errors++;
      },
    );
  });
  test(
    'foreground refresh does not navigate or trust notification content',
    () async {
      await router.receive(const PushInboxSignal(id, opened: false));
      expect(refreshes, 1);
      expect(opens, 0);
      expect(lookups, 0);
    },
  );
  test('tap resolves an authorized record before opening', () async {
    await router.receive(const PushInboxSignal(id, opened: true));
    expect(lookups, 1);
    expect(opens, 1);
    expect(errors, 0);
  });
  test('signed out and malformed ids cause no lookup', () async {
    await router.receive(
      const PushInboxSignal(
        '------------------------------------',
        opened: true,
      ),
    );
    identity = null;
    await router.receive(const PushInboxSignal(id, opened: true));
    expect(lookups, 0);
  });
  test('identity replacement drops the pending record', () async {
    final pending = Completer<NotificationInboxItem?>();
    lookup = (_) => pending.future;
    final work = router.receive(const PushInboxSignal(id, opened: true));
    identity = 'B';
    pending.complete(item());
    await work;
    expect(opens, 0);
    expect(errors, 0);
  });
  test('disposed view drops pending result', () async {
    final pending = Completer<NotificationInboxItem?>();
    lookup = (_) => pending.future;
    final work = router.receive(const PushInboxSignal(id, opened: true));
    router.dispose();
    pending.complete(item());
    await work;
    expect(opens, 0);
  });
  test('missing, mismatched and failed lookup do not navigate', () async {
    const second = '22222222-2222-4222-8222-222222222222';
    const third = '33333333-3333-4333-8333-333333333333';
    lookup = (_) async => null;
    await router.receive(const PushInboxSignal(id, opened: true));
    lookup = (_) async => item('other');
    await router.receive(const PushInboxSignal(second, opened: true));
    lookup = (_) async => throw StateError('private provider detail');
    await router.receive(const PushInboxSignal(third, opened: true));
    expect(opens, 0);
    expect(errors, 3);
  });
  test('newer tap wins over late earlier response', () async {
    final pending = Completer<NotificationInboxItem?>();
    lookup = (_) => pending.future;
    final first = router.receive(const PushInboxSignal(id, opened: true));
    lookup = (_) async => item();
    await router.receive(const PushInboxSignal(id, opened: true));
    pending.complete(item());
    await first;
    expect(opens, 1);
  });

  test(
    'a cold-start tap is retained and replayed after authentication',
    () async {
      identity = null;
      await router.receive(const PushInboxSignal(id, opened: true));
      expect(lookups, 0, reason: 'nothing is fetched before a session exists');
      expect(router.hasRetained, isTrue);
      await router.onAuthenticated();
      identity = 'A';
      await router.onAuthenticated();
      expect(lookups, 1);
      expect(opens, 1);
      expect(router.hasRetained, isFalse);
    },
  );

  test('only the most recent retained tap replays', () async {
    const other = '22222222-2222-4222-8222-222222222222';
    lookup = (value) async => item(value);
    identity = null;
    await router.receive(const PushInboxSignal(id, opened: true));
    await router.receive(const PushInboxSignal(other, opened: true));
    identity = 'A';
    await router.onAuthenticated();
    expect(lookups, 1);
    expect(opens, 1);
    expect(router.hasRetained, isFalse);
  });

  test('a foreground refresh is dropped while signed out', () async {
    identity = null;
    await router.receive(const PushInboxSignal(id, opened: false));
    expect(refreshes, 0);
    expect(router.hasRetained, isFalse);
  });

  test('a repeated opened signal is handled once', () async {
    await router.receive(const PushInboxSignal(id, opened: true));
    await router.receive(const PushInboxSignal(id, opened: true));
    expect(lookups, 1);
    expect(opens, 1);
  });

  test('the role guard blocks navigation without opening', () async {
    router.dispose();
    router = PushInboxRouter(
      identity: () => identity,
      lookup: (id) {
        lookups++;
        return lookup(id);
      },
      refresh: () async {
        refreshes++;
      },
      open: (_) async {
        opens++;
      },
      unavailable: () {
        errors++;
      },
      canOpen: (_) => false,
    );
    await router.receive(const PushInboxSignal(id, opened: true));
    expect(lookups, 1);
    expect(opens, 0);
    expect(errors, 1);
  });

  test('onAuthenticated without a retained tap is a no-op', () async {
    await router.onAuthenticated();
    expect(lookups, 0);
    expect(opens, 0);
  });
}
