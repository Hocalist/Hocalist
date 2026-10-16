/// Meeting data adapter: participant-authorized RPCs over the shared
/// authenticated transport. No table selects, no PIN pathway.
library;

import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/schedule.dart';
import '../marketplace/marketplace_codecs.dart';
import '../marketplace/marketplace_error_mapper.dart';
import '../marketplace/marketplace_session.dart';
import '../marketplace/marketplace_transport.dart';
import 'meeting_codecs.dart';

/// One schedule proposal input shared by propose and reschedule.
class MeetingScheduleInput {
  MeetingScheduleInput({
    required this.schedule,
    required this.placeChoice,
    this.placeLabel,
    this.placeAddress,
    this.placeId,
    this.latitude,
    this.longitude,
  }) {
    if ((latitude == null) != (longitude == null) ||
        (latitude != null && (!latitude!.isFinite || latitude!.abs() > 90)) ||
        (longitude != null &&
            (!longitude!.isFinite || longitude!.abs() > 180))) {
      throw ArgumentError('invalid confirmed place coordinates');
    }
    if (placeChoice != 'seller_business' &&
        placeChoice != 'buyer_location' &&
        placeChoice != 'specific_place') {
      throw ArgumentError.value(placeChoice, 'placeChoice', 'unknown choice');
    }
    if (placeChoice == 'specific_place' &&
        (placeLabel == null || placeLabel!.trim().isEmpty) &&
        (placeId == null || placeId!.trim().isEmpty)) {
      throw ArgumentError(
        'a specific place needs a label or a place reference',
      );
    }
  }

  final LocalSchedule schedule;
  final String placeChoice;
  final String? placeLabel;
  final String? placeAddress;
  final String? placeId;
  final double? latitude;
  final double? longitude;

  Map<String, Object?> toWire() => {
    'schedule_date': schedule.date.toString(),
    'schedule_time': schedule.startTime.toString(),
    'schedule_timezone': schedule.timezoneId,
    if (schedule.occurrence != null)
      'schedule_occurrence': repeatedTimeOccurrenceToWire(schedule.occurrence!),
    'place_choice': placeChoice,
    'place_label': placeLabel,
    'place_address': placeAddress,
    'place_id': placeId,
    if (latitude != null) 'place_latitude': latitude,
    if (longitude != null) 'place_longitude': longitude,
  };
}

class MeetingDataAdapter {
  MeetingDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  static const String schema = 'hocalist';

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  String? _captureIdentity() => session.currentUserId;

  bool _isStillCurrent(String userId) => session.currentUserId == userId;

  RepositoryResult<T> _failure<T>(RepositoryError error) =>
      RepositoryFailureResult(error);

  Future<RepositoryResult<Map<String, Object?>>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(schema: schema, function: function, params: params),
    );
    if (!_isStillCurrent(userId)) return _failure(_staleSession);
    return switch (response) {
      MarketplaceTransportData(:final data) => _decode(function, data),
      MarketplaceTransportError() => RepositoryFailureResult(
        errorMapper.map(response, operation: function),
      ),
    };
  }

  RepositoryResult<Map<String, Object?>> _decode(
    String function,
    Object? data,
  ) {
    try {
      return RepositorySuccess(decodeObject(data, function));
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<MeetingPageView>> fetchMeetings({
    String? status,
    String? cursor,
    int limit = 50,
  }) async {
    final result = await _rpc('meeting_list', {
      'p_status': status,
      'p_limit': limit,
      'p_cursor': cursor,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeMeetingPageJson(result.valueOrNull!, 'meeting_list'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(operation: 'meeting_list', detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<MeetingView>> fetchMeeting(String meetingId) async {
    final result = await _rpc('meeting_detail', {'p_meeting': meetingId});
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeMeetingJson(result.valueOrNull!, 'meeting_detail'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'meeting_detail',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<MeetingView>> proposeMeeting({
    required String conversationId,
    required MeetingScheduleInput input,
    required String operationKey,
  }) async {
    final result = await _rpc('meeting_propose', {
      'p_conversation': conversationId,
      'p_input': input.toWire(),
      'p_key': operationKey,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeMeetingJson(result.valueOrNull!, 'meeting_propose'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'meeting_propose',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<MeetingView>> respondToMeeting({
    required String meetingId,
    required bool accept,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await _rpc('meeting_respond', {
      'p_meeting': meetingId,
      'p_accept': accept,
      'p_expected_revision': expectedRevision,
      'p_key': operationKey,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeMeetingJson(result.valueOrNull!, 'meeting_respond'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'meeting_respond',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<MeetingView>> proposeReschedule({
    required String meetingId,
    required MeetingScheduleInput input,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await _rpc('meeting_reschedule_propose', {
      'p_meeting': meetingId,
      'p_input': input.toWire(),
      'p_expected_revision': expectedRevision,
      'p_key': operationKey,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeMeetingJson(result.valueOrNull!, 'meeting_reschedule_propose'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'meeting_reschedule_propose',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<MeetingView>> cancelMeeting({
    required String meetingId,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await _rpc('meeting_cancel', {
      'p_meeting': meetingId,
      'p_expected_revision': expectedRevision,
      'p_key': operationKey,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeMeetingJson(result.valueOrNull!, 'meeting_cancel'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'meeting_cancel',
          detail: error.detail,
        ),
      );
    }
  }
}
