/// Injected authenticated-session boundary for the chat data layer.
///
/// The adapter derives identity from this boundary only. Caller-supplied user
/// ids are checked against it and are never proof of authorization.
library;

abstract interface class ChatSession {
  /// The authenticated Auth identity id, or null when signed out.
  String? get currentUserId;
}
