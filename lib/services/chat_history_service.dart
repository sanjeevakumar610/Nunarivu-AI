import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import 'db_service.dart';

/// Persists chat messages per profile / session.
class ChatHistoryService {
  Future<List<ChatMessage>> loadForProfile(String profileId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'messages',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// Load messages belonging to a specific chat session.
  Future<List<ChatMessage>> loadForChat(String chatId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> save(ChatMessage m) async {
    final db = await DbService.instance.db;
    await db.insert('messages', m.toMap());
  }

  Future<void> clearForProfile(String profileId) async {
    final db = await DbService.instance.db;
    await db.delete(
      'messages',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }
}

final chatHistoryServiceProvider =
    Provider<ChatHistoryService>((ref) => ChatHistoryService());
