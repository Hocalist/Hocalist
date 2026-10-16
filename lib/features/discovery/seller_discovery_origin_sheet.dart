/// Seller discovery-origin editor (manual area and radius).
///
/// This is the reachable manual fallback for the seller's discovery origin:
/// the approved Leads screen opens it, it produces a client-owned operation
/// key once per intent, and the caller persists the origin through
/// `discovery_origin_set`. An uncertain failure keeps the same key for Retry;
/// a definitive failure starts a new intent. No coordinate picker is implied:
/// the map producer is out of this package, and saving a manual area replaces
/// previously picked coordinates explicitly.
library;

import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/discovery/discovery_adapter.dart';
import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';

class SellerDiscoveryOriginSheet extends StatefulWidget {
  const SellerDiscoveryOriginSheet({
    required this.initial,
    required this.onSave,
    this.newOperationKey,
    super.key,
  });

  /// Current server origin, if one is configured.
  final SellerDiscoveryOrigin? initial;

  /// Persists the origin and returns the authoritative server record. The
  /// callback receives the same operation key on every retry of one intent.
  final Future<SellerDiscoveryOrigin> Function(
    SellerDiscoveryOriginInput input,
    String operationKey,
  )
  onSave;

  /// Injectable key factory for tests; defaults to the repository's factory.
  final String Function(String prefix)? newOperationKey;

  @override
  State<SellerDiscoveryOriginSheet> createState() =>
      _SellerDiscoveryOriginSheetState();
}

class _SellerDiscoveryOriginSheetState
    extends State<SellerDiscoveryOriginSheet> {
  static const List<int> _radii = [5, 10, 25, 50, 100, 250];

  late final TextEditingController _areaController;
  late int _radius;
  bool _saving = false;
  String? _error;
  bool _outcomeUncertain = false;
  String? _operationKey;
  SellerDiscoveryOriginInput? _lastAttempt;

  bool get _coordinatesWillBeReplaced =>
      widget.initial?.coordinatesPresent ?? false;

  @override
  void initState() {
    super.initState();
    _areaController = TextEditingController(
      text: widget.initial?.areaLabel ?? '',
    );
    final radius = widget.initial?.radiusMiles;
    _radius = radius != null && _radii.contains(radius) ? radius : 25;
  }

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  bool _sameAsLastAttempt(SellerDiscoveryOriginInput input) {
    final last = _lastAttempt;
    if (last == null) return false;
    return last.areaLabel == input.areaLabel &&
        last.radiusMiles == input.radiusMiles &&
        last.latitude == input.latitude &&
        last.longitude == input.longitude;
  }

  Future<void> _save() async {
    final area = _areaController.text.trim();
    final input = SellerDiscoveryOriginInput(
      areaLabel: area.isEmpty ? null : area,
      radiusMiles: _radius,
    );
    if (!_sameAsLastAttempt(input)) {
      _operationKey = (widget.newOperationKey ??
          LocalMarketplaceRepository.newStoreOperationKey)('discovery-origin');
    }
    _lastAttempt = input;
    final key = _operationKey!;
    setState(() {
      _saving = true;
      _error = null;
      _outcomeUncertain = false;
    });
    try {
      final saved = await widget.onSave(input, key);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on StoreBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _outcomeUncertain = error.ambiguous;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The modal route is mounted above the page's scope, so the sheet provides
    // its own resolved replica metrics for the approved seller controls.
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: SellerModalSheet(
      key: const Key('sellerDiscoveryOriginSheet'),
      icon: Icons.explore_outlined,
      title: 'Discovery area',
      subtitle: 'Where buyers should see your offers and Store listings.',
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set the area you serve. Leads use this area and your radius for '
            'approximate distance matching; exact buyer addresses are never '
            'shared with you.',
            style: sellerText(
              metrics,
              11.5,
              color: SellerUiColors.body,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('sellerDiscoveryOriginArea'),
            controller: _areaController,
            enabled: !_saving,
            style: sellerInputText(metrics),
            decoration: InputDecoration(
              hintText: 'For example: Yonkers, NY',
              hintStyle: sellerInputPlaceholder(metrics),
              prefixIcon: const Icon(
                Icons.location_on_outlined,
                color: SellerUiColors.body,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: SellerUiColors.lavenderBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: SellerUiColors.primaryBright),
              ),
            ),
          ),
          const SizedBox(height: 10),
          HocalistSelectMenu<int>(
            key: const Key('sellerDiscoveryOriginRadius'),
            role: HocalistControlRole.seller,
            value: _radius,
            options: _radii,
            labelBuilder: (value) => '$value mi',
            selectedLabelBuilder: (value) => 'Within $value miles',
            onSelected: (value) {
              if (!_saving) setState(() => _radius = value);
            },
            leading: Icons.radar_outlined,
            expanded: true,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SellerStatusChip(
              key: const Key('sellerDiscoveryOriginSelected'),
              label: 'Selected: within $_radius miles',
              icon: Icons.check_circle_rounded,
              selected: true,
            ),
          ),
          if (_coordinatesWillBeReplaced) ...[
            const SizedBox(height: 10),
            const SellerStateNotice(
              key: Key('sellerDiscoveryOriginCoordinateNotice'),
              icon: Icons.pin_drop_outlined,
              title: 'Picked coordinates will be replaced',
              body:
                  'Saving a manual area replaces the coordinates picked for '
                  'this account. Use the map picker when it becomes available '
                  'to keep an exact origin.',
              tone: SellerNoticeTone.warning,
            ),
          ],
          if (_saving) ...[
            const SizedBox(height: 12),
            const SellerProgressStrip(label: 'Saving discovery area…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            SellerStateNotice(
              key: const Key('sellerDiscoveryOriginError'),
              icon: _outcomeUncertain
                  ? Icons.sync_problem_rounded
                  : Icons.error_outline_rounded,
              title: 'Area was not saved',
              body: _outcomeUncertain
                  ? '$_error Retry to check safely; the same area change will '
                        'not be applied twice.'
                  : _error!,
              tone: SellerNoticeTone.error,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SellerSecondaryButton(
                  label: 'Cancel',
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SellerPrimaryButton(
                  key: const Key('sellerDiscoveryOriginSave'),
                  label: _saving ? 'Saving…' : 'Save area',
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}


