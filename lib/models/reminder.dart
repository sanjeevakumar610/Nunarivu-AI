enum ReminderType {
  homework,
  studyTime,
  custom;

  String get tamil => switch (this) {
        ReminderType.homework  => 'வீட்டுப்பாடம்',
        ReminderType.studyTime => 'படிப்பு நேரம்',
        ReminderType.custom    => 'தனிப்பயன்',
      };

  String get english => switch (this) {
        ReminderType.homework  => 'Homework',
        ReminderType.studyTime => 'Study Time',
        ReminderType.custom    => 'Custom',
      };

  String get emoji => switch (this) {
        ReminderType.homework  => '📚',
        ReminderType.studyTime => '⏰',
        ReminderType.custom    => '✏️',
      };

  String get dbValue => name;

  static ReminderType fromDb(String v) => ReminderType.values
      .firstWhere((e) => e.name == v, orElse: () => ReminderType.custom);
}

class Reminder {
  final String id;
  final String profileId;
  final String title;
  final ReminderType type;
  final int scheduledHour;
  final int scheduledMinute;
  /// null = daily recurrence; non-null = one-time fire
  final DateTime? onceAt;
  final bool isDaily;
  final bool isActive;
  final int notificationId;
  final DateTime createdAt;

  const Reminder({
    required this.id,
    required this.profileId,
    required this.title,
    required this.type,
    required this.scheduledHour,
    required this.scheduledMinute,
    this.onceAt,
    required this.isDaily,
    required this.isActive,
    required this.notificationId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id'               : id,
        'profile_id'       : profileId,
        'title'            : title,
        'type'             : type.dbValue,
        'scheduled_hour'   : scheduledHour,
        'scheduled_minute' : scheduledMinute,
        'once_at'          : onceAt?.millisecondsSinceEpoch,
        'is_daily'         : isDaily ? 1 : 0,
        'is_active'        : isActive ? 1 : 0,
        'notification_id'  : notificationId,
        'created_at'       : createdAt.millisecondsSinceEpoch,
      };

  factory Reminder.fromMap(Map<String, dynamic> m) => Reminder(
        id             : m['id'] as String,
        profileId      : m['profile_id'] as String,
        title          : m['title'] as String,
        type           : ReminderType.fromDb(m['type'] as String),
        scheduledHour  : m['scheduled_hour'] as int,
        scheduledMinute: m['scheduled_minute'] as int,
        onceAt         : m['once_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['once_at'] as int)
            : null,
        isDaily        : (m['is_daily'] as int) == 1,
        isActive       : (m['is_active'] as int) == 1,
        notificationId : m['notification_id'] as int,
        createdAt      : DateTime.fromMillisecondsSinceEpoch(
            m['created_at'] as int),
      );

  Reminder copyWith({
    bool? isActive,
    String? title,
    ReminderType? type,
    int? scheduledHour,
    int? scheduledMinute,
    DateTime? onceAt,
    bool? isDaily,
    bool clearOnceAt = false,
  }) => Reminder(
        id             : id,
        profileId      : profileId,
        title          : title          ?? this.title,
        type           : type           ?? this.type,
        scheduledHour  : scheduledHour  ?? this.scheduledHour,
        scheduledMinute: scheduledMinute ?? this.scheduledMinute,
        onceAt         : clearOnceAt ? null : (onceAt ?? this.onceAt),
        isDaily        : isDaily        ?? this.isDaily,
        isActive       : isActive       ?? this.isActive,
        notificationId : notificationId,
        createdAt      : createdAt,
      );
}
