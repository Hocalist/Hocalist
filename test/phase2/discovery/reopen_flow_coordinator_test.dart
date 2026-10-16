// Page-authority fences for the buyer reopen flow: a delayed result may only
// adopt the destination, session and selected request it started for.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'package:hocalist/data/phase2/marketplace/request_reopen_intent.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/features/discovery/reopen_flow_coordinator.dart';

import '../marketplace/support/marketplace_fakes.dart';

MarketplaceRequest requestFixture() =>
    decodeRequestJson(requestJson(), 'test');

typedef FlowReopen = Future<MarketplaceRequest> Function({
  required String requestId,
  required int expectedRevision,
});

class FlowHarness {
  FlowHarness({
    required this.reopen,
    this.session = 'user-a',
    this.epoch = 1,
    this.selected = 'request-a',
    this.onDiscard,
  }) {
    coordinator = ReopenFlowCoordinator(
      reopen: reopen,
      sessionUserId: () => session,
      destinationEpoch: () => epoch,
      selectedRequestId: () => selected,
      discardServerIntent: onDiscard,
    );
  }

  final FlowReopen reopen;
  String? session;
  int epoch;
  String? selected;
  final VoidCallback? onDiscard;
  late final ReopenFlowCoordinator coordinator;

  void leaveAndReturn() {
    epoch += 1; // leaving the route
    epoch += 1; // re-entering the same route is a new destination
  }
}

void main() {
  test('a delayed result for A is superseded once B is selected', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(reopen: ({required requestId, required expectedRevision}) => gate.future);
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.selected = 'request-b';
    gate.complete(requestFixture());
    final outcome = await pending;
    expect(outcome, isA<ReopenFlowSuperseded>());
    expect(harness.coordinator.error, isNull);
    expect(harness.coordinator.busy, isFalse);
  });

  test('recovery A → recovery B supersedes the A attempt', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(reopen: ({required requestId, required expectedRevision}) => gate.future);
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.epoch += 1; // navigated to B's recovery route
    harness.selected = 'request-b';
    gate.complete(requestFixture());
    expect(await pending, isA<ReopenFlowSuperseded>());
    expect(harness.coordinator.busy, isFalse);
  });

  test('leave-and-return to the same route supersedes the pending attempt', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(reopen: ({required requestId, required expectedRevision}) => gate.future);
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.leaveAndReturn();
    gate.complete(requestFixture());
    expect(await pending, isA<ReopenFlowSuperseded>());
    expect(harness.coordinator.error, isNull);
  });

  test('a stale failure does not write error state or stick busy', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => gate.future,
    );
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.leaveAndReturn();
    gate.completeError(
      const StoreBackendException(
        'The reopen could not be confirmed.',
        ambiguous: true,
      ),
    );
    expect(await pending, isA<ReopenFlowStale>());
    expect(harness.coordinator.error, isNull);
    expect(harness.coordinator.uncertain, isFalse);
    expect(harness.coordinator.busy, isFalse);
  });

  test('a definitive rejection after a selected-request change stays silent', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => gate.future,
    );
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    // B is selected while A's attempt is still in flight; the epoch is
    // deliberately unchanged so this exercises the selected-request fence.
    harness.selected = 'request-b';
    gate.completeError(
      const StoreBackendException('A was rejected'),
    );
    final outcome = await pending;
    expect(outcome, isA<ReopenFlowStale>());
    expect(reopenPageFeedback(outcome), isNull);
    expect(harness.coordinator.error, isNull, reason: 'B must not inherit A errors');
    expect(harness.coordinator.uncertain, isFalse);
    expect(harness.coordinator.busy, isFalse);
  });

  test('a definitive rejection after a destination change stays silent', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => gate.future,
    );
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.leaveAndReturn();
    gate.completeError(
      const StoreBackendException('Permission denied'),
    );
    final outcome = await pending;
    expect(outcome, isA<ReopenFlowStale>());
    expect(outcome, isNot(isA<ReopenFlowSuperseded>()));
    expect(reopenPageFeedback(outcome), isNull);
    expect(harness.coordinator.error, isNull);
  });

  test('a current-destination failure keeps truthful feedback and retry state', () async {
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) async {
        throw const StoreBackendException(
          'The reopen could not be confirmed. Retry to check it safely.',
          ambiguous: true,
        );
      },
    );
    final outcome = await harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    expect(outcome, isA<ReopenFlowFailed>());
    expect((outcome as ReopenFlowFailed).uncertain, isTrue);
    expect(harness.coordinator.error, contains('Retry to check it safely'));
    expect(harness.coordinator.uncertain, isTrue);
  });

  test('identity replacement and dispose invalidate an in-flight attempt', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => gate.future,
    );
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.session = 'user-b';
    gate.complete(requestFixture());
    final replaced = await pending;
    expect(replaced, isA<ReopenFlowStale>());
    expect(
      reopenPageFeedback(replaced),
      isNull,
      reason: 'a replacement account never shows old-account feedback',
    );
    expect(harness.coordinator.error, isNull);

    final second = Completer<MarketplaceRequest>();
    final harness2 = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) =>
          second.future,
    );
    final pending2 = harness2.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness2.coordinator.dispose();
    second.complete(requestFixture());
    expect(await pending2, isA<ReopenFlowStale>());

    final afterDispose = await harness2.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    expect(afterDispose, isA<ReopenFlowStale>());
  });

  test('a same-destination retry replays the original operation key', () async {
    final keys = <String>[];
    final intent = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) async {
        keys.add(operationKey);
        if (keys.length == 1) {
          throw const StoreBackendException(
            'The reopen could not be confirmed. Retry to check it safely.',
            ambiguous: true,
          );
        }
        return requestFixture();
      },
      apply: (_) {},
    );
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => intent.run(requestId: requestId, expectedRevision: expectedRevision),
    );
    final first = await harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    expect(first, isA<ReopenFlowFailed>());
    final second = await harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    expect(second, isA<ReopenFlowAdopted>());
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
  });

  test('explicit discard starts a new server intent on the next attempt', () async {
    final keys = <String>[];
    final intent = RequestReopenIntentController(
      reopen: ({required requestId, required expectedRevision, required operationKey}) async {
        keys.add(operationKey);
        if (keys.length == 1) {
          throw const StoreBackendException(
            'The reopen could not be confirmed.',
            ambiguous: true,
          );
        }
        return requestFixture();
      },
      apply: (_) {},
    );
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => intent.run(
        requestId: requestId,
        expectedRevision: expectedRevision,
      ),
      onDiscard: intent.discard,
    );
    await harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    expect(harness.coordinator.uncertain, isTrue);
    harness.coordinator.discard();
    expect(harness.coordinator.error, isNull);
    expect(harness.coordinator.uncertain, isFalse);
    await harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    expect(keys, hasLength(2));
    expect(keys[0], isNot(keys[1]));
  });

  test('a confirmed same-account background success is distinct from stale outcomes', () async {
    final gate = Completer<MarketplaceRequest>();
    final harness = FlowHarness(
      reopen: ({required requestId, required expectedRevision}) => gate.future,
    );
    final pending = harness.coordinator.reopenRequest(
      requestId: 'request-a',
      expectedRevision: 3,
    );
    harness.leaveAndReturn();
    final request = requestFixture();
    gate.complete(request);
    final outcome = await pending;
    expect(outcome, isA<ReopenFlowSuperseded>());
    expect((outcome as ReopenFlowSuperseded).request.id, request.id);
    expect(reopenPageFeedback(outcome), ReopenFlowFeedback.superseded);
    expect(reopenPageMayAdopt(outcome), isFalse);
  });

  test('page feedback mapping matches each outcome', () {
    final request = requestFixture();
    expect(reopenPageFeedback(ReopenFlowAdopted(request)), ReopenFlowFeedback.adopted);
    expect(reopenPageMayAdopt(ReopenFlowAdopted(request)), isTrue);
    expect(
      reopenPageFeedback(ReopenFlowSuperseded(request)),
      ReopenFlowFeedback.superseded,
    );
    expect(reopenPageMayAdopt(ReopenFlowSuperseded(request)), isFalse);
    expect(reopenPageFeedback(const ReopenFlowStale()), isNull);
    expect(reopenPageMayAdopt(const ReopenFlowStale()), isFalse);
    expect(
      reopenPageFeedback(
        const ReopenFlowFailed('The reopen failed.', uncertain: true),
      ),
      isNull,
      reason: 'failures render coordinator error state, never a success copy',
    );
    expect(
      reopenPageMayAdopt(
        const ReopenFlowFailed('The reopen failed.', uncertain: true),
      ),
      isFalse,
    );
  });

  test('reopen feedback never claims a new post', () {
    expect(ReopenFlowFeedback.adopted, isNot(contains('Request posted')));
    expect(ReopenFlowFeedback.superseded, isNot(contains('Request posted')));
    expect(ReopenFlowFeedback.adopted, contains('reopened'));
    expect(ReopenFlowFeedback.superseded, contains('reopened'));
  });
}

