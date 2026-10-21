/// Account data & deletion screen: consent records, own-data export and a
/// deletion REQUEST.
///
/// The screen never performs a deletion and never claims one happened. It
/// shows the recorded status and financial/safety holds the server reports.
/// Scope is Hocalist account records; provider sign-in identity removal is
/// handled separately by the account lifecycle service.
library;

import 'package:hocalist/theme/adaptive_palette.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import '../../components/account_role_components.dart';
import '../../components/hocalist_section_intro.dart';

import '../../data/phase2/accounts/account_lifecycle_backend.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';
import 'hocalist_account_controller.dart';

class AccountLifecyclePage extends StatefulWidget {
  const AccountLifecyclePage({
    required this.onBack,
    this.seller = false,
    this.backend,
    this.email,
    this.reauthenticate,
    this.isSessionCurrent,
    this.newOperationKey,
    super.key,
  });

  final VoidCallback onBack;
  final bool seller;

  /// Null keeps the honest unavailable state.
  final AccountLifecycleBackend? backend;
  final String? email;

  /// Confirms the account password before a deletion request is recorded.
  /// Null disables the request action instead of recording an unconfirmed
  /// request.
  final Future<void> Function(String password)? reauthenticate;

  /// Re-checked after password confirmation so a cleared or replaced session
  /// cannot record a deletion request. Null keeps the confirmation-only guard.
  final bool Function()? isSessionCurrent;

  /// Test seam for stable operation keys.
  final String Function()? newOperationKey;

  @override
  State<AccountLifecyclePage> createState() => _AccountLifecyclePageState();
}

class _AccountLifecyclePageState extends State<AccountLifecyclePage> {
  final _deletePassword = TextEditingController();
  AccountLifecycleStatusView? _status;
  AccountExportDocument? _document;
  bool _busy = false;
  String? _error;
  String? _message;
  String? _deleteError;
  int _generation = 0;
  String? _exportKey;
  String? _consentKey;
  String? _consentDocument;
  String? _deletionKey;

  String _newKey() => widget.newOperationKey?.call() ?? UniqueKey().toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _deletePassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final backend = widget.backend;
    if (backend == null) return;
    final run = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await backend.loadStatus();
      if (!mounted || run != _generation) return;
      setState(() => _status = status);
    } catch (_) {
      if (!mounted || run != _generation) return;
      setState(() => _error = 'Account lifecycle status could not be loaded.');
    } finally {
      if (mounted && run == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _accept(ConsentDocumentView document) async {
    final backend = widget.backend;
    if (backend == null || _busy) return;
    if (_consentDocument != document.id) {
      _consentDocument = document.id;
      _consentKey = _newKey();
    }
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await backend.recordConsent(
        documentId: document.id,
        version: document.version,
        operationKey: _consentKey!,
      );
      if (!mounted) return;
      setState(() {
        _consentDocument = null;
        _consentKey = null;
        _message = 'Consent recorded for ${document.label}.';
      });
      await _load();
    } on AccountLifecycleConflictException {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() {
        _consentDocument = null;
        _consentKey = null;
        _error = 'The consent version changed. Reload and review it again.';
      });
    } on AccountLifecycleUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        if (!failure.outcomeUncertain) {
          _consentDocument = null;
          _consentKey = null;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestExport() async {
    final backend = widget.backend;
    if (backend == null || _busy) return;
    _exportKey ??= _newKey();
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await backend.requestExport(operationKey: _exportKey!);
      if (!mounted) return;
      setState(() {
        _exportKey = null;
        _message = 'Export ready. Open it below any time.';
      });
      await _load();
    } on AccountLifecycleUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        if (!failure.outcomeUncertain) _exportKey = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openExport(AccountExportView export) async {
    final backend = widget.backend;
    if (backend == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final document = await backend.readExport(requestId: export.requestId);
      if (!mounted) return;
      setState(() => _document = document);
    } on AccountLifecycleUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final backend = widget.backend;
    final reauthenticate = widget.reauthenticate;
    if (backend == null || reauthenticate == null || _busy) return;
    _deletionKey ??= _newKey();
    setState(() {
      _busy = true;
      _deleteError = null;
      _message = null;
    });
    try {
      await reauthenticate(_deletePassword.text);
    } on AccountActionException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deleteError = error.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deleteError = 'Password confirmation failed. Check it and try again.';
      });
      return;
    }
    final sessionCheck = widget.isSessionCurrent;
    if (sessionCheck != null && !sessionCheck()) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deleteError =
            'The signed-in account changed. Sign in again to continue.';
      });
      return;
    }
    try {
      await backend.requestDeletion(operationKey: _deletionKey!);
      if (!mounted) return;
      _deletePassword.clear();
      setState(() {
        _deletionKey = null;
        _message = 'Deletion request recorded.';
      });
      await _load();
    } on AccountLifecycleUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        _deleteError = failure.message;
        if (!failure.outcomeUncertain) _deletionKey = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDeletion(AccountDeletionView deletion) async {
    final backend = widget.backend;
    if (backend == null || _busy) return;
    setState(() {
      _busy = true;
      _deleteError = null;
      _message = null;
    });
    try {
      await backend.cancelDeletion(
        requestId: deletion.requestId,
        expectedRevision: deletion.revision,
        operationKey: _newKey(),
      );
      if (!mounted) return;
      setState(() => _message = 'Deletion request cancelled.');
      await _load();
    } on AccountLifecycleConflictException {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(
        () => _deleteError = 'The request changed. Reload and try again.',
      );
    } on AccountLifecycleUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() => _deleteError = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                BuyerNestedHeader(
                  title: 'Account data & deletion',
                  subtitle: 'Consent records, your export and deletion.',
                  backKey: const ValueKey('lifecycle-back'),
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 16),
                if (_busy) const BuyerProgressStrip(label: 'Updating…'),
                if (_error != null) ...[
                  _LifecycleNote(
                    seller: widget.seller,
                    key: const ValueKey('lifecycle-error'),
                    text: _error!,
                    tone: BuyerNoticeTone.error,
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                ],
                if (_message != null)
                  _LifecycleNote(
                    seller: widget.seller,
                    key: const ValueKey('lifecycle-message'),
                    text: _message!,
                    tone: BuyerNoticeTone.success,
                  ),
                if (backend == null)
                  _LifecycleNote(
                    seller: widget.seller,
                    key: ValueKey('lifecycle-unavailable'),
                    text:
                        'Consent records, data export and deletion requests '
                        'are not available in this build yet.',
                  )
                else
                  ..._sections(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final status = _status;
    if (status == null) return const <Widget>[];
    return [
      _LifecycleSection(
        title: 'Consent records',
        icon: Icons.fact_check_outlined,
        children: [
          if (status.documents.isEmpty)
            const Text(
              'No consent documents are configured yet.',
              key: ValueKey('lifecycle-consent-empty'),
            )
          else
            for (final document in status.documents) ...[
              Text(
                '${document.label} · ${document.version}',
                key: ValueKey('lifecycle-consent-${document.id}'),
              ),
              const SizedBox(height: 6),
              if (document.isAcceptedBy(status.acceptedConsents))
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BuyerStatusChip(
                    label: 'Accepted',
                    key: ValueKey('lifecycle-consent-accepted'),
                    icon: Icons.check_circle_rounded,
                    tone: BuyerNoticeTone.success,
                  ),
                )
              else
                SizedBox(
                  width: 138,
                  child: BuyerSecondaryButton(
                    key: ValueKey('lifecycle-accept-${document.id}'),
                    compact: true,
                    label: 'Accept',
                    onPressed: _busy ? null : () => _accept(document),
                  ),
                ),
              const SizedBox(height: 10),
            ],
        ],
      ),
      _LifecycleSection(
        title: 'Your data export',
        icon: Icons.download_outlined,
        children: [
          Text(
            status.latestExport == null
                ? 'No export has been generated yet.'
                : 'Latest export: ${status.latestExport!.status} '
                      '· requested ${status.latestExport!.requestedAt.toLocal()}',
            key: const ValueKey('lifecycle-export-status'),
            style: TextStyle(
              fontSize: 12.5,
              color: HocalistPalette.text(context, BuyerUiTokens.muted),
            ),
          ),
          const SizedBox(height: 10),
          AccountActionButton(
            seller: widget.seller,
            key: const ValueKey('lifecycle-export-request'),
            label: _busy ? 'Preparing...' : 'Request my data export',
            onPressed: _busy ? null : _requestExport,
          ),
          if (status.latestExport?.isReady ?? false) ...[
            const SizedBox(height: 8),
            BuyerSecondaryButton(
              key: const ValueKey('lifecycle-export-open'),
              compact: true,
              label: 'Open latest export',
              onPressed: _busy ? null : () => _openExport(status.latestExport!),
            ),
          ],
          if (_document != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('lifecycle-export-document'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  BuyerUiTokens.softSurface,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                const JsonEncoder().convert(_document!.payload),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ],
      ),
      _LifecycleSection(
        title: 'Delete account',
        icon: Icons.person_remove_outlined,
        children: [
          const Text(
            'Request deletion of your Hocalist account records. Sign-in identity '
            'removal is handled separately. Financial or safety holds pause '
            'the request until they clear.',
            key: ValueKey('lifecycle-deletion-scope'),
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (status.openDeletion == null) ...[
            Text(
              widget.reauthenticate == null
                  ? 'Password confirmation is not available in this build, so '
                        'deletion requests are disabled.'
                  : (widget.email == null
                        ? 'Re-enter your password to record the request.'
                        : 'Re-enter the password for ${widget.email} to record '
                              'the request.'),
              style: TextStyle(
                fontSize: 12,
                color: HocalistPalette.text(context, BuyerUiTokens.muted),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('lifecycle-delete-password'),
              controller: _deletePassword,
              enabled: !_busy && widget.reauthenticate != null,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: buyerInputDecoration(
                context,
                hintText: 'Account password',
              ).copyWith(labelText: 'Account password'),
            ),
            if (_deleteError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _deleteError!,
                  key: const ValueKey('lifecycle-delete-error'),
                  style: TextStyle(
                    color: HocalistPalette.text(
                      context,
                      Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            BuyerPrimaryButton(
              key: const ValueKey('lifecycle-delete-request'),
              label: _busy ? 'Recording...' : 'Request account deletion',
              onPressed:
                  _busy ||
                      widget.reauthenticate == null ||
                      _deletePassword.text.isEmpty
                  ? null
                  : _requestDeletion,
            ),
          ] else ...[
            Text(
              'Deletion request: ${status.openDeletion!.status}'
              ' · recorded ${status.openDeletion!.requestedAt.toLocal()}',
              key: const ValueKey('lifecycle-deletion-status'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final hold in status.openDeletion!.holds)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Hold: ${hold.kind}'
                  '${hold.detail == null ? '' : ' (${hold.detail})'}',
                  key: ValueKey('lifecycle-hold-${hold.kind}'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: HocalistPalette.text(context, BuyerUiTokens.muted),
                  ),
                ),
              ),
            if (_deleteError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _deleteError!,
                  key: const ValueKey('lifecycle-delete-error'),
                  style: TextStyle(
                    color: HocalistPalette.text(
                      context,
                      Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (status.openDeletion!.cancelable)
              BuyerSecondaryButton(
                key: const ValueKey('lifecycle-delete-cancel'),
                label: 'Cancel deletion request',
                onPressed: _busy
                    ? null
                    : () => _cancelDeletion(status.openDeletion!),
              ),
          ],
        ],
      ),
    ];
  }
}

class _LifecycleSection extends StatelessWidget {
  const _LifecycleSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

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
    return Container(
      margin: EdgeInsets.only(bottom: metrics.spacing(16)),
      padding: metrics.geometryInsets(const EdgeInsets.all(16)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.surface),
        borderRadius: BorderRadius.circular(metrics.geometry(16)),
        border: Border.all(
          color: HocalistPalette.border(context, BuyerUiTokens.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HocalistSectionIntro(title: title, icon: icon),
          ...children,
        ],
      ),
    );
  }
}

class _LifecycleNote extends StatelessWidget {
  const _LifecycleNote({
    required this.text,
    required this.seller,
    this.tone = BuyerNoticeTone.neutral,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String text;
  final bool seller;
  final BuyerNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

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
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.spacing(12)),
      child: AccountStateNotice(
        seller: seller,
        icon: switch (tone) {
          BuyerNoticeTone.error => Icons.error_outline_rounded,
          BuyerNoticeTone.success => Icons.check_circle_rounded,
          BuyerNoticeTone.warning => Icons.warning_amber_rounded,
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
