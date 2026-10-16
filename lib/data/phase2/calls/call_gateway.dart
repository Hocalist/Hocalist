import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/phase2/communication_completion.dart';
import '../marketplace/supabase_marketplace_transport.dart';
import '../marketplace/marketplace_transport.dart';
import 'call_codecs.dart';
import '../accounts/fresh_session_token.dart';

String newCallKey() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Stable call failure codes. The UI maps these; raw server messages and
/// signaling payloads are never propagated.
class CallGatewayException implements Exception {
  const CallGatewayException(this.code);

  final String code;

  @override
  String toString() => 'CallGatewayException($code)';
}

abstract interface class CallService {
  String? get identity;
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, Object?> input,
  );
  Future<CallStatusSnapshot> status(String callId, {int cursor = 0});
  Future<Map<String, dynamic>> configuration(String id);
}

class CallGateway implements CallService {
  CallGateway(this.client)
    : identity = client.auth.currentUser?.id,
      transport = SupabaseMarketplaceTransport(client);
  final SupabaseClient client;
  @override
  final String? identity;
  final SupabaseMarketplaceTransport transport;

  /// Only the reviewed call actions are ever sent.
  static const Set<String> allowedActions = {
    'incoming',
    'invite',
    'poll',
    'status',
    'accept',
    'decline',
    'signal',
    'end',
  };

  void fence() {
    if (identity == null || client.auth.currentUser?.id != identity) {
      throw const CallGatewayException('session_changed');
    }
  }

  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, Object?> input,
  ) async {
    fence();
    if (!allowedActions.contains(action)) {
      throw const CallGatewayException('invalid_action');
    }
    final result = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(
        schema: 'hocalist',
        function: 'call_command',
        params: {'p_action': action, 'p_input': input},
      ),
    );
    fence();
    if (result is MarketplaceTransportError) throw _mapError(result);
    if (result is! MarketplaceTransportData || result.data is! Map) {
      throw const CallGatewayException('call_unavailable');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<CallStatusSnapshot> status(String callId, {int cursor = 0}) async {
    fence();
    final result = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(
        schema: 'hocalist',
        function: 'call_status',
        params: {'p_call_id': callId, 'p_cursor': cursor},
      ),
    );
    fence();
    if (result is MarketplaceTransportError) throw _mapError(result);
    if (result is! MarketplaceTransportData || result.data is! Map) {
      throw const CallGatewayException('call_unavailable');
    }
    try {
      return decodeCallStatusJson(
        Map<String, Object?>.from(result.data as Map),
      );
    } on CallDecodeException {
      throw const CallGatewayException('invalid_response');
    }
  }

  @override
  Future<Map<String, dynamic>> configuration(String id) async {
    fence();
    final token = await freshSessionToken(client);
    fence();
    if (token == null) {
      throw const CallGatewayException('session_changed');
    }
    final response = await http
        .post(
          Uri.parse(
            'https://icqwbzswokoulatomgql.supabase.co/functions/v1/hocalist-call-ice',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'call_id': id}),
        )
        .timeout(const Duration(seconds: 15));
    fence();
    if (response.statusCode != 200) {
      throw const CallGatewayException('relay_unconfigured');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['iceServers'] is! List) {
      throw const CallGatewayException('invalid_response');
    }
    // Relay-only protects participants' network addresses from each other.
    return {
      'iceServers': data['iceServers'],
      'iceTransportPolicy': 'relay',
      'sdpSemantics': 'unified-plan',
    };
  }

  static CallGatewayException _mapError(MarketplaceTransportError error) {
    switch (error.kind) {
      case MarketplaceTransportErrorKind.connectivity:
        return const CallGatewayException('call_unavailable');
      case MarketplaceTransportErrorKind.unauthorized:
        return const CallGatewayException('authentication_required');
      case MarketplaceTransportErrorKind.server:
        final message = error.message ?? '';
        for (final code in const [
          'authentication_required',
          'account_restricted',
          'role_not_active',
          'conversation_blocked',
          'conversation_access_denied',
          'call_access_denied',
          'call_not_found',
          'call_finished',
          'call_not_accepted',
          'calls_disabled',
          'idempotency_conflict',
          'meeting_required',
          'invalid_action',
          'invalid_input',
          'invalid_cursor',
        ]) {
          if (message.contains(code)) return CallGatewayException(code);
        }
        if (error.statusCode == 404) {
          return const CallGatewayException('call_not_found');
        }
        return const CallGatewayException('call_unavailable');
    }
  }
}
