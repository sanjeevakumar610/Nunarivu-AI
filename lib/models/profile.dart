enum AiPersona {
  teacher,
  friend,
  parent;

  String get tamil => switch (this) {
        AiPersona.teacher => 'ஆசிரியர்',
        AiPersona.friend  => 'நண்பர்',
        AiPersona.parent  => 'பெற்றோர்',
      };

  String get english => switch (this) {
        AiPersona.teacher => 'Teacher',
        AiPersona.friend  => 'Friend',
        AiPersona.parent  => 'Parent',
      };

  String get dbValue => name;

  static AiPersona fromDb(String? v) => switch (v) {
        'friend' => AiPersona.friend,
        'parent' => AiPersona.parent,
        _        => AiPersona.teacher,
      };
}

enum ReplyLength {
  normal,
  short,
  long;

  String get tamil => switch (this) {
        ReplyLength.normal => 'சாதாரண',
        ReplyLength.short  => 'சுருக்கமாக',
        ReplyLength.long   => 'விரிவாக',
      };

  String get english => switch (this) {
        ReplyLength.normal => 'Normal',
        ReplyLength.short  => 'Short',
        ReplyLength.long   => 'Long',
      };

  String get dbValue => name; // 'normal' | 'short' | 'long'

  static ReplyLength fromDb(String? v) => switch (v) {
        'short' => ReplyLength.short,
        'long'  => ReplyLength.long,
        _       => ReplyLength.normal,
      };
}

enum AgeGroup {
  kids,
  school,
  highSchool,
  languageLearner;

  String get tamil => switch (this) {
        AgeGroup.kids            => 'குழந்தைகள்',
        AgeGroup.school          => 'பாடசாலை',
        AgeGroup.highSchool      => 'உயர்நிலை',
        AgeGroup.languageLearner => 'மொழி கற்பவர்',
      };

  String get english => switch (this) {
        AgeGroup.kids            => 'Kids (1–5)',
        AgeGroup.school          => 'School',
        AgeGroup.highSchool      => 'High School',
        AgeGroup.languageLearner => 'Language Learner',
      };

  String get dbValue => switch (this) {
        AgeGroup.kids            => 'kids',
        AgeGroup.school          => 'school',
        AgeGroup.highSchool      => 'high_school',
        AgeGroup.languageLearner => 'language_learner',
      };

  static AgeGroup fromDb(String v) => switch (v) {
        'kids'             => AgeGroup.kids,
        'school'           => AgeGroup.school,
        'high_school'      => AgeGroup.highSchool,
        'language_learner' => AgeGroup.languageLearner,
        _                  => AgeGroup.school,
      };
}

class Profile {
  final String id;
  final String name;

  /// Stable seed used to generate avatar colour deterministically.
  final int avatarSeed;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  // ── Language preferences ─────────────────────────────────────────────────
  final bool langTamil;
  final bool langEnglish;

  // ── Student context ──────────────────────────────────────────────────────
  final AgeGroup ageGroup;
  final int? age;
  final String? schoolName;
  final String? grade;

  // ── Teaching instructions ────────────────────────────────────────────────
  final bool instrExplainWithExamples;
  final bool instrLearningDisability;
  final String? customInstructions;
  final ReplyLength replyLength;
  final AiPersona aiPersona;

  const Profile({
    required this.id,
    required this.name,
    required this.avatarSeed,
    required this.createdAt,
    required this.lastUsedAt,
    this.langTamil = true,
    this.langEnglish = true,
    this.ageGroup = AgeGroup.school,
    this.age,
    this.schoolName,
    this.grade,
    this.instrExplainWithExamples = false,
    this.instrLearningDisability = false,
    this.customInstructions,
    this.replyLength = ReplyLength.normal,
    this.aiPersona = AiPersona.teacher,
  });

  Profile copyWith({
    String? name,
    DateTime? lastUsedAt,
    bool? langTamil,
    bool? langEnglish,
    AgeGroup? ageGroup,
    int? age,
    String? schoolName,
    String? grade,
    bool? instrExplainWithExamples,
    bool? instrLearningDisability,
    String? customInstructions,
    ReplyLength? replyLength,
    AiPersona? aiPersona,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        avatarSeed: avatarSeed,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        langTamil: langTamil ?? this.langTamil,
        langEnglish: langEnglish ?? this.langEnglish,
        ageGroup: ageGroup ?? this.ageGroup,
        age: age ?? this.age,
        schoolName: schoolName ?? this.schoolName,
        grade: grade ?? this.grade,
        instrExplainWithExamples:
            instrExplainWithExamples ?? this.instrExplainWithExamples,
        instrLearningDisability:
            instrLearningDisability ?? this.instrLearningDisability,
        customInstructions: customInstructions ?? this.customInstructions,
        replyLength: replyLength ?? this.replyLength,
        aiPersona: aiPersona ?? this.aiPersona,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'avatar_seed': avatarSeed,
        'created_at': createdAt.millisecondsSinceEpoch,
        'last_used_at': lastUsedAt.millisecondsSinceEpoch,
        'lang_tamil': langTamil ? 1 : 0,
        'lang_english': langEnglish ? 1 : 0,
        'age_group': ageGroup.dbValue,
        'age': age,
        'school_name': schoolName,
        'grade': grade,
        'instr_examples': instrExplainWithExamples ? 1 : 0,
        'instr_disability': instrLearningDisability ? 1 : 0,
        'custom_instructions': customInstructions,
        'reply_length': replyLength.dbValue,
        'ai_persona': aiPersona.dbValue,
      };

  factory Profile.fromMap(Map<String, Object?> m) => Profile(
        id: m['id'] as String,
        name: m['name'] as String,
        avatarSeed: m['avatar_seed'] as int,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        lastUsedAt:
            DateTime.fromMillisecondsSinceEpoch(m['last_used_at'] as int),
        langTamil:   (m['lang_tamil']    as int? ?? 1) == 1,
        langEnglish: (m['lang_english']  as int? ?? 1) == 1,
        ageGroup:    AgeGroup.fromDb(m['age_group'] as String? ?? 'school'),
        age:         m['age']         as int?,
        schoolName:  m['school_name'] as String?,
        grade:       m['grade']       as String?,
        instrExplainWithExamples: (m['instr_examples']   as int? ?? 0) == 1,
        instrLearningDisability:  (m['instr_disability']  as int? ?? 0) == 1,
        customInstructions: m['custom_instructions'] as String?,
        replyLength: ReplyLength.fromDb(m['reply_length'] as String?),
        aiPersona: AiPersona.fromDb(m['ai_persona'] as String?),
      );

  // ── System prompt built from profile ─────────────────────────────────────
  //
  // Keep this SHORT and simple — the Gemma 4 E2B model returns 0 tokens when
  // the system prompt is too long or contains complex multi-line structure.
  // The library chat's _buildPrompt (which always works) is the reference:
  // short, plain English, no empty sections, ends with a clear answer signal.

  String buildSystemPrompt() {
    final buf = StringBuffer();

    // Role
    switch (aiPersona) {
      case AiPersona.teacher:
        buf.write('You are Nunarivu AI, a helpful and patient tutor for $name.');
      case AiPersona.friend:
        buf.write('You are Nunarivu AI, a friendly study buddy for $name.');
      case AiPersona.parent:
        buf.write('You are Nunarivu AI, a caring and supportive tutor for $name.');
    }

    // Grade / level — only if set
    if (grade != null && grade!.isNotEmpty) {
      buf.write(' Student is in $grade.');
    } else {
      buf.write(' Student level: ${ageGroup.english}.');
    }

    // Teaching flags — only written when enabled, so section is never empty
    if (instrExplainWithExamples) {
      buf.write(' Always include a real-life example in your explanation.');
    }
    if (instrLearningDisability) {
      buf.write(' Use very simple language and short sentences (under 15 words each).');
    }
    if (replyLength == ReplyLength.short) {
      buf.write(' Keep the reply to 2-4 sentences.');
    } else if (replyLength == ReplyLength.long) {
      buf.write(' Give a detailed explanation with examples.');
    }
    if (customInstructions != null && customInstructions!.trim().isNotEmpty) {
      buf.write(' ${customInstructions!.trim()}');
    }

    // Language
    if (langTamil && langEnglish) {
      buf.write(' Reply in Tamil if the student writes in Tamil, English if in English.');
    } else if (langTamil) {
      buf.write(' Always reply in Tamil.');
    } else {
      buf.write(' Always reply in English.');
    }

    return buf.toString();
  }
}
