import 'package:hocalist/theme/adaptive_palette.dart';
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import '../../data/phase2/maps/device_location.dart';
import '../../data/phase2/maps/places_contract.dart';
import '../../data/phase2/maps/places_repository.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../data/phase2/maps/route_repository.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import 'hocalist_map_surface.dart';

class MeetingDirectionsPage extends StatefulWidget {
  const MeetingDirectionsPage({
    required this.meetingId,
    required this.destination,
    this.load = loadConfiguredMeetingRoute,
    this.mapBuilder,
    this.seller = false,
    this.places,
    this.locationReader = readForegroundLocation,
    this.destinationLatitude,
    this.destinationLongitude,
    this.destinationMapBuilder,
    super.key,
  });
  final String meetingId, destination;
  final MeetingRouteLoader load;
  final Widget Function(MeetingRoute)? mapBuilder;
  final bool seller;
  final PlacesRepository? places;
  final LocationReader locationReader;
  final double? destinationLatitude, destinationLongitude;
  final Widget Function(LatLng)? destinationMapBuilder;
  @override
  State<MeetingDirectionsPage> createState() => _MeetingDirectionsPageState();
}

class _MeetingDirectionsPageState extends State<MeetingDirectionsPage> {
  final origin = TextEditingController();
  final sheetController = DraggableScrollableController();
  bool editingStart = true;
  LatLng? destinationPoint;
  bool destinationLoading = false;

  @override
  void initState() {
    super.initState();
    final lat = widget.destinationLatitude, lng = widget.destinationLongitude;
    if (lat != null && lng != null && lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180) {
      destinationPoint = LatLng(lat, lng);
    } else if (widget.places != null) {
      destinationLoading = true;
      unawaited(loadDestination());
    }
  }

  Future<void> loadDestination() async {
    try {
      final place = await widget.places!.resolveAddress(widget.destination).timeout(const Duration(seconds: 12));
      if (mounted) setState(() => destinationPoint = LatLng(place.latitude, place.longitude));
    } catch (_) {
      // Route lookup can still use the confirmed address if map preview fails.
    } finally {
      if (mounted) setState(() => destinationLoading = false);
    }
  }
  String mode = 'DRIVE';
  bool busy = false;
  String? error;
  MeetingRoute? route;
  int generation = 0;
  Timer? debounce;
  int searchGeneration = 0;
  bool findingStart = false;
  int startGeneration = 0;
  String startProgress = 'Finding starting point…';
  void cancelStart() {
    startGeneration++;
    setState(() => findingStart = false);
  }
  List<PlaceSuggestion> suggestions = [];
  PlacesSession session = PlacesSession.start();

  void searchStart(String value) {
    if (findingStart) cancelStart();
    debounce?.cancel();
    final request = ++searchGeneration;
    setState(() { suggestions = []; route = null; error = null; });
    if (value.trim().length < 3 || widget.places == null) return;
    debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final rows = await widget.places!.search(input: value, session: session);
        if (mounted && request == searchGeneration) setState(() => suggestions = rows);
      } catch (_) {
        if (mounted && request == searchGeneration) {
          session = PlacesSession.start();
          setState(() => error = 'Address suggestions are unavailable. You can still enter a full address.');
        }
      }
    });
  }

  Future<void> chooseStart(PlaceSuggestion? suggestion) async {
    if (busy || findingStart) return;
    debounce?.cancel();
    ++searchGeneration;
    final request = ++startGeneration;
    bool current() => mounted && request == startGeneration;
    setState(() { findingStart = true; startProgress = suggestion == null ? 'Getting your location…' : 'Loading address…'; suggestions = []; error = null; route = null; });
    try {
      final places = widget.places;
      if (places == null) throw const PlacesFailure(PlacesFailureCode.unconfigured);
      final PlaceDetails place;
      if (suggestion != null) {
        place = await places.resolve(placeId: suggestion.placeId, session: session).timeout(const Duration(seconds: 12));
      } else {
        final position = await widget.locationReader().timeout(const Duration(seconds: 15));
        if (!current()) return;
        setState(() => startProgress = 'Finding your address…');
        place = await places.resolveCoordinates(latitude: position.latitude, longitude: position.longitude).timeout(const Duration(seconds: 12));
      }
      if (current()) setState(() { origin.text = place.address; });
    } catch (failure) {
      if (current()) setState(() => error = failure is TimeoutException
          ? 'Finding your location took too long. Try again or enter a starting address.'
          : failure is LocationFailure
          ? 'Your location is unavailable or permission was denied. Enter a starting address instead.'
          : 'That starting location could not be loaded. Enter an address or try again.');
    } finally {
      if (current()) {
        session = PlacesSession.start();
        setState(() => findingStart = false);
      }
    }
  }
  Widget notice(
    IconData icon,
    String title,
    String body, {
    bool failed = false,
  }) => widget.seller
      ? SellerStateNotice(
          icon: icon,
          title: title,
          body: body,
          tone: failed ? SellerNoticeTone.error : SellerNoticeTone.neutral,
        )
      : BuyerStateNotice(
          icon: icon,
          title: title,
          body: body,
          tone: failed ? BuyerNoticeTone.error : BuyerNoticeTone.neutral,
        );
  Future<void> findRoute() async {
    if (busy || findingStart) return;
    debounce?.cancel();
    ++searchGeneration;
    if (origin.text.trim().isEmpty || origin.text.length > 200) {
      setState(() => error = 'Enter a starting address, including the city.');
      return;
    }
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
      route = null;
      suggestions = [];
    });
    try {
      final result = await widget.load(
        widget.meetingId,
        origin.text.trim(),
        mode,
      );
      if (mounted && run == generation) {
        setState(() => route = result);
        setState(() => editingStart = false);
        if (sheetController.isAttached) {
          unawaited(sheetController.animateTo(.48, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
        }
      }
    } catch (failure) {
      if (mounted && run == generation) {
        setState(
          () => error = failure is RouteFailure
              ? failure.message
              : 'Directions could not be loaded. Please try again.',
        );
      }
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    searchGeneration++;
    startGeneration++;
    debounce?.cancel();
    origin.dispose();
    sheetController.dispose();
    super.dispose();
  }

  Widget routeMap(MeetingRoute value) {
    if (widget.mapBuilder != null) {
      return widget.mapBuilder!(value);
    }
    if (!mapSdkAvailable) {
      return notice(
        Icons.map_outlined,
        'Map needs configuration',
        'The directions below remain available.',
      );
    }
    final points = value.points
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    return GoogleMap(
      key: ValueKey(value),
      initialCameraPosition: CameraPosition(target: points.first, zoom: 13),
      myLocationButtonEnabled: false,
        padding: EdgeInsets.only(top: 90, bottom: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .48),
      zoomControlsEnabled: true,
      markers: {
        Marker(
          markerId: const MarkerId('start'),
          position: points.first,
          infoWindow: const InfoWindow(title: 'Start'),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: points.last,
          infoWindow: const InfoWindow(title: 'Meeting destination'),
        ),
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('meeting-route'),
          points: points,
          color: BuyerUiTokens.action,
          width: 5,
        ),
      },
      onMapCreated: (controller) {
        var south = points.first.latitude,
            north = south,
            west = points.first.longitude,
            east = west;
        for (final point in points) {
          if (point.latitude < south) south = point.latitude;
          if (point.latitude > north) north = point.latitude;
          if (point.longitude < west) west = point.longitude;
          if (point.longitude > east) east = point.longitude;
        }
        controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(south, west),
              northeast: LatLng(north, east),
            ),
            40,
          ),
        );
      },
    );
  }

  Widget destinationMap() {
    final point = destinationPoint;
    if (point != null && widget.destinationMapBuilder != null) return widget.destinationMapBuilder!(point);
    if (point != null && mapSdkAvailable) {
      return GoogleMap(
        key: const ValueKey('meeting-destination-map'),
        initialCameraPosition: CameraPosition(target: point, zoom: 14),
        myLocationButtonEnabled: false,
        padding: EdgeInsets.only(top: 90, bottom: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .48),
        mapToolbarEnabled: false,
        markers: {Marker(markerId: const MarkerId('destination'), position: point,
          infoWindow: const InfoWindow(title: 'Meeting place'))},
      );
    }
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.map_outlined, size: 40),
        const SizedBox(height: 12),
        Text(destinationLoading ? 'Loading meeting map…' : 'Map preview unavailable', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!destinationLoading) const Text('Enter your starting point to find a route.', textAlign: TextAlign.center),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final surface = HocalistPalette.surface(context, Colors.white);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: surface,
      body: LayoutBuilder(builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(child: SizedBox(
            key: const Key('meeting-map-panel'),
            child: route == null ? destinationMap() : routeMap(route!),
          )),
          Positioned(top: 0, left: 16, right: 16, child: SafeArea(
            bottom: false,
            child: Row(children: [
              Material(color: surface, shape: const CircleBorder(), elevation: 3,
                child: IconButton(tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded))),
              const SizedBox(width: 12),
              Expanded(child: Material(color: surface, elevation: 3, borderRadius: BorderRadius.circular(20),
                child: const Padding(padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Text('Your meeting route', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))))),
            ]),
          )),
          Align(alignment: Alignment.bottomCenter, child: SizedBox(
            width: constraints.maxWidth > 600 ? 600 : constraints.maxWidth,
            child: DraggableScrollableSheet(
              key: const Key('meeting-route-sheet'),
              controller: sheetController,
              initialChildSize: .48,
              minChildSize: .24,
              maxChildSize: .88,
              snap: true,
              snapSizes: const [.24, .48, .88],
              builder: (context, sheetScroll) => ScrollConfiguration(
                behavior: const MaterialScrollBehavior().copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.trackpad},
                ),
                child: Material(
                color: surface,
                elevation: 12,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  key: const Key('meeting-directions-scroll'),
                  controller: sheetScroll,
                  padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.paddingOf(context).bottom + 20),
                  children: [
                    Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(color: HocalistPalette.border(context, const Color(0xFFD7D5E4)), borderRadius: BorderRadius.circular(8)))),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(route == null ? 'Meet here' : (route!.seconds / 60).ceil().toString() + ' min',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        if (route != null) Text((route!.distanceMeters / 1609.344).toStringAsFixed(1) + ' miles · ' + (mode == 'WALK' ? 'Walking' : 'Driving'),
                          style: const TextStyle(fontSize: 14)),
                      ])),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: HocalistPalette.surface(context, const Color(0xFFF1EEFF)),borderRadius: BorderRadius.circular(20)),
                        child: const Text('Meeting place', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 8),
                    Text(widget.destination, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: travelOption('DRIVE', 'Driving')),
                      const SizedBox(width: 10),
                      Expanded(child: travelOption('WALK', 'Walking')),
                    ]),
                    const SizedBox(height: 14),
                    if (route == null || editingStart) ...[
                      ...startControls(),
                      const SizedBox(height: 12),
                    ] else
                      ListTile(contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.trip_origin, size: 20),
                        title: Text(origin.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => setState(() => editingStart = true)),
                    if (widget.seller)
                      SellerPrimaryButton(label: busy ? 'Finding route…' : 'Show directions', onPressed: busy || findingStart ? null : findRoute)
                    else
                      BuyerPrimaryButton(label: busy ? 'Finding route…' : 'Show directions', onPressed: busy || findingStart ? null : findRoute),
                    if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: BuyerProgressStrip()),
                    if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: notice(Icons.info_outline, 'Route update', error!, failed: true)),
                    if (route case final value?)
                      ExpansionTile(
                        key: const Key('route-steps'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Step-by-step directions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        subtitle: Text(value.steps.length.toString() + ' steps · Google'),
                        children: [for (var i = 0; i < value.steps.length; i++) ListTile(
                          leading: Text((i + 1).toString()), title: Text(value.steps[i], style: const TextStyle(fontSize: 14))),
                          const Padding(padding: EdgeInsets.all(12), child: Text('Follow road signs and local conditions.'))],
                      ),
                    const SizedBox(height: 16),
                    const Text('Google provides address suggestions and directions. Location is used only when you choose it.',
                      style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            )),
          )),
        ],
      )),
    );
  }

  List<Widget> startControls() => [
          if (widget.seller)
            SellerSecondaryButton(compact: true, label: findingStart ? startProgress : 'Use my current location', onPressed: busy || findingStart ? null : () => chooseStart(null))
          else
            BuyerSecondaryButton(compact: true, label: findingStart ? startProgress : 'Use my current location', onPressed: busy || findingStart ? null : () => chooseStart(null)),
          if (findingStart)
            TextButton(onPressed: cancelStart, child: const Text('Cancel location lookup')),
          const SizedBox(height: 12),
          TextField(
            controller: origin,
            enabled: !busy,
            onChanged: searchStart,
            maxLength: 200,
            decoration: widget.seller
                ? sellerInputDecoration(
                    context,
                    hintText: 'Street and city',
                  ).copyWith(labelText: 'Starting address', counterText: '')
                : buyerInputDecoration(
                    context,
                    hintText: 'Street and city',
                  ).copyWith(labelText: 'Starting address', counterText: ''),
          ),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: HocalistPalette.surface(context, Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: HocalistPalette.border(context, const Color(0xFFE4E2F3))),
              ),
              child: Material(color: Colors.transparent, child: Column(children: [
                for (final suggestion in suggestions) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Icon(Icons.location_on_outlined, color: HocalistPalette.text(context, BuyerUiTokens.action)),
                    title: Text(suggestion.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => chooseStart(suggestion),
                  ),
                  if (suggestion != suggestions.last) const Divider(height: 1, indent: 16, endIndent: 16),
                ],
                const Padding(padding: EdgeInsets.all(12), child: Text('Powered by Google', style: TextStyle(fontSize: 12))),
              ])),
            ),
  ];

  Widget travelOption(String value, String label) {
    void select() => setState(() { mode = value; route = null; error = null; });
    final action = busy ? null : select;
    if (widget.seller) {
      return mode == value
          ? SellerPrimaryButton(compact: true, label: label, onPressed: action)
          : SellerSecondaryButton(compact: true, label: label, onPressed: action);
    }
    return mode == value
        ? BuyerPrimaryButton(compact: true, label: label, onPressed: action)
        : BuyerSecondaryButton(compact: true, label: label, onPressed: action);
  }
}
