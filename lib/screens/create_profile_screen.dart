import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
import 'home_screen.dart';

/// Full bilingual profile creation / edit form.
///
/// Pass [existingProfile] to enter edit mode (updates in place).
/// When [navigateHome] is true the screen replaces itself with [HomeScreen]
/// after saving — used from onboarding and profile picker.
class CreateProfileScreen extends ConsumerStatefulWidget {
  final Profile? existingProfile;
  final bool navigateHome;

  const CreateProfileScreen({
    super.key,
    this.existingProfile,
    this.navigateHome = true,
  });

  @override
  ConsumerState<CreateProfileScreen> createState() =>
      _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final _nameCtrl    = TextEditingController();
  final _ageCtrl     = TextEditingController();
  final _schoolCtrl  = TextEditingController();
  final _customCtrl  = TextEditingController();

  // Grade selection: 'Grade 10', 'Grade 11', 'others', or null (unset)
  String? _selectedGrade;

  bool _langTamil   = true;
  bool _langEnglish = true;
  AgeGroup _ageGroup = AgeGroup.school;
  bool _instrExamples  = false;
  bool _instrDisability = false;
  bool _busy = false;

  bool get _isEdit => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    if (p != null) {
      _nameCtrl.text   = p.name;
      _ageCtrl.text    = p.age?.toString() ?? '';
      _schoolCtrl.text = p.schoolName ?? '';
      _customCtrl.text = p.customInstructions ?? '';
      _langTamil    = p.langTamil;
      _langEnglish  = p.langEnglish;
      _ageGroup     = p.ageGroup;
      _instrExamples   = p.instrExplainWithExamples;
      _instrDisability = p.instrLearningDisability;
      // Map existing grade string → chip selection
      final g = p.grade ?? '';
      if (g.contains('10')) {
        _selectedGrade = 'Grade 10';
      } else if (g.contains('11') || g.toUpperCase().contains('O/L')) {
        _selectedGrade = 'Grade 11';
      } else if (g.isNotEmpty) {
        _selectedGrade = 'others';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _schoolCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    if (!_langTamil && !_langEnglish) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one language / ஒரு மொழியையாவது தேர்ந்தெடுங்கள்')),
      );
      return;
    }
    setState(() => _busy = true);

    final age = int.tryParse(_ageCtrl.text.trim());
    final schoolName = _schoolCtrl.text.trim().isEmpty ? null : _schoolCtrl.text.trim();
    // Map chip selection back to a grade string stored in profile.
    // 'Grade 10' → 'Grade 10', 'Grade 11' → 'Grade 11', 'others'/'null' → null
    final String? grade = (_selectedGrade == 'Grade 10' || _selectedGrade == 'Grade 11')
        ? _selectedGrade
        : null;
    final custom = _customCtrl.text.trim().isEmpty ? null : _customCtrl.text.trim();

    try {
      if (_isEdit) {
        final updated = widget.existingProfile!.copyWith(
          name: name,
          langTamil: _langTamil,
          langEnglish: _langEnglish,
          ageGroup: _ageGroup,
          age: age,
          schoolName: schoolName,
          grade: grade,
          instrExplainWithExamples: _instrExamples,
          instrLearningDisability: _instrDisability,
          customInstructions: custom,
        );
        await ref.read(profileServiceProvider).update(updated);
        // Refresh current profile state
        await ref.read(currentProfileProvider.notifier).setActive(updated);
        ref.invalidate(allProfilesProvider);
        if (mounted) Navigator.of(context).pop(updated);
      } else {
        final p = await ref.read(profileServiceProvider).create(
          name,
          langTamil: _langTamil,
          langEnglish: _langEnglish,
          ageGroup: _ageGroup,
          age: age,
          schoolName: schoolName,
          grade: grade,
          instrExplainWithExamples: _instrExamples,
          instrLearningDisability: _instrDisability,
          customInstructions: custom,
        );
        await ref.read(currentProfileProvider.notifier).setActive(p);
        ref.invalidate(allProfilesProvider);
        if (!mounted) return;
        if (widget.navigateHome) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          Navigator.of(context).pop(p);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'சுயவிவரம் திருத்து' : 'புதிய சுயவிவரம்',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _isEdit ? 'Edit Profile' : 'Create Profile',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 11, color: cs.onPrimary.withOpacity(0.7)),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // ── Name ────────────────────────────────────────────────────
            _SectionTitle(tamil: 'பெயர்', english: 'Name'),
            TextField(
              controller: _nameCtrl,
              style: GoogleFonts.notoSansTamil(fontSize: 17),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'உங்கள் பெயர் / Your name',
                hintStyle: GoogleFonts.notoSansTamil(
                    color: cs.onSurfaceVariant, fontSize: 14),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ).animate().fadeIn(delay: 100.ms),

            // ── Language ─────────────────────────────────────────────────
            _SectionTitle(tamil: 'மொழி', english: 'Language'),
            Row(
              children: [
                Expanded(
                  child: _LangChip(
                    label: 'தமிழ்',
                    sublabel: 'Tamil',
                    selected: _langTamil,
                    onTap: () => setState(() => _langTamil = !_langTamil),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LangChip(
                    label: 'English',
                    sublabel: 'ஆங்கிலம்',
                    selected: _langEnglish,
                    onTap: () => setState(() => _langEnglish = !_langEnglish),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 150.ms),

            // ── Level ─────────────────────────────────────────────────────
            _SectionTitle(tamil: 'நிலை', english: 'Level'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AgeGroup.values.map((g) {
                final selected = _ageGroup == g;
                return ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(g.tamil,
                          style: GoogleFonts.notoSansTamil(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      Text(g.english,
                          style: GoogleFonts.notoSansTamil(
                              fontSize: 10,
                              color: selected
                                  ? cs.onSecondaryContainer
                                  : cs.onSurfaceVariant)),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _ageGroup = g),
                );
              }).toList(),
            ).animate().fadeIn(delay: 200.ms),

            // ── Age / Grade / School ─────────────────────────────────────
            _SectionTitle(tamil: 'வயது', english: 'Age'),
            TextField(
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.notoSansTamil(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'வயது / Age',
                hintStyle:
                    GoogleFonts.notoSansTamil(color: cs.onSurfaceVariant),
                prefixIcon: const Icon(Icons.cake_outlined),
              ),
            ).animate().fadeIn(delay: 250.ms),

            _SectionTitle(tamil: 'தரம்', english: 'Grade'),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _GradeChip(
                  tamilLabel: 'தரம் 10',
                  englishLabel: 'Grade 10',
                  value: 'Grade 10',
                  selected: _selectedGrade == 'Grade 10',
                  onTap: () => setState(() =>
                      _selectedGrade = _selectedGrade == 'Grade 10' ? null : 'Grade 10'),
                ),
                _GradeChip(
                  tamilLabel: 'தரம் 11',
                  englishLabel: 'O/L · Grade 11',
                  value: 'Grade 11',
                  selected: _selectedGrade == 'Grade 11',
                  onTap: () => setState(() =>
                      _selectedGrade = _selectedGrade == 'Grade 11' ? null : 'Grade 11'),
                ),
                _GradeChip(
                  tamilLabel: 'மற்றவை',
                  englishLabel: 'Others',
                  value: 'others',
                  selected: _selectedGrade == 'others',
                  onTap: () => setState(() =>
                      _selectedGrade = _selectedGrade == 'others' ? null : 'others'),
                ),
              ],
            ).animate().fadeIn(delay: 280.ms),

            _SectionTitle(tamil: 'பாடசாலை', english: 'School'),
            TextField(
              controller: _schoolCtrl,
              style: GoogleFonts.notoSansTamil(fontSize: 16),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'பாடசாலை பெயர் / School name',
                hintStyle:
                    GoogleFonts.notoSansTamil(color: cs.onSurfaceVariant),
                prefixIcon: const Icon(Icons.school_outlined),
              ),
            ).animate().fadeIn(delay: 310.ms),

            // ── Special Instructions ──────────────────────────────────────
            _SectionTitle(
                tamil: 'சிறப்பு வழிமுறைகள்',
                english: 'Special Instructions'),

            _InstructionTile(
              tamilTitle: 'உதாரணத்துடன் விளக்கவும்',
              englishTitle: 'Explain with examples',
              tamilDesc: 'ஒவ்வொரு பதிலிலும் உதாரணம் தர வேண்டும்',
              englishDesc: 'Model always gives real-life examples',
              icon: Icons.lightbulb_outline,
              value: _instrExamples,
              onChanged: (v) => setState(() => _instrExamples = v),
            ).animate().fadeIn(delay: 350.ms),

            _InstructionTile(
              tamilTitle: 'கற்றல் குறைபாடு',
              englishTitle: 'Learning Disability',
              tamilDesc: 'எளிய மொழி, குறுகிய வாக்கியங்கள்',
              englishDesc: 'Simple language, short sentences, extra patience',
              icon: Icons.favorite_border,
              value: _instrDisability,
              onChanged: (v) => setState(() => _instrDisability = v),
            ).animate().fadeIn(delay: 380.ms),

            // ── Custom instructions ───────────────────────────────────────
            _SectionTitle(
                tamil: 'கூடுதல் வழிமுறைகள்',
                english: 'Additional Instructions'),
            TextField(
              controller: _customCtrl,
              style: GoogleFonts.notoSansTamil(fontSize: 14),
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'மாதிரிக்கு கூடுதல் வழிமுறைகள் தட்டச்சு செய்யவும்…\n'
                    'Type any extra instructions for the AI model…',
                hintStyle: GoogleFonts.notoSansTamil(
                    color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ).animate().fadeIn(delay: 410.ms),

            const SizedBox(height: 32),

            // ── Save button ──────────────────────────────────────────────
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isEdit ? 'சேமி' : 'தொடங்கு',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _isEdit ? 'Save' : 'Get started',
                    style: GoogleFonts.notoSansTamil(fontSize: 11),
                  ),
                ],
              ),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ).animate().fadeIn(delay: 450.ms),
          ],
        ),
      ),
    );
  }
}

// ── Shared UI helpers ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String tamil;
  final String english;
  const _SectionTitle({required this.tamil, required this.english});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tamil,
              style: GoogleFonts.notoSansTamil(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary)),
          Text(english,
              style: GoogleFonts.notoSansTamil(
                  fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;
  const _LangChip({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withOpacity(0.4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? cs.onPrimaryContainer
                            : cs.onSurface)),
                Text(sublabel,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11,
                        color: selected
                            ? cs.onPrimaryContainer.withOpacity(0.7)
                            : cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  final String tamilLabel;
  final String englishLabel;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _GradeChip({
    required this.tamilLabel,
    required this.englishLabel,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withOpacity(0.4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tamilLabel,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        color: selected
                            ? cs.onPrimaryContainer
                            : cs.onSurface)),
                Text(englishLabel,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 10,
                        color: selected
                            ? cs.onPrimaryContainer.withOpacity(0.7)
                            : cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionTile extends StatelessWidget {
  final String tamilTitle;
  final String englishTitle;
  final String tamilDesc;
  final String englishDesc;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _InstructionTile({
    required this.tamilTitle,
    required this.englishTitle,
    required this.tamilDesc,
    required this.englishDesc,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: value ? cs.secondaryContainer : null,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: value ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tamilTitle,
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: value
                                ? cs.onSecondaryContainer
                                : cs.onSurface)),
                    Text(englishTitle,
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 11,
                            color: value
                                ? cs.onSecondaryContainer.withOpacity(0.8)
                                : cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(tamilDesc,
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 11,
                            color: value
                                ? cs.onSecondaryContainer.withOpacity(0.7)
                                : cs.onSurfaceVariant)),
                    Text(englishDesc,
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 10,
                            color: value
                                ? cs.onSecondaryContainer.withOpacity(0.6)
                                : cs.onSurfaceVariant.withOpacity(0.8))),
                  ],
                ),
              ),
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: cs.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
