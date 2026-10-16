import 'package:supabase_flutter/supabase_flutter.dart';

/// Refresh before pinning a Bearer token. Supabase's HTTP client deliberately
/// keeps an explicit Authorization header, even when it refreshes the session.
/// Cancel if the initiating identity leaves during the refresh.
Future<String?> freshSessionToken(SupabaseClient client) async {
  final initiating = client.auth.currentSession;
  if (initiating == null) return null;
  var replaced = false;
  final changes = client.auth.onAuthStateChange.listen(
    (event) {
      if (event.session?.user.id != initiating.user.id) replaced = true;
    },
    onError: (_) {}, // getSession reports refresh failures to the caller.
  );
  try {
    final session = await client.auth.getSession();
    if (replaced ||
        session == null ||
        session.user.id != initiating.user.id ||
        client.auth.currentUser?.id != initiating.user.id ||
        (session.expiresAt != null &&
            session.expiresAt! <=
                DateTime.now().millisecondsSinceEpoch ~/ 1000) ||
        session.accessToken.isEmpty) {
      return null;
    }
    return session.accessToken;
  } finally {
    await changes.cancel();
  }
}
