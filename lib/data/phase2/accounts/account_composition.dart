/// Composition entry point for the SQL-draft-backed account data layer.
///
/// Pass the app's authenticated official `SupabaseClient` (for example
/// `Supabase.instance.client` after `Supabase.initialize`) and receive the
/// narrow `AccountDataAdapter`. This does not initialize the production app,
/// read credentials or touch any screen; see the account adapter handoff for
/// the integration steps and remaining gaps.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_adapter.dart';
import 'account_error_mapper.dart';
import 'supabase_account_session.dart';
import 'supabase_account_transport.dart';

/// Builds the account adapter over the official SDK client.
///
/// The client must be the authenticated app client; there is no service-role
/// option. The adapter and its live session/transport are cheap wrappers and
/// can be recreated per composition instead of cached across account changes.
AccountDataAdapter createAccountDataAdapter({
  required SupabaseClient client,
  AccountErrorMapper errorMapper = const AccountErrorMapper(),
}) {
  return AccountDataAdapter(
    transport: SupabaseAccountTransport(client),
    session: SupabaseAccountSession(client),
    errorMapper: errorMapper,
  );
}
