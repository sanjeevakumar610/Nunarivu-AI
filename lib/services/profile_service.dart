import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/profile.dart';
import 'db_service.dart';

class ProfileService {
  static const _uuid = Uuid();

  Future<List<Profile>> all() async {
    final db = await DbService.instance.db;
    final rows = await db.query('profiles', orderBy: 'last_used_at DESC');
    return rows.map(Profile.fromMap).toList();
  }

  Future<int> count() async {
    final db = await DbService.instance.db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM profiles');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<Profile> create(
    String name, {
    bool langTamil = true,
    bool langEnglish = true,
    AgeGroup ageGroup = AgeGroup.school,
    int? age,
    String? schoolName,
    String? grade,
    bool instrExplainWithExamples = false,
    bool instrLearningDisability = false,
    String? customInstructions,
  }) async {
    final db = await DbService.instance.db;
    final now = DateTime.now();
    final profile = Profile(
      id: _uuid.v4(),
      name: name.trim(),
      avatarSeed: Random().nextInt(0xFFFFFF),
      createdAt: now,
      lastUsedAt: now,
      langTamil: langTamil,
      langEnglish: langEnglish,
      ageGroup: ageGroup,
      age: age,
      schoolName: schoolName,
      grade: grade,
      instrExplainWithExamples: instrExplainWithExamples,
      instrLearningDisability: instrLearningDisability,
      customInstructions: customInstructions,
    );
    await db.insert('profiles', profile.toMap());
    return profile;
  }

  Future<void> touch(Profile p) async {
    final db = await DbService.instance.db;
    await db.update(
      'profiles',
      {'last_used_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  /// Save all profile fields back to DB (after editing).
  Future<void> update(Profile p) async {
    final db = await DbService.instance.db;
    await db.update(
      'profiles',
      p.toMap(),
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  Future<void> rename(Profile p, String newName) async {
    final db = await DbService.instance.db;
    await db.update(
      'profiles',
      {'name': newName.trim()},
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  Future<void> delete(Profile p) async {
    final db = await DbService.instance.db;
    await db.delete('profiles', where: 'id = ?', whereArgs: [p.id]);
  }
}

final profileServiceProvider =
    Provider<ProfileService>((ref) => ProfileService());
