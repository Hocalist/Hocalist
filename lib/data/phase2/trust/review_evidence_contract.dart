/// Authorized review/report evidence read contract for the admin package.
///
/// Exact backend surface (deployed by migrations media/100 + trust/120 +
/// account_completion/132):
///
/// - `hocalist.admin_review_evidence(p_limit integer)` (authenticated admin
///   only, provisioned through `hocalist.platform_admins`):
///   `{read_contract:{...}, retention_jobs_enabled:false, items:[{
///      media_id, purpose, state, size_bytes, width, height, created_at,
///      owner_user_id, owner_name, submission_id, submission_kind,
///      submission_status, case_id, case_reason, case_status, held }]}`
/// - Bytes: `POST <project>/functions/v1/hocalist-media?action=read&id=<media_id>`
///   with the admin's `Authorization: Bearer <access token>`. The media
///   gateway authorizes the caller as an admin with an evidence link; the
///   response is `image/jpeg`, never a signed URL or storage credential.
///
/// Restrictions the admin surface must preserve:
/// - No generic profile/chat reader can read `review`/`report` media; the read
///   rule requires an evidence link plus an admin identity.
/// - Media with an active hold is flagged `held` and must render as retained;
///   there is no delete or retention action in this contract.
/// - `evidence_count` from `verification_status` is advisory metadata; the
///   authorized queue above is the only readable evidence source.
library;

import 'dart:typed_data';

import 'trust_backend.dart';

/// The two pieces an admin evidence screen needs.
abstract interface class ReviewEvidenceAdminContract {
  /// Authorized metadata queue. Requires an admin session.
  Future<ReviewEvidencePage> loadReviewEvidence({int limit});

  /// Streams one authorized evidence image. The injected reader carries the
  /// caller's session; it never exposes a storage URL.
  Future<Uint8List> readEvidenceBytes(String mediaId);
}

/// Composes the contract from the trust backend and an authenticated byte
/// reader (normally the `hocalist-media` gateway).
class TrustReviewEvidenceAdminContract implements ReviewEvidenceAdminContract {
  const TrustReviewEvidenceAdminContract({
    required this.backend,
    required this.readBytes,
  });

  final TrustBackend backend;
  final Future<Uint8List> Function(String mediaId) readBytes;

  @override
  Future<ReviewEvidencePage> loadReviewEvidence({int limit = 50}) =>
      backend.loadReviewEvidence(limit: limit);

  @override
  Future<Uint8List> readEvidenceBytes(String mediaId) => readBytes(mediaId);
}
