enum BadgeType {
  firstStep,
  curious,
  studyBuddy,
  scholar,
  champion,
  dedicated,
  weekStreak,
  monthUser;

  String get tamil => switch (this) {
        BadgeType.firstStep  => 'முதல் படி',
        BadgeType.curious    => 'ஆர்வமுள்ளவன்',
        BadgeType.studyBuddy => 'படிப்பு நண்பன்',
        BadgeType.scholar    => 'அறிஞர்',
        BadgeType.champion   => 'சாம்பியன்',
        BadgeType.dedicated  => 'அர்ப்பணிப்பு',
        BadgeType.weekStreak => 'வாரத் தொடர்',
        BadgeType.monthUser  => 'மாத மாணவன்',
      };

  String get english => switch (this) {
        BadgeType.firstStep  => 'First Step',
        BadgeType.curious    => 'Curious',
        BadgeType.studyBuddy => 'Study Buddy',
        BadgeType.scholar    => 'Scholar',
        BadgeType.champion   => 'Champion',
        BadgeType.dedicated  => 'Dedicated',
        BadgeType.weekStreak => 'Week Streak',
        BadgeType.monthUser  => 'Month Scholar',
      };

  String get emoji => switch (this) {
        BadgeType.firstStep  => '🌱',
        BadgeType.curious    => '🔍',
        BadgeType.studyBuddy => '📖',
        BadgeType.scholar    => '🎓',
        BadgeType.champion   => '🏆',
        BadgeType.dedicated  => '💎',
        BadgeType.weekStreak => '🔥',
        BadgeType.monthUser  => '⭐',
      };

  String get dbValue => name;

  static BadgeType fromDb(String v) => BadgeType.values
      .firstWhere((e) => e.name == v, orElse: () => BadgeType.firstStep);
}

class BadgeEntry {
  final String id;
  final String profileId;
  final BadgeType badgeType;
  final DateTime earnedAt;

  const BadgeEntry({
    required this.id,
    required this.profileId,
    required this.badgeType,
    required this.earnedAt,
  });

  Map<String, dynamic> toMap() => {
        'id'         : id,
        'profile_id' : profileId,
        'badge_type' : badgeType.dbValue,
        'earned_at'  : earnedAt.millisecondsSinceEpoch,
      };

  factory BadgeEntry.fromMap(Map<String, dynamic> m) => BadgeEntry(
        id        : m['id'] as String,
        profileId : m['profile_id'] as String,
        badgeType : BadgeType.fromDb(m['badge_type'] as String),
        earnedAt  : DateTime.fromMillisecondsSinceEpoch(m['earned_at'] as int),
      );
}
