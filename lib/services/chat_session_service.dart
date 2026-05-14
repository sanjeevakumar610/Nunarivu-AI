import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import 'db_service.dart';

class ChatSessionService {
  /// Creates a new session and returns its UUID.
  Future<String> create(String profileId, String title) async {
    final id = const Uuid().v4();
    final db = await DbService.instance.db;
    await db.insert('chats', {
      'id': id,
      'profile_id': profileId,
      'title': title,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  Future<List<ChatSession>> loadForProfile(String profileId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'chats',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ChatSession.fromMap).toList();
  }

  /// Renames a session.
  Future<void> rename(String chatId, String newTitle) async {
    final db = await DbService.instance.db;
    await db.update('chats', {'title': newTitle},
        where: 'id = ?', whereArgs: [chatId]);
  }

  /// Deletes a session and all its messages (messages deleted first to satisfy FK).
  Future<void> delete(String chatId) async {
    final db = await DbService.instance.db;
    await db.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
    await db.delete('chats', where: 'id = ?', whereArgs: [chatId]);
  }
}

final chatSessionServiceProvider =
    Provider<ChatSessionService>((ref) => ChatSessionService());
