/// Debounced, generation-fenced inbox conversation search controller.
///
/// Owns the search text, debounce, stale-result fencing, loading/error state
/// and the server rows for an inbox list. The UI (buyer or seller) stays a thin
/// renderer; the controller never decides authorization and delegates every
/// read to the injected callback, which is session-fenced upstream.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/conversations.dart';
import 'chat_safety_coordinator.dart';

typedef InboxSearchCallback =
    Future<PageSlice<ConversationSummary>> Function(String query);

class ChatInboxSearchController extends ChangeNotifier {
  ChatInboxSearchController({
    required this.search,
    this.debounce = const Duration(milliseconds: 350),
    this.minimumQueryLength = 2,
    this.unavailableMessage =
        'Search is unavailable right now. Check your connection and try again.',
  });

  /// Null keeps the caller's local behavior; the controller then reports
  /// [isAvailable] false and never schedules a request.
  final InboxSearchCallback? search;
  final Duration debounce;
  final int minimumQueryLength;
  final String unavailableMessage;

  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  String _query = '';
  bool _loading = false;
  String? _error;
  String _completedQuery = '';
  List<ConversationSummary> _results = const <ConversationSummary>[];

  String get query => _query;
  bool get loading => _loading;
  String? get error => _error;
  List<ConversationSummary> get results => _results;
  bool get isAvailable => search != null;

  /// True when the query is long enough to search server-side.
  bool get isSearching =>
      isAvailable && _query.trim().length >= minimumQueryLength;

  /// True when a search finished for the current query.
  bool get hasCompleted => _completedQuery == _query.trim() && !_loading;

  void updateQuery(String value) {
    _query = value;
    _error = null;
    final query = value.trim();
    if (!isAvailable || query.length < minimumQueryLength) {
      _generation += 1;
      _timer?.cancel();
      _timer = null;
      _loading = false;
      _completedQuery = '';
      _results = const <ConversationSummary>[];
      notifyListeners();
      return;
    }
    _generation += 1;
    final generation = _generation;
    _loading = true;
    _results = const <ConversationSummary>[];
    _completedQuery = '';
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_run(query, generation)));
  }

  /// Re-runs the current query (retry after a failure).
  Future<void> retry() async {
    final query = _query.trim();
    if (!isAvailable || query.length < minimumQueryLength) return;
    _generation += 1;
    final generation = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    await _run(query, generation);
  }

  void clear() => updateQuery('');

  Future<void> _run(String query, int generation) async {
    final search = this.search;
    if (search == null || _disposed) return;
    try {
      final page = await search(query);
      if (_disposed || generation != _generation || _query.trim() != query) {
        return;
      }
      _results = page.items;
      _completedQuery = query;
      _loading = false;
      _error = null;
    } catch (error) {
      if (_disposed || generation != _generation || _query.trim() != query) {
        return;
      }
      _results = const <ConversationSummary>[];
      _completedQuery = query;
      _loading = false;
      _error = error is ChatSafetyException
          ? error.message
          : unavailableMessage;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
