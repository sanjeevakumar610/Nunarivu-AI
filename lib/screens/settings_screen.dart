import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/badge_entry.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/theme_provider.dart';
import '../services/badge_service.dart';
import '../services/chat_history_service.dart';
import '../services/profile_service.dart';
import '../services/tts_service.dart';
import '../widgets/profile_avatar.dart';
import 'profile_picker_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _instrExamples = false;
  bool _instrDisability = false;
  final _customCtrl = TextEditingController();
  ReplyLength _replyLength = ReplyLength.normal;
  AiPersona _aiPersona = AiPersona.teacher;
  bool _dirty = false;
  bool _synced = false; // true once loaded from profile
  bool _badgesExpanded = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider);
    if (profile != null) _syncFromProfile(profile);
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _syncFromProfile(Profile profile) {
    _instrExamples = profile.instrExplainWithExamples;
    _instrDisability = profile.instrLearningDisability;
    _customCtrl.text = profile.customInstructions ?? '';
    _replyLength = profile.replyLength;
    _aiPersona = profile.aiPersona;
    _synced = true;
    _dirty = false;
  }

  /// Maps a free-text grade to one of the three segment values.
  String _gradeSegment(String? grade) {
    if (grade == null || grade.isEmpty) return 'other';
    if (grade.contains('10')) return 'Grade 10';
    if (grade.contains('11') || grade.toUpperCase().contains('O/L')) return 'Grade 11';
    return 'other';
  }

  Future<void> _saveInstructions() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    final updated = profile.copyWith(
      instrExplainWithExamples: _instrExamples,
      instrLearningDisability: _instrDisability,
      customInstructions: _customCtrl.text.trim(),
      replyLength: _replyLength,
      aiPersona: _aiPersona,
    );
    await ref.read(profileServiceProvider).update(updated);
    await ref.read(currentProfileProvider.notifier).setActive(updated);
    if (mounted) {
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('சேமிக்கப்பட்டது',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              Text('Instructions saved',
                  style: GoogleFonts.notoSansTamil(fontSize: 11)),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    // Re-sync local state whenever profile changes (e.g. after switch)
    if (profile != null && !_synced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _syncFromProfile(profile));
      });
    }

    final themeMode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('அமைப்புகள்',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Settings',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimary
                        .withOpacity(0.7))),
          ],
        ),
      ),
      body: ListView(
        children: [
          if (profile != null) ...[
            const SizedBox(height: 24),
            Center(
              child: Hero(
                tag: 'avatar-${profile.id}',
                child: ProfileAvatar(
                  name: profile.name,
                  seed: profile.avatarSeed,
                  size: 96,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                profile.name,
                style: GoogleFonts.notoSansTamil(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (profile.grade != null && profile.grade!.isNotEmpty)
              Center(
                child: Text(
                  '${profile.grade} · ${profile.ageGroup.tamil}',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 10),
            // ── Grade selector ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'தரம் · Grade',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Grade 10',
                          label: Text('Grade 10'),
                          icon: Icon(Icons.school_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'Grade 11',
                          label: Text('Grade 11'),
                          icon: Icon(Icons.school, size: 16),
                        ),
                        ButtonSegment(
                          value: 'other',
                          label: Text('Other'),
                          icon: Icon(Icons.more_horiz, size: 16),
                        ),
                      ],
                      selected: {
                        _gradeSegment(profile.grade),
                      },
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        textStyle: WidgetStatePropertyAll(
                            GoogleFonts.notoSansTamil(fontSize: 12)),
                      ),
                      onSelectionChanged: (sel) async {
                        final seg = sel.first;
                        if (seg == 'other') return; // direct to Edit Profile
                        final updated = profile.copyWith(grade: seg);
                        await ref.read(profileServiceProvider).update(updated);
                        await ref
                            .read(currentProfileProvider.notifier)
                            .setActive(updated);
                      },
                    ),
                  ),
                  if (_gradeSegment(profile.grade) == 'other')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Edit Profile to set a custom grade.',
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 10, color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  ref.read(currentProfileProvider.notifier).clear();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => const ProfilePickerScreen()),
                  );
                },
                icon: const Icon(Icons.swap_horiz),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('சுயவிவரம் மாற்று',
                        style: GoogleFonts.notoSansTamil(fontSize: 13)),
                    Text('Switch profile',
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
          ],

          // ── Teaching Instructions ──────────────────────────────────────────
          if (profile != null && _synced) ...[
            _SectionHeader('கற்பித்தல் அமைப்புகள் · Teaching'),

            // AI Persona dropdown
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: Text('AI என்னை எப்படி பார்க்கிறது?',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text('How should the AI relate to me?',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant)),
              trailing: DropdownButton<AiPersona>(
                value: _aiPersona,
                underline: const SizedBox.shrink(),
                items: AiPersona.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(p.tamil,
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(p.english,
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 10,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _aiPersona = v;
                      _dirty = true;
                    });
                  }
                },
              ),
            ),

            // Reply length segmented button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 20),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('பதில் நீளம்',
                              style: GoogleFonts.notoSansTamil(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          Text('Reply length',
                              style: GoogleFonts.notoSansTamil(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: SegmentedButton<ReplyLength>(
                      segments: [
                        ButtonSegment(
                          value: ReplyLength.short,
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('சுருக்கமாக',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 11)),
                              Text('Short',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 9,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        ButtonSegment(
                          value: ReplyLength.normal,
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('சாதாரண',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 11)),
                              Text('Normal',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 9,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        ButtonSegment(
                          value: ReplyLength.long,
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('விரிவாக',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 11)),
                              Text('Long',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 9,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                      selected: {_replyLength},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _replyLength = s.first;
                        _dirty = true;
                      }),
                    ),
                  ),
                ],
              ),
            ),

            // Explain with examples
            SwitchListTile(
              secondary: const Icon(Icons.lightbulb_outline),
              title: Text('உதாரணத்துடன் விளக்கவும்',
                  style: GoogleFonts.notoSansTamil(fontSize: 14)),
              subtitle: Text('Explain with examples',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant)),
              value: _instrExamples,
              onChanged: (v) => setState(() {
                _instrExamples = v;
                _dirty = true;
              }),
            ),

            // Learning disability
            SwitchListTile(
              secondary: const Icon(Icons.accessibility_new),
              title: Text('கற்றல் குறைபாடு',
                  style: GoogleFonts.notoSansTamil(fontSize: 14)),
              subtitle: Text('Learning disability — simpler language',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant)),
              value: _instrDisability,
              onChanged: (v) => setState(() {
                _instrDisability = v;
                _dirty = true;
              }),
            ),

            // Custom instructions text field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _customCtrl,
                maxLines: 3,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: InputDecoration(
                  labelText: 'கூடுதல் வழிமுறைகள் · Additional instructions',
                  labelStyle:
                      GoogleFonts.notoSansTamil(fontSize: 13),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                style: GoogleFonts.notoSansTamil(fontSize: 13),
              ),
            ),

            // Save button — only visible when dirty
            if (_dirty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: FilledButton.icon(
                  icon: const Icon(Icons.save_rounded),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('சேமி',
                          style: GoogleFonts.notoSansTamil(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('Save',
                          style: GoogleFonts.notoSansTamil(fontSize: 10)),
                    ],
                  ),
                  onPressed: _saveInstructions,
                ),
              ),

            const Divider(height: 24),
          ],

          // ── Badges ───────────────────────────────────────────────────────
          if (profile != null) ...[
            _SectionHeader('பதக்கங்கள் · Badges'),
            FutureBuilder<List<BadgeEntry>>(
              future: BadgeService.instance.getEarned(profile.id),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final badges = snap.data ?? [];
                if (badges.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text(
                      'இன்னும் பதக்கம் இல்லை — கேட்கத் தொடங்குங்கள்!\n'
                      'No badges yet — start asking questions!',
                      style: GoogleFonts.notoSansTamil(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  );
                }
                final shown = _badgesExpanded
                    ? badges
                    : badges.take(3).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: shown
                            .map((b) => _BadgeChip(entry: b))
                            .toList(),
                      ),
                    ),
                    if (badges.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _badgesExpanded = !_badgesExpanded),
                          child: Text(
                            _badgesExpanded
                                ? 'Show less ▲'
                                : 'Show all ${badges.length} badges ▼',
                            style: GoogleFonts.notoSansTamil(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(height: 24),
          ],

          // ── Appearance ────────────────────────────────────────────────────
          _SectionHeader('தோற்றம் · Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text('தீம் · Theme', style: GoogleFonts.notoSansTamil()),
            subtitle: Text(
              switch (themeMode) {
                ThemeMode.light  => 'Light',
                ThemeMode.dark   => 'Dark',
                ThemeMode.system => 'Follow system',
              },
              style: GoogleFonts.notoSansTamil(fontSize: 12),
            ),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),

          const Divider(height: 24),

          // ── Voice ─────────────────────────────────────────────────────────
          _SectionHeader('குரல் · Voice'),
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: Text('தமிழ் குரல் சோதனை',
                style: GoogleFonts.notoSansTamil()),
            subtitle: Text('Test Tamil voice',
                style: GoogleFonts.notoSansTamil(fontSize: 12)),
            onTap: () =>
                ref.read(ttsServiceProvider).speak('வணக்கம் மாணவர்களே'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('தமிழ் குரல் வேலை செய்யவில்லையா?',
                style: GoogleFonts.notoSansTamil()),
            subtitle: Text(
              'Android Settings → Language → Text-to-speech → Install Tamil voice.',
              style: GoogleFonts.notoSansTamil(fontSize: 12, height: 1.5),
            ),
          ),

          const Divider(height: 24),

          // ── Data ──────────────────────────────────────────────────────────
          _SectionHeader('தரவு · Data'),
          ListTile(
            leading: Icon(Icons.delete_sweep, color: cs.error),
            title: Text(
              'அரட்டை வரலாற்றை நீக்கு',
              style: GoogleFonts.notoSansTamil(color: cs.error),
            ),
            subtitle: Text(
              profile != null
                  ? '${profile.name} மட்டும் / For ${profile.name} only'
                  : 'This profile only',
              style: GoogleFonts.notoSansTamil(fontSize: 12),
            ),
            onTap: profile == null
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: Text('அரட்டை வரலாற்றை நீக்கவா?',
                            style: GoogleFonts.notoSansTamil()),
                        content: Text(
                            'Clear chat history?\nThis cannot be undone.',
                            style: GoogleFonts.notoSansTamil()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: Text('ரத்து / Cancel',
                                style: GoogleFonts.notoSansTamil()),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: Text('நீக்கு / Clear',
                                style: GoogleFonts.notoSansTamil()),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref
                          .read(chatHistoryServiceProvider)
                          .clearForProfile(profile.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('நீக்கப்பட்டது / Chat history cleared',
                                style: GoogleFonts.notoSansTamil()),
                          ),
                        );
                      }
                    }
                  },
          ),

          const SizedBox(height: 32),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // App logo — graduation cap
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1A237E),
                          const Color(0xFF3949AB),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1A237E).withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'நுணரிவு AI · v2.2',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Nunarivu AI · v2.2',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'மாணவர்களும் ஆசிரியர்களும் தமிழில்\n'
                    'AI உதவியுடன் கற்க உருவாக்கப்பட்டது.',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withOpacity(0.85),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Built for students and teachers to learn\n'
                    'in Tamil language using AI assistant.',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withOpacity(0.55),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Gemma is a trademark of Google LLC.',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 9,
                      color: cs.onSurfaceVariant.withOpacity(0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: cs.primary.withOpacity(0.2), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 13, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          'உங்கள் தரவு உங்கள் சாதனத்திலேயே உள்ளது.\n'
                          'எந்தத் தகவலும் சர்வருக்கு அனுப்பப்படவில்லை.',
                          style: GoogleFonts.notoSansTamil(
                            fontSize: 10,
                            color: cs.primary,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.notoSansTamil(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── Badge chip ───────────────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final BadgeEntry entry;
  const _BadgeChip({required this.entry});

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade300.withOpacity(0.85),
            Colors.amber.shade600.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(entry.badgeType.emoji,
              style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            entry.badgeType.tamil,
            style: GoogleFonts.notoSansTamil(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.brown.shade800,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            entry.badgeType.english,
            style: GoogleFonts.notoSansTamil(
              fontSize: 8,
              color: Colors.brown.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _fmtDate(entry.earnedAt),
            style: TextStyle(
              fontSize: 7,
              color: cs.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
