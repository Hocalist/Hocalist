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
