/// Injected authenticated-session boundary for the account data layer.
///
/// The adapter derives identity from this boundary only. Method parameters
/// never carry a caller identity, and a caller-supplied id is never proof of
/// authorization. The future Supabase implementation reads the current
/// session user id; tests use a synthetic fake.
library;

abstract interface class AccountSession {
  /// The authenticated Auth identity id, or null when signed out.
  String? get currentUserId;
}
