/// Authenticated-session boundary for the marketplace data layer.
library;

abstract interface class MarketplaceSession {
  /// The signed-in user id, or null before a session exists.
  String? get currentUserId;
}
