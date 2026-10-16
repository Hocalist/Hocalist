import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/calls/call_gateway.dart';
import 'package:hocalist/data/phase2/calls/call_notifications.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';
import 'package:hocalist/features/calls/hocalist_call_page.dart';

CallSessionStatus callStatus(
  String state, {
  bool enabled = true,
  Duration expiresIn = const Duration(seconds: 40),
}) => CallSessionStatus(
  id: 'call',
  conversationId: 'conversation',
  callerUserId: 'a',
  calleeUserId: 'b',
  state: CallLifecycleState.values.firstWhere((value) => value.name == state),
  createdAt: DateTime.utc(2026, 5, 1),
  expiresAt: DateTime.utc(2026, 5, 1).add(expiresIn),
  serverNow: DateTime.utc(2026, 5, 1),
  enabled: enabled,
  settingsRevision: 1,
);

class FakeCalls implements CallService {
  @override
  String get identity => 'b';
  String state = 'ringing';
  final actions = <String>[];
  int statusReads = 0;
  List<CallSignalEnvelope> signals = const [];

  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, Object?> input,
  ) async {
    actions.add(action);
    if (action == 'decline') state = 'declined';
    if (action == 'end') state = 'ended';
    return {
      'call': {
        'id': 'call',
        'conversation_id': 'conversation',
        'caller_id': 'a',
        'callee_id': 'b',
        'state': state,
      },
      'signals': [],
    };
  }

  @override
  Future<CallStatusSnapshot> status(String callId, {int cursor = 0}) async {
    statusReads += 1;
    return CallStatusSnapshot(call: callStatus(state), signals: signals);
  }

  @override
  Future<Map<String, dynamic>> configuration(String id) async => {
    'iceServers': const <Object?>[],
    'iceTransportPolicy': 'relay',
    'sdpSemantics': 'unified-plan',
  };
}

/// Denies status reads with an authoritative failure once [denied] is set, and
/// keeps returning nonterminal snapshots afterwards to model a late server
/// response that must not revive the controls.
class DisabledCalls extends FakeCalls {
  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, Object?> input,
  ) async {
    actions.add(action);
    throw const CallGatewayException('calls_disabled');
  }
}

class DeniedCalls extends FakeCalls {
  bool denied = false;
  CallGatewayException denial = const CallGatewayException(
    'call_access_denied',
  );

  @override
  Future<CallStatusSnapshot> status(String callId, {int cursor = 0}) async {
    if (denied) throw denial;
    return super.status(callId, cursor: cursor);
  }
}

void mockWebRtc(
  List<String> methods,
  void Function(int) texture, {
  bool media = false,
}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var next = 0;
  messenger.setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC.Method'),
    (call) async {
      methods.add(call.method);
      switch (call.method) {
        case 'createVideoRenderer':
          return {'textureId': ++next};
        case 'createPeerConnection':
          return {'peerConnectionId': 'peer-1'};
        case 'getUserMedia':
          if (!media) return null;
          return {
            'streamId': 'stream-1',
            'audioTracks': [
              {
                'id': 'audio-1',
                'label': 'audio',
                'kind': 'audio',
                'enabled': true,
                'settings': <String, Object?>{},
              },
            ],
            'videoTracks': [
              {
                'id': 'video-1',
                'label': 'video',
                'kind': 'video',
                'enabled': true,
                'settings': <String, Object?>{},
              },
            ],
          };
      }
      return null;
    },
  );
  for (final id in [1, 2, 3]) {
    messenger.setMockMethodCallHandler(
      MethodChannel('FlutterWebRTC/Texture$id'),
      (_) async => null,
    );
  }
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      null,
    );
    for (final id in [1, 2, 3]) {
      messenger.setMockMethodCallHandler(
        MethodChannel('FlutterWebRTC/Texture$id'),
        null,
      );
    }
  });
}

void main() {
  testWidgets(
    'disabled calling never claims a camera failure or starts media',
    (tester) async {
      final methods = <String>[];
      mockWebRtc(methods, (_) {});
      final gateway = DisabledCalls();
      await tester.pumpWidget(
        MaterialApp(
          home: HocalistCallPage(
            conversationId: 'conversation',
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video calling is turned off.'), findsOneWidget);
      expect(find.text('Call not started'), findsOneWidget);
      expect(find.text('Camera preview unavailable'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
      expect(methods, isNot(contains('getUserMedia')));
      expect(gateway.actions, ['incoming']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incoming call offers explicit answer or decline', (
    tester,
  ) async {
    final methods = <String>[];
    mockWebRtc(methods, (_) {});
    final gateway = FakeCalls();
    await tester.pumpWidget(
      MaterialApp(
        home: HocalistCallPage(
          conversationId: 'conversation',
          incomingId: 'call',
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(methods, isNot(contains('getUserMedia')));

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(find.text('Call declined'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(gateway.actions, contains('end'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server terminal state closes media and offers Close', (
    tester,
  ) async {
    final methods = <String>[];
    mockWebRtc(methods, (_) {});
    final gateway = FakeCalls()..state = 'accepted';
    await tester.pumpWidget(
      MaterialApp(
        home: HocalistCallPage(
          conversationId: 'conversation',
          incomingId: 'call',
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    gateway.state = 'missed';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Call missed'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('app resume refreshes the authoritative state', (tester) async {
    final methods = <String>[];
    mockWebRtc(methods, (_) {});
    final gateway = FakeCalls();
    await tester.pumpWidget(
      MaterialApp(
        home: HocalistCallPage(
          conversationId: 'conversation',
          incomingId: 'call',
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = gateway.statusReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.statusReads, greaterThan(before));
    expect(find.text('End call'), findsOneWidget);
  });

  test('the no-op native bridge is inert and explicit', () async {
    const bridge = NoopCallNotificationBridge();
    await bridge.showIncoming(
      callId: 'call',
      conversationId: 'conversation',
      callerLabel: 'Buyer',
    );
    await bridge.cancel('call');
    await bridge.dispose();
  });

  test('a native bridge fake records the contract calls', () async {
    final bridge = FakeCallNotificationBridge();
    await bridge.showIncoming(
      callId: 'call',
      conversationId: 'conversation',
      callerLabel: 'Buyer',
    );
    await bridge.cancel('call');
    await bridge.dispose();
    expect(bridge.shown, ['call/conversation/Buyer']);
    expect(bridge.cancelled, ['call']);
    expect(bridge.disposed, isTrue);
  });

  testWidgets('an accepted call closes controls and media on access denial', (
    tester,
  ) async {
    final methods = <String>[];
    mockWebRtc(methods, (_) {}, media: true);
    final gateway = DeniedCalls()..state = 'accepted';
    await tester.pumpWidget(
      MaterialApp(
        home: HocalistCallPage(
          conversationId: 'conversation',
          incomingId: 'call',
          gateway: gateway,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      methods,
      contains('getUserMedia'),
      reason: 'the accepted call acquired local media first',
    );

    gateway.denied = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Answer'), findsNothing);
    expect(find.text('End call'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
    expect(
      methods,
      contains('trackDispose'),
      reason: 'local audio/video tracks are stopped',
    );
    expect(methods, contains('streamDispose'));
    expect(methods, contains('peerConnectionClose'));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a locally terminal state survives a stale nonterminal snapshot',
    (tester) async {
      final methods = <String>[];
      mockWebRtc(methods, (_) {});
      final gateway = DeniedCalls();
      await tester.pumpWidget(
        MaterialApp(
          home: HocalistCallPage(
            conversationId: 'conversation',
            incomingId: 'call',
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Answer'), findsOneWidget);

      gateway.denied = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Answer'), findsNothing);

      // The server now returns an old nonterminal snapshot; the local terminal
      // state and cancelled polling must keep the controls closed.
      gateway.denied = false;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Answer'), findsNothing);
      expect(find.text('Close'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a session replacement denial closes the call locally', (
    tester,
  ) async {
    final methods = <String>[];
    mockWebRtc(methods, (_) {});
    final gateway = DeniedCalls()
      ..denial = const CallGatewayException('session_changed');
    await tester.pumpWidget(
      MaterialApp(
        home: HocalistCallPage(
          conversationId: 'conversation',
          incomingId: 'call',
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    gateway.denied = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Answer'), findsNothing);
    expect(find.text('Close'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a transient failure keeps the call polling', (tester) async {
    final methods = <String>[];
    mockWebRtc(methods, (_) {});
    final gateway = DeniedCalls()
      ..denial = const CallGatewayException('call_unavailable');
    await tester.pumpWidget(
      MaterialApp(
        home: HocalistCallPage(
          conversationId: 'conversation',
          incomingId: 'call',
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = gateway.statusReads;

    gateway.denied = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.text('Answer'),
      findsOneWidget,
      reason: 'no revocation happened',
    );

    gateway.denied = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(gateway.statusReads, greaterThan(before));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// Test double for the native call-notification boundary.
class FakeCallNotificationBridge implements CallNotificationBridge {
  final List<String> shown = [];
  final List<String> cancelled = [];
  bool disposed = false;

  @override
  Future<void> showIncoming({
    required String callId,
    required String conversationId,
    required String callerLabel,
  }) async {
    shown.add('$callId/$conversationId/$callerLabel');
  }

  @override
  Future<void> cancel(String callId) async {
    cancelled.add(callId);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
