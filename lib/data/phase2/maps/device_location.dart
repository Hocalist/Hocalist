/// Foreground device-location reader for place capture.
///
/// Requests permission on first use, never starts background tracking and maps
/// every geolocator state to the typed [LocationFailure] the UI handles.
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'places_contract.dart';

Future<LocationReading> readForegroundLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationFailure(LocationFailureCode.serviceDisabled);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationFailure(LocationFailureCode.denied);
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationFailure(LocationFailureCode.deniedForever);
  }
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return LocationReading(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } on TimeoutException {
    throw const LocationFailure(LocationFailureCode.unavailable);
  } catch (_) {
    throw const LocationFailure(LocationFailureCode.unavailable);
  }
}
