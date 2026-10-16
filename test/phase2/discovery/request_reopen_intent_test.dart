// Reopen intent retention: lost acknowledgement, same-key replay, changed
// intent, overlapping calls, discard and identity replacement.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'package:hocalist/data/phase2/marketplace/request_reopen_intent.dart';
import 'package:hocalist/domain/phase2/requests.dart';

import '../marketplace/support/marketplace_fakes.dart';

MarketplaceRequestFixture fixture() => MarketplaceRequestFixture();

class MarketplaceRequestFixture {
  final request = decodeRequestJson(requestJson(), 'test');
}

void main() {
  test('a lost acknowledgement is retried with the same key, applied once', () async {
    final keys = <String>[];
    final applied = <String>[];
    var calls = 0;
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) async {
        keys.add(operationKey);
        calls += 1;
        if (calls == 1) {
          throw const StoreBackendException('lost acknowledgement', ambiguous: true);
        }
        return fixture().request;
      },
      apply: (request) => applied.add(request.id),
    );
    await expectLater(
      controller.run(requestId: 'request-1', expectedRevision: 3),
      throwsA(isA<StoreBackendException>().having((e) => e.ambiguous, 'ambiguous', isTrue)),
    );
    expect(controller.hasPendingIntent, isTrue);
    expect(controller.pendingRequestId, 'request-1');
    expect(controller.pendingExpectedRevision, 3);

    await controller.run(requestId: 'request-1', expectedRevision: 3);
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
    expect(applied, hasLength(1));
    expect(controller.hasPendingIntent, isFalse);
  });

  test('a definitive rejection clears the intent and a new key is used', () async {
    final keys = <String>[];
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) async {
        keys.add(operationKey);
        if (keys.length == 1) {
          throw const StoreBackendException('That request cannot be reopened.');
        }
        return fixture().request;
      },
      apply: (_) {},
    );
    await expectLater(
      controller.run(requestId: 'request-1', expectedRevision: 3),
      throwsA(isA<StoreBackendException>()),
    );
    expect(controller.hasPendingIntent, isFalse);
    await controller.run(requestId: 'request-1', expectedRevision: 4);
    expect(keys[0], isNot(keys[1]));
  });

  test('a changed intent while unresolved uses a new key', () async {
    final keys = <String>[];
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) async {
        keys.add(operationKey);
        if (keys.length == 1) {
          throw const StoreBackendException('lost acknowledgement', ambiguous: true);
        }
        return fixture().request;
      },
      apply: (_) {},
    );
    await expectLater(
      controller.run(requestId: 'request-1', expectedRevision: 3),
      throwsA(isA<StoreBackendException>()),
    );
    await controller.run(requestId: 'request-1', expectedRevision: 4);
    expect(keys[0], isNot(keys[1]));
  });

  test('overlapping calls are refused while one intent is in flight', () async {
    final gate = Completer<MarketplaceRequest>();
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) =>
          gate.future,
      apply: (_) {},
    );
    final pending = controller.run(requestId: 'request-1', expectedRevision: 3);
    await expectLater(
      controller.run(requestId: 'request-1', expectedRevision: 3),
      throwsA(
        isA<StoreBackendException>().having(
          (e) => e.message,
          'message',
          contains('already in progress'),
        ),
      ),
    );
    gate.complete(fixture().request);
    await pending;
  });

  test('discard fences a late result so it is never applied', () async {
    final gate = Completer<MarketplaceRequest>();
    final keys = <String>[];
    final applied = <String>[];
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) {
        keys.add(operationKey);
        if (keys.length == 1) return gate.future;
        return Future.value(fixture().request);
      },
      apply: (request) => applied.add(request.id),
    );
    final pending = controller.run(requestId: 'request-1', expectedRevision: 3);
    controller.discard();
    gate.complete(fixture().request);
    await expectLater(
      pending,
      throwsA(isA<StoreBackendException>().having((e) => e.ambiguous, 'ambiguous', isTrue)),
    );
    expect(applied, isEmpty);
    await controller.run(requestId: 'request-1', expectedRevision: 3);
    expect(keys[0], isNot(keys[1]));
    expect(applied, hasLength(1));
  });

  test('dispose fences identity replacement and refuses later calls', () async {
    final gate = Completer<MarketplaceRequest>();
    final applied = <String>[];
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) =>
          gate.future,
      apply: (request) => applied.add(request.id),
    );
    final pending = controller.run(requestId: 'request-1', expectedRevision: 3);
    controller.dispose();
    gate.complete(fixture().request);
    await expectLater(
      pending,
      throwsA(isA<StoreBackendException>().having((e) => e.ambiguous, 'ambiguous', isTrue)),
    );
    expect(applied, isEmpty);
    await expectLater(
      controller.run(requestId: 'request-1', expectedRevision: 3),
      throwsA(
        isA<StoreBackendException>().having(
          (e) => e.message,
          'message',
          contains('account changed'),
        ),
      ),
    );
  });

  test('a successful reopen clears the intent before the next request', () async {
    final keys = <String>[];
    final controller = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) async {
        keys.add(operationKey);
        return fixture().request;
      },
      apply: (_) {},
    );
    await controller.run(requestId: 'request-1', expectedRevision: 3);
    await controller.run(requestId: 'request-1', expectedRevision: 4);
    expect(keys[0], isNot(keys[1]));
    expect(controller.hasPendingIntent, isFalse);
  });
}

