import '../../../domain/phase2/notifications.dart';

/// Push data is a lookup hint, never a trusted navigation destination.
class PushInboxSignal {
  const PushInboxSignal(this.id, {required this.opened});
  final String id;
  final bool opened;
}

/// Routes push lookups to an authorized destination.
///
/// A signal is only a hint: every opened signal is re-fetched through the
/// authenticated inbox lookup before navigation, the open callback owns the
/// final authorization (role, restriction, stale/deleted record), and a
/// signal that arrives before authentication is retained for one replay after
/// the session becomes active. Duplicate opened signals are handled once.
class PushInboxRouter {
  PushInboxRouter({
    required this.identity,
    required this.lookup,
    required this.refresh,
    required this.open,
    required this.unavailable,
    this.canOpen,
    this.maxRetained = 5,
  });

  final String? Function() identity;
  final Future<NotificationInboxItem?> Function(String) lookup;
  final Future<void> Function() refresh;
  final Future<void> Function(NotificationInboxItem) open;
  final void Function() unavailable;

  /// Optional role/restriction guard applied after the lookup and before
  /// [open]. A false result uses [unavailable] and never navigates.
  final bool Function(NotificationInboxItem item)? canOpen;

  /// Bound on cold-start signals retained while signed out.
  final int maxRetained;

  int _generation = 0;
  bool _closed = false;
  final List<PushInboxSignal> _retained = <PushInboxSignal>[];
  final Set<String> _handledOpened = <String>{};

  /// True when an opened signal is waiting for an authenticated replay.
  bool get hasRetained => _retained.isNotEmpty;

  void dispose() {
    _closed = true;
    _generation++;
    _retained.clear();
    _handledOpened.clear();
  }

  Future<void> receive(PushInboxSignal signal) async {
    final user = identity();
    if (_closed || !_isUuid(signal.id)) return;
    if (user == null) {
      // Cold start: keep the most recent opened taps until authentication.
      if (!signal.opened) return;
      _retained.removeWhere((pending) => pending.id == signal.id);
      _retained.add(signal);
      while (_retained.length > maxRetained) {
        _retained.removeAt(0);
      }
      return;
    }
    await _deliver(signal);
  }

  /// Replays the most recent retained cold-start tap after the session becomes
  /// active; older retained taps are dropped because the latest user tap is the
  /// intended destination. Call from the auth/account state listener; safe to
  /// call repeatedly.
  Future<void> onAuthenticated() async {
    if (_closed || identity() == null || _retained.isEmpty) return;
    final pending = _retained.removeLast();
    _retained.clear();
    await _deliver(pending);
  }

  Future<void> _deliver(PushInboxSignal signal) async {
    final user = identity();
    if (_closed || user == null) return;
    // Foreground arrivals must not cancel a pending user tap.
    final generation = signal.opened ? ++_generation : _generation;
    bool current() =>
        !_closed && identity() == user && generation == _generation;
    try {
      if (!signal.opened) {
        await refresh();
        return;
      }
      if (_handledOpened.contains(signal.id)) return;
      final item = await lookup(signal.id);
      if (!current()) return;
      if (item == null || item.id != signal.id) {
        _rememberHandled(signal.id);
        unavailable();
        return;
      }
      if (canOpen != null && !canOpen!(item)) {
        _rememberHandled(signal.id);
        unavailable();
        return;
      }
      await open(item);
      _rememberHandled(signal.id);
    } catch (_) {
      if (signal.opened && current()) unavailable();
    }
  }

  void _rememberHandled(String id) {
    _handledOpened.add(id);
    while (_handledOpened.length > 32) {
      _handledOpened.remove(_handledOpened.first);
    }
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
