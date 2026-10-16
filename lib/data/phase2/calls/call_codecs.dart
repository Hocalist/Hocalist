/// Strict decoders for the call lifecycle wire shapes (migration 152).
///
/// Validates required fields, known states and parseable timestamps. Failures
/// raise [CallDecodeException] with a safe field path; signal payloads are
/// never included in errors.
library;

import '../../../domain/phase2/communication_completion.dart';
import '../accounts/timestamptz.dart';

class CallDecodeException implements Exception {
  const CallDecodeException(this.detail);

  final String detail;

  @override
  String toString() => 'CallDecodeException($detail)';
}

CallLifecycleState _state(String wire) {
  for (final value in CallLifecycleState.values) {
    if (value.name == wire) return value;
  }
  return CallLifecycleState.unknown;
}

String _requireString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw CallDecodeException(key);
  }
  return value;
}

DateTime _requireTimestamp(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String) throw CallDecodeException(key);
  try {
    return parsePostgresTimestamptz(value, context: key);
  } catch (_) {
    throw CallDecodeException(key);
  }
}

CallSessionStatus decodeCallSessionJson(Map<String, Object?> row) {
  final terminal = row['terminal'];
  if (terminal != null && terminal is! bool) {
    throw const CallDecodeException('call.terminal');
  }
  try {
    return CallSessionStatus(
      id: _requireString(row, 'id'),
      conversationId: _requireString(row, 'conversation_id'),
      callerUserId: _requireString(row, 'caller_id'),
      calleeUserId: _requireString(row, 'callee_id'),
      state: _state(_requireString(row, 'state')),
      createdAt: _requireTimestamp(row, 'created_at'),
      expiresAt: _requireTimestamp(row, 'expires_at'),
      serverNow: _requireTimestamp(row, 'server_now'),
      enabled: row['enabled'] == true,
      settingsRevision: row['settings_revision'] is int
          ? row['settings_revision']! as int
          : 0,
      isTerminal: terminal as bool?,
    );
  } on ArgumentError {
    throw const CallDecodeException('call');
  }
}

CallStatusSnapshot decodeCallStatusJson(Map<String, Object?> json) {
  final callJson = json['call'];
  if (callJson is! Map) throw const CallDecodeException('call');
  final signalJson = json['signals'];
  if (signalJson is! List) throw const CallDecodeException('signals');
  final signals = <CallSignalEnvelope>[];
  for (final entry in signalJson) {
    if (entry is! Map) throw const CallDecodeException('signals.item');
    final sequence = entry['seq'];
    final kind = entry['kind'];
    final payload = entry['payload'];
    if (sequence is! int ||
        sequence < 0 ||
        kind is! String ||
        payload is! Map) {
      throw const CallDecodeException('signals.item');
    }
    signals.add(
      CallSignalEnvelope(
        sequence: sequence,
        kind: kind,
        payload: Map<String, Object?>.from(payload),
      ),
    );
  }
  // The 152 RPC returns the switch state and clock at the status level, so
  // merge them into the call projection before validating it.
  final merged = <String, Object?>{
    ...Map<String, Object?>.from(callJson),
    'server_now': json['server_now'],
    'enabled': json['enabled'],
    'settings_revision': json['settings_revision'],
  };
  return CallStatusSnapshot(
    call: decodeCallSessionJson(merged),
    signals: signals,
  );
}
