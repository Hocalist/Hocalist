import 'package:hocalist/theme/adaptive_palette.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/phase2/calls/call_gateway.dart';
import '../../domain/phase2/communication_completion.dart';
import '../../theme/buyer_ui_foundation.dart';

/// Optional two-person call surface. The admin switch, participant fence and
/// terminal states are server-owned; this page renders them and closes media on
/// a terminal state. Background ringing is explicitly not provided by a
/// foreground polling loop (see `call_notifications.dart`).
class HocalistCallPage extends StatefulWidget {
  const HocalistCallPage({
    required this.conversationId,
    this.incomingId,
    this.gateway,
    super.key,
  });
  final String conversationId;
  final String? incomingId;
  final CallService? gateway;
  @override
  State<HocalistCallPage> createState() => _HocalistCallPageState();
}

class _HocalistCallPageState extends State<HocalistCallPage>
    with WidgetsBindingObserver {
  late final gateway = widget.gateway ?? CallGateway(Supabase.instance.client);
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  final inviteKey = newCallKey();
  RTCPeerConnection? peer;
  MediaStream? stream;
  Timer? timer;
  Future<void>? initializing;
  int epoch = 0;
  int reconnectAttempts = 0;
  bool connected = false;
  String? id, error;
  String state = 'loading';
  CallSessionStatus? session;
  bool caller = true,
      ready = false,
      polling = false,
      starting = false,
      remoteReady = false,
      disposed = false,
      permissionDenied = false,
      locallyTerminal = false,
      mic = true,
      camera = true,
      speaker = true;
  int cursor = 0;
  final candidates = <RTCIceCandidate>[];

  /// A locally terminal state always wins over an older server snapshot: once
  /// authoritative access is lost or the call ends, no late nonterminal
  /// response may revive the controls.
  bool get terminal =>
      locallyTerminal ||
      (session?.isTerminal ??
          const {'ended', 'missed', 'declined', 'cancelled'}.contains(state));
  bool get alive => mounted && !disposed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializing = initialize();
  }

  Future<void> initialize() async {
    try {
      await local.initialize();
      await remote.initialize();
      if (!alive) return;
      Map<String, dynamic> result;
      if (widget.incomingId != null) {
        id = widget.incomingId;
        result = await gateway.command('poll', {'call_id': id});
      } else {
        final incoming = await gateway.command('incoming', {});
        if (incoming['call'] is Map &&
            incoming['call']['conversation_id'] == widget.conversationId) {
          result = incoming;
        } else {
          result = await gateway.command('invite', {
            'conversation_id': widget.conversationId,
            'key': inviteKey,
          });
        }
      }
      if (!alive) {
        final orphan = result['call'];
        if (orphan is Map) {
          await gateway.command('end', {'call_id': orphan['id']});
        }
        return;
      }
      if (result['status'] == 'busy') {
        setState(
          () => error = 'The other person is on another call. Try again soon.',
        );
        return;
      }
      apply(result);
      ready = true;
      await refreshStatus();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
    } on CallGatewayException catch (failure) {
      if (alive) {
        setState(() {
          locallyTerminal = true;
          error = failure.code == 'calls_disabled'
              ? 'Video calling is turned off.'
              : _isAuthoritativeDenial(failure.code)
              ? 'This conversation is not available for calling.'
              : 'The call could not start. Please try again later.';
        });
      }
    } catch (_) {
      if (alive) {
        setState(() {
          locallyTerminal = true;
          error = 'The call could not start. Please try again later.';
        });
      }
    }
  }

  void apply(Map<String, dynamic> result) {
    final call = result['call'];
    if (call is! Map) throw StateError('invalid_call');
    id = call['id'] as String;
    caller = call['caller_id'] == gateway.identity;
    state = call['state'] as String;
    if (alive) setState(() {});
  }

  /// Authoritative read used for reconnect, app resume and terminal handling.
  /// Signals are only read here; the server owns the state machine.
  Future<CallStatusSnapshot?> refreshStatus() async {
    final callId = id;
    if (!alive || callId == null || terminal) return null;
    try {
      final snapshot = await gateway.status(callId, cursor: cursor);
      if (!alive) return null;
      session = snapshot.call;
      state = snapshot.call.state.name;
      return snapshot;
    } on CallGatewayException catch (failure) {
      if (!alive) return null;
      if (_isAuthoritativeDenial(failure.code)) {
        // Access was revoked by the server (restriction, revocation, block or a
        // replaced session). Close media now instead of waiting for another
        // successful call; no server round-trip is needed to release local
        // camera/microphone tracks.
        await _closeLocally();
      }
      // A transient failure keeps the call open and polling continues.
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isAuthoritativeDenial(String code) => const {
    'call_access_denied',
    'authentication_required',
    'session_changed',
    'account_restricted',
    'role_not_active',
    'conversation_blocked',
    'conversation_access_denied',
    'call_not_found',
  }.contains(code);

  /// Ends the call locally and releases media without depending on another
  /// successful server call. Polling, outstanding results and repeat sends are
  /// invalidated through [epoch].
  Future<void> _closeLocally({String? message}) async {
    locallyTerminal = true;
    epoch++;
    timer?.cancel();
    timer = null;
    await stopMedia();
    if (!alive) return;
    setState(() {
      state = 'ended';
      error = message;
    });
  }

  Future<void> poll() async {
    if (!alive || polling || id == null || terminal) return;
    final runEpoch = epoch;
    polling = true;
    try {
      final snapshot = await refreshStatus();
      if (!alive || runEpoch != epoch) return;
      if (snapshot == null) return;
      if (snapshot.call.isTerminal) {
        locallyTerminal = true;
        timer?.cancel();
        timer = null;
        await stopMedia();
        if (alive) setState(() {});
        return;
      }
      if (!snapshot.call.enabled) {
        // The admin switch ended the call server-side; render the terminal
        // state instead of continuing to ring.
        locallyTerminal = true;
        timer?.cancel();
        timer = null;
        await stopMedia();
        if (alive) setState(() {});
        return;
      }
      if (state == 'accepted' && peer == null && !starting) await startMedia();
      if (peer == null || !alive) return;
      for (final message in snapshot.signals) {
        final data = message.payload;
        switch (message.kind) {
          case 'offer':
            if (caller) throw StateError('invalid_offer');
            await peer!.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String, 'offer'),
            );
            remoteReady = true;
            final answer = await peer!.createAnswer();
            await peer!.setLocalDescription(answer);
            await signal('answer', {'sdp': answer.sdp});
          case 'answer':
            if (!caller) throw StateError('invalid_answer');
            await peer!.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String, 'answer'),
            );
            remoteReady = true;
          case 'candidate':
            candidates.add(
              RTCIceCandidate(
                data['candidate'] as String?,
                data['sdpMid'] as String?,
                data['sdpMLineIndex'] as int?,
              ),
            );
        }
        cursor = message.sequence;
      }
      if (remoteReady) {
        for (final candidate in candidates) {
          await peer!.addCandidate(candidate);
        }
        candidates.clear();
      }
    } on CallGatewayException catch (failure) {
      if (!alive) return;
      if (_isAuthoritativeDenial(failure.code) ||
          failure.code == 'call_finished' ||
          failure.code == 'call_not_accepted') {
        await _closeLocally();
        return;
      }
      setState(
        () => error =
            'The connection was interrupted. End this call and try again.',
      );
    } catch (_) {
      if (alive) {
        setState(
          () => error =
              'The connection was interrupted. End this call and try again.',
        );
        await end();
      }
    } finally {
      polling = false;
    }
  }

  Future<void> signal(String kind, Map<String, Object?> payload) async {
    final key = newCallKey();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!alive) return;
      try {
        await gateway.command('signal', {
          'call_id': id,
          'key': key,
          'kind': kind,
          'payload': payload,
        });
        return;
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> startMedia() async {
    starting = true;
    final runEpoch = epoch;
    try {
      final config = await gateway.configuration(id!);
      if (!alive || runEpoch != epoch) return;
      final connection = await createPeerConnection(config);
      if (!alive || runEpoch != epoch) {
        await connection.close();
        return;
      }
      peer = connection;
      MediaStream media;
      try {
        media = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': {'facingMode': 'user', 'width': 640, 'height': 480},
        });
      } on PlatformException {
        if (alive) {
          setState(() {
            permissionDenied = true;
            error =
                'Microphone and camera permission is needed for calls. Allow it in phone settings, then start a new call.';
          });
        }
        return;
      }
      if (!alive || runEpoch != epoch) {
        for (final t in media.getTracks()) {
          await t.stop();
        }
        await media.dispose();
        return;
      }
      stream = media;
      local.srcObject = media;
      for (final track in media.getTracks()) {
        await connection.addTrack(track, media);
      }
      connection.onTrack = (event) {
        if (alive && runEpoch == epoch && event.streams.isNotEmpty) {
          remote.srcObject = event.streams.first;
          setState(() {});
        }
      };
      connection.onIceCandidate = (candidate) {
        if (alive && runEpoch == epoch && candidate.candidate != null) {
          unawaited(
            signal('candidate', candidate.toMap()).catchError((_) {
              if (alive) {
                setState(
                  () => error =
                      'Connection setup failed. End the call and retry.',
                );
              }
            }),
          );
        }
      };
      connection.onConnectionState = (value) {
        if (!alive || runEpoch != epoch) return;
        setState(
          () => connected =
              value == RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        if (value == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          if (reconnectAttempts < 2) {
            reconnectAttempts += 1;
            unawaited(connection.restartIce());
            return;
          }
          setState(() => error = 'Connection failed. End the call and retry.');
        }
      };
      if (caller) {
        final offer = await connection.createOffer();
        await connection.setLocalDescription(offer);
        await signal('offer', {'sdp': offer.sdp});
      }
      if (alive) setState(() {});
    } finally {
      starting = false;
    }
  }

  Future<void> respond(bool accept) async {
    if (polling || id == null) return;
    final runEpoch = epoch;
    polling = true;
    try {
      final result = await gateway.command(accept ? 'accept' : 'decline', {
        'call_id': id,
      });
      if (alive && runEpoch == epoch) apply(result);
    } on CallGatewayException catch (failure) {
      if (!alive) return;
      if (_isAuthoritativeDenial(failure.code)) {
        await _closeLocally();
      } else {
        setState(() => error = 'Could not update the call. Try again.');
      }
    } catch (_) {
      if (alive) {
        setState(() => error = 'Could not update the call. Try again.');
      }
    } finally {
      polling = false;
    }
    if (accept) await poll();
  }

  Future<void> stopMedia() async {
    final oldPeer = peer;
    peer = null;
    final oldStream = stream;
    stream = null;
    local.srcObject = null;
    remote.srcObject = null;
    if (oldStream != null) {
      for (final track in oldStream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await oldStream.dispose();
      } catch (_) {}
    }
    try {
      await oldPeer?.close();
    } catch (_) {}
    try {
      await oldPeer?.dispose();
    } catch (_) {}
  }

  Future<void> end() async {
    final wasTerminal = terminal;
    locallyTerminal = true;
    epoch++;
    timer?.cancel();
    timer = null;
    await stopMedia();
    if (id != null && !wasTerminal) {
      try {
        await gateway.command('end', {'call_id': id});
      } catch (_) {}
    }
    if (alive) setState(() => state = 'ended');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) {
      // App resume: read the authoritative state and keep media open only for a
      // live call. A drop is not treated as an implicit end by the client.
      unawaited(poll());
    }
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      (initializing ?? Future<void>.value()).then((_) => end()).whenComplete(
        () async {
          try {
            await local.dispose();
          } catch (_) {}
          try {
            await remote.dispose();
          } catch (_) {}
        },
      ),
    );
    super.dispose();
  }

  String get _statusLabel =>
      error ??
      switch (state) {
        'ringing' => caller ? 'Calling…' : 'Incoming call',
        'accepted' => connected ? 'In call' : 'Connecting…',
        'ended' => 'Call ended',
        'missed' => 'Call missed',
        'declined' => 'Call declined',
        'cancelled' => 'Call cancelled',
        _ => terminal ? 'Call ended' : 'Preparing call…',
      };

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) {
    final activeColor = active ? const Color(0xffffeef0) : Colors.white;
    final iconColor = active ? const Color(0xffc62828) : BuyerUiTokens.text;
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: activeColor,
        shape: CircleBorder(
          side: BorderSide(
            color: active ? const Color(0xffffc9cf) : BuyerUiTokens.border,
          ),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }

  Widget _stage(BuildContext context) {
    if (ready) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: HocalistPalette.surface(context, const Color(0xff0b1231)),
          child: Stack(
            children: [
              Positioned.fill(child: RTCVideoView(remote)),
              Positioned(
                right: 12,
                top: 12,
                width: 110,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(local, mirror: true),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      if (id == null) {
        return const Center(
          child: BuyerStateNotice(
            icon: Icons.videocam_off_outlined,
            tone: BuyerNoticeTone.neutral,
            title: 'Call not started',
            body:
                'Your camera and microphone have not been used. Return to '
                'the conversation to continue messaging.',
          ),
        );
      }
      return const Center(
        child: BuyerStateNotice(
          icon: Icons.videocam_off_outlined,
          tone: BuyerNoticeTone.error,
          title: 'Camera preview unavailable',
          body:
              'The call media could not be shown. End the call and start a new '
              'one, or check camera and microphone permissions in phone '
              'settings.',
        ),
      );
    }
    return const Center(
      child: BuyerStateNotice(
        icon: Icons.phone_in_talk_outlined,
        tone: BuyerNoticeTone.brand,
        title: 'Preparing call…',
        body:
            'Media permission is requested only after you answer or the call '
            'connects.',
        detail: Padding(
          padding: EdgeInsets.only(top: 2),
          child: BuyerProgressStrip(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waitingIncoming = state == 'ringing' && !caller && !terminal;
    final inCall = state == 'accepted' && !permissionDenied && !terminal;
    return Scaffold(
      backgroundColor: HocalistPalette.surface(context, Colors.white),
      appBar: AppBar(
        backgroundColor: HocalistPalette.surface(context, Colors.white),
        surfaceTintColor: Colors.white,
        foregroundColor: HocalistPalette.text(context, BuyerUiTokens.text),
        title: Text(
          'Hocalist call',
          style: TextStyle(
            color: HocalistPalette.text(context, BuyerUiTokens.text),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              BuyerStateNotice(
                icon: error != null
                    ? Icons.error_outline_rounded
                    : terminal
                    ? Icons.call_end_rounded
                    : state == 'accepted'
                    ? Icons.phone_in_talk_rounded
                    : Icons.ring_volume_rounded,
                tone: error != null
                    ? BuyerNoticeTone.error
                    : terminal
                    ? BuyerNoticeTone.neutral
                    : BuyerNoticeTone.brand,
                title: _statusLabel,
                body: error != null
                    ? 'No call controls are shown while the problem persists.'
                    : 'Calls are available only between matched participants.',
              ),
              const SizedBox(height: 12),
              Expanded(child: _stage(context)),
              const SizedBox(height: 12),
              if (waitingIncoming)
                Row(
                  children: [
                    Expanded(
                      child: BuyerSecondaryButton(
                        label: 'Decline',
                        color: const Color(0xffc62828),
                        onPressed: () => respond(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BuyerPrimaryButton(
                        label: 'Answer',
                        colors: const [Color(0xff109b4e), Color(0xff0c7d3e)],
                        onPressed: () => respond(true),
                      ),
                    ),
                  ],
                ),
              if (inCall)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _controlButton(
                      icon: mic ? Icons.mic : Icons.mic_off,
                      tooltip: mic ? 'Mute microphone' : 'Unmute microphone',
                      active: !mic,
                      onPressed: () {
                        for (final t
                            in stream?.getAudioTracks() ??
                                <MediaStreamTrack>[]) {
                          t.enabled = !mic;
                        }
                        setState(() => mic = !mic);
                      },
                    ),
                    _controlButton(
                      icon: camera ? Icons.videocam : Icons.videocam_off,
                      tooltip: camera ? 'Turn camera off' : 'Turn camera on',
                      active: !camera,
                      onPressed: () {
                        for (final t
                            in stream?.getVideoTracks() ??
                                <MediaStreamTrack>[]) {
                          t.enabled = !camera;
                        }
                        setState(() => camera = !camera);
                      },
                    ),
                    _controlButton(
                      icon: Icons.cameraswitch,
                      tooltip: 'Switch camera',
                      active: false,
                      onPressed: () async {
                        final tracks = stream?.getVideoTracks();
                        if (tracks != null && tracks.isNotEmpty) {
                          try {
                            await Helper.switchCamera(tracks.first);
                          } catch (_) {
                            if (alive) {
                              setState(
                                () => error = 'Could not switch the camera.',
                              );
                            }
                          }
                        }
                      },
                    ),
                    _controlButton(
                      icon: speaker ? Icons.volume_up : Icons.hearing,
                      tooltip: speaker ? 'Use earpiece' : 'Use speaker',
                      active: !speaker,
                      onPressed: () async {
                        try {
                          await Helper.setSpeakerphoneOn(!speaker);
                          if (alive) setState(() => speaker = !speaker);
                        } catch (_) {
                          if (alive) {
                            setState(
                              () =>
                                  error = 'Could not change the audio output.',
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              BuyerPrimaryButton(
                key: const Key('callEndButton'),
                colors: terminal
                    ? null
                    : const [Color(0xffc62828), Color(0xffe53935)],
                label: terminal ? 'Close' : 'End call',
                onPressed: () async {
                  await end();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
