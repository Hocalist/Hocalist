// Shared fakes for the chat data-layer tests. No SDK, network or plugin use.
import 'dart:async';

import 'package:hocalist/data/phase2/chat/chat_live_updates.dart';
import 'package:hocalist/data/phase2/chat/chat_session.dart';
import 'package:hocalist/data/phase2/chat/chat_transport.dart';

class FakeChatSession implements ChatSession {
  FakeChatSession(this.currentUserId);

  @override
  String? currentUserId;

  void replaceWith(String? userId) => currentUserId = userId;
}

class FakeChatTransport implements ChatTransport {
  final List<ChatRpcCall> calls = <ChatRpcCall>[];
  ChatTransportResponse Function(ChatRpcCall call)? handler;

  /// Optional gate: when set, the next call waits for this future.
  Future<void>? gate;

  @override
  Future<ChatTransportResponse> callChatRpc(ChatRpcCall call) async {
    calls.add(call);
    final gate = this.gate;
    if (gate != null) await gate;
    final handler = this.handler;
    if (handler != null) return handler(call);
    return const ChatTransportData(<String, Object?>{});
  }
}

class FakeChatChangeSource implements ChatChangeSource {
  final StreamController<String> controller =
      StreamController<String>.broadcast();
  bool disposed = false;

  @override
  Stream<String> get conversationChanges => controller.stream;

  void emit(String conversationId) => controller.add(conversationId);

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

/// Change source with a controllable connection lifecycle.
class FakeChatChangeConnection
    implements ChatChangeSource, ChatChangeConnection {
  final StreamController<String> controller =
      StreamController<String>.broadcast();
  final StreamController<ChatChangeConnectionState> connections =
      StreamController<ChatChangeConnectionState>.broadcast();
  bool disposed = false;
  int reconnectCalls = 0;

  @override
  Stream<String> get conversationChanges => controller.stream;

  @override
  Stream<ChatChangeConnectionState> get connectionStates => connections.stream;

  void emit(String conversationId) => controller.add(conversationId);

  void setConnection(ChatChangeConnectionState state) => connections.add(state);

  @override
  Future<void> reconnect() async {
    reconnectCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
    await connections.close();
  }
}

Map<String, Object?> conversationJson({
  String id = '50000000-0000-4000-8000-000000000001',
  String origin = 'targeted_request',
  String status = 'open',
  String? requestId = '60000000-0000-4000-8000-000000000001',
  int revision = 1,
  List<Map<String, Object?>>? members,
}) => <String, Object?>{
  'id': id,
  'origin': origin,
  'status': status,
  'request_id': requestId,
  'offer_id': null,
  'listing_id': null,
  'discovery_topic_id': null,
  'revision': revision,
  'created_at': '2026-05-01T00:00:00+00:00',
  'updated_at': '2026-05-01T00:01:00+00:00',
  'members':
      members ??
      [
        memberJson(),
        memberJson(
          userId: 'user-b',
          profileId: '10000000-0000-4000-8000-00000000000b',
          role: 'seller',
        ),
      ],
};

Map<String, Object?> memberJson({
  String userId = 'user-a',
  String profileId = '10000000-0000-4000-8000-00000000000a',
  String role = 'buyer',
  bool isMuted = false,
  String? lastReadMessageId,
}) => <String, Object?>{
  'user_id': userId,
  'profile_id': profileId,
  'role': role,
  'joined_at': '2026-05-01T00:00:00+00:00',
  'revoked_at': null,
  'is_muted': isMuted,
  'last_read_message_id': lastReadMessageId,
  'last_read_at': null,
};

Map<String, Object?> messageJson({
  String id = '70000000-0000-4000-8000-000000000001',
  String conversationId = '50000000-0000-4000-8000-000000000001',
  String senderUserId = 'user-a',
  String kind = 'text',
  String text = 'Synthetic message',
  int seq = 1,
  String? clientMessageId = 'key-1',
  List<String> attachmentMediaIds = const <String>[],
}) => <String, Object?>{
  'id': id,
  'conversation_id': conversationId,
  'sender_user_id': senderUserId,
  'sender_profile_id': '10000000-0000-4000-8000-00000000000a',
  'kind': kind,
  'text': text,
  'attachment_media_ids': attachmentMediaIds,
  'client_message_id': clientMessageId,
  'request_hash': 'hash',
  'seq': seq,
  'sent_at': '2026-05-01T00:00:01+00:00',
};

Map<String, Object?> inboxItemJson({
  String conversationId = '50000000-0000-4000-8000-000000000001',
  String counterpartName = 'Seller B',
  int unreadCount = 2,
  Map<String, Object?>? latest,
}) => <String, Object?>{
  'conversation': conversationJson(id: conversationId),
  'counterpart_display_name': counterpartName,
  'counterpart_profile_id': '10000000-0000-4000-8000-00000000000b',
  'latest_message': latest ?? messageJson(),
  'unread_count': unreadCount,
};
