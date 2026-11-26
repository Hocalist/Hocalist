import 'package:flutter/material.dart';
import 'lower_offer_confirmation.dart';
import '../../data/phase2/media/image_gateway.dart';
import 'approved_seller_leads_page.dart';
import '../../data/local_marketplace_repository.dart';
import '../../domain/phase2/money.dart';
import '../../domain/phase2/offers.dart';
import '../../theme/seller_ui_foundation.dart';

/// Edits submitted offers only; the server decides eligibility and revision.
class SellerOfferRevisionEditor extends StatefulWidget {
  const SellerOfferRevisionEditor({
    required this.offer,
    required this.onSave,
    this.onWithdraw,
    this.withdrawalEligibility,
    this.lead,
    this.uploadImage,
    this.choosePlace,
    this.resolveBusiness,
    this.businessAddress,
    this.addBusinessAddress,
    super.key,
  });
  final Offer offer;
  final Future<bool>? withdrawalEligibility;
  final SellerLeadView? lead;
  final ImageUpload? uploadImage;
  final SellerOfferPlacePicker? choosePlace, resolveBusiness;
  final String? Function()? businessAddress;
  final Future<void> Function()? addBusinessAddress;
  final Future<SellerOfferActionResult> Function()? onWithdraw;
  final Future<SellerOfferActionResult> Function(OfferTerms terms, String key)
  onSave;
  @override
  State<SellerOfferRevisionEditor> createState() =>
      _SellerOfferRevisionEditorState();
}

class _SellerOfferRevisionEditorState extends State<SellerOfferRevisionEditor> {
  late final TextEditingController _price;
  late final TextEditingController _message;
  String? _error;
  bool _busy = false;
  bool _ambiguousTime = false;
  bool _withdrawing = false;
  bool _retryWithdrawal = false;
  ({OfferTerms terms, String key})? _uncertain;

  @override
  void initState() {
    super.initState();
    final terms = widget.offer.latestRevision.terms;
    final cents = terms.price.minorUnits;
    _price = TextEditingController(
      text: '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}',
    );
    _message = TextEditingController(text: terms.message);
  }

  @override
  void dispose() {
    _price.dispose();
    _message.dispose();
    super.dispose();
  }

  OfferTerms? _buildTerms(OfferTerms? Function() readDraft) {
    final raw = _price.text.trim();
    if (!RegExp(r'^[0-9]{1,9}(\.[0-9]{1,2})?$').hasMatch(raw)) {
      setState(
        () => _error =
            'Enter a valid positive price with up to two decimal places.',
      );
      return null;
    }
    final parts = raw.split('.');
    final cents =
        int.parse(parts.first) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
    if (cents == 0) {
      setState(() => _error = 'Enter a price greater than zero.');
      return null;
    }
    final draft = readDraft();
    if (draft == null) return null;
    final terms = draft.copyWith(
      price: Money(
        minorUnits: cents,
        currencyCode: widget.offer.latestRevision.terms.price.currencyCode,
      ),
      message: _message.text.trim(),
    );
    if (terms.validationIssues().isNotEmpty) {
      setState(() => _error = terms.validationIssues().first.message);
      return null;
    }
    return terms;
  }

  Future<void> _save(OfferTerms? Function() readDraft) async {
    if (_busy || _retryWithdrawal) return;
    final terms = _uncertain?.terms ?? _buildTerms(readDraft);
    if (terms == null) return;
    final key =
        _uncertain?.key ??
        LocalMarketplaceRepository.newStoreOperationKey('offer-revise');
    setState(() {
      _busy = true;
      _error = null;
    });
    final minimum = widget.offer.requestMinimumMinor;
    if (_uncertain == null && minimum != null && terms.price.minorUnits < minimum) {
      final confirmed = await confirmLowerOffer(context, terms.price.minorUnits, minimum);
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _busy = false);
        return;
      }
    }
    SellerOfferActionResult result;
    try {
      result = await widget.onSave(terms, key);
    } catch (_) {
      result = const SellerOfferActionResult.failure(
        'The update was not confirmed. Retry the same details.',
        outcomeUncertain: true,
      );
    }
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(result.offer);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.error ?? 'Could not update the offer.';
      _ambiguousTime = result.ambiguousTime;
      _uncertain = result.outcomeUncertain ? (terms: terms, key: key) : null;
    });
  }

  Future<void> _withdraw() async {
    if (_busy || _uncertain != null || widget.onWithdraw == null) return;
    setState(() {
      _busy = true;
      _withdrawing = true;
      _error = null;
    });
    SellerOfferActionResult result;
    try {
      result = await widget.onWithdraw!();
    } catch (_) {
      result = const SellerOfferActionResult.failure(
        'Withdrawal was not confirmed. Retry to check the same offer.',
        outcomeUncertain: true,
      );
    }
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(result.offer);
      return;
    }
    setState(() {
      _busy = false;
      _retryWithdrawal = result.outcomeUncertain;
      _withdrawing = false;
      _error = result.error ?? 'Could not withdraw this offer.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final terms = widget.offer.latestRevision.terms;
    return SellerOfferForm(
      lead: widget.lead ?? SellerLeadView.fromOffer(widget.offer),
      sellerName: widget.offer.sellerDisplayName ?? 'Seller',
      presentation: const SellerOfferPresentation.real(),
      onChooseSpecificLocation: widget.choosePlace, resolveBusinessPlace: widget.resolveBusiness,
      readBusinessAddress: widget.businessAddress, onAddBusinessAddress: widget.addBusinessAddress,
      uploadImage: widget.uploadImage, automaticTimezone: true,
      edit: (
        terms: terms, price: _price, message: _message,
        locked: _busy || _uncertain != null || _retryWithdrawal,
        ambiguousTime: _ambiguousTime,
        actions: (readDraft, waiting) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) ...[
              const SizedBox(height: 10),
              SellerProgressStrip(label: _withdrawing ? 'Withdrawing offer…' : 'Saving update…'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              SellerStateNotice(
                key: const Key('sellerOfferRevisionError'),
                icon: Icons.error_outline_rounded,
                tone: SellerNoticeTone.error,
                title: 'Offer change not confirmed',
                body: _error,
              ),
            ],
            const SizedBox(height: 12),
            SellerPrimaryButton(
              key: const Key('sellerOfferRevisionSave'),
              onPressed: _busy || _retryWithdrawal || waiting ? null : () => _save(readDraft),
              label: _busy && !_withdrawing
                  ? 'Saving…'
                  : _uncertain != null
                  ? 'Retry same update'
                  : 'Save changes',
            ),
            if (widget.onWithdraw != null && widget.offer.status == OfferStatus.submitted && !widget.offer.requestClosed) ...[
              const SizedBox(height: 8),
              FutureBuilder<bool>(
                future: widget.withdrawalEligibility,
                builder: (_, approval) => (widget.withdrawalEligibility == null || approval.data == true)
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Align(alignment: Alignment.centerLeft,
                      child: SellerPlanBadge(label: 'Pro & Elite benefit')),
                    const SizedBox(height: 6),
                    SellerSecondaryButton(
                      key: const Key('sellerOfferWithdraw'),
                      color: SellerUiColors.red,
                      label: _retryWithdrawal ? 'Retry withdrawal' : 'Withdraw offer',
                      onPressed: _busy || _uncertain != null || waiting ? null : _withdraw,
                    ),
                  ]) : const SizedBox.shrink(),
              ),
            ],
            if (_uncertain != null) ...[
              const SizedBox(height: 8),
              SellerSecondaryButton(
                label: 'Discard retry',
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _uncertain = null;
                        _error =
                            'The previous update may have succeeded. Check your offers before starting a different update.';
                      }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
