/// A participant chat can contain multiple independent deals.
typedef ConversationSendScope = ({String? conversationId, String? offerId});

class ConversationSendFeedback {
  final Map<ConversationSendScope, String> _errors = {};

  String? errorFor(ConversationSendScope scope) => _errors[scope];

  /// Async send results retain the scope captured before sending.
  void setError(ConversationSendScope scope, String? error) {
    if (error == null) {
      _errors.remove(scope);
    } else {
      _errors[scope] = error;
    }
  }
}
