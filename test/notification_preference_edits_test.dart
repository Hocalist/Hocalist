import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/notification_preference_edits.dart';
import 'package:hocalist/domain/phase2/profiles.dart';

void main() {
  test(
    'independent switches queue without overwriting an acknowledged change',
    () async {
      var current = NotificationPreferences.defaults;
      final first = Completer<String?>();
      final writes = <NotificationPreferences>[];
      late NotificationPreferenceEdits edits;
      edits = NotificationPreferenceEdits(
        read: () => current,
        changed: () {},
        save: (next) async {
          writes.add(next);
          if (writes.length == 1) await first.future;
          current = next;
          return null;
        },
      );
      final saving = edits.update('offers', false);
      expect(edits.pending('offers'), true);
      expect(edits.pending('messages'), false);
      await edits.update('messages', false);
      expect(writes.length, 1);
      expect(edits.value('messages', true), false);
      first.complete(null);
      await saving;
      expect(writes.length, 2);
      expect(current.offers, false);
      expect(current.messages, false);
      expect(current.deals, true);
      expect(edits.pending('offers'), false);
    },
  );
  test(
    'failed switch rolls back without dropping another queued switch',
    () async {
      var current = NotificationPreferences.defaults;
      final first = Completer<String?>();
      var calls = 0;
      final edits = NotificationPreferenceEdits(
        read: () => current,
        changed: () {},
        save: (next) async {
          if (++calls == 1) return first.future;
          current = next;
          return null;
        },
      );
      final saving = edits.update('offers', false);
      await edits.update('deals', false);
      first.complete('Retry offers');
      await saving;
      expect(current.offers, true);
      expect(current.deals, false);
      expect(edits.error, 'Retry offers');
    },
  );
  test('dispose suppresses pending callbacks and further writes', () async {
    final first = Completer<String?>();
    var callbacks = 0;
    var calls = 0;
    final edits = NotificationPreferenceEdits(
      read: () => NotificationPreferences.defaults,
      changed: () => callbacks++,
      save: (_) {
        calls++;
        return first.future;
      },
    );
    final saving = edits.update('offers', false);
    await edits.update('messages', false);
    edits.dispose();
    final before = callbacks;
    first.complete(null);
    await saving;
    expect(callbacks, before);
    expect(calls, 1);
  });
}
