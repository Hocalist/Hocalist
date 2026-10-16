import 'package:supabase_flutter/supabase_flutter.dart';
import '../accounts/fresh_session_token.dart';

class RoutePoint {
  const RoutePoint(this.latitude, this.longitude);
  final double latitude, longitude;
  @override
  String toString() => 'RoutePoint([redacted])';
}

class MeetingRoute {
  MeetingRoute({
    required this.distanceMeters,
    required this.seconds,
    required this.points,
    required this.steps,
  });
  final int distanceMeters, seconds;
  final List<RoutePoint> points;
  final List<String> steps;
}

class RouteFailure implements Exception {
  const RouteFailure(this.code);
  final String code;
  String get message => switch (code) {
    'no_route' =>
      'No route was found. Try a nearby starting address or another travel mode.',
    'rate_limited' =>
      'Too many direction requests. Please wait before trying again.',
    'meeting_access_denied' ||
    'access_denied' => 'You cannot view directions for this meeting.',
    'destination_missing' =>
      'Confirm a meeting destination before viewing directions.',
    'session_changed' ||
    'unauthorized' => 'Your session changed. Sign in again to view directions.',
    _ => 'Directions could not be loaded. Please try again.',
  };
}

typedef MeetingRouteLoader =
    Future<MeetingRoute> Function(String meetingId, String origin, String mode);

MeetingRoute decodeMeetingRoute(Map data, String meetingId) {
  if (data['meetingId'] != meetingId ||
      data['distanceMeters'] is! num ||
      (data['distanceMeters'] as num) < 0 ||
      data['duration'] is! String ||
      data['polyline'] is! String ||
      data['steps'] is! List) {
    throw const RouteFailure('invalid_response');
  }
  final duration = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(data['duration']);
  if (duration == null) throw const RouteFailure('invalid_response');
  final encoded = data['polyline'] as String;
  if (encoded.length > 200000) throw const RouteFailure('invalid_response');
  final points = <RoutePoint>[];
  var index = 0, latitude = 0, longitude = 0;
  int next() {
    var result = 0, shift = 0, value = 0;
    do {
      if (index >= encoded.length || shift > 30) {
        throw const RouteFailure('invalid_response');
      }
      value = encoded.codeUnitAt(index++) - 63;
      if (value < 0 || value > 63) throw const RouteFailure('invalid_response');
      result |= (value & 31) << shift;
      shift += 5;
    } while (value >= 32);
    // Arithmetic sign decoding works on both native Dart and web, where
    // bitwise complement can produce an unsigned 32-bit value.
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (index < encoded.length) {
    latitude += next();
    longitude += next();
    if (latitude.abs() > 9000000 ||
        longitude.abs() > 18000000 ||
        points.length >= 30000) {
      throw const RouteFailure('invalid_response');
    }
    points.add(RoutePoint(latitude / 1e5, longitude / 1e5));
  }
  if (points.length < 2 || (data['steps'] as List).length > 1000) {
    throw const RouteFailure('invalid_response');
  }
  final steps = (data['steps'] as List)
      .map((step) {
        if (step is! String || step.length > 1000) {
          throw const RouteFailure('invalid_response');
        }
        return step;
      })
      .toList(growable: false);
  return MeetingRoute(
    distanceMeters: (data['distanceMeters'] as num).round(),
    seconds: double.parse(duration[1]!).ceil(),
    points: List.unmodifiable(points),
    steps: List.unmodifiable(steps),
  );
}

Future<MeetingRoute> loadConfiguredMeetingRoute(
  String meetingId,
  String origin,
  String mode,
) async {
  final client = Supabase.instance.client;
  final identity = client.auth.currentUser?.id;
  final token = await freshSessionToken(client);
  if (identity == null ||
      token == null ||
      client.auth.currentUser?.id != identity) {
    throw const RouteFailure('session_changed');
  }
  try {
    final response = await client.functions.invoke(
      'hocalist-routes',
      headers: {'Authorization': 'Bearer $token'},
      body: {'meetingId': meetingId, 'origin': origin.trim(), 'mode': mode},
    );
    if (client.auth.currentUser?.id != identity) {
      throw const RouteFailure('session_changed');
    }
    if (response.data is! Map) throw const RouteFailure('invalid_response');
    return decodeMeetingRoute(response.data, meetingId);
  } on FunctionException catch (failure) {
    final data = failure.details;
    throw RouteFailure(
      data is Map && data['error'] is String ? data['error'] : 'unavailable',
    );
  }
}
