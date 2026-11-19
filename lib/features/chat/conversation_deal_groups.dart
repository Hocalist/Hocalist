import '../../data/phase2/meetings/meeting_codecs.dart';

/// Only confirmed outcome identities move an accepted meeting into history.
/// A past appointment date alone is never evidence of purchase completion.
class ConversationDealGroups {
  ConversationDealGroups(List<MeetingView> meetings, Set<String>? completed, {Set<String> closedRequests = const {}}) {
    active = List.unmodifiable(
      meetings.where(
        (meeting) =>
            !closedRequests.contains(meeting.requestId) && !meeting.isCancelled &&
            !(completed?.contains(meeting.meetingId) ?? false),
      ),
    );
    previous = completed == null && closedRequests.isEmpty
        ? null
        : List.unmodifiable(
            meetings.where(
              (meeting) =>
                  closedRequests.contains(meeting.requestId) || meeting.isCancelled || (completed?.contains(meeting.meetingId) ?? false),
            ),
          );
  }
  late final List<MeetingView> active;
  late final List<MeetingView>? previous;
}
