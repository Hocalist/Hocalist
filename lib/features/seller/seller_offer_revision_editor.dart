import 'package:flutter/material.dart';
import '../../data/local_marketplace_repository.dart';
import '../../domain/phase2/money.dart';
import '../../domain/phase2/offers.dart';
import '../../theme/seller_ui_foundation.dart';

/// Edits submitted offers only; the server decides eligibility and revision.
class SellerOfferRevisionEditor extends StatefulWidget {
  const SellerOfferRevisionEditor({
    required this.offer,
    required this.onSave,
    super.key,
  });
  final Offer offer;
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

  OfferTerms? _buildTerms() {
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
    final terms = widget.offer.latestRevision.terms.copyWith(
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

  Future<void> _save() async {
    if (_busy) return;
    final terms = _uncertain?.terms ?? _buildTerms();
    if (terms == null) return;
    final key =
        _uncertain?.key ??
        LocalMarketplaceRepository.newStoreOperationKey('offer-revise');
    setState(() {
      _busy = true;
      _error = null;
    });
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
      _uncertain = result.outcomeUncertain ? (terms: terms, key: key) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: SellerModalSheet(
        icon: Icons.edit_note_rounded,
        title: 'Update offer',
        subtitle:
            'Price and message can be changed here. The meeting time, place and '
            'existing photos stay as submitted.',
        onClose: () => Navigator.of(context).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('sellerOfferRevisionPrice'),
              controller: _price,
              readOnly: _busy || _uncertain != null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: sellerInputText(metrics),
              decoration: sellerInputDecoration(
                context,
                labelText:
                    'Price (${widget.offer.latestRevision.terms.price.currencyCode})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sellerOfferRevisionMessage'),
              controller: _message,
              readOnly: _busy || _uncertain != null,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              style: sellerInputText(metrics),
              decoration: sellerInputDecoration(
                context,
                labelText: 'Message to buyer',
              ).copyWith(counterText: ''),
            ),
            if (_busy) ...[
              const SizedBox(height: 10),
              const SellerProgressStrip(label: 'Saving update…'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              SellerStateNotice(
                key: const Key('sellerOfferRevisionError'),
                icon: Icons.error_outline_rounded,
                tone: SellerNoticeTone.error,
                title: 'Update not confirmed',
                body: _error,
              ),
            ],
            const SizedBox(height: 12),
            SellerPrimaryButton(
              key: const Key('sellerOfferRevisionSave'),
              onPressed: _busy ? null : _save,
              label: _busy
                  ? 'Saving…'
                  : _uncertain != null
                  ? 'Retry same update'
                  : 'Send updated offer',
            ),
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
