/// Native/background call-notification contract.
///
/// This is a boundary, not an implementation. The MVP ships no plugin, so the
/// only composition is [NoopCallNotificationBridge]: foreground calls are shown
/// by the call page and missed-call rows are produced server-side (migration
/// 153) and delivered through the normal push lookup.
///
/// Explicit Android limits:
/// - Terminated-app ringing requires a native notification channel plus a
///   full-screen intent / foreground service and the POST_NOTIFICATIONS
///   runtime permission. A Dart foreground polling loop cannot provide it.
/// - A plugin such as `flutter_local_notifications` (with
///   `fullScreenIntent: true` and a high-importance channel) is required and
///   must arrive as a pinned, separately reviewed dependency patch; it is not
///   installed by this package.
///
/// Explicit iOS limits:
/// - Ringing while backgrounded or terminated requires APNs VoIP push plus
///   CallKit (PushKit). Apple/APNs is owner-deferred; without it an iOS device
///   only shows the generic notification produced by the push worker.
///
/// Until those native integrations exist, [CallNotificationEvent.incoming]
/// should only be used to update an already-foreground UI state.
library;

/// Events a native bridge may present.
enum CallNotificationEvent { incoming, cancelled, missed, ended }

/// Minimal native call-notification surface. Implementations must never
/// fabricate a call state; the server remains the only authority.
abstract interface class CallNotificationBridge {
  /// Shows (or updates) an incoming-call notification for [callId].
  Future<void> showIncoming({
    required String callId,
    required String conversationId,
    required String callerLabel,
  });

  /// Cancels a previously shown incoming notification.
  Future<void> cancel(String callId);

  Future<void> dispose();
}

/// Composition used until a reviewed native integration exists.
class NoopCallNotificationBridge implements CallNotificationBridge {
  const NoopCallNotificationBridge();

  @override
  Future<void> showIncoming({
    required String callId,
    required String conversationId,
    required String callerLabel,
  }) async {}

  @override
  Future<void> cancel(String callId) async {}

  @override
  Future<void> dispose() async {}
}
