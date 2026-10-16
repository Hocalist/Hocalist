/// Real-mode manual review seam.
///
/// Reads reviewed evidence status and account-health restrictions, and submits
/// verification evidence or a restriction appeal through the reviewed RPCs.
/// Verified email/phone stays an Auth fact, separate from reviewed evidence; a
/// report never restricts an account by itself.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class TrustRpcException implements Exception {
  const TrustRpcException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'TrustRpcException($code: $message)';
}

class TrustUnavailableException implements Exception {
  const TrustUnavailableException(
    this.message, {
    this.outcomeUncertain = false,
  });

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => 'TrustUnavailableException($message)';
}

class VerificationItemView {
  const VerificationItemView({
    required this.id,
    required this.kind,
    required this.status,
    required this.evidenceCount,
    this.evidenceMediaIds,
    this.decisionReason,
    required this.createdAt,
  });

  final String id;
  final String kind;

  /// `pending`, `approved` or `rejected`.
  final String status;
  final int evidenceCount;

  /// Null means the older server read does not project saved references.
  final List<String>? evidenceMediaIds;
  final String? decisionReason;
  final DateTime createdAt;
}

class AccountRestrictionView {
  const AccountRestrictionView({
    required this.id,
    required this.scope,
    required this.reason,
    required this.createdAt,
    this.appealId,
    this.appealStatus,
  });

  final String id;
  final String scope;
  final String reason;
  final DateTime createdAt;
  final String? appealId;

  /// `submitted`, `upheld` or `reversed`.
  final String? appealStatus;

  bool get canAppeal => appealId == null;
}

class TrustStatusView {
  const TrustStatusView({
    required this.emailVerified,
    required this.phoneVerified,
    required this.reviewStatus,
    required this.items,
    required this.restrictions,
  });

  final bool emailVerified;
  final bool phoneVerified;
  final String reviewStatus;
  final List<VerificationItemView> items;
  final List<AccountRestrictionView> restrictions;
}

abstract interface class TrustBackend {
  Future<TrustStatusView> loadStatus();

  Future<VerificationItemView> submitVerification({
    required String kind,
    required String note,
    required String operationKey,
    List<String> evidenceMediaIds = const <String>[],
  });

  /// Attaches ready review-purpose media owned by the caller to a pending
  /// submission. A replacement is detach + attach.
  Future<EvidenceMutationView> attachReviewEvidence({
    required String submissionId,
    required List<String> mediaIds,
    required String operationKey,
  });

  Future<EvidenceMutationView> detachReviewEvidence({
    required String submissionId,
    required String mediaId,
    required String operationKey,
  });

  Future<EvidenceMutationView> attachReportEvidence({
    required String caseId,
    required List<String> mediaIds,
    required String operationKey,
  });

  Future<EvidenceMutationView> detachReportEvidence({
    required String caseId,
    required String mediaId,
    required String operationKey,
  });

  /// Authorized reviewer evidence metadata. Bytes are read through the
  /// authenticated media gateway with the returned media id; this contract
  /// never returns a storage URL or credential.
  Future<ReviewEvidencePage> loadReviewEvidence({int limit = 50});

  Future<void> submitAppeal({
    required String restrictionId,
    required String body,
    required String operationKey,
  });
}

/// Result of one evidence attach/detach command.
class EvidenceMutationView {
  const EvidenceMutationView({
    this.submissionId,
    this.caseId,
    required this.revision,
    required this.mediaIds,
  });

  final String? submissionId;
  final String? caseId;

  /// Submission revision after the mutation, when a submission was touched.
  final int revision;
  final List<String> mediaIds;
}

/// One authorized reviewer evidence row.
class ReviewEvidenceItem {
  const ReviewEvidenceItem({
    required this.mediaId,
    required this.purpose,
    required this.state,
    required this.ownerUserId,
    required this.createdAt,
    required this.held,
    this.sizeBytes,
    this.width,
    this.height,
    this.ownerName,
    this.submissionId,
    this.submissionKind,
    this.submissionStatus,
    this.caseId,
    this.caseReason,
    this.caseStatus,
  });

  final String mediaId;
  final String purpose;
  final String state;
  final String ownerUserId;
  final DateTime createdAt;
  final bool held;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final String? ownerName;
  final String? submissionId;
  final String? submissionKind;
  final String? submissionStatus;
  final String? caseId;
  final String? caseReason;
  final String? caseStatus;
}

/// Admin evidence page plus the exact read contract the admin package uses.
class ReviewEvidencePage {
  const ReviewEvidencePage({
    required this.items,
    required this.retentionJobsEnabled,
  });

  final List<ReviewEvidenceItem> items;
  final bool retentionJobsEnabled;

  /// Edge-function route used to read one item's bytes with the caller's
  /// session token: POST `hocalist-media?action=read&id=<mediaId>`.
  static const String edgeFunction = 'hocalist-media';
  static const String readAction = 'read';
  static const String mediaIdParameter = 'id';
}

class Phase2TrustBackend implements TrustBackend {
  Phase2TrustBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String verificationStatusFunction = 'verification_status';
  static const String healthStatusFunction = 'account_health_status';
  static const String submitFunction = 'verification_submit';
  static const String appealFunction = 'restriction_appeal_submit';
  static const String attachReviewEvidenceFunction = 'review_evidence_attach';
  static const String detachReviewEvidenceFunction = 'review_evidence_detach';
  static const String attachReportEvidenceFunction = 'report_evidence_attach';
  static const String detachReportEvidenceFunction = 'report_evidence_detach';
  static const String adminEvidenceFunction = 'admin_review_evidence';
  static const Set<String> allowedFunctions = {
    verificationStatusFunction,
    healthStatusFunction,
    submitFunction,
    appealFunction,
    attachReviewEvidenceFunction,
    detachReviewEvidenceFunction,
    attachReportEvidenceFunction,
    detachReportEvidenceFunction,
    adminEvidenceFunction,
  };

  final Future<Map<String, Object?>> Function(
    String function,
    Map<String, Object?> params,
  )
  rpc;
  final String? Function() identity;

  @override
  Future<TrustStatusView> loadStatus() async {
    final verification = await _call(verificationStatusFunction, const {});
    final health = await _call(healthStatusFunction, const {});
    final emailPhone = verification['email_phone'];
    final items = verification['items'];
    final restrictions = health['restrictions'];
    if (emailPhone is! Map || items is! List || restrictions is! List) {
      throw const TrustUnavailableException(
        'The review status response was invalid.',
      );
    }
    return TrustStatusView(
      emailVerified: emailPhone['email_verified'] == true,
      phoneVerified: emailPhone['phone_verified'] == true,
      reviewStatus: health['review_status'] is String
          ? health['review_status']! as String
          : 'not_submitted',
      items: List.unmodifiable(items.map((row) => _decodeItem(row))),
      restrictions: List.unmodifiable(
        restrictions.map((row) => _decodeRestriction(row)),
      ),
    );
  }

  @override
  Future<VerificationItemView> submitVerification({
    required String kind,
    required String note,
    required String operationKey,
    List<String> evidenceMediaIds = const <String>[],
  }) async {
    final submittingIdentity = identity();
    final data = await _call(submitFunction, {
      'p_key': operationKey,
      'p_input': {
        'kind': kind,
        'note': note,
        'evidence_media_ids': List<String>.from(evidenceMediaIds),
      },
    });
    if (data['created_at'] is String) return _decodeItem(data);
    final id = data['id'];
    if (id is! String || data['kind'] != kind || data['status'] != 'pending') {
      throw const TrustUnavailableException(
        'The submission acknowledgement was invalid.',
        outcomeUncertain: true,
      );
    }
    try {
      if (identity() != submittingIdentity) throw StateError('session_changed');
      final confirmed = await loadStatus();
      if (identity() != submittingIdentity) throw StateError('session_changed');
      for (final item in confirmed.items) {
        if (item.id == id && item.kind == kind) return item;
      }
    } catch (_) {
      throw const TrustUnavailableException(
        'Submission received, but its status could not be confirmed. Retry to check the same submission.',
        outcomeUncertain: true,
      );
    }
    throw const TrustUnavailableException(
      'Submission received, but its record is not available yet. Retry to check the same submission.',
      outcomeUncertain: true,
    );
  }

  @override
  Future<EvidenceMutationView> attachReviewEvidence({
    required String submissionId,
    required List<String> mediaIds,
    required String operationKey,
  }) async {
    final data = await _call(attachReviewEvidenceFunction, {
      'p_key': operationKey,
      'p_input': {
        'submission_id': submissionId,
        'media_ids': List<String>.from(mediaIds),
      },
    });
    return _decodeMutation(data, submissionKey: 'submission_id');
  }

  @override
  Future<EvidenceMutationView> detachReviewEvidence({
    required String submissionId,
    required String mediaId,
    required String operationKey,
  }) async {
    final data = await _call(detachReviewEvidenceFunction, {
      'p_key': operationKey,
      'p_input': {'submission_id': submissionId, 'media_id': mediaId},
    });
    return _decodeMutation(data, submissionKey: 'submission_id');
  }

  @override
  Future<EvidenceMutationView> attachReportEvidence({
    required String caseId,
    required List<String> mediaIds,
    required String operationKey,
  }) async {
    final data = await _call(attachReportEvidenceFunction, {
      'p_key': operationKey,
      'p_input': {'case_id': caseId, 'media_ids': List<String>.from(mediaIds)},
    });
    return _decodeMutation(data, caseKey: 'case_id');
  }

  @override
  Future<EvidenceMutationView> detachReportEvidence({
    required String caseId,
    required String mediaId,
    required String operationKey,
  }) async {
    final data = await _call(detachReportEvidenceFunction, {
      'p_key': operationKey,
      'p_input': {'case_id': caseId, 'media_id': mediaId},
    });
    return _decodeMutation(data, caseKey: 'case_id');
  }

  @override
  Future<ReviewEvidencePage> loadReviewEvidence({int limit = 50}) async {
    final data = await _call(adminEvidenceFunction, {'p_limit': limit});
    final items = data['items'];
    if (items is! List) {
      throw const TrustUnavailableException(
        'The evidence response was invalid.',
      );
    }
    return ReviewEvidencePage(
      items: List.unmodifiable(items.map(_decodeEvidenceItem)),
      retentionJobsEnabled: data['retention_jobs_enabled'] == true,
    );
  }

  @override
  Future<void> submitAppeal({
    required String restrictionId,
    required String body,
    required String operationKey,
  }) async {
    await _call(appealFunction, {
      'p_key': operationKey,
      'p_input': {'restriction_id': restrictionId, 'body': body},
    });
  }

  VerificationItemView _decodeItem(Object? raw) {
    if (raw is! Map) {
      throw const TrustUnavailableException(
        'The review status response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final id = row['id'];
    final kind = row['kind'];
    final status = row['status'];
    final created = row['created_at'];
    final evidenceIds = row['evidence_media_ids'];
    if (evidenceIds != null &&
        (evidenceIds is! List ||
            evidenceIds.length > 8 ||
            evidenceIds.any(
              (id) =>
                  id is! String ||
                  !RegExp(
                    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                  ).hasMatch(id),
            ))) {
      throw const TrustUnavailableException(
        'The saved evidence response was invalid.',
      );
    }
    if (id is! String ||
        kind is! String ||
        status is! String ||
        !const {'pending', 'approved', 'rejected'}.contains(status) ||
        created is! String ||
        DateTime.tryParse(created) == null) {
      throw const TrustUnavailableException(
        'The review status response was invalid.',
      );
    }
    return VerificationItemView(
      id: id,
      kind: kind,
      status: status,
      evidenceCount: row['evidence_count'] is int
          ? row['evidence_count']! as int
          : 0,
      evidenceMediaIds: evidenceIds == null
          ? null
          : List<String>.unmodifiable((evidenceIds as List).cast<String>()),
      decisionReason: row['decision_reason'] is String
          ? row['decision_reason']! as String
          : null,
      createdAt: DateTime.parse(created).toUtc(),
    );
  }

  AccountRestrictionView _decodeRestriction(Object? raw) {
    if (raw is! Map) {
      throw const TrustUnavailableException(
        'The review status response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final id = row['id'];
    final scope = row['scope'];
    final reason = row['reason'];
    final created = row['created_at'];
    if (id is! String ||
        scope is! String ||
        reason is! String ||
        created is! String ||
        DateTime.tryParse(created) == null) {
      throw const TrustUnavailableException(
        'The review status response was invalid.',
      );
    }
    return AccountRestrictionView(
      id: id,
      scope: scope,
      reason: reason,
      createdAt: DateTime.parse(created).toUtc(),
      appealId: row['appeal_id'] is String ? row['appeal_id']! as String : null,
      appealStatus: row['appeal_status'] is String
          ? row['appeal_status']! as String
          : null,
    );
  }

  EvidenceMutationView _decodeMutation(
    Object? raw, {
    String? submissionKey,
    String? caseKey,
  }) {
    if (raw is! Map) {
      throw const TrustUnavailableException(
        'The evidence response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final ids = row['evidence_media_ids'];
    final submissionId = submissionKey == null ? null : row[submissionKey];
    final caseId = caseKey == null ? null : row[caseKey];
    if ((submissionKey != null && submissionId is! String) ||
        (caseKey != null && caseId is! String) ||
        (ids != null && ids is! List)) {
      throw const TrustUnavailableException(
        'The evidence response was invalid.',
      );
    }
    return EvidenceMutationView(
      submissionId: submissionId as String?,
      caseId: caseId as String?,
      revision: row['revision'] is int ? row['revision']! as int : 0,
      mediaIds: ids is List
          ? List.unmodifiable(ids.whereType<String>())
          : const <String>[],
    );
  }

  ReviewEvidenceItem _decodeEvidenceItem(Object? raw) {
    if (raw is! Map) {
      throw const TrustUnavailableException(
        'The evidence response was invalid.',
      );
    }
    final row = Map<String, Object?>.from(raw);
    final mediaId = row['media_id'];
    final purpose = row['purpose'];
    final state = row['state'];
    final owner = row['owner_user_id'];
    final created = row['created_at'];
    if (mediaId is! String ||
        purpose is! String ||
        state is! String ||
        owner is! String ||
        created is! String ||
        DateTime.tryParse(created) == null) {
      throw const TrustUnavailableException(
        'The evidence response was invalid.',
      );
    }
    return ReviewEvidenceItem(
      mediaId: mediaId,
      purpose: purpose,
      state: state,
      ownerUserId: owner,
      createdAt: DateTime.parse(created).toUtc(),
      held: row['held'] == true,
      sizeBytes: row['size_bytes'] is int ? row['size_bytes']! as int : null,
      width: row['width'] is int ? row['width']! as int : null,
      height: row['height'] is int ? row['height']! as int : null,
      ownerName: row['owner_name'] is String
          ? row['owner_name']! as String
          : null,
      submissionId: row['submission_id'] is String
          ? row['submission_id']! as String
          : null,
      submissionKind: row['submission_kind'] is String
          ? row['submission_kind']! as String
          : null,
      submissionStatus: row['submission_status'] is String
          ? row['submission_status']! as String
          : null,
      caseId: row['case_id'] is String ? row['case_id']! as String : null,
      caseReason: row['case_reason'] is String
          ? row['case_reason']! as String
          : null,
      caseStatus: row['case_status'] is String
          ? row['case_status']! as String
          : null,
    );
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const TrustUnavailableException('Review actions are unavailable.');
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const TrustUnavailableException('Sign in to continue.');
    }
    try {
      final data = await rpc(function, params);
      if (identity() != captured) {
        throw const TrustUnavailableException(
          'Your session changed. Sign in again.',
        );
      }
      return data;
    } on TrustRpcException catch (error) {
      throw _mapRpcError(error);
    } on TrustUnavailableException {
      rethrow;
    } catch (_) {
      throw const TrustUnavailableException(
        'The review action could not be confirmed. Retry to check it safely.',
        outcomeUncertain: true,
      );
    }
  }

  TrustUnavailableException _mapRpcError(TrustRpcException error) {
    final message = error.message;
    if (error.code == 'P0001' && message.contains('verification_pending')) {
      return const TrustUnavailableException(
        'A verification review is already pending.',
      );
    }
    if (error.code == 'P0001' && message.contains('appeal_exists')) {
      return const TrustUnavailableException(
        'An appeal is already recorded for this restriction.',
      );
    }
    if (message.contains('invalid_evidence_reference')) {
      return const TrustUnavailableException(
        'Attach only your own ready review evidence.',
      );
    }
    if (message.contains('evidence_limit')) {
      return const TrustUnavailableException(
        'At most eight evidence images are allowed.',
      );
    }
    if (message.contains('submission_not_editable') ||
        message.contains('case_not_editable')) {
      return const TrustUnavailableException(
        'This review can no longer be edited.',
      );
    }
    if (message.contains('evidence_hold_active')) {
      return const TrustUnavailableException(
        'This evidence is retained and cannot be removed yet.',
      );
    }
    if (message.contains('evidence_already_linked')) {
      return const TrustUnavailableException(
        'One of these images is already attached to another review.',
      );
    }
    return TrustUnavailableException(
      message,
      outcomeUncertain: error.statusCode == null || error.statusCode! >= 500,
    );
  }
}

/// Set true only after the reviewed trust migration is deployed.
const bool kTrustReviewEnabled = bool.fromEnvironment('HOCALIST_TRUST_REVIEW');

TrustBackend? createConfiguredTrustBackend({
  bool enabled = kTrustReviewEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2TrustBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2TrustBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const TrustUnavailableException(
              'The review response was invalid.',
            );
          }
          return Map<String, Object?>.from(data);
        } on PostgrestException catch (error) {
          throw TrustRpcException(
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
