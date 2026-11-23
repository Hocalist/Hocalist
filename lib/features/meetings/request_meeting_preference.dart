import 'dart:math' as math;

import '../../domain/phase2/requests.dart';

/// Buyer-only comparison. Never add the returned private address to lead data.
String? preferredPlaceToReview({
  required MarketplaceRequest? request,
  required String requestId,
  required String? buyerUserId,
  required String? proposedAddress,
  required double? latitude,
  required double? longitude,
}) {
  if (request == null || request.id != requestId || buyerUserId == null ||
      request.buyerUserId != buyerUserId || !request.draft.location.preferMeetHere) return null;
  final location = request.draft.location;
  final address = location.address;
  final fullAddress = [address?.line1, address?.line2, address?.city,
    address?.state, address?.postalCode, address?.country]
      .whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
  String normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[\s,.]+'), '');
  if ((address?.line1?.trim().isNotEmpty ?? false) && proposedAddress != null &&
      normalize(fullAddress) == normalize(proposedAddress)) return null;
  final pin = location.coordinates;
  // Only use a tightly matching confirmed pin when there is no separate unit.
  if (pin != null && latitude != null && longitude != null &&
      (address?.line2?.trim().isEmpty ?? true)) {
    final north = (latitude - pin.latitude) * 111320;
    final east = (longitude - pin.longitude) * 111320 * math.cos(pin.latitude * math.pi / 180);
    if (math.sqrt(north * north + east * east) <= 10) return null;
  }
  return location.useHomeAddress ? 'The home address selected for this request'
      : fullAddress.isEmpty ? 'The address selected for this request' : fullAddress;
}
