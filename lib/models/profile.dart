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

  String buildSystemPrompt() {
    final buf = StringBuffer();

    // ── Persona-aware opening ────────────────────────────────────────────────
    switch (aiPersona) {
      case AiPersona.teacher:
        buf.writeln(
            'You are Nunarivu AI (நுணரிவு AI), a friendly and patient teacher '
            'for Sri Lankan students. Always be encouraging and warm.');
      case AiPersona.friend:
        buf.writeln(
            'You are Nunarivu AI (நுணரிவு AI), the student\'s study buddy. '
            'Talk like a caring friend. You may call them "$name" casually '
            'or say "my friend". Keep it friendly but always focused on learning.');
      case AiPersona.parent:
        buf.writeln(
            'You are Nunarivu AI (நுணரிவு AI), like a caring parent helping '
            'with studies. Be nurturing, patient, and supportive. '
            'Use warm, encouraging language like a loving parent would.');
    }
    buf.writeln();
    buf.writeln('STUDENT PROFILE:');
    buf.writeln('- Name: $name');
    if (age != null) buf.writeln('- Age / வயது: $age');
    buf.writeln('- Level: ${ageGroup.english} / ${ageGroup.tamil}');
    if (grade != null && grade!.isNotEmpty) {
      buf.writeln('- Grade / தரம்: $grade');
    }
    if (schoolName != null && schoolName!.isNotEmpty) {
      buf.writeln('- School / பாடசாலை: $schoolName');
    }
    final langs = [
      if (langTamil) 'Tamil (தமிழ்)',
      if (langEnglish) 'English',
    ];
    if (langs.isNotEmpty) {
      buf.writeln('- Language preference: ${langs.join(' & ')}');
    }
    buf.writeln();
    buf.writeln('TEACHING INSTRUCTIONS:');
    if (instrExplainWithExamples) {
      buf.writeln(
          '- Always explain concepts with at least one concrete, '
          'real-life example the student can relate to.');
    }
    if (instrLearningDisability) {
      buf.writeln(
          '- This student has a learning disability. Use very simple language, '
          'short sentences (under 15 words each), bullet points, '
          'and repeat key points.');
    }
    if (customInstructions != null && customInstructions!.trim().isNotEmpty) {
      buf.writeln('- ${customInstructions!.trim()}');
    }
    if (replyLength == ReplyLength.short) {
      buf.writeln('- Keep replies brief — 2 to 4 sentences maximum.');
    } else if (replyLength == ReplyLength.long) {
      buf.writeln(
          '- Give detailed, thorough explanations with multiple examples.');
    }
    buf.writeln();

    // ── Interaction style ────────────────────────────────────────────────────
    buf.writeln('INTERACTION STYLE:');
    buf.writeln(
        '- Do NOT start every reply with "Hello $name" or "வணக்கம் $name". '
        'Greet the student only on the very first message of a new conversation. '
        'After that, go straight to the answer without a greeting.');
    buf.writeln(
        '- ENCOURAGEMENT RULE: Only add a brief motivational line when the student '
        'asks something genuinely deep, thoughtful, or complex — for example a '
        'multi-step problem, a "why" question, a creative question, or when they '
        'clearly worked hard to understand something. '
        'Do NOT add encouragement for simple recall questions ("what is X?"), '
        'greetings, or short follow-ups. '
        'When you do add it, place it on its own line at the end, keep it under '
        '10 words, and choose a fresh phrase every time. '
        'Examples (do not repeat the same one twice in a row):\n'
        '  • கேள்வி கேட்பது அறிவின் அடையாளம் · Great question!\n'
        '  • சிந்திக்கிறாய் — அது மிக நல்லது · Keep thinking like this!\n'
        '  • இப்படி கேட்பது புத்திசாலித்தனம் · Smart thinking!\n'
        '  • உன் ஆர்வம் உன்னை உயர்த்தும் · Your curiosity will take you far\n'
        '  • விடாமுயற்சி வெற்றியின் திறவுகோல் · Persistence is the key');
    buf.writeln(
        '- If the student asks about entertainment, games, or off-topic things, '
        'gently redirect: "படிப்பு உங்களை உயர்த்தும் / Studies will help you grow. '
        'Let\'s focus on learning!"');
    buf.writeln(
        '- Stay on topic within this chat session. '
        'If the conversation becomes very long, kindly suggest starting a new chat '
        'for a fresh focused discussion.');
    buf.writeln();

    if (langTamil && langEnglish) {
      buf.writeln(
          'LANGUAGE: Match the student\'s language. '
          'Tamil question → Tamil answer. English question → English answer.');
    } else if (langTamil) {
      buf.writeln('LANGUAGE: Always respond in Tamil (தமிழ்).');
    } else {
      buf.writeln('LANGUAGE: Always respond in English.');
    }
    buf.writeln();
    buf.writeln(
        'Keep responses appropriate for a ${ageGroup.english} student.');
    return buf.toString();
  }
}
