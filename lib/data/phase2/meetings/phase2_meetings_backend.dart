/// Real-mode meeting backend for the meeting/reschedule screens.
library;

import '../../../domain/phase2/failures.dart';
import '../../local_marketplace_repository.dart';
import 'meeting_adapter.dart';
import 'meeting_codecs.dart';

class Phase2MarketplaceMeetingsBackend implements MarketplaceMeetingsBackend {
  Phase2MarketplaceMeetingsBackend({required this.adapter});

  final MeetingDataAdapter adapter;

  @override
  Future<MeetingPageView> loadMeetings({
    String? status,
    String? cursor,
    int limit = 50,
  }) async {
    final result = await adapter.fetchMeetings(
      status: status,
      cursor: cursor,
      limit: limit,
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: error is ValidationError ? error.issues.firstOrNull?.code : null,
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<MeetingView> loadMeeting(String meetingId) async {
    final result = await adapter.fetchMeeting(meetingId);
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: error is ValidationError ? error.issues.firstOrNull?.code : null,
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<MeetingView> proposeMeeting({
    required String conversationId,
    required MeetingScheduleInput input,
    required String operationKey,
  }) async {
    final result = await adapter.proposeMeeting(
      conversationId: conversationId,
      input: input,
      operationKey: operationKey,
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: error is ValidationError ? error.issues.firstOrNull?.code : null,
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<MeetingView> respondToMeeting({
    required String meetingId,
    required bool accept,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await adapter.respondToMeeting(
      meetingId: meetingId,
      accept: accept,
      expectedRevision: expectedRevision,
      operationKey: operationKey,
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: error is ValidationError ? error.issues.firstOrNull?.code : null,
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<MeetingView> proposeReschedule({
    required String meetingId,
    required MeetingScheduleInput input,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await adapter.proposeReschedule(
      meetingId: meetingId,
      input: input,
      expectedRevision: expectedRevision,
      operationKey: operationKey,
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: error is ValidationError ? error.issues.firstOrNull?.code : null,
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<MeetingView> cancelMeeting({
    required String meetingId,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await adapter.cancelMeeting(
      meetingId: meetingId,
      expectedRevision: expectedRevision,
      operationKey: operationKey,
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: error is ValidationError ? error.issues.firstOrNull?.code : null,
      );
    }
    return result.valueOrNull!;
  }

  bool _isAmbiguous(RepositoryError? error) {
    if (error == null) return false;
    return switch (error.kind) {
      RepositoryFailureKind.network ||
      RepositoryFailureKind.malformedResponse => true,
      RepositoryFailureKind.server =>
        error is ServerError &&
            (error.statusCode == null || error.statusCode! >= 500),
      _ => false,
    };
  }

  String _message(RepositoryError? error) {
    if (error is ValidationError) {
      final codes = error.issues.map((issue) => issue.code);
      if (codes.contains('ambiguous_local_time')) {
        return 'This time occurs twice because the clocks change. Choose Earlier or Later and send again.';
      }
      if (codes.contains('nonexistent_local_time')) {
        return 'This time does not exist because the clocks change. Choose another time.';
      }
    }
    if (error == null) {
      return 'The meeting could not be updated. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.permissionDenied =>
        'You cannot change this meeting.',
      RepositoryFailureKind.notFound => 'This meeting is no longer available.',
      RepositoryFailureKind.conflict =>
        'This meeting changed. Please try again.',
      RepositoryFailureKind.network =>
        'The change could not be confirmed. Retry to check it safely.',
      RepositoryFailureKind.validation =>
        'Check the meeting details and try again.',
      _ => 'The meeting could not be updated. Try again.',
    };
  }
}
