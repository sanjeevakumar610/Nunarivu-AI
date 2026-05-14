import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/badge_entry.dart';
import 'db_service.dart';

const _uuid = Uuid();

final badgeServiceProvider = Provider<BadgeService>((_) => BadgeService.instance);

class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  /// Called after every user message — awards any newly-unlocked badges
  /// and returns the list of newly-awarded entries (so caller can show toasts).
  Future<List<BadgeEntry>> checkAndAward(String profileId) async {
    final db = await DbService.instance.db;

    // Count user messages for this profile
    final msgCount = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM messages WHERE profile_id=? AND role='user'",
            [profileId])) ??
        0;

    // Count distinct calendar days with any activity
    final dayCount = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(DISTINCT DATE(created_at/1000, 'unixepoch')) "
            "FROM messages WHERE profile_id=?",
            [profileId])) ??
        0;

    // Already-earned badge types
    final earned = (await db.query('badges',
            columns: ['badge_type'],
            where: 'profile_id = ?',
            whereArgs: [profileId]))
        .map((r) => r['badge_type'] as String)
        .toSet();

    final newBadges = <BadgeEntry>[];
    for (final b in BadgeType.values) {
      if (earned.contains(b.dbValue)) continue;
      if (_isUnlocked(b, msgCount, dayCount)) {
        final entry = BadgeEntry(
          id: _uuid.v4(),
          profileId: profileId,
          badgeType: b,
          earnedAt: DateTime.now(),
        );
        // UNIQUE INDEX on (profile_id, badge_type) prevents double-award
        await db.insert('badges', entry.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        newBadges.add(entry);
      }
    }
    return newBadges;
  }

  bool _isUnlocked(BadgeType b, int msgs, int days) => switch (b) {
        BadgeType.firstStep  => msgs >= 1,
        BadgeType.curious    => msgs >= 10,
        BadgeType.studyBuddy => msgs >= 50,
        BadgeType.scholar    => msgs >= 100,
        BadgeType.champion   => msgs >= 250,
        BadgeType.dedicated  => msgs >= 500,
        BadgeType.weekStreak => days >= 7,
        BadgeType.monthUser  => days >= 30,
      };

  Future<List<BadgeEntry>> getEarned(String profileId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'badges',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'earned_at ASC',
    );
    return rows.map(BadgeEntry.fromMap).toList();
  }
}
