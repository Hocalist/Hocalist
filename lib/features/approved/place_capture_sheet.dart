/// Place capture sheet: Places search, current location, map confirmation and
/// a manual fallback.
///
/// The sheet never reveals another participant's address; it returns the place
/// the user confirmed so the caller can submit it with the offer or request.
/// A provider failure keeps manual entry available (MAP-03/04/06).
library;

import 'package:hocalist/theme/adaptive_palette.dart';

import 'dart:async';
import '../../domain/phase2/common.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_flow_stages.dart';

import '../../data/phase2/maps/places_contract.dart';
import '../../data/phase2/maps/places_repository.dart';
import '../../theme/buyer_ui_foundation.dart';
import 'approved_replica_metrics.dart';
import 'hocalist_map_surface.dart';

/// How the confirmed place was captured.
enum PlaceCaptureSource { search, currentLocation, manual }

/// One device-location reading is defined in the maps contract so the data
/// layer and UI share one type. See [LocationReading].
@immutable
class PlaceCaptureResult {
  const PlaceCaptureResult({
    required this.label,
    required this.address,
    this.placeId,
    this.latitude,
    this.longitude,
    this.postalAddress,
    this.attributions = const <PlaceAttribution>[],
    required this.source,
  });

  final String label;
  final String address;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final PostalAddress? postalAddress;
  final List<PlaceAttribution> attributions;
  final PlaceCaptureSource source;

  bool get hasCoordinates => latitude != null && longitude != null;

  @override
  String toString() =>
      'PlaceCaptureResult(${source.name}, coordinates: $hasCoordinates)';
}

/// Shows the capture sheet and returns the confirmed place, or null.
Future<PlaceCaptureResult?> showPlaceCaptureSheet({
  required BuildContext context,
  PlacesRepository? places,
  HocalistMapBuilder? mapBuilder,
  LocationReader? locationReader,
  PlaceCaptureResult? initial,
  Future<List<String>> Function()? loadAreas,
}) {
  if (kIsWeb) {
    // ModalBottomSheetRoute adds an opaque semantics node over HTML platform
    // views. A dialog route keeps the same sheet while letting the map receive
    // pointer input; Close remains the explicit dismissal control.
    return showGeneralDialog<PlaceCaptureResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x990B1231),
      transitionDuration:
          MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.accessibleNavigationOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      pageBuilder: (sheetContext, animation, secondaryAnimation) => SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: PlaceCaptureSheet(
            places: places,
            mapBuilder: mapBuilder,
            locationReader: locationReader,
            initial: initial,
            loadAreas: loadAreas,
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
            child: child,
          ),
    );
  }
  return showModalBottomSheet<PlaceCaptureResult>(
    context: context,
    sheetAnimationStyle: HocalistMotion.sheetStyle(context),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: HocalistPalette.surface(context, Colors.transparent),
    barrierColor: const Color(0x990B1231),
    builder: (sheetContext) => PlaceCaptureSheet(
      places: places,
      mapBuilder: mapBuilder,
      locationReader: locationReader,
      initial: initial,
      loadAreas: loadAreas,
    ),
  );
}

class PlaceCaptureSheet extends StatefulWidget {
  const PlaceCaptureSheet({
    this.places,
    this.mapBuilder,
    this.locationReader,
    this.initial,
    this.loadAreas,
    super.key,
  });

  final PlacesRepository? places;
  final HocalistMapBuilder? mapBuilder;
  final LocationReader? locationReader;
  final PlaceCaptureResult? initial;
  final Future<List<String>> Function()? loadAreas;

  @override
  State<PlaceCaptureSheet> createState() => _PlaceCaptureSheetState();
}

class _PlaceCaptureSheetState extends State<PlaceCaptureSheet> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  Timer? _debounce;
  int _searchToken = 0;
  PlacesSession? _session;
  List<PlaceSuggestion> _suggestions = const <PlaceSuggestion>[];
  bool _searching = false;
  String? _searchError;
  bool _searchErrorIsValidation = false;
  String? _resolvingPlaceId;
  PlaceCaptureResult? _confirmed;
  bool _locating = false;
  String? _locationError;
  bool _manual = false;
  List<String> _areas = const [];
  bool _areasFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAreas());
    final initial = widget.initial;
    if (initial != null) {
      _confirmed = initial;
      _labelController.text = initial.label;
      _addressController.text = initial.address;
      _manual = initial.source == PlaceCaptureSource.manual;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _searchAvailable => widget.places != null;

  Future<void> _loadAreas() async {
    final load = widget.loadAreas;
    if (load == null) return;
    try {
      final areas = await load();
      if (mounted) {
        setState(() {
          _areas = areas;
          _areasFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _areasFailed = true);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (!_searchAvailable) return;
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = const <PlaceSuggestion>[];
        _searching = false;
        _searchError = null;
        _searchErrorIsValidation = false;
        _resolvingPlaceId = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final places = widget.places;
    if (places == null) return;
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchErrorIsValidation = false;
      _resolvingPlaceId = null;
    });
    try {
      final suggestions = await _runSearch(places, query, allowRestart: true);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _suggestions = suggestions;
        _searching = false;
      });
    } on PlacesFailure catch (failure) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _suggestions = const <PlaceSuggestion>[];
        _searchError = placesFailureMessage(failure);
      });
    }
  }

  /// Runs one autocomplete against the current session. When the server has
  /// discarded that session (expired, resolved or unknown), a fresh session is
  /// started once and the query is retried, so a stale token cannot strand the
  /// sheet while manual entry stays available.
  Future<List<PlaceSuggestion>> _runSearch(
    PlacesRepository places,
    String query, {
    required bool allowRestart,
  }) async {
    var session = _session;
    if (session == null || session.isExpiredAt(DateTime.now())) {
      session = PlacesSession.start();
      _session = session;
    }
    try {
      return await places.search(input: query, session: session);
    } on PlacesFailure catch (failure) {
      if (allowRestart && failure.code == PlacesFailureCode.sessionExpired) {
        _session = PlacesSession.start();
        return _runSearch(places, query, allowRestart: false);
      }
      rethrow;
    }
  }

  Future<void> _choose(PlaceSuggestion suggestion) async {
    final places = widget.places;
    if (places == null) return;
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _searchError = null;
      _resolvingPlaceId = suggestion.placeId;
    });
    try {
      final details = await _resolveSuggestion(
        places,
        suggestion,
        allowRestart: true,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _resolvingPlaceId = null;
        _suggestions = const <PlaceSuggestion>[];
        _queryController.text = suggestion.label;
        _session = null;
        _confirmed = PlaceCaptureResult(
          label: suggestion.label,
          address: details.address,
          postalAddress: details.postalAddress,
          placeId: details.placeId,
          latitude: details.latitude,
          longitude: details.longitude,
          attributions: details.attributions,
          source: PlaceCaptureSource.search,
        );
        _labelController.text = suggestion.label;
        _addressController.text = details.address;
      });
    } on PlacesFailure catch (failure) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _resolvingPlaceId = null;
        _searchError = placesFailureMessage(failure);
      });
    }
  }

  /// Resolves one suggestion against a session that has received it. When the
  /// session was replaced (client-side expiry) or the server reports that the
  /// suggestion is unknown, the current query is re-run with a fresh session
  /// before resolving once more.
  Future<PlaceDetails> _resolveSuggestion(
    PlacesRepository places,
    PlaceSuggestion suggestion, {
    required bool allowRestart,
  }) async {
    final query = _queryController.text.trim();
    var session = _session;
    if (session == null || session.isExpiredAt(DateTime.now())) {
      session = PlacesSession.start();
      _session = session;
      if (query.length >= 3) {
        await _runSearch(places, query, allowRestart: true);
        session = _session;
      }
    }
    try {
      return await places.resolve(
        placeId: suggestion.placeId,
        session: session!,
      );
    } on PlacesFailure catch (failure) {
      final recoverable =
          failure.code == PlacesFailureCode.suggestionRequired ||
          failure.code == PlacesFailureCode.sessionExpired;
      if (!allowRestart || !recoverable) rethrow;
      _session = PlacesSession.start();
      if (query.length >= 3) {
        await _runSearch(places, query, allowRestart: false);
      }
      return _resolveSuggestion(places, suggestion, allowRestart: false);
    }
  }

  Future<void> _useCurrentLocation() async {
    final reader = widget.locationReader;
    if (reader == null) {
      setState(
        () => _locationError =
            'Location is unavailable in this build. Enter the place manually.',
      );
      return;
    }
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final reading = await reader();
      if (!mounted) return;
      setState(() {
        _locating = false;
        _confirmed = PlaceCaptureResult(
          label: _labelController.text.trim().isEmpty
              ? 'Near my current location'
              : _labelController.text.trim(),
          address: _addressController.text.trim(),
          latitude: reading.latitude,
          longitude: reading.longitude,
          source: PlaceCaptureSource.currentLocation,
        );
      });
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError = switch (failure.code) {
          LocationFailureCode.denied =>
            'Location permission was not granted. Enter the place manually or '
                'allow location in settings.',
          LocationFailureCode.deniedForever =>
            'Location is blocked for Hocalist. Enable it in system settings or '
                'enter the place manually.',
          LocationFailureCode.serviceDisabled =>
            'Location services are turned off. Turn them on or enter the place '
                'manually.',
          LocationFailureCode.unavailable =>
            'Your location could not be read. Enter the place manually.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError =
            'Your location could not be read. Enter the place manually.';
      });
    }
  }

  void _movePin(HocalistCoordinates coordinates) {
    final current = _confirmed;
    if (current == null) return;
    setState(() {
      _confirmed = PlaceCaptureResult(
        label: current.label,
        address: current.address,
        postalAddress: current.postalAddress,
        placeId: current.placeId,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        attributions: current.attributions,
        source: current.source,
      );
    });
  }

  void _confirmManual() {
    final label = _labelController.text.trim();
    final address = _addressController.text.trim();
    if (label.isEmpty && address.isEmpty) {
      setState(() {
        _searchError = 'Enter a place name or address.';
        _searchErrorIsValidation = true;
      });
      return;
    }
    final current = _confirmed;
    Navigator.pop(
      context,
      PlaceCaptureResult(
        label: label.isEmpty ? address : label,
        address: address.isEmpty ? label : address,
        placeId: current?.placeId,
        latitude: current?.latitude,
        longitude: current?.longitude,
        attributions: current?.attributions ?? const <PlaceAttribution>[],
        source: PlaceCaptureSource.manual,
      ),
    );
  }

  void _confirm() {
    final confirmed = _confirmed;
    if (confirmed == null) {
      _confirmManual();
      return;
    }
    Navigator.pop(context, confirmed);
  }

  InputDecoration _placeInput({
    String? label,
    required String hint,
    IconData? icon,
    Widget? suffix,
  }) {
    final decoration = buyerInputDecoration(
      context,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, color: BuyerUiTokens.action),
    );
    return decoration.copyWith(
      labelText: label,
      suffixIcon: suffix,
      suffixIconConstraints: suffix == null
          ? null
          : const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  Widget _mapPreview(BuildContext context, PlaceCaptureResult confirmed) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final hasMap = widget.mapBuilder != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Map preview',
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.cardTitle,
                ).copyWith(fontSize: metrics.fontSize(12.5)),
              ),
            ),
            SizedBox(width: metrics.spacing(8)),
            Flexible(
              child: BuyerStatusChip(
                label: hasMap ? 'Pin movable' : 'Preview only',
                icon: hasMap
                    ? Icons.open_with_rounded
                    : Icons.visibility_outlined,
                tone: hasMap ? BuyerNoticeTone.brand : BuyerNoticeTone.neutral,
              ),
            ),
          ],
        ),
        SizedBox(height: metrics.spacing(6)),
        ClipRRect(
          borderRadius: BorderRadius.circular(metrics.geometry(14)),
          child: SizedBox(
            height: metrics.geometry(180),
            child: hasMap
                ? widget.mapBuilder!(
                    context,
                    latitude: confirmed.latitude!,
                    longitude: confirmed.longitude!,
                    onMoved: _movePin,
                  )
                : HocalistMapPlaceholder(
                    latitude: confirmed.latitude!,
                    longitude: confirmed.longitude!,
                  ),
          ),
        ),
        SizedBox(height: metrics.spacing(6)),
        Text(
          hasMap
              ? 'Move the pin if the meeting point is slightly '
                    'different. The other party sees the agreed place only.'
              : 'Confirm the searched address, or search again to choose '
                    'a different place. Pin movement needs the map preview.',
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.secondaryBody,
          ),
        ),
        for (final attribution in confirmed.attributions) ...[
          SizedBox(height: metrics.spacing(2)),
          Text(
            attribution.provider,
            key: ValueKey('hocalistPlaceAttribution-${attribution.provider}'),
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.metadata,
            ),
          ),
        ],
      ],
    );
  }

  Widget _confirmedCard(BuildContext context, PlaceCaptureResult confirmed) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      key: const Key('hocalistPlaceConfirmed'),
      padding: metrics.geometryInsets(const EdgeInsets.all(12)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
        borderRadius: BorderRadius.circular(metrics.geometry(14)),
        border: Border.all(
          color: HocalistPalette.border(context, const Color(0xffd9d5ff)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: metrics.artSize(30),
            height: metrics.artSize(30),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, Colors.white),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: BuyerGlyphIcon(
                icon: Icons.check_rounded,
                slotSize: metrics.artSize(18),
                glyphSize: metrics.artSize(18),
                color: HocalistPalette.text(context, BuyerUiTokens.action),
              ),
            ),
          ),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BuyerStatusChip(
                  label: 'Confirmed place',
                  icon: Icons.place_rounded,
                  tone: BuyerNoticeTone.brand,
                ),
                SizedBox(height: metrics.spacing(5)),
                Text(
                  confirmed.label,
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.cardTitle,
                  ).copyWith(fontSize: metrics.fontSize(13)),
                ),
                if (confirmed.address.isNotEmpty) ...[
                  SizedBox(height: metrics.spacing(2)),
                  Text(
                    confirmed.address,
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.secondaryBody,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmed;
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final query = _queryController.text.trim();
    final searchingQuery = _searching && _resolvingPlaceId == null;
    final showEmptySearch =
        _searchAvailable &&
        !_searching &&
        _searchError == null &&
        _suggestions.isEmpty &&
        query.length >= 3 &&
        confirmed == null;
    final stackActions =
        metrics.availableWidth < 360 || metrics.textScale > 1.15;
    final locationAction = OutlinedButton.icon(
      key: const Key('hocalistPlaceUseLocation'),
      onPressed: _locating ? null : _useCurrentLocation,
      style: OutlinedButton.styleFrom(
        foregroundColor: HocalistPalette.text(context, BuyerUiTokens.action),
        minimumSize: Size.fromHeight(metrics.geometry(44)),
        padding: EdgeInsets.symmetric(horizontal: metrics.geometry(10)),
        side: BorderSide(
          color: HocalistPalette.border(context, BuyerUiTokens.action),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(13)),
        ),
        textStyle: BuyerTypography.style(
          context,
          metrics,
          BuyerTextRole.buttonLabel,
        ).copyWith(fontSize: metrics.fontSize(12.5)),
      ),
      icon: Icon(Icons.my_location_rounded, size: metrics.artSize(17)),
      label: Text(_locating ? 'Locating…' : 'Use my location'),
    );
    final manualAction = OutlinedButton.icon(
      key: const Key('hocalistPlaceManualToggle'),
      onPressed: () => setState(() => _manual = !_manual),
      style: OutlinedButton.styleFrom(
        foregroundColor: HocalistPalette.text(context, BuyerUiTokens.action),
        backgroundColor: HocalistPalette.surface(
          context,
          _manual ? BuyerUiTokens.activeSurface : BuyerUiTokens.surface,
        ),
        minimumSize: Size.fromHeight(metrics.geometry(44)),
        padding: EdgeInsets.symmetric(horizontal: metrics.geometry(10)),
        side: BorderSide(
          color: HocalistPalette.border(
            context,
            _manual ? BuyerUiTokens.action : BuyerUiTokens.border,
          ),
          width: _manual ? 1.5 : 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(13)),
        ),
        textStyle: BuyerTypography.style(
          context,
          metrics,
          BuyerTextRole.buttonLabel,
        ).copyWith(fontSize: metrics.fontSize(12.5)),
      ),
      icon: Icon(
        _manual ? Icons.check_circle_rounded : Icons.edit_outlined,
        size: metrics.artSize(17),
      ),
      label: const Text('Enter manually'),
    );

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Material(
        key: const Key('hocalistPlaceCaptureSheet'),
        color: HocalistPalette.surface(context, BuyerUiTokens.surface),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 56,
              height: 5,
              decoration: BoxDecoration(
                color: HocalistPalette.surface(context, BuyerUiTokens.border),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.geometry(16),
                metrics.geometry(10),
                metrics.geometry(8),
                metrics.geometry(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: metrics.artSize(34),
                    height: metrics.artSize(34),
                    decoration: BoxDecoration(
                      color: HocalistPalette.surface(
                        context,
                        BuyerUiTokens.softSurface,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: BuyerGlyphIcon(
                        icon: Icons.place_outlined,
                        slotSize: metrics.artSize(18),
                        glyphSize: metrics.artSize(18),
                        color: HocalistPalette.text(
                          context,
                          BuyerUiTokens.action,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.spacing(10)),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: metrics.spacing(1)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose the meeting place',
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.pageTitle,
                              weight: FontWeight.w900,
                            ).copyWith(fontSize: metrics.fontSize(15.5)),
                          ),
                          SizedBox(height: metrics.spacing(3)),
                          Text(
                            'Search for a public place or use your current '
                            'location. The exact address is only shared with '
                            'the other party after the deal is agreed.',
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.secondaryBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: metrics.artSize(40),
                    child: IconButton(
                      key: const Key('hocalistPlaceCaptureClose'),
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      icon: BuyerGlyphIcon(
                        icon: Icons.close_rounded,
                        slotSize: metrics.artSize(22),
                        glyphSize: metrics.artSize(22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  metrics.geometry(16),
                  0,
                  metrics.geometry(16),
                  metrics.geometry(16),
                ),
                children: [
                  HocalistFlowStages(
                    key: const Key('hocalistPlaceStages'),
                    labels: const ['Find a place', 'Review & confirm'],
                    active: confirmed != null || _manual ? 1 : 0,
                  ),
                  SizedBox(height: metrics.spacing(16)),
                  if (_areas.isNotEmpty && _searchAvailable) ...[
                    Text(
                      'Suggested areas',
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.secondaryBody,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(6)),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final area in _areas)
                          ActionChip(
                            label: Text(area),
                            onPressed: () {
                              _queryController.text = area;
                              _onQueryChanged(area);
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                    SizedBox(height: metrics.spacing(10)),
                    Text(
                      'Choose an area to search, then confirm the exact place.',
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.secondaryBody,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(10)),
                  ],
                  if (_areasFailed)
                    TextButton(
                      onPressed: _loadAreas,
                      child: const Text('Reload suggested areas'),
                    ),
                  TextField(
                    key: const Key('hocalistPlaceSearchField'),
                    controller: _queryController,
                    onChanged: _onQueryChanged,
                    enabled: _searchAvailable,
                    decoration: _placeInput(
                      hint: _searchAvailable
                          ? 'Search a place or address'
                          : 'Place search is not configured — enter manually',
                      icon: Icons.search_rounded,
                      suffix: _queryController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _onQueryChanged('');
                                _queryController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                  ),
                  HocalistExpand(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (searchingQuery) ...[
                          SizedBox(height: metrics.spacing(10)),
                          BuyerProgressStrip(
                            key: const Key('hocalistPlaceSearching'),
                            label: 'Searching nearby places…',
                          ),
                        ],
                        if (_searchError != null) ...[
                          SizedBox(height: metrics.spacing(10)),
                          BuyerStateNotice(
                            key: const Key('hocalistPlaceSearchError'),
                            icon: _searchErrorIsValidation
                                ? Icons.edit_location_alt_outlined
                                : Icons.cloud_off_rounded,
                            tone: BuyerNoticeTone.warning,
                            title: _searchErrorIsValidation
                                ? 'Add a place to continue'
                                : 'Place search did not finish',
                            body: _searchError,
                            actionLabel: _manual || _searchErrorIsValidation
                                ? null
                                : 'Enter it manually',
                            onAction: _manual || _searchErrorIsValidation
                                ? null
                                : () => setState(() => _manual = true),
                          ),
                        ],
                        if (showEmptySearch) ...[
                          SizedBox(height: metrics.spacing(10)),
                          const BuyerStateNotice(
                            icon: Icons.search_off_rounded,
                            title: 'No places matched',
                            body:
                                'Try a different spelling, a nearby landmark, '
                                'or enter the place manually.',
                          ),
                        ],
                        for (final suggestion in _suggestions) ...[
                          SizedBox(height: metrics.spacing(8)),
                          Material(
                            key: ValueKey(
                              'hocalistPlaceSuggestion-${suggestion.placeId}',
                            ),
                            color: HocalistPalette.surface(
                              context,
                              BuyerUiTokens.surface,
                            ),
                            borderRadius: BorderRadius.circular(
                              metrics.geometry(13),
                            ),
                            child: InkWell(
                              onTap: _searching
                                  ? null
                                  : () => _choose(suggestion),
                              borderRadius: BorderRadius.circular(
                                metrics.geometry(13),
                              ),
                              child: Container(
                                padding: metrics.geometryInsets(
                                  const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 11,
                                  ),
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    metrics.geometry(13),
                                  ),
                                  border: Border.all(
                                    color: HocalistPalette.border(
                                      context,
                                      _resolvingPlaceId == suggestion.placeId
                                          ? BuyerUiTokens.action
                                          : BuyerUiTokens.border,
                                    ),
                                    width:
                                        _resolvingPlaceId == suggestion.placeId
                                        ? 1.5
                                        : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: metrics.artSize(32),
                                      height: metrics.artSize(32),
                                      decoration: BoxDecoration(
                                        color: HocalistPalette.surface(
                                          context,
                                          BuyerUiTokens.softSurface,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: BuyerGlyphIcon(
                                          icon: Icons.location_on_outlined,
                                          slotSize: metrics.artSize(18),
                                          glyphSize: metrics.artSize(18),
                                          color: HocalistPalette.text(
                                            context,
                                            BuyerUiTokens.action,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: metrics.spacing(10)),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            suggestion.label,
                                            style:
                                                BuyerTypography.style(
                                                  context,
                                                  metrics,
                                                  BuyerTextRole.cardTitle,
                                                ).copyWith(
                                                  fontSize: metrics.fontSize(
                                                    12.75,
                                                  ),
                                                ),
                                          ),
                                          SizedBox(height: metrics.spacing(2)),
                                          Text(
                                            _resolvingPlaceId ==
                                                    suggestion.placeId
                                                ? 'Resolving address…'
                                                : 'Place result',
                                            style: BuyerTypography.style(
                                              context,
                                              metrics,
                                              BuyerTextRole.metadata,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_resolvingPlaceId == suggestion.placeId)
                                      SizedBox.square(
                                        dimension: metrics.artSize(18),
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: BuyerUiTokens.action,
                                        ),
                                      )
                                    else
                                      BuyerGlyphIcon(
                                        icon: Icons.chevron_right_rounded,
                                        slotSize: metrics.artSize(20),
                                        glyphSize: metrics.artSize(20),
                                        color: HocalistPalette.text(
                                          context,
                                          BuyerUiTokens.muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: metrics.spacing(12)),
                  if (stackActions) ...[
                    locationAction,
                    SizedBox(height: metrics.spacing(8)),
                    manualAction,
                  ] else
                    Row(
                      children: [
                        Expanded(child: locationAction),
                        SizedBox(width: metrics.spacing(8)),
                        Expanded(child: manualAction),
                      ],
                    ),
                  if (_locating) ...[
                    SizedBox(height: metrics.spacing(10)),
                    const BuyerProgressStrip(label: 'Reading your location…'),
                  ],
                  if (_locationError != null) ...[
                    SizedBox(height: metrics.spacing(10)),
                    BuyerStateNotice(
                      key: const Key('hocalistPlaceLocationError'),
                      icon: Icons.location_off_outlined,
                      tone: BuyerNoticeTone.warning,
                      title: 'Location is not available',
                      body: _locationError,
                      actionLabel: _manual ? null : 'Enter it manually',
                      onAction: _manual
                          ? null
                          : () => setState(() => _manual = true),
                    ),
                  ],
                  HocalistExpand(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_manual || confirmed == null) ...[
                          SizedBox(height: metrics.spacing(12)),
                          TextField(
                            key: const Key('hocalistPlaceLabelField'),
                            controller: _labelController,
                            decoration: _placeInput(
                              label: 'Place name',
                              hint: 'e.g., Public library',
                            ),
                          ),
                          SizedBox(height: metrics.spacing(8)),
                          TextField(
                            key: const Key('hocalistPlaceAddressField'),
                            controller: _addressController,
                            decoration: _placeInput(
                              label: 'Address',
                              hint: 'Street, city',
                            ),
                          ),
                        ],
                        if (confirmed != null && confirmed.hasCoordinates) ...[
                          SizedBox(height: metrics.spacing(14)),
                          _mapPreview(context, confirmed),
                        ],
                        if (confirmed != null) ...[
                          SizedBox(height: metrics.spacing(12)),
                          _confirmedCard(context, confirmed),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.geometry(16),
                  metrics.geometry(8),
                  metrics.geometry(16),
                  metrics.geometry(12),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: BuyerPrimaryButton(
                    key: const Key('hocalistPlaceConfirm'),
                    onPressed: _confirm,
                    label: confirmed == null
                        ? 'Use this place'
                        : 'Confirm meeting place',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
