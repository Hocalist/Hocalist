/// Provider-neutral Places transport used by the app.
///
/// Implementations call the authenticated Hocalist Places endpoint. They must
/// never receive or expose the Google server key, must not log queries or
/// addresses, and must map provider failures to [PlacesFailure].
library;

import 'places_contract.dart';

/// One raw transport response for one operation.
class PlacesTransportResult {
  const PlacesTransportResult(this.data);

  final Map<String, Object?> data;
}

abstract interface class PlacesTransport {
  /// Autocomplete suggestions for [input] under [session].
  Future<PlacesTransportResult> autocomplete({
    required String input,
    required String sessionToken,
  });

  /// Resolves one selected suggestion under the same [session].
  Future<PlacesTransportResult> details({
    required String placeId,
    required String sessionToken,
  });
}

/// Optional capability for resolving a moved pin/current location. Kept
/// separate so search-only transports cannot silently guess a timezone.
abstract interface class CoordinatePlacesTransport {
  Future<PlacesTransportResult> coordinates({
    required double latitude,
    required double longitude,
    required String sessionToken,
  });
}

abstract interface class AddressPlacesTransport {
  Future<PlacesTransportResult> address({required String address, required String sessionToken});
}
