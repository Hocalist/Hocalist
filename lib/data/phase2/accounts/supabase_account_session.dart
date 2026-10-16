/// Live Supabase Auth-backed account session.
///
/// Reads the current SDK auth state on every access; no constructor-cached
/// user id. A token refresh for the same user keeps the id stable, while a
/// logout or account replacement changes it so the adapter's session fence can
/// discard stale work.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_session.dart';

class SupabaseAccountSession implements AccountSession {
  SupabaseAccountSession(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;
}
