/// Live SDK session boundary for the chat data layer.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_session.dart';

class SupabaseChatSession implements ChatSession {
  const SupabaseChatSession(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentUser?.id;
}
