/// Restricted-account status, appeal and support surface.
///
/// Rendered by the real account gate while a membership is restricted or
/// disabled. It never mounts the marketplace subtree: the only backend calls
/// are the read-only review status and the limited appeal command, both of
/// which are authorized independently of marketplace access.
library;

import 'package:flutter/material.dart';

import '../../data/phase2/trust/trust_backend.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import 'account_recovery_pages.dart';
import 'hocalist_account_controller.dart';

class RestrictedAccountPanel extends StatefulWidget {
  const RestrictedAccountPanel({
    required this.controller,
    required this.backend,
    this.onSupport,
    super.key,
  });

  final HocalistAccountController controller;

  /// Manual review capability. Null keeps the honest refresh/logout state and
  /// never fakes an appeal.
  final TrustBackend? backend;

  /// Optional support entry supplied by the app shell.
  final VoidCallback? onSupport;

  @override
  State<RestrictedAccountPanel> createState() => _RestrictedAccountPanelState();
}

class _RestrictedAccountPanelState extends State<RestrictedAccountPanel> {
  final _appealBody = TextEditingController();
  TrustStatusView? _status;
  bool _loading = false;
  bool _submitting = false;
  String? _loadError;
  String? _submitError;
  String? _logoutError;
  String? _appealRestrictionId;
  String? _appealKey;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _appealBody.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final backend = widget.backend;
    if (backend == null) return;
    final run = ++_generation;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final status = await backend.loadStatus();
      if (!mounted || run != _generation) return;
      setState(() => _status = status);
    } catch (_) {
      if (!mounted || run != _generation) return;
      setState(() => _loadError = 'Review status could not be loaded.');
    } finally {
      if (mounted && run == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await widget.controller.refresh();
    await _load();
  }

  Future<void> _submitAppeal(String restrictionId) async {
    final backend = widget.backend;
    if (backend == null || _submitting) return;
    final body = _appealBody.text.trim();
    if (body.length < 10) {
      setState(
        () => _submitError = 'Describe the appeal in at least 10 characters.',
      );
      return;
    }
    if (_appealRestrictionId != restrictionId) {
      _appealRestrictionId = restrictionId;
      _appealKey = UniqueKey().toString();
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await backend.submitAppeal(
        restrictionId: restrictionId,
        body: body,
        operationKey: _appealKey!,
      );
      if (!mounted) return;
      _appealRestrictionId = null;
      _appealKey = null;
      _appealBody.clear();
      setState(() => _submitting = false);
      await _load();
    } on TrustUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = failure.message;
        if (!failure.outcomeUncertain) {
          _appealRestrictionId = null;
          _appealKey = null;
        }
      });
    }
  }

  Future<void> _logout() async {
    setState(() => _logoutError = null);
    try {
      await widget.controller.logout();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _logoutError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _logoutError = 'Could not sign out. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final backend = widget.backend;
    final status = _status;
    return AccountRecoveryScaffold(
      key: const ValueKey('restricted-account-panel'),
      title: 'Account access restricted',
      body:
          'A reviewer restricted this account. You can review the reason, '
          'submit one appeal, and sign out. App content stays unavailable '
          'until the restriction is lifted.',
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_loadError != null)
          _PanelNote(
            key: const ValueKey('restricted-status-error'),
            text: _loadError!,
            tone: BuyerNoticeTone.error,
            actionLabel: 'Retry',
            onAction: _load,
          ),
        if (backend == null)
          const _PanelNote(
            key: ValueKey('restricted-status-unavailable'),
            text:
                'Review details and appeals are not available in this build '
                'yet. Refresh to check again, or sign out.',
          ),
        if (status != null) ...[
          if (status.restrictions.isEmpty)
            const _PanelCard(
              key: ValueKey('restricted-none-active'),
              title: 'No active restriction on this role',
              lines: [
                'The selected role is not active. Refresh after a reviewer '
                    'decision, or switch role from the log-in screen.',
              ],
            ),
          for (final restriction in status.restrictions)
            _RestrictionCard(
              key: ValueKey('restricted-${restriction.id}'),
              restriction: restriction,
              appealBody: _appealBody,
              submitting: _submitting,
              onSubmit: () => _submitAppeal(restriction.id),
            ),
          _PanelCard(
            key: const ValueKey('restricted-contact-status'),
            title: 'Contact verification',
            lines: [
              'Email verified: ${status.emailVerified ? 'yes' : 'no'}',
              'Phone verified: ${status.phoneVerified ? 'yes' : 'no'}',
              'Reviewed evidence: ${status.reviewStatus}',
            ],
          ),
        ],
        if (_submitError != null)
          _PanelNote(
            key: const ValueKey('restricted-appeal-error'),
            text: _submitError!,
          ),
        const SizedBox(height: 8),
        BuyerPrimaryButton(
          key: const ValueKey('restricted-refresh'),
          label: controller.busy ? 'Checking...' : 'Refresh status',
          onPressed: controller.busy ? null : _refresh,
        ),
        if (widget.onSupport != null) ...[
          const SizedBox(height: 8),
          BuyerSecondaryButton(
            key: const ValueKey('restricted-support'),
            label: 'Contact support',
            onPressed: widget.onSupport,
          ),
        ],
        SizedBox(height: 8),
        BuyerSecondaryButton(
          key: const ValueKey('restricted-logout'),
          label: 'Log out',
          onPressed: controller.busy ? null : _logout,
        ),
        if (_logoutError != null)
          Text(
            _logoutError!,
            key: const ValueKey('real-account-gate-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xffb3261e),
            ),
          ),
      ],
    );
  }
}

class _RestrictionCard extends StatelessWidget {
  const _RestrictionCard({
    required this.restriction,
    required this.appealBody,
    required this.submitting,
    required this.onSubmit,
    super.key,
  });

  final AccountRestrictionView restriction;
  final TextEditingController appealBody;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '${restriction.scope} restriction',
      lines: [restriction.reason],
      footer: restriction.canAppeal
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: appealBody,
                  enabled: !submitting,
                  maxLines: 2,
                  decoration: buyerInputDecoration(
                    context,
                    hintText: 'Explain what happened',
                  ).copyWith(labelText: 'Appeal note'),
                ),
                const SizedBox(height: 8),
                BuyerSecondaryButton(
                  key: const ValueKey('restricted-appeal-submit'),
                  compact: true,
                  label: 'Submit appeal',
                  onPressed: submitting ? null : onSubmit,
                ),
              ],
            )
          : BuyerStatusChip(
              label: 'Appeal ${restriction.appealStatus ?? 'submitted'}',
              key: const ValueKey('restricted-appeal-status'),
              icon: Icons.hourglass_top_rounded,
              tone: BuyerNoticeTone.neutral,
            ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.lines,
    this.footer,
    super.key,
  });

  final String title;
  final List<String> lines;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Container(
      margin: EdgeInsets.only(bottom: metrics.spacing(10)),
      padding: metrics.geometryInsets(const EdgeInsets.all(14)),
      decoration: BoxDecoration(
        color: BuyerUiTokens.surface,
        borderRadius: BorderRadius.circular(metrics.geometry(14)),
        border: Border.all(color: BuyerUiTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.cardTitle,
                ).copyWith(fontSize: metrics.fontSize(13.5)),
          ),
          for (final line in lines)
            Padding(
              padding: EdgeInsets.only(top: metrics.spacing(4)),
              child: Text(
                line,
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.secondaryBody,
                ),
              ),
            ),
          if (footer != null) ...[
            SizedBox(height: metrics.spacing(6)),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote({
    required this.text,
    this.tone = BuyerNoticeTone.neutral,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String text;
  final BuyerNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.spacing(8)),
      child: BuyerStateNotice(
        icon: switch (tone) {
          BuyerNoticeTone.error => Icons.error_outline_rounded,
          BuyerNoticeTone.warning => Icons.warning_amber_rounded,
          BuyerNoticeTone.success => Icons.check_circle_rounded,
          _ => Icons.info_outline_rounded,
        },
        tone: tone,
        title: text,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}
