import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feedback_entry.dart';
import 'db_service.dart';

class FeedbackService {
  Future<void> save(FeedbackEntry entry) async {
    final db = await DbService.instance.db;
    await db.insert('feedback', entry.toMap());
  }

  /// Returns all unsynced feedback entries for the given profile.
  Future<List<FeedbackEntry>> unsyncedForProfile(String profileId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'feedback',
      where: 'profile_id = ? AND synced = 0',
      whereArgs: [profileId],
      orderBy: 'created_at ASC',
    );
    return rows.map(FeedbackEntry.fromMap).toList();
  }

  /// Count of unsynced entries across all profiles (shown in Settings).
  Future<int> unsyncedCount() async {
    final db = await DbService.instance.db;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM feedback WHERE synced = 0');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Mark all unsynced entries as synced (call after successful upload).
  Future<void> markAllSynced() async {
    final db = await DbService.instance.db;
    await db.update('feedback', {'synced': 1}, where: 'synced = 0');
  }
}

final feedbackServiceProvider =
    Provider<FeedbackService>((ref) => FeedbackService());
