import '../domain/phase2/profiles.dart';

/// Serializes revisioned writes while keeping unrelated switches interactive.
class NotificationPreferenceEdits {
  NotificationPreferenceEdits({
    required this.read,
    required this.save,
    required this.changed,
  });
  final NotificationPreferences Function() read;
  final Future<String?> Function(NotificationPreferences) save;
  final void Function() changed;
  final Map<String, bool> _pending = {};
  bool _running = false;
  bool _disposed = false;
  String? error;
  bool pending(String field) => _pending.containsKey(field);
  bool value(String field, bool authoritative) =>
      _pending[field] ?? authoritative;

  Future<void> update(String field, bool value) async {
    if (_disposed || pending(field)) return;
    _pending[field] = value;
    error = null;
    changed();
    if (_running) return;
    _running = true;
    try {
      while (!_disposed && _pending.isNotEmpty) {
        final field = _pending.keys.first;
        final value = _pending[field]!;
        final current = read();
        final next = switch (field) {
          'offers' => current.copyWith(offers: value),
          'messages' => current.copyWith(messages: value),
          'deals' => current.copyWith(deals: value),
          'leads' => current.copyWith(leads: value),
          _ => throw ArgumentError.value(field),
        };
        try {
          final failure = await save(next);
          if (failure != null) error = failure;
        } catch (_) {
          error = 'Could not save this notification preference. Try again.';
        }
        if (_disposed) return;
        _pending.remove(field);
        changed();
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
