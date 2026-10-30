import '../../data/phase2/meetings/meeting_adapter.dart';
import '../../data/phase2/maps/meeting_directions.dart';
import '../../domain/phase2/schedule.dart';
import '../../domain/phase2/requests.dart';

/// Reuses only this buyer's confirmed request pin, never a seller projection.
MeetingPlace? buyerRequestMeetingPlace({
  required MarketplaceRequest? request,
  required String requestId,
  required String? buyerUserId,
  required MeetingPlace place,
}) {
  if (place.choice != MeetupPlaceChoice.buyerLocation ||
      request == null ||
      request.id != requestId ||
      buyerUserId == null ||
      request.buyerUserId != buyerUserId) {
    return null;
  }
  final location = request.draft.location;
  final pin = location.coordinates;
  final address = location.address;
  if (location.useHomeAddress ||
      pin == null ||
      address == null ||
      (address.line1?.trim().isEmpty ?? true)) {
    return null;
  }
  return MeetingPlace(
    choice: place.choice,
    label: place.label,
    address: [
      address.line1,
      address.line2,
      address.city,
      address.state,
      address.postalCode,
      address.country,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', '),
    latitude: pin.latitude,
    longitude: pin.longitude,
    timezoneId: location.timezoneId,
  );
}

/// Resolves a participant-confirmed destination before creating a proposal.
/// Generic location choices never resolve another participant's private address.
/// Returning null cancels without producing a command or operation key.
Future<MeetingScheduleInput?> prepareMeetingProposalLocation({
  required LocalSchedule schedule,
  required MeetingPlace place,
  required Future<MeetingPlace?> Function(MeetingPlace) confirmPlace,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return null;
  var confirmed = place;
  final hasDestination = hasConfirmedMeetingDestination(
    address: place.address,
    label: place.label,
    placeId: place.placeId,
  );
  if (!hasDestination) {
    final selected = await confirmPlace(place);
    if (!isCurrent() || selected == null) return null;
    if (!hasConfirmedMeetingDestination(
      address: selected.address,
      label: selected.label,
      placeId: selected.placeId,
    )) {
      return null;
    }
    confirmed = selected;
  }
  return MeetingScheduleInput(
    schedule: confirmed.timezoneId == null || confirmed.timezoneId == schedule.timezoneId
        ? schedule
        : LocalSchedule(date: schedule.date, startTime: schedule.startTime,
            timezoneId: confirmed.timezoneId!),
    placeChoice: switch (place.choice) {
      MeetupPlaceChoice.sellerBusiness => 'seller_business',
      MeetupPlaceChoice.buyerLocation => 'buyer_location',
      MeetupPlaceChoice.specificPlace => 'specific_place',
    },
    placeLabel: confirmed.label,
    placeAddress: confirmed.address,
    placeId: confirmed.placeId,
    latitude: confirmed.latitude,
    longitude: confirmed.longitude,
  );
}
