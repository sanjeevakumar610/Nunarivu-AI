enum MessageRole { user, assistant }

class ChatMessage {
  final String id;
  final String? chatId;        // null for in-memory messages
  final String? profileId;     // null for in-memory messages
  final MessageRole role;
  final String text;
  final String? imagePath;
  final String? pdfId;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    this.chatId,
    this.profileId,
    required this.role,
    required this.text,
    this.imagePath,
    this.pdfId,
    required this.timestamp,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'chat_id': chatId,
        'profile_id': profileId,
        'role': role == MessageRole.user ? 'user' : 'assistant',
        'text': text,
        'image_path': imagePath,
        'pdf_id': pdfId,
        'created_at': timestamp.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromMap(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as String,
        chatId: m['chat_id'] as String?,
        profileId: m['profile_id'] as String?,
        role: (m['role'] as String) == 'user'
            ? MessageRole.user
            : MessageRole.assistant,
        text: m['text'] as String,
        imagePath: m['image_path'] as String?,
        pdfId: m['pdf_id'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
