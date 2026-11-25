import '../domain/phase2/common.dart';
import '../domain/phase2/money.dart';
import '../domain/phase2/offers.dart';
import '../domain/phase2/schedule.dart';
import 'local_marketplace_repository.dart';
import 'phase2/meetings/meeting_codecs.dart';

const sampleDealRequest = LocalRequestRecord(
  id: 'jons-dev-dining-table',
  buyerName: 'Maya Chen',
  title: 'Dining table for four',
  budget: r'$175 – $250',
);

const sampleDealSeller = 'Brooksville Home Goods';
const sampleDealTimezone = 'America/New_York';

LocalOfferRecord initialSampleOffer(DateTime today) => LocalOfferRecord(
  id: 'offer-mc',
  requestId: sampleDealRequest.id,
  buyerName: sampleDealRequest.buyerName,
  sellerName: sampleDealSeller,
  requestTitle: sampleDealRequest.title,
  price: r'$225',
  location: 'Brooksville Home Goods business location',
  meetingDate: '',
  meetingTime: '',
  meetingAt: DateTime(today.year, today.month, today.day + 1, 15),
  message: 'Solid wood table with four chairs. I can help load it at pickup.',
  imageNames: const [],
  status: LocalOfferStatus.sent,
);

class SampleDealView {
  SampleDealView(this.record);

  final LocalOfferRecord record;

  static const buyerId = 'jons-dev-buyer';
  static const sellerId = 'jons-dev-seller';

  DateTime get meetingAt => record.meetingAt!;
  bool get confirmed => record.status == LocalOfferStatus.meetingConfirmed;
  bool get pending => record.proposedMeetingAt != null;

  Money get price => Money(
    minorUnits: (double.parse(record.price.substring(1)) * 100).round(),
    currencyCode: 'USD',
  );

  static LocalSchedule schedule(DateTime time) => LocalSchedule(
    date: LocalDate.fromDateTime(time),
    startTime: LocalTime.fromDateTime(time),
    timezoneId: sampleDealTimezone,
  );

  Offer get offer {
    final status = switch (record.status) {
      LocalOfferStatus.sent => OfferStatus.submitted,
      LocalOfferStatus.selected ||
      LocalOfferStatus.meetingConfirmed => OfferStatus.selected,
      LocalOfferStatus.completed => OfferStatus.completed,
      LocalOfferStatus.declined => OfferStatus.declined,
    };
    final accepted =
        status == OfferStatus.selected || status == OfferStatus.completed;
    final revision = OfferRevision(
      id: '${record.id}-terms',
      offerId: record.id,
      sequence: 1,
      terms: OfferTerms(
        price: price,
        message: record.message,
        schedule: schedule(meetingAt),
        place: MeetingPlace(
          choice: MeetupPlaceChoice.specificPlace,
          label: record.location,
        ),
      ),
      status: accepted
          ? OfferRevisionStatus.accepted
          : OfferRevisionStatus.proposed,
      proposedByUserId: sellerId,
      createdAt: meetingAt,
    );
    return Offer(
      id: record.id,
      requestId: record.requestId,
      requestTitle: record.requestTitle,
      buyerUserId: buyerId,
      sellerUserId: sellerId,
      sellerProfileId: sellerId,
      sellerDisplayName: record.sellerName,
      revisions: [revision],
      status: status,
      acceptedRevisionId: accepted ? revision.id : null,
      conversationId: accepted ? '${record.id}-chat' : null,
      stamp: RecordStamp(
        revision: 1,
        createdAt: meetingAt,
        updatedAt: meetingAt,
      ),
    );
  }

  MeetingScheduleView _meetingSchedule(
    DateTime time, {
    required bool proposed,
  }) {
    final value = schedule(time);
    return MeetingScheduleView(
      sequence: proposed ? 2 : 1,
      date: value.date,
      startTime: value.startTime,
      timezoneId: value.timezoneId,
      offsetMinutes: time.timeZoneOffset.inMinutes,
      instant: time.toUtc(),
      placeChoice: 'specific_place',
      placeLabel: record.location,
      proposedByUserId: proposed ? buyerId : sellerId,
      status: proposed ? 'proposed' : 'accepted',
      createdAt: time,
    );
  }

  MeetingView? get meeting {
    if (!confirmed && !pending) return null;
    final accepted = confirmed
        ? _meetingSchedule(meetingAt, proposed: false)
        : null;
    final proposal = record.proposedMeetingAt;
    final proposed = proposal == null
        ? null
        : _meetingSchedule(proposal, proposed: true);
    return MeetingView(
      meetingId: '${record.id}-meeting',
      conversationId: '${record.id}-chat',
      requestId: record.requestId,
      offerId: record.id,
      buyerUserId: buyerId,
      sellerUserId: sellerId,
      status: pending
          ? (confirmed ? 'reschedule_proposed' : 'proposed')
          : 'accepted',
      revision: pending ? 2 : 1,
      acceptedSchedule: accepted,
      pendingSchedule: proposed,
      revisions: [
        if (accepted != null) accepted,
        if (proposed != null) proposed,
      ],
      offerSummary: MeetingOfferSummary(
        title: record.requestTitle,
        priceMinor: price.minorUnits,
        currencyCode: price.currencyCode,
        revisionId: '${record.id}-terms',
      ),
    );
  }
}
