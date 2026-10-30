/// Hocalist account lifecycle backend (consent, export, deletion request).
///
/// Deployment gate: [createConfiguredAccountLifecycleBackend] returns null
/// unless `enabled` is true, so these surfaces keep their honest unavailable
/// state until `account_completion/130` is deployed. The backend only reaches
/// Hocalist records; shared Supabase Auth identity deletion is not available
/// here by design. Tests inject an [rpc] fake.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class AccountLifecycleRpcException implements Exception {
  const AccountLifecycleRpcException(
    this.message, {
    this.code,
    this.statusCode,
  });

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'AccountLifecycleRpcException($code: $message)';
}

class AccountLifecycleConflictException implements Exception {
  const AccountLifecycleConflictException();

  @override
  String toString() => 'AccountLifecycleConflictException()';
}

class AccountLifecycleUnavailableException implements Exception {
  const AccountLifecycleUnavailableException(
    this.message, {
    this.outcomeUncertain = false,
  });

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => 'AccountLifecycleUnavailableException($message)';
}

class ConsentDocumentView {
  const ConsentDocumentView({
    required this.id,
    required this.version,
    required this.label,
    required this.isRequired,
    required this.sortOrder,
    required this.revision,
  });

  final String id;
  final String version;
  final String label;
  final bool isRequired;
  final int sortOrder;
  final int revision;

  bool isAcceptedBy(List<ConsentRecordView> accepted) => accepted.any(
    (record) => record.documentId == id && record.version == version,
  );
}

class ConsentRecordView {
  const ConsentRecordView({
    required this.documentId,
    required this.version,
    required this.acceptedAt,
  });

  final String documentId;
  final String version;
  final DateTime acceptedAt;
}

class AccountExportView {
  const AccountExportView({
    required this.requestId,
    required this.status,
    required this.requestedAt,
    this.readyAt,
    required this.revision,
  });

  final String requestId;

  /// `pending`, `processing`, `ready` or `failed`.
  final String status;
  final DateTime requestedAt;
  final DateTime? readyAt;
  final int revision;

  bool get isReady => status == 'ready';
}

class AccountExportDocument {
  const AccountExportDocument({
    required this.requestId,
    required this.generatedAt,
    required this.payload,
  });

  final String requestId;
  final DateTime generatedAt;
  final Map<String, Object?> payload;
}

class DeletionHoldView {
  const DeletionHoldView({required this.kind, this.detail});

  /// `active_restriction`, `withdrawal_processing` or `credit_reservation`.
  final String kind;
  final String? detail;
}

class AccountDeletionView {
  const AccountDeletionView({
    required this.requestId,
    required this.status,
    required this.scope,
    required this.holds,
    required this.requestedAt,
    required this.revision,
    required this.cancelable,
    this.reused = false,
  });

  final String requestId;

  /// `requested`, `blocked` or `cancelled`.
  final String status;
  final String scope;
  final List<DeletionHoldView> holds;
  final DateTime requestedAt;
  final int revision;
  final bool cancelable;
  final bool reused;

  bool get isBlocked => status == 'blocked' && holds.isNotEmpty;
}

class AccountLifecycleStatusView {
  const AccountLifecycleStatusView({
    required this.documents,
    required this.acceptedConsents,
    this.latestExport,
    this.openDeletion,
  });

  final List<ConsentDocumentView> documents;
  final List<ConsentRecordView> acceptedConsents;
  final AccountExportView? latestExport;
  final AccountDeletionView? openDeletion;
}

typedef AccountLifecycleRpc =
    Future<Map<String, Object?>> Function(
      String function,
      Map<String, Object?> params,
    );

abstract interface class AccountLifecycleBackend {
  Future<AccountLifecycleStatusView> loadStatus();

  Future<ConsentRecordView> recordConsent({
    required String documentId,
    required String version,
    required String operationKey,
  });

  Future<AccountExportView> requestExport({required String operationKey});

  Future<AccountExportDocument> readExport({required String requestId});

  Future<AccountDeletionView> requestDeletion({required String operationKey});

  Future<AccountDeletionView> cancelDeletion({
    required String requestId,
    required int expectedRevision,
    String? reason,
    required String operationKey,
  });
}

class Phase2AccountLifecycleBackend implements AccountLifecycleBackend {
  Phase2AccountLifecycleBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String statusFunction = 'account_lifecycle_status';
  static const String consentFunction = 'account_consent_record';
  static const String exportRequestFunction = 'account_export_request';
  static const String exportReadFunction = 'account_export_read';
  static const String deletionRequestFunction = 'account_deletion_request';
  static const String deletionCancelFunction = 'account_deletion_cancel';
  static const Set<String> allowedFunctions = {
    statusFunction,
    consentFunction,
    exportRequestFunction,
    exportReadFunction,
    deletionRequestFunction,
    deletionCancelFunction,
  };

  final AccountLifecycleRpc rpc;
  final String? Function() identity;

  @override
  Future<AccountLifecycleStatusView> loadStatus() async {
    final data = await _call(statusFunction, const {});
    final documents = data['consent_documents'];
    final accepted = data['accepted_consents'];
    if (documents is! List || accepted is! List) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    return AccountLifecycleStatusView(
      documents: List.unmodifiable(documents.map(_decodeDocument)),
      acceptedConsents: List.unmodifiable(accepted.map(_decodeConsent)),
      latestExport: data['export'] is Map
          ? _decodeExport(Map<String, Object?>.from(data['export']! as Map))
          : null,
      openDeletion: data['deletion'] is Map
          ? _decodeDeletion(Map<String, Object?>.from(data['deletion']! as Map))
          : null,
    );
  }

  @override
  Future<ConsentRecordView> recordConsent({
    required String documentId,
    required String version,
    required String operationKey,
  }) async {
    final data = await _call(consentFunction, {
      'p_key': operationKey,
      'p_input': {'document_id': documentId, 'version': version},
    });
    return _decodeConsent(data);
  }

  @override
  Future<AccountExportView> requestExport({
    required String operationKey,
  }) async {
    final data = await _call(exportRequestFunction, {'p_key': operationKey});
    return _decodeExport(data);
  }

  @override
  Future<AccountExportDocument> readExport({required String requestId}) async {
    final data = await _call(exportReadFunction, {'p_request': requestId});
    final payload = data['payload'];
    final generated = data['generated_at'];
    final id = data['request_id'];
    if (payload is! Map || generated is! String || id is! String) {
      throw const AccountLifecycleUnavailableException(
        'The export response was invalid.',
      );
    }
    return AccountExportDocument(
      requestId: id,
      generatedAt: DateTime.parse(generated).toUtc(),
      payload: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(payload),
      ),
    );
  }

  @override
  Future<AccountDeletionView> requestDeletion({
    required String operationKey,
  }) async {
    final data = await _call(deletionRequestFunction, {'p_key': operationKey});
    return _decodeDeletion(data);
  }

  @override
  Future<AccountDeletionView> cancelDeletion({
    required String requestId,
    required int expectedRevision,
    String? reason,
    required String operationKey,
  }) async {
    final data = await _call(deletionCancelFunction, {
      'p_key': operationKey,
      'p_input': {
        'request_id': requestId,
        'expected_revision': expectedRevision,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    });
    return AccountDeletionView(
      requestId: data['request_id'] is String
          ? data['request_id']! as String
          : requestId,
      status: data['status'] is String
          ? data['status']! as String
          : 'cancelled',
      scope: 'hocalist',
      holds: const <DeletionHoldView>[],
      requestedAt: DateTime.now().toUtc(),
      revision: data['revision'] is int ? data['revision']! as int : 1,
      cancelable: false,
    );
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const AccountLifecycleUnavailableException(
        'Account lifecycle actions are unavailable.',
      );
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const AccountLifecycleUnavailableException('Sign in to continue.');
    }
    try {
      final data = await rpc(function, params);
      if (identity() != captured) {
        throw const AccountLifecycleUnavailableException(
          'Your session changed. Sign in again.',
        );
      }
      return data;
    } on AccountLifecycleRpcException catch (error) {
      if (error.code == 'P0001' &&
          (error.message.contains('revision_conflict') ||
              error.message.contains('consent_version_mismatch'))) {
        throw const AccountLifecycleConflictException();
      }
      if (error.code == 'P0001' &&
          error.message.contains('idempotency_conflict')) {
        throw const AccountLifecycleUnavailableException(
          'This request conflicts with an earlier attempt. Please try again.',
        );
      }
      throw AccountLifecycleUnavailableException(
        error.message,
        outcomeUncertain: error.statusCode == null || error.statusCode! >= 500,
      );
    } on AccountLifecycleUnavailableException {
      rethrow;
    } catch (_) {
      throw const AccountLifecycleUnavailableException(
        'The account action could not be confirmed. Retry to check it safely.',
        outcomeUncertain: true,
      );
    }
  }

  ConsentDocumentView _decodeDocument(Object? raw) {
    if (raw is! Map) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final id = row['id'];
    final version = row['version'];
    final label = row['label'];
    if (id is! String || version is! String || label is! String) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    return ConsentDocumentView(
      id: id,
      version: version,
      label: label,
      isRequired: row['is_required'] == true,
      sortOrder: row['sort_order'] is int ? row['sort_order']! as int : 0,
      revision: row['revision'] is int ? row['revision']! as int : 1,
    );
  }

  ConsentRecordView _decodeConsent(Object? raw) {
    if (raw is! Map) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final documentId = row['document_id'];
    final version = row['version'];
    final acceptedAt = row['accepted_at'];
    if (documentId is! String ||
        version is! String ||
        acceptedAt is! String ||
        DateTime.tryParse(acceptedAt) == null) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    return ConsentRecordView(
      documentId: documentId,
      version: version,
      acceptedAt: DateTime.parse(acceptedAt).toUtc(),
    );
  }

  AccountExportView _decodeExport(Map<String, Object?> row) {
    final requestId = row['request_id'];
    final status = row['status'];
    final requestedAt = row['requested_at'];
    if (requestId is! String ||
        status is! String ||
        requestedAt is! String ||
        DateTime.tryParse(requestedAt) == null) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    return AccountExportView(
      requestId: requestId,
      status: status,
      requestedAt: DateTime.parse(requestedAt).toUtc(),
      readyAt: row['ready_at'] is String
          ? DateTime.tryParse(row['ready_at']! as String)?.toUtc()
          : null,
      revision: row['revision'] is int ? row['revision']! as int : 1,
    );
  }

  AccountDeletionView _decodeDeletion(Map<String, Object?> row) {
    final requestId = row['request_id'];
    final status = row['status'];
    final requestedAt = row['requested_at'];
    if (requestId is! String ||
        status is! String ||
        requestedAt is! String ||
        DateTime.tryParse(requestedAt) == null) {
      throw const AccountLifecycleUnavailableException(
        'The lifecycle response was invalid.',
      );
    }
    final rawHolds = row['holds'];
    return AccountDeletionView(
      requestId: requestId,
      status: status,
      scope: row['scope'] is String ? row['scope']! as String : 'hocalist',
      holds: rawHolds is List
          ? List.unmodifiable([
              for (final raw in rawHolds)
                if (raw is Map)
                  DeletionHoldView(
                    kind: raw['kind'] is String
                        ? raw['kind']! as String
                        : 'unknown',
                    detail: raw['detail'] is String
                        ? raw['detail']! as String
                        : null,
                  ),
            ])
          : const <DeletionHoldView>[],
      requestedAt: DateTime.parse(requestedAt).toUtc(),
      revision: row['revision'] is int ? row['revision']! as int : 1,
      cancelable: row['cancelable'] == true,
      reused: row['reused'] == true,
    );
  }
}

/// Set true only after the reviewed `130_account_lifecycle` migration is
/// deployed.
const bool kAccountLifecycleEnabled = bool.fromEnvironment('HOCALIST_ACCOUNT_LIFECYCLE');

AccountLifecycleBackend? createConfiguredAccountLifecycleBackend({
  bool enabled = kAccountLifecycleEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2AccountLifecycleBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2AccountLifecycleBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const AccountLifecycleUnavailableException(
              'The lifecycle response was invalid.',
            );
          }
          return Map<String, Object?>.from(data);
        } on PostgrestException catch (error) {
          throw AccountLifecycleRpcException(
            error.message,
            code: error.code,
            statusCode: error.code == null ? null : 400,
          );
        }
      },
    );
  } catch (_) {
    return null;
  }
}
