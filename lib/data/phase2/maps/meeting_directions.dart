/// Fixed-host, user-initiated Maps handoff. No key or device location included.
/// https://developers.google.com/maps/documentation/urls/get-started
bool hasConfirmedMeetingDestination({
  String? address,
  String? label,
  String? placeId,
}) =>
    address?.trim().isNotEmpty == true ||
    (placeId?.trim().isNotEmpty == true && label?.trim().isNotEmpty == true);

Uri? meetingDirectionsUri({String? address, String? label, String? placeId}) {
  final destination = address?.trim().isNotEmpty == true
      ? address!.trim()
      : label?.trim();
  if (destination == null || destination.isEmpty) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
    if (placeId?.trim().isNotEmpty == true)
      'destination_place_id': placeId!.trim(),
  });
}
