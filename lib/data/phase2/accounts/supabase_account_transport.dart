/// Concrete account transport over the official Supabase Flutter SDK.
///
/// Restricted to the `hocalist` schema, the three reviewed account tables,
/// allowlisted columns/filters/order fields and the `account_command`
/// function/operations. Anything else is rejected locally with an
/// [UnsupportedError] or [ArgumentError]; there is no arbitrary query surface
/// and no service-role or API-key pathway.
///
/// The captured access token is pinned on each request with an explicit
/// `Authorization` header, so a session replacement cannot attach another
/// identity's token to a queued operation. RLS remains authoritative; this is
/// defense in depth. Signed-out calls return an `unauthorized` transport
/// result before any HTTP request is made.
library;

import 'dart:async';

import 'fresh_session_token.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_transport.dart';

class SupabaseAccountTransport implements AccountTransport {
  SupabaseAccountTransport(this._client);

  static const String schema = 'hocalist';
  static const String accountCommandFunction = 'account_command';

  static const Set<String> allowedTables = {
    'memberships',
    'role_profiles',
    'profile_contacts',
  };

  static const Map<String, Set<String>> allowedColumns = {
    'memberships': {
      'id',
      'user_id',
      'role',
      'status',
      'revision',
      'created_at',
      'updated_at',
    },
    'role_profiles': {
      'membership_id',
      'display_name',
      'area_label',
      'profile_note',
      'preferred_meetup_type',
      'service_radius_miles',
      'pickup_availability',
      'revision',
      'created_at',
      'updated_at',
    },
    'profile_contacts': {
      'user_id',
      'phone',
      'address_line1',
      'address_line2',
      'city',
      'region',
      'postal_code',
      'country_code',
      'revision',
      'created_at',
      'updated_at',
    },
  };

  static const Map<String, Set<String>> allowedFilters = {
    'memberships': {'user_id', 'role'},
    'role_profiles': {'membership_id'},
    'profile_contacts': {'user_id'},
  };

  static const Map<String, Set<String>> allowedOrderColumns = {
    'memberships': {'role'},
    'role_profiles': <String>{},
    'profile_contacts': <String>{},
  };

  static const Set<String> allowedOperations = {
    'onboard',
    'profile.update',
    'contact.update',
  };

  final SupabaseClient _client;

  @override
  Future<AccountTransportResponse> selectRows(AccountTableQuery query) async {
    _validateSelectQuery(query);
    try {
      final token = await freshSessionToken(_client);
      if (token == null) return _unauthorized;
      PostgrestFilterBuilder<PostgrestList> filtered = _client
          .schema(query.schema)
          .from(query.table)
          .select(query.columns.join(','));
      for (final filter in query.filters) {
        if (filter.isNull) {
          filtered = filtered.isFilter(filter.column, null);
          continue;
        }
        final value = filter.value;
        if (value == null) {
          throw ArgumentError.value(
            filter.column,
            'filters',
            'null equality must use isNull',
          );
        }
        filtered = filtered.eq(filter.column, value);
      }
      PostgrestTransformBuilder<PostgrestList> ordered = filtered;
      for (final column in query.orderBy) {
        ordered = ordered.order(column, ascending: true);
      }
      final data = await ordered.setHeader('Authorization', 'Bearer $token');
      return AccountTransportData(data);
    } on PostgrestException catch (error) {
      return _fromPostgrest(error);
    } on AuthRetryableFetchException {
      return _connectivity;
    } on AuthException {
      return _unauthorized;
    } on TimeoutException {
      return _connectivity;
    } on http.ClientException {
      return _connectivity;
    } on Exception {
      return const AccountTransportError(
        kind: AccountTransportErrorKind.server,
      );
    }
  }

  @override
  Future<AccountTransportResponse> callAccountCommand({
    required String schema,
    required String function,
    required String operation,
    required String key,
    required Map<String, Object?> input,
  }) async {
    if (schema != SupabaseAccountTransport.schema) {
      throw UnsupportedError('Unsupported account schema');
    }
    if (function != accountCommandFunction) {
      throw UnsupportedError('Unsupported account function');
    }
    if (!allowedOperations.contains(operation)) {
      throw UnsupportedError('Unsupported account operation');
    }
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be blank');
    }
    try {
      final token = await freshSessionToken(_client);
      if (token == null) return _unauthorized;
      final data = await _client
          .schema(schema)
          .rpc(
            function,
            params: <String, Object?>{
              'p_operation': operation,
              'p_key': key,
              'p_input': input,
            },
          )
          .setHeader('Authorization', 'Bearer $token');
      return AccountTransportData(data);
    } on PostgrestException catch (error) {
      return _fromPostgrest(error);
    } on AuthRetryableFetchException {
      return _connectivity;
    } on AuthException {
      return _unauthorized;
    } on TimeoutException {
      return _connectivity;
    } on http.ClientException {
      return _connectivity;
    } on Exception {
      return const AccountTransportError(
        kind: AccountTransportErrorKind.server,
      );
    }
  }

  void _validateSelectQuery(AccountTableQuery query) {
    if (query.schema != schema) {
      throw UnsupportedError('Unsupported account schema');
    }
    if (!allowedTables.contains(query.table)) {
      throw UnsupportedError('Unsupported account table');
    }
    if (query.columns.isEmpty) {
      throw ArgumentError.value(query.columns, 'columns', 'must not be empty');
    }
    final columns = allowedColumns[query.table]!;
    for (final column in query.columns) {
      if (!columns.contains(column)) {
        throw ArgumentError.value(
          column,
          'columns',
          'Unsupported account column',
        );
      }
    }
    final filters = allowedFilters[query.table]!;
    for (final filter in query.filters) {
      if (!filters.contains(filter.column)) {
        throw ArgumentError.value(
          filter.column,
          'filters',
          'Unsupported account filter',
        );
      }
    }
    final orderColumns = allowedOrderColumns[query.table]!;
    for (final column in query.orderBy) {
      if (!orderColumns.contains(column)) {
        throw ArgumentError.value(
          column,
          'orderBy',
          'Unsupported account order column',
        );
      }
    }
  }

  AccountTransportError _fromPostgrest(PostgrestException error) {
    final code = error.code;
    final parsedCode = int.tryParse(code ?? '');
    // The SDK folds the HTTP status into `code` only when the error body has
    // no code of its own; SQLSTATE/PGRST codes are not status codes.
    final statusCode =
        parsedCode != null && parsedCode >= 100 && parsedCode <= 599
        ? parsedCode
        : null;
    final unauthorized =
        code == 'PGRST301' ||
        code == 'PGRST302' ||
        code == 'PGRST303' ||
        statusCode == 401;
    return AccountTransportError(
      kind: unauthorized
          ? AccountTransportErrorKind.unauthorized
          : AccountTransportErrorKind.server,
      code: code,
      message: error.message,
      statusCode: statusCode,
      retryable: statusCode != null && statusCode >= 500,
    );
  }

  static const AccountTransportResponse _unauthorized = AccountTransportError(
    kind: AccountTransportErrorKind.unauthorized,
  );

  static const AccountTransportResponse _connectivity = AccountTransportError(
    kind: AccountTransportErrorKind.connectivity,
    retryable: true,
  );
}
