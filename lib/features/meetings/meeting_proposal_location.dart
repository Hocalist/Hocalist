import '../../data/phase2/meetings/meeting_adapter.dart';
import '../../data/phase2/maps/meeting_directions.dart';
import '../../domain/phase2/schedule.dart';

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
    schedule: schedule,
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
