/// Account health projection for dashboard consumption.
///
/// This is a projection only: it renders the facts the server already reports
/// (Auth email/phone verification, reviewed-evidence status and active
/// restrictions). It never calculates or invents a health score, threshold or
/// penalty.
library;

import 'package:hocalist/theme/adaptive_palette.dart';

import 'package:flutter/material.dart';

import '../../data/phase2/trust/trust_backend.dart';
import '../../domain/phase2/profiles.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

class AccountHealthProjection {
  const AccountHealthProjection({
    required this.emailVerified,
    required this.phoneVerified,
    required this.reviewStatus,
    required this.reviewKind,
    required this.pendingReview,
    required this.activeRestrictions,
    required this.retentionJobsEnabled,
  });

  factory AccountHealthProjection.fromTrustStatus(TrustStatusView status) {
    String? kind;
    var pending = false;
    for (final item in status.items) {
      if (item.status == 'pending') {
        pending = true;
        kind ??= item.kind;
      }
    }
    return AccountHealthProjection(
      emailVerified: status.emailVerified,
      phoneVerified: status.phoneVerified,
      reviewStatus: status.reviewStatus,
      reviewKind: kind,
      pendingReview: pending,
      activeRestrictions: status.restrictions
          .map((restriction) => restriction.scope)
          .toList(growable: false),
      retentionJobsEnabled: false,
    );
  }

  final bool emailVerified;
  final bool phoneVerified;

  /// `not_submitted`, `pending`, `approved` or `rejected`.
  final String reviewStatus;
  final String? reviewKind;
  final bool pendingReview;
  final List<String> activeRestrictions;
  final bool retentionJobsEnabled;

  bool get isRestricted => activeRestrictions.isNotEmpty;

  String get summary {
    if (isRestricted) {
      return 'Restricted: ${activeRestrictions.join(', ')}';
    }
    if (pendingReview) {
      return 'Review pending${reviewKind == null ? '' : ' ($reviewKind)'}';
    }
    return switch (reviewStatus) {
      'approved' => 'Reviewed evidence approved',
      'rejected' => 'Reviewed evidence not approved',
      'not_submitted' => 'No review submitted yet',
      _ => 'Review: $reviewStatus',
    };
  }
}

/// Compact status row for a buyer/seller dashboard header. `role` picks the
/// existing buyer or seller accent without changing either role's design.
class AccountHealthStatusCard extends StatelessWidget {
  const AccountHealthStatusCard({
    required this.projection,
    this.onRefresh,
    this.busy = false,
    super.key,
  });

  final AccountHealthProjection projection;
  final VoidCallback? onRefresh;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final accent = projection.isRestricted
        ? const Color(0xffc62828)
        : BuyerUiTokens.action;
    return Container(
      key: const ValueKey('accountHealthStatusCard'),
      padding: metrics.geometryInsets(const EdgeInsets.all(12)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.surface),
        borderRadius: BorderRadius.circular(metrics.geometry(14)),
        border: Border.all(
          color: HocalistPalette.border(
            context,
            projection.isRestricted
                ? const Color(0xffffc9cf)
                : BuyerUiTokens.border,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: metrics.artSize(32),
            height: metrics.artSize(32),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(
                context,
                projection.isRestricted
                    ? const Color(0xffffeef0)
                    : BuyerUiTokens.softSurface,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: BuyerGlyphIcon(
                icon: projection.isRestricted
                    ? Icons.report_gmailerrorred_outlined
                    : Icons.health_and_safety_outlined,
                slotSize: metrics.artSize(17),
                glyphSize: metrics.artSize(17),
                color: HocalistPalette.text(context, accent),
              ),
            ),
          ),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projection.summary,
                  key: const ValueKey('accountHealthStatusSummary'),
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.cardTitle,
                  ).copyWith(fontSize: metrics.fontSize(12.5)),
                ),
                SizedBox(height: metrics.spacing(2)),
                Text(
                  'Email ${projection.emailVerified ? 'verified' : 'not verified'}'
                  ' · Phone ${projection.phoneVerified ? 'verified' : 'not verified'}'
                  ' · No automatic score',
                  key: const ValueKey('accountHealthStatusFacts'),
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.metadata,
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              key: const ValueKey('accountHealthStatusRefresh'),
              tooltip: 'Refresh account health',
              onPressed: busy ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Seller/buyer dashboard helper that never guesses the role.
AccountHealthStatusCard accountHealthStatusCardFor({
  required HocalistRole role,
  required AccountHealthProjection projection,
  VoidCallback? onRefresh,
  bool busy = false,
}) {
  return AccountHealthStatusCard(
    key: ValueKey('accountHealth-${role.name}'),
    projection: projection,
    onRefresh: onRefresh,
    busy: busy,
  );
}
