import '../../../domain/phase2/failures.dart';
import '../marketplace/marketplace_transport.dart';
import '../marketplace/marketplace_session.dart';
import '../marketplace/marketplace_error_mapper.dart';
import '../accounts/timestamptz.dart';

class SupportCase {
  const SupportCase({
    required this.id,
    required this.reason,
    required this.body,
    required this.status,
    required this.revision,
    required this.createdAt,
    this.response,
  });
  final String id, reason, body, status;
  final int revision;
  final DateTime createdAt;
  final String? response;
  @override
  String toString() => 'SupportCase(redacted, $status)';
}

class SupportReason {
  const SupportReason(this.code, this.label);
  final String code, label;
}

class SupportPageResult {
  const SupportPageResult(this.items, this.cursor);
  final List<SupportCase> items;
  final String? cursor;
}

class SupportAdapter {
  SupportAdapter({required this.transport, required this.session});
  final MarketplaceTransport transport;
  final MarketplaceSession session;
  Future<RepositoryResult<T>> _call<T>(
    String name,
    Map<String, Object?> params,
    T Function(Map<String, Object?>) decode,
  ) async {
    final user = session.currentUserId;
    if (user == null) {
      return const RepositoryFailureResult(
        PermissionDeniedError(action: 'authenticate', entityType: 'support'),
      );
    }
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(schema: 'hocalist', function: name, params: params),
    );
    if (session.currentUserId != user) {
      return const RepositoryFailureResult(
        PermissionDeniedError(action: 'session_changed', entityType: 'support'),
      );
    }
    if (response is MarketplaceTransportError) {
      return RepositoryFailureResult(
        const MarketplaceErrorMapper().map(response, operation: name),
      );
    }
    try {
      return RepositorySuccess(
        decode(
          Map<String, Object?>.from(
            (response as MarketplaceTransportData).data as Map,
          ),
        ),
      );
    } catch (_) {
      return RepositoryFailureResult(
        MalformedResponseError(
          operation: name,
          detail: 'invalid_support_response',
        ),
      );
    }
  }

  static String _string(Map<String, Object?> m, String k, {int max = 4000}) {
    final v = m[k];
    if (v is! String || v.isEmpty || v.length > max) {
      throw const FormatException();
    }
    return v;
  }

  static String _id(Map<String, Object?> m, String k) {
    final v = _string(m, k, max: 36);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(v)) {
      throw const FormatException();
    }
    return v;
  }

  static String _status(Map<String, Object?> m) {
    final v = _string(m, 'status');
    if (!['open', 'in_review', 'resolved'].contains(v)) {
      throw const FormatException();
    }
    return v;
  }

  Future<RepositoryResult<List<SupportReason>>> reasons() =>
      _call('support_reasons', {}, (m) {
        final rows = m['items'] as List;
        final seen = <String>{};
        return List.unmodifiable(
          rows.map((raw) {
            final r = Map<String, Object?>.from(raw as Map);
            final code = _string(r, 'code', max: 40);
            if (!seen.add(code)) throw const FormatException();
            return SupportReason(code, _string(r, 'label', max: 100));
          }),
        );
      });
  Future<RepositoryResult<SupportPageResult>> cases({String? cursor}) => _call(
    'support_list',
    {'p_limit': 30, 'p_cursor': cursor, 'p_admin': false},
    (m) {
      final rows = m['items'] as List;
      if (rows.length > 30) throw const FormatException();
      final seen = <String>{};
      final items = rows
          .map((raw) {
            final r = Map<String, Object?>.from(raw as Map);
            final id = _id(r, 'id');
            final rev = r['revision'];
            if (!seen.add(id) || rev is! int || rev < 1) {
              throw const FormatException();
            }
            final response = r['response'];
            if (response != null &&
                (response is! String || response.length > 4000)) {
              throw const FormatException();
            }
            return SupportCase(
              id: id,
              reason: _string(r, 'reason', max: 100),
              body: _string(r, 'body'),
              status: _status(r),
              revision: rev,
              createdAt: parsePostgresTimestamptz(_string(r, 'created_at'), context: 'support.created_at'),
              response: response as String?,
            );
          })
          .toList(growable: false);
      final next = m['next_cursor'] == null ? null : _id(m, 'next_cursor');
      if (next != null && (items.isEmpty || items.last.id != next)) {
        throw const FormatException();
      }
      return SupportPageResult(List.unmodifiable(items), next);
    },
  );
  Future<RepositoryResult<String>> submit({
    required String reason,
    required String body,
    required String operationKey,
  }) => _call(
    'support_command',
    {
      'p_operation': 'create',
      'p_key': operationKey,
      'p_input': {'reason_code': reason, 'body': body},
    },
    (m) {
      _status(m);
      final rev = m['revision'];
      if (rev is! int || rev < 1) throw const FormatException();
      return _id(m, 'id');
    },
  );
}
