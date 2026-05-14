import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../models/reminder.dart';
import 'db_service.dart';
import 'notification_service.dart';

final reminderServiceProvider =
    Provider<ReminderService>((_) => ReminderService.instance);

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  Future<void> create(Reminder reminder) async {
    final db = await DbService.instance.db;
    await db.insert('reminders', reminder.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (reminder.isActive) await _schedule(reminder);
  }

  Future<List<Reminder>> loadForProfile(String profileId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'reminders',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Reminder.fromMap).toList();
  }

  Future<void> toggle(Reminder reminder, {required bool isActive}) async {
    final db = await DbService.instance.db;

    // For a one-time reminder that has already passed, bump the time to
    // "same clock time tomorrow" so re-enabling actually fires.
    Reminder effective = reminder.copyWith(isActive: isActive);
    if (isActive && !reminder.isDaily && reminder.onceAt != null) {
      final now = DateTime.now();
      var at = reminder.onceAt!;
      while (at.isBefore(now)) {
        at = at.add(const Duration(days: 1));
      }
      effective = reminder.copyWith(isActive: true, onceAt: at);
    }

    await db.update(
      'reminders',
      effective.toMap(),
      where: 'id = ?',
      whereArgs: [effective.id],
    );

    if (isActive) {
      await _schedule(effective);
    } else {
      await NotificationService.instance.cancel(reminder.notificationId);
    }
  }

  /// Update an existing reminder (e.g. after editing time/title).
  Future<void> update(Reminder reminder) async {
    final db = await DbService.instance.db;
    await db.update(
      'reminders',
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
    // Cancel old notification then reschedule.
    await NotificationService.instance.cancel(reminder.notificationId);
    if (reminder.isActive) await _schedule(reminder);
  }

  Future<void> delete(String reminderId) async {
    final db = await DbService.instance.db;
    final rows = await db.query('reminders',
        where: 'id = ?', whereArgs: [reminderId]);
    if (rows.isNotEmpty) {
      final r = Reminder.fromMap(rows.first);
      await NotificationService.instance.cancel(r.notificationId);
    }
    await db.delete('reminders', where: 'id = ?', whereArgs: [reminderId]);
  }

  Future<void> _schedule(Reminder r) async {
    final ns = NotificationService.instance;
    final title = '${r.type.emoji} ${r.title}';
    const body  = 'Nunarivu AI உதவ தயார் · Ready to help you study!';
    if (r.isDaily) {
      await ns.scheduleDaily(
        id: r.notificationId,
        title: title,
        body: body,
        hour: r.scheduledHour,
        minute: r.scheduledMinute,
      );
    } else if (r.onceAt != null) {
      await ns.scheduleOnce(
        id: r.notificationId,
        title: title,
        body: body,
        at: r.onceAt!,
      );
    }
  }
}
