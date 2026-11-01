library;
import 'dart:async';
import '../../data/phase2/maps/places_contract.dart';

import 'package:hocalist/theme/adaptive_palette.dart';

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
    this.onAddLocation,
    this.onSearchLocations,
    this.onSelectLocation,
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
  final VoidCallback? onAddLocation;
  final Future<List<PlaceSuggestion>> Function(String)? onSearchLocations;
  final Future<SellerDiscoveryOriginInput> Function(PlaceSuggestion)? onSelectLocation;

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

  SellerDiscoveryOriginInput? _resolved;
  bool _resolving = false;
  String? _confirmedArea;
  bool get locationMissing => _confirmedArea != _areaController.text.trim() ||
      (_resolved == null && widget.initial?.coordinatesPresent != true);

  Timer? _searchTimer;
  int _searchEpoch = 0;
  List<PlaceSuggestion> _suggestions = [];
  bool _searching = false;
  void _search(String query) {
    _searchTimer?.cancel();
    final epoch = ++_searchEpoch;
    setState(() { _resolved = null; _error = null; _suggestions = []; _searching = false; });
    if (query.trim().length < 2 || widget.onSearchLocations == null) return;
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      try {
        final options = await widget.onSearchLocations!(query.trim());
        if (!mounted || epoch != _searchEpoch) return;
        setState(() { _suggestions = options; if (options.isEmpty) _error = 'No matching places. Try another search.'; });
      } catch (_) {
        if (mounted && epoch == _searchEpoch) setState(() => _error = 'Location search is unavailable. Try again.');
      } finally {
        if (mounted && epoch == _searchEpoch) setState(() => _searching = false);
      }
    });
  }
  Future<void> _selectLocation(PlaceSuggestion suggestion) async {
    final resolve = widget.onSelectLocation;
    if (resolve == null || _resolving) return;
    final query = _areaController.text.trim();
    setState(() { _resolving = true; _error = null; });
    try {
      final place = await resolve(suggestion);
      if (!mounted || query != _areaController.text.trim()) return;
      if (place.latitude == null || place.longitude == null) throw StateError('Unresolved location');
      setState(() {
        _resolved = place;
        _suggestions = [];
        _areaController.text = place.areaLabel ?? query;
        _confirmedArea = _areaController.text.trim();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'This location could not be confirmed. Try a more specific place.');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _areaController = TextEditingController(
      text: widget.initial?.areaLabel ?? '',
    );
    final radius = widget.initial?.radiusMiles;
    _radius = radius ?? 25;
    _confirmedArea = widget.initial?.coordinatesPresent == true ? _areaController.text.trim() : null;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchEpoch++;
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
    if (locationMissing) return;
    final area = _areaController.text.trim();
    final input = SellerDiscoveryOriginInput(
      areaLabel: area.isEmpty ? null : area,
      radiusMiles: _radius,
      latitude: _resolved?.latitude,
      longitude: _resolved?.longitude,
    );
    if (!_sameAsLastAttempt(input)) {
      _operationKey =
          (widget.newOperationKey ??
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
    } catch (_) {
      if (mounted) setState(() => _error = 'The search could not be saved. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The modal route is mounted above the page's scope, so the sheet provides
    // its own resolved replica metrics for the approved seller controls.
    final metrics = ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: SellerModalSheet(
        key: const Key('sellerDiscoveryOriginSheet'),
        icon: Icons.explore_outlined,
        title: 'Choose location',
        subtitle: 'Choose where to search for customers.',
        onClose: () => Navigator.of(context).pop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search around your Business / Store location or choose another place. '
              'Changing this search does not change your saved business address.',
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
              enabled: !_saving && !_resolving,
              onChanged: _search,
              style: sellerInputText(metrics),
              decoration: InputDecoration(
                hintText: 'For example: Yonkers, NY',
                hintStyle: sellerInputPlaceholder(metrics),
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  color: HocalistPalette.text(context, SellerUiColors.body),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                    color: HocalistPalette.border(
                      context,
                      SellerUiColors.lavenderBorder,
                    ),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                    color: HocalistPalette.border(
                      context,
                      SellerUiColors.primaryBright,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_searching || _resolving)
              SellerProgressStrip(label: _resolving ? 'Setting location…' : 'Finding places…'),
            if (_suggestions.isNotEmpty)
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder))),
                child: Column(children: [
                  for (final option in _suggestions) Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('sellerSearchPlace-' + option.placeId),
                      onTap: _resolving ? null : () => _selectLocation(option),
                      child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                        Icon(Icons.location_on_outlined, size: 20, color: HocalistPalette.text(context, SellerUiColors.primaryBright)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(option.label, style: sellerText(metrics, 12, weight: FontWeight.w600))),
                      ])),
                    ),
                  ),
                ]),
              ),
            Row(children: [
              Text('Radius', style: sellerText(metrics, 11.5)),
              const SizedBox(width: 10),
              if (locationMissing) Flexible(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_areaController.text.trim().isEmpty ? 'Location missing.' : 'Confirm location.', style: sellerText(metrics, 11.5)),
                TextButton(key: const Key('sellerDiscoveryAddLocation'),
                  onPressed: widget.onAddLocation,
                  child: Text('Add location', style: sellerText(metrics, 11.5).copyWith(decoration: TextDecoration.underline))),
              ])),
            ]),
            AbsorbPointer(
              absorbing: _saving || locationMissing,
              child: Opacity(opacity: locationMissing ? 0.45 : 1,
              child: HocalistSelectMenu<int>(
              key: const Key('sellerDiscoveryOriginRadius'),
              role: HocalistControlRole.seller,
              value: _radius,
              options: ({..._radii, _radius}.toList()..sort()),
              labelBuilder: (value) => '$value mi',
              selectedLabelBuilder: (value) => locationMissing ? 'Set location first' : 'Within $value miles',
              onSelected: (value) {
                if (!_saving && !locationMissing) setState(() => _radius = value);
              },
              leading: Icons.radar_outlined,
              expanded: true,
            ))),
            const SizedBox(height: 8),
            if (!locationMissing) Align(
              alignment: Alignment.centerLeft,
              child: SellerStatusChip(
                key: const Key('sellerDiscoveryOriginSelected'),
                label: 'Selected: within $_radius miles',
                icon: Icons.check_circle_rounded,
                selected: true,
              ),
            ),
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SellerPrimaryButton(
                    key: const Key('sellerDiscoveryOriginSave'),
                    label: _saving ? 'Saving…' : 'Save area',
                    onPressed: _saving || locationMissing ? null : _save,
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
