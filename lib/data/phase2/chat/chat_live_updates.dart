/// Secure live-update boundary for chat.
///
/// Design: a change signal is never permission evidence. Every signal only
/// triggers an authoritative refetch through the authenticated chat adapter,
/// so a forged or stale event cannot expose another member's data. Signals are
/// fenced by the identity captured when watching, so a replacement identity
/// never receives the previous identity's updates.
///
/// Lifecycle: [ChatLiveUpdates] also consumes connection state when the source
/// exposes [ChatChangeConnection]. After a drop and reconnect, a same-identity
/// re-authentication, or an explicit offline fallback, the current watch is
/// refetched once; duplicate signals collapse; a refetch already running never
/// overlaps another.
///
/// Limitation: reliable realtime delivery needs the reviewed
/// `hocalist.chat_change_signals` publication (migration 154) and client
/// enablement. [SupabaseChatChangeSource] is disabled by default, so screens
/// must use explicit refresh (re-running the read calls) and must not present
/// polling as live proof.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_session.dart';

/// Source of "this conversation may have changed" signals.
abstract interface class ChatChangeSource {
  Stream<String> get conversationChanges;

  Future<void> dispose();
}

/// Connection lifecycle for a change source that can drop and reconnect.
abstract interface class ChatChangeConnection {
  /// Emits `connected` after a successful (re)subscribe and `disconnected`
  /// when the underlying transport drops or errors.
  Stream<ChatChangeConnectionState> get connectionStates;

  /// Asks the source to resubscribe; safe to call repeatedly.
  Future<void> reconnect();
}

enum ChatChangeConnectionState { connected, disconnected }

/// Opaque fence for one [ChatLiveUpdates.watch] cycle.
///
/// The fence is active only while its watch is the current one, the session
/// still holds the identity captured at watch time, and the driver has not
/// been stopped or disposed. A consuming controller receives the fence in its
/// refetch callback and must check [isActive] after every `await` before
/// applying fetched results; this rejects a result that arrives after an
/// identity switch, a re-watch or a stop.
class ChatWatchFence {
  ChatWatchFence._(
    this._owner,
    this._generation,
    this.conversationId,
    this.identity,
  );

  final ChatLiveUpdates _owner;
  final int _generation;

  /// Conversation watched when this fence was created.
  final String conversationId;

  /// Session identity captured when this fence was created.
  final String? identity;

  bool get isActive => _owner._isFenceActive(this);
}

/// Refetch callback: fetches authoritative data and applies it only while
/// [ChatWatchFence.isActive] still holds.
typedef ChatRefetch = Future<void> Function(ChatWatchFence fence);

/// Fenced, debounced, reconnect-aware refetch driver.
///
/// A change signal is only a hint. Identity and watch generation are captured
/// when watching, re-checked when a signal arrives and re-checked again when
/// the debounce timer fires, so a signal that arrives before an identity
/// replacement can never execute a refetch for the previous identity.
class ChatLiveUpdates {
  ChatLiveUpdates({
    required this.source,
    required this.session,
    this.debounce = const Duration(milliseconds: 250),
    this.reconnectDelay = const Duration(seconds: 1),
  }) {
    final connection = source is ChatChangeConnection
        ? source as ChatChangeConnection
        : null;
    _connection = connection;
    _connectionSubscription = connection?.connectionStates.listen((state) {
      final wasOffline = _offline;
      _offline = state == ChatChangeConnectionState.disconnected;
      _connectionController.add(state);
      if (!_offline && wasOffline) {
        // Recovery after a drop: one authoritative refetch for the current
        // watch. Identity and generation are re-checked by the timer.
        final fence = _lastFence;
        if (fence != null && fence.isActive) _schedule(fence);
      }
    });
  }

  final ChatChangeSource source;
  final ChatSession session;
  final Duration debounce;
  final Duration reconnectDelay;

  final StreamController<ChatChangeConnectionState> _connectionController =
      StreamController<ChatChangeConnectionState>.broadcast();
  StreamSubscription<ChatChangeConnectionState>? _connectionSubscription;
  ChatChangeConnection? _connection;

  StreamSubscription<String>? _subscription;
  Timer? _timer;
  Future<void> Function(ChatWatchFence fence)? _refetch;
  ChatWatchFence? _lastFence;
  ChatWatchFence? _queuedFence;
  int _generation = 0;
  bool _disposed = false;
  bool _offline = false;
  bool _refetching = false;

  /// True while the source reported a dropped connection. Screens should show
  /// a refresh fallback instead of assuming live delivery.
  bool get isOffline => _offline;

  /// Connection transitions, including reconnects. Broadcast.
  Stream<ChatChangeConnectionState> get connectionStates =>
      _connectionController.stream;

  /// Starts watching one conversation and returns its fence. A signal for
  /// another conversation is ignored; duplicate signals within [debounce]
  /// collapse into one refetch. Calling [watch] again, [stop] or [dispose]
  /// invalidates any pending timer and fence from the previous cycle.
  ChatWatchFence watch({
    required String conversationId,
    required ChatRefetch refetch,
  }) {
    stop();
    final fence = ChatWatchFence._(
      this,
      _generation,
      conversationId,
      session.currentUserId,
    );
    _lastFence = fence;
    _refetch = refetch;
    _subscription = source.conversationChanges.listen((changed) {
      if (!fence.isActive || changed != conversationId) return;
      _schedule(fence);
    });
    return fence;
  }

  void _schedule(ChatWatchFence fence, {Duration? delay}) {
    if (!fence.isActive) return;
    _timer?.cancel();
    _timer = Timer(delay ?? debounce, () {
      if (!fence.isActive) return;
      unawaited(_runRefetch(fence));
    });
  }

  Future<void> _runRefetch(ChatWatchFence fence) async {
    if (!fence.isActive || _disposed) return;
    if (_refetching) {
      // Keep the newest queued fence. A watch switch replaces any pending one,
      // so the new watch's work is scheduled by the running fetch's `finally`
      // instead of being discarded with the old fence.
      _queuedFence = fence;
      return;
    }
    _refetching = true;
    try {
      final refetch = _refetch;
      if (refetch != null) await refetch(fence);
    } catch (_) {
      // A failed refetch stays a screen-level error; the driver never
      // surfaces an unhandled exception.
    } finally {
      _refetching = false;
      final queued = _queuedFence;
      _queuedFence = null;
      if (queued != null && queued.isActive) {
        _schedule(queued, delay: Duration.zero);
      }
    }
  }

  /// Explicit fallback for manual refresh, app resume or a screen that knows
  /// its data may be stale while live delivery is unavailable.
  void refetchNow() {
    final fence = _lastFence;
    if (fence != null && fence.isActive) _schedule(fence, delay: Duration.zero);
  }

  /// Call after a same-identity session refresh (token rotation, re-auth or app
  /// resume). A changed identity invalidates the fence, so nothing is fetched
  /// for the previous identity; the caller must [watch] again for the new one.
  void sessionRefreshed() => refetchNow();

  /// Asks the source to reconnect (offline fallback). No-op for sources
  /// without a connection lifecycle.
  Future<void> reconnect() async {
    await _connection?.reconnect();
  }

  bool _isFenceActive(ChatWatchFence fence) =>
      !_disposed &&
      _generation == fence._generation &&
      session.currentUserId == fence.identity;

  /// Stops watching and invalidates any pending timer, fence and in-flight
  /// application of results.
  void stop() {
    _generation += 1;
    _lastFence = null;
    _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _refetch = null;
    _queuedFence = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _connectionSubscription?.cancel();
    await _connectionController.close();
    await source.dispose();
  }
}

/// Supabase Realtime change source over the content-free signal table.
///
/// Disabled by default: it requires the reviewed `chat_change_signals`
/// publication and client enablement. It never treats an event as
/// authorization; it only emits the conversation id for an authoritative
/// refetch. Reconnects use bounded exponential backoff.
class SupabaseChatChangeSource
    implements ChatChangeSource, ChatChangeConnection {
  SupabaseChatChangeSource(this._client, {this.enabled = false});

  final SupabaseClient _client;

  /// Must be enabled only after the publication/enablement review.
  final bool enabled;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final StreamController<ChatChangeConnectionState> _connectionController =
      StreamController<ChatChangeConnectionState>.broadcast();
  RealtimeChannel? _channel;
  Timer? _retryTimer;
  int _attempts = 0;
  bool _started = false;
  bool _disposed = false;

  @override
  Stream<String> get conversationChanges => _controller.stream;

  @override
  Stream<ChatChangeConnectionState> get connectionStates =>
      _connectionController.stream;

  /// Subscribes when [enabled]. Without the reviewed publication this is a
  /// no-op; callers must use explicit refresh instead.
  Future<void> start() async {
    if (!enabled || _started || _disposed) return;
    _started = true;
    _subscribe();
  }

  void _subscribe() {
    if (_disposed || !enabled) return;
    _retryTimer?.cancel();
    final channel = _client.channel('hocalist-chat-signals');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'hocalist',
      table: 'chat_change_signals',
      callback: (payload) {
        final record = payload.newRecord.isNotEmpty
            ? payload.newRecord
            : payload.oldRecord;
        final conversationId = record['conversation_id'];
        if (conversationId is String && conversationId.isNotEmpty) {
          _controller.add(conversationId);
        }
      },
    );
    _channel = channel;
    channel.subscribe((status, _) {
      if (_disposed) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _attempts = 0;
          _connectionController.add(ChatChangeConnectionState.connected);
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          _connectionController.add(ChatChangeConnectionState.disconnected);
          _scheduleReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_disposed || !enabled || _retryTimer != null) return;
    final exponent = _attempts > 5 ? 5 : _attempts;
    final delay = Duration(
      milliseconds: (reconnectBase.inMilliseconds * (1 << exponent)).clamp(
        1000,
        30000,
      ),
    );
    _attempts += 1;
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      if (_disposed) return;
      final channel = _channel;
      _channel = null;
      if (channel != null) {
        await _client.removeChannel(channel);
      }
      if (!_disposed) _subscribe();
    });
  }

  static const Duration reconnectBase = Duration(seconds: 1);

  @override
  Future<void> reconnect() async {
    if (!enabled || _disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempts = 0;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
    if (!_disposed) _subscribe();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
    await _controller.close();
    await _connectionController.close();
  }
}
