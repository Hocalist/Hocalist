import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../../data/phase2/media/image_gateway.dart';
import '../../data/phase2/trust/trust_backend.dart';
import '../../theme/seller_ui_foundation.dart';
import '../media/private_image_picker.dart';
import '../media/private_remote_image.dart';

/// Manual review status and appeal entry for a signed-in seller.
///
/// Reviewed evidence is shown separately from Auth email/phone verification.
/// A report never restricts an account by itself; the panel only renders the
/// server's recorded restrictions and their appeal route.
class VerificationReviewPanel extends StatefulWidget {
  const VerificationReviewPanel({
    required this.load,
    required this.submit,
    required this.appeal,
    this.evidenceUpload,
    this.attachEvidence,
    this.detachEvidence,
    this.onStatusChanged,
    this.readEvidence,
    super.key,
  });

  final Future<TrustStatusView> Function() load;
  final VoidCallback? onStatusChanged;
  final Future<Uint8List> Function(String id)? readEvidence;
  final Future<VerificationItemView> Function(
    String kind,
    String note,
    String operationKey,
  )
  submit;
  final Future<void> Function(
    String restrictionId,
    String body,
    String operationKey,
  )
  appeal;

  /// Private review-purpose uploader. Null keeps evidence attach unavailable.
  final ImageUpload? evidenceUpload;
  final Future<EvidenceMutationView> Function(
    String submissionId,
    List<String> mediaIds,
    String operationKey,
  )?
  attachEvidence;
  final Future<EvidenceMutationView> Function(
    String submissionId,
    String mediaId,
    String operationKey,
  )?
  detachEvidence;

  @override
  State<VerificationReviewPanel> createState() =>
      _VerificationReviewPanelState();
}

class _VerificationReviewPanelState extends State<VerificationReviewPanel> {
  final note = TextEditingController();
  final appealBody = TextEditingController();
  String kind = 'identity';
  TrustStatusView? status;
  bool busy = true;
  bool showHistory = false;
  bool photoBusy = false;
  bool submitting = false;
  String? error;
  String? submitError;
  String? operationKey;
  ({String kind, String note})? submissionIntent;
  String? appealRestrictionId;
  String? appealKey;
  String? appealIntentBody;
  List<String> attachmentIds = const <String>[];
  String? attachKey;
  List<String>? frozenAttachmentIds;
  bool attachmentUncertain = false;
  int pickerGeneration = 0;
  final detachKeys = <String, String>{};
  int generation = 0;

  Future<void> detachSaved(VerificationItemView item, String mediaId) async {
    final detach = widget.detachEvidence;
    if (detach == null || submitting || item.status != 'pending') return;
    final intent = '${item.id}/$mediaId';
    final key = detachKeys.putIfAbsent(intent, () => UniqueKey().toString());
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      await detach(item.id, mediaId, key);
      if (!mounted) return;
      detachKeys.remove(intent);
      setState(() => submitting = false);
      await refresh();
    } on TrustUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = failure.message;
        if (!failure.outcomeUncertain) detachKeys.remove(intent);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = 'Removal was not confirmed. Retry the same saved photo.';
      });
    }
  }

  Future<void> attachToPending(VerificationItemView item) async {
    final attach = widget.attachEvidence;
    if (attach == null || submitting || attachmentIds.isEmpty) return;
    attachKey ??= UniqueKey().toString();
    frozenAttachmentIds ??= List.unmodifiable(attachmentIds);
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      await attach(item.id, frozenAttachmentIds!, attachKey!);
      if (!mounted) return;
      attachKey = null;
      frozenAttachmentIds = null;
      attachmentUncertain = false;
      pickerGeneration++;
      attachmentIds = const <String>[];
      setState(() => submitting = false);
      await refresh();
    } on TrustUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = failure.message;
        attachmentUncertain = failure.outcomeUncertain;
        if (!failure.outcomeUncertain) {
          attachKey = null;
          frozenAttachmentIds = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        attachmentUncertain = true;
        submitError = 'Attachment was not confirmed. Retry the same photos.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    generation++;
    note.dispose();
    appealBody.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.load();
      if (!mounted || run != generation) return;
      setState(() => status = value);
      widget.onStatusChanged?.call();
    } catch (_) {
      if (!mounted || run != generation) return;
      setState(() => error = 'Review status could not be loaded.');
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (submitting || photoBusy) return;
    final text = submissionIntent?.note ?? note.text.trim();
    if (text.length < 10) {
      setState(
        () => submitError = 'Describe the evidence in at least 10 characters.',
      );
      return;
    }
    operationKey ??= UniqueKey().toString();
    submissionIntent ??= (kind: kind, note: text);
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      final created = await widget.submit(
        submissionIntent!.kind,
        text,
        operationKey!,
      );
      if (!mounted) return;
      operationKey = null;
      submissionIntent = null;
      note.clear();
      setState(() => submitting = false);
      await refresh();
      if (mounted && attachmentIds.isNotEmpty) await attachToPending(created);
    } on TrustUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = failure.message;
        if (!failure.outcomeUncertain) {
          operationKey = null;
          submissionIntent = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError =
            'Submission was not confirmed. Retry the same evidence note.';
      });
    }
  }

  Future<void> sendAppeal(String restrictionId) async {
    if (submitting) return;
    if (appealKey != null && appealRestrictionId != restrictionId) {
      setState(
        () => submitError =
            'Confirm the pending appeal before submitting another.',
      );
      return;
    }
    final text = appealIntentBody ?? appealBody.text.trim();
    if (text.length < 10) {
      setState(
        () => submitError = 'Describe the appeal in at least 10 characters.',
      );
      return;
    }
    if (appealRestrictionId != restrictionId) {
      appealRestrictionId = restrictionId;
      appealKey = UniqueKey().toString();
    }
    appealIntentBody ??= text;
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      await widget.appeal(restrictionId, text, appealKey!);
      if (!mounted) return;
      appealRestrictionId = null;
      appealKey = null;
      appealIntentBody = null;
      appealBody.clear();
      setState(() => submitting = false);
      await refresh();
    } on TrustUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = failure.message;
        if (!failure.outcomeUncertain) {
          appealRestrictionId = null;
          appealKey = null;
          appealIntentBody = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = 'Appeal was not confirmed. Retry the same appeal note.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = status;
    final pending =
        current?.items.any((item) => item.status == 'pending') ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: const Key('verificationReviewPanel'),
      children: [
        if (busy) const SellerProgressStrip(label: 'Checking review status…'),
        if (error != null) ...[
          const SizedBox(height: 8),
          SellerStateNotice(
            key: const Key('verificationLoadError'),
            icon: Icons.cloud_off_rounded,
            tone: SellerNoticeTone.error,
            title: 'Review status unavailable',
            body: error,
            actionKey: const Key('verificationRetry'),
            actionLabel: 'Retry',
            onAction: busy ? null : refresh,
          ),
        ],
        if (current != null) ...[
          SellerStateNotice(
            icon: current.restrictions.isEmpty
                ? Icons.verified_user_outlined
                : Icons.report_gmailerrorred_outlined,
            tone: current.restrictions.isNotEmpty
                ? SellerNoticeTone.warning
                : current.reviewStatus == 'approved'
                ? SellerNoticeTone.success
                : current.reviewStatus == 'pending'
                ? SellerNoticeTone.brand
                : SellerNoticeTone.neutral,
            title: switch (current.reviewStatus) {
              'approved' => 'Review approved',
              'pending' => 'Under review',
              'rejected' => 'Review not approved',
              _ => 'Ready for review',
            },
            trailing: null,
            detail: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (current.items.isNotEmpty &&
                    current.items.first.decisionReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(current.items.first.decisionReason!),
                  ),
                if (current.items.isNotEmpty)
                  SellerSecondaryButton(
                    key: const Key('reviewHistoryToggle'),
                    label: showHistory
                        ? 'Hide review history'
                        : 'Review history',
                    onPressed: () => setState(() => showHistory = !showHistory),
                  ),
                if (showHistory && current.items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final item in current.items)
                        SellerStatusChip(
                          key: Key('reviewItem-${item.id}'),
                          label:
                              '${item.kind} · ${item.status}'
                              '${item.decisionReason == null ? '' : ' · ${item.decisionReason}'}',
                          icon: item.status == 'pending'
                              ? Icons.hourglass_top_rounded
                              : item.status == 'approved'
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          tone: item.status == 'pending'
                              ? SellerNoticeTone.brand
                              : item.status == 'approved'
                              ? SellerNoticeTone.success
                              : SellerNoticeTone.neutral,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final item
              in current.items
                  .where(
                    (item) =>
                        item.status == 'pending' ||
                        item.id == current.items.first.id,
                  )
                  .take(1)) ...[
            if (item.evidenceCount > 0)
              SellerStateNotice(
                key: Key('savedEvidence-${item.id}'),
                icon: Icons.attach_file_rounded,
                tone: SellerNoticeTone.neutral,
                title:
                    '${item.evidenceCount} saved evidence '
                    '${item.evidenceCount == 1 ? 'photo' : 'photos'}',
                body: 'Only you and our review team can see these photos.',
              ),
            if (item.evidenceMediaIds != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final id in item.evidenceMediaIds!)
                    Container(
                      width: 146,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: HocalistPalette.surface(context, SellerUiColors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: PrivateRemoteImage(
                            id: id,
                            size: 128,
                            showWholeImage: true,
                            read: widget.readEvidence,
                            ),
                          ),
                          if (item.status == 'pending' &&
                              widget.detachEvidence != null) ...[
                            const SizedBox(height: 6),
                            TextButton.icon(
                              key: Key('detachEvidence-$id'),
                              style: TextButton.styleFrom(
                                foregroundColor: HocalistPalette.text(context, SellerUiColors.primary),
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: Text(submitting
                                  ? 'Removing…'
                                  : detachKeys.containsKey('${item.id}/$id')
                                  ? 'Retry removal'
                                  : 'Remove photo'),
                              onPressed: submitting
                                  ? null
                                  : () => detachSaved(item, id),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                ),
              ),
          ],
          for (final restriction in current.restrictions)
            Container(
              key: Key('restriction-${restriction.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  SellerUiColors.redSurface,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: HocalistPalette.border(context, SellerUiColors.red),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 18,
                        color: HocalistPalette.text(
                          context,
                          SellerUiColors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${restriction.scope} restriction',
                          style: sellerText(
                            ApprovedReplicaScope.maybeOf(context) ??
                                ApprovedReplicaMetrics.resolve(
                                  brightness: Theme.of(context).brightness,
                                  availableWidth: MediaQuery.sizeOf(
                                    context,
                                  ).width,
                                  textScaler: MediaQuery.textScalerOf(context),
                                ),
                            13.5,
                            weight: FontWeight.w800,
                            color: SellerUiColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    restriction.reason,
                    style: sellerText(
                      ApprovedReplicaScope.maybeOf(context) ??
                          ApprovedReplicaMetrics.resolve(
                            brightness: Theme.of(context).brightness,
                            availableWidth: MediaQuery.sizeOf(context).width,
                            textScaler: MediaQuery.textScalerOf(context),
                          ),
                      12,
                      color: SellerUiColors.body,
                      height: 1.35,
                    ),
                  ),
                  if (restriction.canAppeal) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: appealBody,
                      enabled: !submitting && appealKey == null,
                      maxLines: 3,
                      style: sellerInputText(
                        ApprovedReplicaScope.maybeOf(context) ??
                            ApprovedReplicaMetrics.resolve(
                              brightness: Theme.of(context).brightness,
                              availableWidth: MediaQuery.sizeOf(context).width,
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                      ),
                      decoration: sellerInputDecoration(
                        context,
                        labelText: 'Appeal note',
                        hintText:
                            'Explain what happened. One appeal per restriction.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SellerSecondaryButton(
                      key: Key('appeal-${restriction.id}'),
                      label: 'Submit appeal',
                      onPressed: submitting
                          ? null
                          : () => sendAppeal(restriction.id),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SellerStatusChip(
                        key: Key('appealStatus-${restriction.id}'),
                        label:
                            'Appeal ${restriction.appealStatus ?? 'submitted'}',
                        icon: Icons.hourglass_top_rounded,
                        tone: SellerNoticeTone.neutral,
                      ),
                    ),
                ],
              ),
            ),
          if (widget.evidenceUpload != null &&
              widget.attachEvidence != null) ...[
            _ReviewSection(
              children: [
                const SizedBox(height: 10),
                Text(
                  'Photos for review',
                  key: const Key('verificationEvidenceTitle'),
                  style: sellerText(
                    ApprovedReplicaScope.maybeOf(context) ??
                        ApprovedReplicaMetrics.resolve(
                          brightness: Theme.of(context).brightness,
                          availableWidth: MediaQuery.sizeOf(context).width,
                          textScaler: MediaQuery.textScalerOf(context),
                        ),
                    13,
                    weight: FontWeight.w800,
                    color: SellerUiColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add clear photos for our review team. Your photos stay private.',
                  style: sellerText(
                    ApprovedReplicaScope.maybeOf(context) ??
                        ApprovedReplicaMetrics.resolve(
                          brightness: Theme.of(context).brightness,
                          availableWidth: MediaQuery.sizeOf(context).width,
                          textScaler: MediaQuery.textScalerOf(context),
                        ),
                    11.5,
                    color: SellerUiColors.body,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: const Key('verificationEvidencePicker'),
                  child: PrivateImagePicker(
                    key: ValueKey(pickerGeneration),
                    upload: widget.evidenceUpload!,
                    enabled:
                        !submitting &&
                        !attachmentUncertain &&
                        submissionIntent == null,
                    maxImages: 8,
                    showGuidance: false,
                    existingImageCount:
                        current.items
                            .where((item) => item.status == 'pending')
                            .firstOrNull
                            ?.evidenceCount ??
                        0,
                    onPendingChanged: (value) {
                      if (mounted) setState(() => photoBusy = value);
                    },
                    onChanged: (ids) {
                      if (!submitting && !attachmentUncertain) {
                        setState(() => attachmentIds = ids);
                      }
                    },
                  ),
                ),
                if (pending && attachmentIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SellerSecondaryButton(
                    key: const Key('verificationEvidenceAttach'),
                    label: attachmentUncertain
                        ? 'Retry attachment'
                        : 'Save photos to this review',
                    onPressed: submitting
                        ? null
                        : () {
                            for (final item in current.items) {
                              if (item.status == 'pending') {
                                attachToPending(item);
                                return;
                              }
                            }
                          },
                  ),
                ],
              ],
            ),
          ],
          if (!pending) ...[
            _ReviewSection(
              children: [
                const SellerSectionHeading(title: 'Review details'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('verificationKind'),
                  initialValue: kind,
                  isExpanded: true,
                  dropdownColor: HocalistPalette.surface(
                    context,
                    SellerUiColors.white,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  style: sellerInputText(
                    ApprovedReplicaScope.maybeOf(context) ??
                        ApprovedReplicaMetrics.resolve(
                          brightness: Theme.of(context).brightness,
                          availableWidth: MediaQuery.sizeOf(context).width,
                          textScaler: MediaQuery.textScalerOf(context),
                        ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'business',
                      child: Text('Business'),
                    ),
                    DropdownMenuItem(
                      value: 'identity',
                      child: Text('Identity'),
                    ),
                  ],
                  onChanged: submitting || submissionIntent != null
                      ? null
                      : (value) => setState(() => kind = value ?? 'business'),
                  decoration: sellerInputDecoration(
                    context,
                    labelText: 'What are you verifying?',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('verificationNote'),
                  controller: note,
                  enabled: !submitting && submissionIntent == null,
                  maxLines: 3,
                  style: sellerInputText(
                    ApprovedReplicaScope.maybeOf(context) ??
                        ApprovedReplicaMetrics.resolve(
                          brightness: Theme.of(context).brightness,
                          availableWidth: MediaQuery.sizeOf(context).width,
                          textScaler: MediaQuery.textScalerOf(context),
                        ),
                  ),
                  decoration: sellerInputDecoration(
                    context,
                    labelText: 'Note for the reviewer',
                    hintText: 'Tell us about the photos you are sending.',
                  ),
                ),
                if (submitError != null) ...[
                  const SizedBox(height: 8),
                  SellerStateNotice(
                    key: const Key('verificationSubmitError'),
                    icon: Icons.error_outline_rounded,
                    tone: SellerNoticeTone.error,
                    title: 'Submission was not confirmed',
                    body: submitError,
                  ),
                ],
                const SizedBox(height: 10),
                SellerPrimaryButton(
                  key: const Key('verificationSubmit'),
                  label: submitting ? 'Submitting…' : 'Submit for review',
                  onPressed: submitting || photoBusy ? null : send,
                ),
              ],
            ),
          ] else ...[
            if (submitError != null) ...[
              SellerStateNotice(
                key: const Key('verificationSubmitError'),
                icon: Icons.error_outline_rounded,
                tone: SellerNoticeTone.error,
                title: 'Photo change was not confirmed',
                body: submitError,
              ),
              const SizedBox(height: 8),
            ],
            SellerStateNotice(
              key: const Key('verificationPendingNotice'),
              icon: Icons.hourglass_top_rounded,
              tone: SellerNoticeTone.brand,
              title: 'A review is pending',
              body:
                  'Our team will check your submission. You can add or remove photos while you wait.',
            ),
          ],
          const SizedBox(height: 8),
          SellerSecondaryButton(
            key: const Key('verificationRefresh'),
            label: 'Refresh review status',
            onPressed: busy ? null : refresh,
          ),
          const SizedBox(height: 8),
          Text(
            'Our team reviews your submission. Sending photos does not mean your identity has been verified.',
            style: sellerText(
              ApprovedReplicaScope.maybeOf(context) ??
                  ApprovedReplicaMetrics.resolve(
                    brightness: Theme.of(context).brightness,
                    availableWidth: MediaQuery.sizeOf(context).width,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
              12,
              color: SellerUiColors.muted,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: HocalistPalette.surface(context, SellerUiColors.white),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: HocalistPalette.border(context, SellerUiColors.lavenderBorder),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}
