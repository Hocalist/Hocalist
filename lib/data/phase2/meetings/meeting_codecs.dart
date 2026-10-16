/// Meeting views and strict decoders for the meeting RPC payloads.
///
/// These are app-facing projections over the meeting/reschedule foundation.
/// PIN state is intentionally absent: issuance and verification stay gated on
/// the owner's PIN policy decision.
library;

import '../../../domain/phase2/schedule.dart';
import '../marketplace/marketplace_codecs.dart';

/// One schedule revision as the screens need it.
class MeetingScheduleView {
  MeetingScheduleView({
    required this.sequence,
    required this.date,
    required this.startTime,
    required this.timezoneId,
    this.occurrence,
    required this.offsetMinutes,
    required this.instant,
    required this.placeChoice,
    this.placeLabel,
    this.placeAddress,
    this.placeId,
    this.latitude,
    this.longitude,
    required this.proposedByUserId,
    required this.status,
    required this.createdAt,
  });

  final int sequence;
  final LocalDate date;
  final LocalTime startTime;
  final String timezoneId;
  final RepeatedTimeOccurrence? occurrence;
  final int offsetMinutes;
  final DateTime instant;
  final String placeChoice;
  final String? placeLabel;
  final String? placeAddress;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final String proposedByUserId;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'proposed';
}

/// One meeting with its accepted and pending schedules.
class MeetingView {
  MeetingView({
    required this.meetingId,
    required this.conversationId,
    required this.requestId,
    required this.offerId,
    required this.buyerUserId,
    required this.sellerUserId,
    required this.status,
    required this.revision,
    this.meetingExpiresAt,
    this.acceptedSchedule,
    this.pendingSchedule,
    this.offerSummary,
    this.purchaseSelected = false,
    this.purchaseSelectedAt,
    required List<MeetingScheduleView> revisions,
  }) : revisions = List<MeetingScheduleView>.unmodifiable(revisions);

  final String meetingId;
  final String conversationId;
  final String requestId;
  final String offerId;
  final String buyerUserId;
  final String sellerUserId;

  /// `proposed`, `accepted`, `reschedule_proposed` or `cancelled`.
  final String status;
  final int revision;

  /// Exclusive start of the local day after the accepted meeting date.
  final DateTime? meetingExpiresAt;
  final MeetingScheduleView? acceptedSchedule;
  final MeetingScheduleView? pendingSchedule;

  /// Authorized summary of the offer revision accepted at selection time.
  /// Null when the server could not provide it; never replaced with a newer
  /// offer revision.
  final MeetingOfferSummary? offerSummary;
  final List<MeetingScheduleView> revisions;

  /// True when the buyer designated this negotiation as the final purchase, so
  /// this meeting's seller is the only one who can complete the PIN.
  final bool purchaseSelected;
  final DateTime? purchaseSelectedAt;

  bool get hasAcceptedSchedule => acceptedSchedule != null;

  bool get hasPendingSchedule => pendingSchedule != null;

  bool get isCancelled => status == 'cancelled';

  @override
  String toString() => 'MeetingView($meetingId, $status, revision: $revision)';
}

/// The meeting's accepted offer revision facts the screens may display.
class MeetingOfferSummary {
  const MeetingOfferSummary({
    required this.title,
    required this.priceMinor,
    required this.currencyCode,
    required this.revisionId,
  });

  final String title;
  final int priceMinor;
  final String currencyCode;
  final String revisionId;

  /// Display label for the accepted price. USD keeps the app's dollar style;
  /// any other currency falls back to an explicit code-and-amount label.
  String get priceLabel {
    final major = priceMinor / 100;
    final fixed = priceMinor % 100 == 0
        ? major.toStringAsFixed(0)
        : major.toStringAsFixed(2);
    return currencyCode == 'USD' ? '\$$fixed' : '$currencyCode $fixed';
  }
}

/// One page of participant meetings.
class MeetingPageView {
  MeetingPageView({required List<MeetingView> items, this.nextCursor})
    : items = List<MeetingView>.unmodifiable(items);

  final List<MeetingView> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

MeetingView decodeMeetingJson(Map<String, Object?> row, String context) {
  final revisions = <MeetingScheduleView>[];
  final rawRevisions = row['revisions'];
  if (rawRevisions != null) {
    final rows = decodeObjectList(rawRevisions, '$context.revisions');
    for (var index = 0; index < rows.length; index++) {
      revisions.add(
        decodeMeetingRevisionJson(rows[index], '$context.revisions[$index]'),
      );
    }
  }
  MeetingScheduleView? schedule(Object? value, String field) {
    if (value == null) return null;
    try {
      return decodeMeetingRevisionJson(
        decodeObject(value, '$context.$field'),
        '$context.$field',
      );
    } on MarketplaceDecodeException {
      throw MarketplaceDecodeException('$context.$field');
    }
  }

  MeetingOfferSummary? summary(Object? value, String field) {
    if (value == null) return null;
    final object = decodeObject(value, '$context.$field');
    final title = object['title'];
    final price = object['price_minor'];
    final currency = object['currency_code'];
    final revisionId = object['revision_id'];
    if (title is! String ||
        price is! num ||
        currency is! String ||
        revisionId is! String) {
      throw MarketplaceDecodeException('$context.$field');
    }
    return MeetingOfferSummary(
      title: title,
      priceMinor: price.toInt(),
      currencyCode: currency,
      revisionId: revisionId,
    );
  }

  final id = row['id'];
  final status = row['status'];
  final revision = row['revision'];
  if (id is! String || status is! String || revision is! num) {
    throw MarketplaceDecodeException(context);
  }
  final expires = row['meeting_expires_at'];
  try {
    return MeetingView(
      meetingId: id,
      conversationId: row['conversation_id']! as String,
      requestId: row['request_id']! as String,
      offerId: row['offer_id']! as String,
      buyerUserId: row['buyer_user_id']! as String,
      sellerUserId: row['seller_user_id']! as String,
      status: status,
      revision: revision.toInt(),
      meetingExpiresAt: expires is String
          ? DateTime.parse(expires).toUtc()
          : null,
      acceptedSchedule: schedule(row['accepted_schedule'], 'accepted_schedule'),
      pendingSchedule: schedule(row['pending_schedule'], 'pending_schedule'),
      offerSummary: summary(row['offer_summary'], 'offer_summary'),
      purchaseSelected: row['purchase_selected'] == true,
      purchaseSelectedAt: row['purchase_selected_at'] is String
          ? DateTime.parse(row['purchase_selected_at']! as String).toUtc()
          : null,
      revisions: revisions,
    );
  } on TypeError {
    throw MarketplaceDecodeException(context);
  } on FormatException {
    throw MarketplaceDecodeException('$context.meeting_expires_at');
  }
}

MeetingScheduleView decodeMeetingRevisionJson(
  Map<String, Object?> row,
  String context,
) {
  final sequence = row['sequence'];
  final date = row['schedule_date'];
  final time = row['schedule_time'];
  final timezone = row['schedule_timezone'];
  final offset = row['schedule_offset_minutes'];
  final instant = row['schedule_instant'];
  final placeChoice = row['place_choice'];
  final proposedBy = row['proposed_by_user_id'];
  final status = row['status'];
  final createdAt = row['created_at'];
  if (sequence is! num ||
      date is! String ||
      time is! String ||
      timezone is! String ||
      offset is! num ||
      instant is! String ||
      placeChoice is! String ||
      proposedBy is! String ||
      status is! String ||
      createdAt is! String) {
    throw MarketplaceDecodeException(context);
  }
  try {
    return MeetingScheduleView(
      sequence: sequence.toInt(),
      date: _localDate(date, '$context.schedule_date'),
      startTime: _localTime(time, '$context.schedule_time'),
      timezoneId: timezone,
      occurrence: _optionalOccurrence(row['schedule_occurrence'], context),
      offsetMinutes: offset.toInt(),
      instant: DateTime.parse(instant).toUtc(),
      placeChoice: placeChoice,
      placeLabel: row['place_label'] is String
          ? row['place_label'] as String
          : null,
      placeAddress: row['place_address'] is String
          ? row['place_address'] as String
          : null,
      placeId: row['place_id'] is String ? row['place_id'] as String : null,
      latitude: decodePlaceCoordinate(row, 'place_latitude'),
      longitude: decodePlaceCoordinate(row, 'place_longitude'),
      proposedByUserId: proposedBy,
      status: status,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  } on ArgumentError {
    throw MarketplaceDecodeException(context);
  } on FormatException {
    throw MarketplaceDecodeException(context);
  }
}

MeetingPageView decodeMeetingPageJson(
  Map<String, Object?> row,
  String context,
) {
  final rawItems = row['items'];
  final items = <MeetingView>[];
  if (rawItems != null) {
    final rows = decodeObjectList(rawItems, '$context.items');
    for (var index = 0; index < rows.length; index++) {
      items.add(decodeMeetingJson(rows[index], '$context.items[$index]'));
    }
  }
  final nextCursor = row['next_cursor'];
  if (nextCursor != null &&
      (nextCursor is! String || nextCursor.trim().isEmpty)) {
    throw MarketplaceDecodeException('$context.next_cursor');
  }
  return MeetingPageView(items: items, nextCursor: nextCursor as String?);
}

LocalDate _localDate(String value, String context) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) throw MarketplaceDecodeException(context);
  try {
    return LocalDate(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
    );
  } on ArgumentError {
    throw MarketplaceDecodeException(context);
  }
}

LocalTime _localTime(String value, String context) {
  final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2})?$').firstMatch(value);
  if (match == null) throw MarketplaceDecodeException(context);
  try {
    return LocalTime(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
    );
  } on ArgumentError {
    throw MarketplaceDecodeException(context);
  }
}

RepeatedTimeOccurrence? _optionalOccurrence(Object? value, String context) {
  if (value == null) return null;
  if (value is! String) {
    throw MarketplaceDecodeException('$context.schedule_occurrence');
  }
  try {
    return repeatedTimeOccurrenceFromWire(
      value,
      '$context.schedule_occurrence',
    );
  } on MarketplaceDecodeException {
    throw MarketplaceDecodeException('$context.schedule_occurrence');
  }
}
