class ChatSession {
  final String id;
  final String profileId;
  final String title;
  final DateTime createdAt;

  const ChatSession({
    required this.id,
    required this.profileId,
    required this.title,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ChatSession.fromMap(Map<String, Object?> m) => ChatSession(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        title: m['title'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
