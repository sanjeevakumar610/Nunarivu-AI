enum FeedbackType {
  moreExamples,
  extraHelp,
  improveModel;

  String get dbValue => switch (this) {
        FeedbackType.moreExamples  => 'more_examples',
        FeedbackType.extraHelp     => 'extra_help',
        FeedbackType.improveModel  => 'improve_model',
      };

  static FeedbackType fromDb(String v) => switch (v) {
        'more_examples' => FeedbackType.moreExamples,
        'extra_help'    => FeedbackType.extraHelp,
        _               => FeedbackType.improveModel,
      };
}

class FeedbackEntry {
  final String id;
  final String profileId;
  final String? chatId;
  final String messageId;
  final FeedbackType feedbackType;
  final String originalPrompt;
  final String originalResponse;
  final DateTime createdAt;
  final bool synced;

  const FeedbackEntry({
    required this.id,
    required this.profileId,
    this.chatId,
    required this.messageId,
    required this.feedbackType,
    required this.originalPrompt,
    required this.originalResponse,
    required this.createdAt,
    this.synced = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'chat_id': chatId,
        'message_id': messageId,
        'feedback_type': feedbackType.dbValue,
        'original_prompt': originalPrompt,
        'original_response': originalResponse,
        'created_at': createdAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  factory FeedbackEntry.fromMap(Map<String, Object?> m) => FeedbackEntry(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        chatId: m['chat_id'] as String?,
        messageId: m['message_id'] as String,
        feedbackType: FeedbackType.fromDb(m['feedback_type'] as String),
        originalPrompt: m['original_prompt'] as String,
        originalResponse: m['original_response'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        synced: (m['synced'] as int? ?? 0) == 1,
      );
}
