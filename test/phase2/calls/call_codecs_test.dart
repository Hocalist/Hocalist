// Strict decoder tests for the call lifecycle wire shapes (migration 152).
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/calls/call_codecs.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';

const callId = '30000000-0000-4000-8000-000000000001';
const conversationId = '50000000-0000-4000-8000-000000000001';

Map<String, Object?> statusJson({
  String state = 'ringing',
  Object? enabled = true,
  Object? settingsRevision = 4,
  Object? serverNow = '2026-09-26T12:00:10+00:00',
  Object? terminal,
  List<Object?>? signals,
}) => <String, Object?>{
  'call': <String, Object?>{
    'id': callId,
    'conversation_id': conversationId,
    'caller_id': '00000000-0000-4000-8000-00000000000a',
    'callee_id': '00000000-0000-4000-8000-00000000000b',
    'state': state,
    'created_at': '2026-09-26T12:00:00+00:00',
    'expires_at': '2026-09-26T12:00:45+00:00',
    'terminal':
        terminal ??
        const {'declined', 'cancelled', 'ended', 'missed'}.contains(state),
  },
  'signals':
      signals ??
      <Object?>[
        <String, Object?>{
          'seq': 3,
          'kind': 'offer',
          'payload': <String, Object?>{'sdp': 'synthetic'},
        },
      ],
  'server_now': serverNow,
  'enabled': enabled,
  'settings_revision': settingsRevision,
};

void main() {
  test('decodes the exact 152 status shape with signals and switch state', () {
    final snapshot = decodeCallStatusJson(statusJson());
    expect(snapshot.call.id, callId);
    expect(snapshot.call.state, CallLifecycleState.ringing);
    expect(snapshot.call.isTerminal, isFalse);
    expect(snapshot.call.enabled, isTrue);
    expect(snapshot.call.settingsRevision, 4);
    expect(snapshot.call.expiresAt, DateTime.parse('2026-09-26T12:00:45Z'));
    expect(snapshot.call.serverNow, DateTime.parse('2026-09-26T12:00:10Z'));
    expect(snapshot.call.remaining, const Duration(seconds: 35));
    expect(snapshot.signals.single.sequence, 3);
    expect(snapshot.signals.single.payload['sdp'], 'synthetic');
  });

  test('terminal and disabled snapshots decode honestly', () {
    final missed = decodeCallStatusJson(statusJson(state: 'missed'));
    expect(missed.call.state, CallLifecycleState.missed);
    expect(missed.call.isTerminal, isTrue);

    final off = decodeCallStatusJson(
      statusJson(state: 'ended', enabled: false, settingsRevision: 0),
    );
    expect(off.call.enabled, isFalse);
    expect(off.call.isTerminal, isTrue);
  });

  test('an unknown future state stays unknown but not terminal', () {
    final future = decodeCallStatusJson(statusJson(state: 'ringing_v2'));
    expect(future.call.state, CallLifecycleState.unknown);
    expect(future.call.isTerminal, isFalse);

    final closed = decodeCallStatusJson(
      statusJson(state: 'ended_v2', terminal: true),
    );
    expect(closed.call.state, CallLifecycleState.unknown);
    expect(
      closed.call.isTerminal,
      isTrue,
      reason: 'the server terminal flag wins over the local state map',
    );
  });

  test('malformed fields raise safe decode details', () {
    expect(
      () =>
          decodeCallStatusJson(<String, Object?>{'call': null, 'signals': []}),
      throwsA(
        isA<CallDecodeException>().having((e) => e.detail, 'detail', 'call'),
      ),
    );
    expect(
      () => decodeCallStatusJson(statusJson(serverNow: null)),
      throwsA(
        isA<CallDecodeException>().having(
          (e) => e.detail,
          'detail',
          'server_now',
        ),
      ),
    );
    expect(
      () => decodeCallStatusJson(statusJson(signals: <Object?>['nope'])),
      throwsA(
        isA<CallDecodeException>().having(
          (e) => e.detail,
          'detail',
          'signals.item',
        ),
      ),
    );
  });
}
