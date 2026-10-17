import 'package:hocalist/theme/adaptive_palette.dart';
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
    super.key,
  });
  final String meetingId, destination;
  final MeetingRouteLoader load;
  final Widget Function(MeetingRoute)? mapBuilder;
  final bool seller;
  @override
  State<MeetingDirectionsPage> createState() => _MeetingDirectionsPageState();
}

class _MeetingDirectionsPageState extends State<MeetingDirectionsPage> {
  final origin = TextEditingController();
  String mode = 'DRIVE';
  bool busy = false;
  String? error;
  MeetingRoute? route;
  int generation = 0;
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
    if (busy) return;
    if (origin.text.trim().isEmpty || origin.text.length > 200) {
      setState(() => error = 'Enter a starting address, including the city.');
      return;
    }
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
      route = null;
    });
    try {
      final result = await widget.load(
        widget.meetingId,
        origin.text.trim(),
        mode,
      );
      if (mounted && run == generation) {
        setState(() => route = result);
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
    origin.dispose();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HocalistPalette.surface(
      context,
      BuyerUiTokens.softSurface,
    ),
    appBar: AppBar(title: const Text('Meeting directions')),
    body: SafeArea(
      child: ListView(
        key: const Key('meeting-directions-scroll'),
        padding: const EdgeInsets.all(16),
        children: [
          notice(
            Icons.place_outlined,
            'Confirmed destination',
            widget.destination,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: origin,
            enabled: !busy,
            maxLength: 200,
            decoration: widget.seller
                ? sellerInputDecoration(
                    context,
                    hintText: 'Street and city',
                  ).copyWith(labelText: 'Starting address')
                : buyerInputDecoration(
                    context,
                    hintText: 'Street and city',
                  ).copyWith(labelText: 'Starting address'),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                'DRIVE': 'Driving',
                'WALK': 'Walking',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: mode == entry.key,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                          mode = entry.key;
                          route = null;
                          error = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.seller)
            SellerPrimaryButton(
              label: busy ? 'Finding route…' : 'Show directions',
              onPressed: busy ? null : findRoute,
            )
          else
            BuyerPrimaryButton(
              label: busy ? 'Finding route…' : 'Show directions',
              onPressed: busy ? null : findRoute,
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: BuyerProgressStrip(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: notice(
                Icons.route_outlined,
                'Directions need attention',
                error!,
                failed: true,
              ),
            ),
          if (route case final value?) ...[
            const SizedBox(height: 16),
            notice(
              Icons.route_outlined,
              '${(value.distanceMeters / 1609.344).toStringAsFixed(1)} miles · ${(value.seconds / 60).ceil()} min',
              'Estimated ${mode == 'WALK' ? 'walking' : 'driving'} route. Follow road signs and local conditions.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: routeMap(value),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < value.steps.length; i++)
              ListTile(
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(value.steps[i]),
              ),
            const Text('Directions by Google', textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          const Text(
            'Your starting address is sent to Google only when you request a route. '
            'No background location tracking is used.',
          ),
        ],
      ),
    ),
  );
}
