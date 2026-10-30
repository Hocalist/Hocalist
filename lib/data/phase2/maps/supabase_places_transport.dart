/// Supabase Edge Function transport for the Hocalist Places endpoint.
///
/// The function name is a deployment configuration value; the Google server
/// credential stays in the function's secrets and never reaches the app. The
/// endpoint is not deployed yet, so callers must treat `unconfigured` and
/// `unavailable` as normal states and keep manual place entry available.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'places_contract.dart';
import 'places_transport.dart';

/// Deployment-owned function name. Overridable through
/// `HOCALIST_PLACES_FUNCTION` at build time; the literal is the agreed default.
const String kHocalistPlacesFunction = 'hocalist-places';

class SupabasePlacesTransport implements PlacesTransport, CoordinatePlacesTransport, AddressPlacesTransport {
  SupabasePlacesTransport(
    this._client, {
    this.functionName = kHocalistPlacesFunction,
  });

  final SupabaseClient _client;
  final String functionName;

  @override
  Future<PlacesTransportResult> address({required String address, required String sessionToken}) => _invoke({
    'operation':'address', 'address':address, 'sessionToken':sessionToken,
  });

  @override
  Future<PlacesTransportResult> coordinates({
    required double latitude,
    required double longitude,
    required String sessionToken,
  }) => _invoke({
    'operation': 'coordinates', 'latitude': latitude, 'longitude': longitude,
    'sessionToken': sessionToken,
  });

  @override
  Future<PlacesTransportResult> autocomplete({
    required String input,
    required String sessionToken,
  }) {
    return _invoke({
      'operation': 'autocomplete',
      'input': input,
      'sessionToken': sessionToken,
    });
  }

  @override
  Future<PlacesTransportResult> details({
    required String placeId,
    required String sessionToken,
  }) {
    return _invoke({
      'operation': 'details',
      'placeId': placeId,
      'sessionToken': sessionToken,
    });
  }

  Future<PlacesTransportResult> _invoke(Map<String, Object?> body) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(functionName, body: body);
    } on FunctionException catch (error) {
      // The endpoint returns only typed codes; never surface its body.
      throw placesFailureFromEndpoint(
        status: error.status,
        details: error.details,
      );
    } catch (_) {
      throw const PlacesFailure(PlacesFailureCode.unavailable);
    }
    final data = response.data;
    if (data is! Map) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    return PlacesTransportResult(
      data.map((key, value) => MapEntry('$key', value)),
    );
  }
}
