/// Composition entry point for the SQL-draft-backed chat data layer.
///
/// Pass the app's authenticated official `SupabaseClient`. The adapter is a
/// cheap wrapper; recreate it per session composition rather than caching it
/// across account changes.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_adapter.dart';
import 'chat_error_mapper.dart';
import 'supabase_chat_session.dart';
import 'supabase_chat_transport.dart';

ChatDataAdapter createChatDataAdapter({
  required SupabaseClient client,
  ChatErrorMapper errorMapper = const ChatErrorMapper(),
}) {
  return ChatDataAdapter(
    transport: SupabaseChatTransport(client),
    session: SupabaseChatSession(client),
    errorMapper: errorMapper,
  );
}
