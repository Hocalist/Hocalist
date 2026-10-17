/// Map surface for place confirmation.
///
/// The Google Maps widget is only constructed when the caller supplies a
/// builder and the platform supports it; widget tests and unconfigured builds
/// use the coordinate placeholder instead. The Maps SDK credential is injected
/// natively (see android/app/build.gradle.kts) and never handled here.
library;

import 'package:hocalist/theme/adaptive_palette.dart';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../theme/buyer_ui_foundation.dart';
export 'map_sdk_available.dart';

/// One movable-pin map surface.
typedef HocalistMapBuilder =
    Widget Function(
      BuildContext context, {
      required double latitude,
      required double longitude,
      required ValueChanged<HocalistCoordinates> onMoved,
    });

@immutable
class HocalistCoordinates {
  const HocalistCoordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is HocalistCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'HocalistCoordinates([redacted])';
}

/// Real Google Maps surface with a draggable confirmation pin.
Widget buildGoogleMapSurface(
  BuildContext context, {
  required double latitude,
  required double longitude,
  required ValueChanged<HocalistCoordinates> onMoved,
}) {
  final position = LatLng(latitude, longitude);
  return GoogleMap(
    key: const Key('hocalistGoogleMap'),
    initialCameraPosition: CameraPosition(target: position, zoom: 16),
    mapType: MapType.normal,
    myLocationButtonEnabled: false,
    zoomControlsEnabled: false,
    markers: {
      Marker(
        markerId: const MarkerId('hocalist-confirmed-place'),
        position: position,
        draggable: true,
        onDragEnd: (updated) =>
            onMoved(HocalistCoordinates(updated.latitude, updated.longitude)),
      ),
    },
  );
}

/// Fallback surface used when no map builder is supplied.
class HocalistMapPlaceholder extends StatelessWidget {
  const HocalistMapPlaceholder({
    required this.latitude,
    required this.longitude,
    super.key,
  });

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('hocalistMapPlaceholder'),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HocalistPalette.border(context, BuyerUiTokens.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.map_outlined,
            color: HocalistPalette.text(context, BuyerUiTokens.action),
          ),
          const SizedBox(height: 6),
          Text(
            'Map preview is not configured for this build.\nYou can still confirm the searched address.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: HocalistPalette.text(context, BuyerUiTokens.text),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
