import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../models/reminder.dart';
import '../providers/profile_provider.dart';
import '../services/notification_service.dart';
import '../services/reminder_service.dart';

const _uuid = Uuid();

class ReminderScreen extends ConsumerStatefulWidget {
  const ReminderScreen({super.key});

  @override
  ConsumerState<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends ConsumerState<ReminderScreen> {
  List<Reminder>? _reminders;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final reminders =
        await ReminderService.instance.loadForProfile(profile.id);
    if (mounted) setState(() { _reminders = reminders; _loading = false; });
  }

  Future<void> _addReminder() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final result = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddReminderSheet(profileId: profile.id),
    );
    if (result == null) return;

    await NotificationService.instance.requestPermission();
    try {
      await ReminderService.instance.create(result);
    } catch (e) {
      print('ReminderScreen: create error: $e');
    }
    await _load(); // always refresh list, even if scheduling failed
  }

  Future<void> _editReminder(Reminder r) async {
    final result = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddReminderSheet(
        profileId: r.profileId,
        existing: r,
      ),
    );
    if (result == null) return;
    await ReminderService.instance.update(result);
    await _load();
  }

  Future<void> _toggleReminder(Reminder r, bool active) async {
    await ReminderService.instance.toggle(r, isActive: active);
    setState(() {
      final idx = _reminders?.indexWhere((e) => e.id == r.id) ?? -1;
      if (idx >= 0) _reminders![idx] = r.copyWith(isActive: active);
    });
  }

  Future<void> _confirmDelete(Reminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('நீக்கவா? · Delete?',
            style: GoogleFonts.notoSansTamil()),
        content: Text('"${r.title}"\nThis reminder will be deleted.',
            style: GoogleFonts.notoSansTamil()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ரத்து · Cancel',
                style: GoogleFonts.notoSansTamil()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('நீக்கு · Delete',
                style: GoogleFonts.notoSansTamil()),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ReminderService.instance.delete(r.id);
      setState(() => _reminders?.remove(r));
    }
  }

  String _fmtTime(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('நினைவூட்டல்கள்',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Study Reminders',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimary
                        .withOpacity(0.7))),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_reminders == null || _reminders!.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 72,
                          color: cs.onSurfaceVariant.withOpacity(0.35)),
                      const SizedBox(height: 16),
                      Text('நினைவூட்டல் இல்லை',
                          style: GoogleFonts.notoSansTamil(
                              fontSize: 18, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('No reminders yet.\nTap + to add a study alarm.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTamil(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _reminders!.length,
                  itemBuilder: (_, i) {
                    final r = _reminders![i];
                    return Dismissible(
                      key: Key(r.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        await _confirmDelete(r);
                        return false; // we handle list removal ourselves
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.delete_outline,
                            color: cs.onErrorContainer),
                      ),
                      child: Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              // Emoji icon
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(r.type.emoji,
                                      style:
                                          const TextStyle(fontSize: 24)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Title + time
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(r.title,
                                        style: GoogleFonts.notoSansTamil(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      r.isDaily
                                          ? 'தினசரி ${_fmtTime(r.scheduledHour, r.scheduledMinute)} · Daily'
                                          : 'ஒரே ஒருமுறை ${_fmtTime(r.scheduledHour, r.scheduledMinute)} · Once',
                                      style: GoogleFonts.notoSansTamil(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant),
                                    ),
                                    Text(r.type.english,
                                        style: GoogleFonts.notoSansTamil(
                                            fontSize: 10,
                                            color: cs.primary
                                                .withOpacity(0.8))),
                                  ],
                                ),
                              ),
                              // Edit time / details
                              IconButton(
                                icon: Icon(Icons.edit_outlined,
                                    size: 20, color: cs.primary),
                                tooltip: 'நேரம் மாற்று · Edit',
                                onPressed: () => _editReminder(r),
                              ),
                              // Active toggle
                              Switch(
                                value: r.isActive,
                                onChanged: (v) => _toggleReminder(r, v),
                              ),
                              // Delete
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 20, color: cs.error),
                                tooltip: 'நீக்கு · Delete',
                                onPressed: () => _confirmDelete(r),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReminder,
        icon: const Icon(Icons.add_alarm_rounded),
        label: Text('நினைவூட்டல் சேர்',
            style: GoogleFonts.notoSansTamil(fontSize: 13)),
      ),
    );
  }
}

// ─── Add Reminder Sheet ────────────────────────────────────────────────────────

class _AddReminderSheet extends StatefulWidget {
  final String profileId;
  /// When non-null, the sheet is in "edit" mode — pre-filled with existing data.
  final Reminder? existing;
  const _AddReminderSheet({required this.profileId, this.existing});

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  late ReminderType _type;
  late TextEditingController _titleCtrl;
  late TimeOfDay _time;
  late bool _isDaily;
  late DateTime _onceDate;

  bool get _isEdit => widget.existing != null;

  // Simple auto-increment for notification IDs; starts at 200 to avoid
  // collision with any system IDs.
  static int _nextId = 200;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      // Edit mode — pre-fill from existing reminder.
      _type     = ex.type;
      _time     = TimeOfDay(hour: ex.scheduledHour, minute: ex.scheduledMinute);
      _isDaily  = ex.isDaily;
      _onceDate = ex.onceAt ?? DateTime.now().add(const Duration(hours: 1));
      _titleCtrl = TextEditingController(text: ex.title);
    } else {
      _type     = ReminderType.studyTime;
      _time     = const TimeOfDay(hour: 18, minute: 0);
      _isDaily  = true;
      _onceDate = DateTime.now().add(const Duration(hours: 1));
      _titleCtrl = TextEditingController(text: ReminderType.studyTime.english);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _onceDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _onceDate = DateTime(
            picked.year, picked.month, picked.day, _time.hour, _time.minute);
      });
    }
  }

  String _fmtTime() {
    final h = _time.hourOfPeriod == 0 ? 12 : _time.hourOfPeriod;
    final m = _time.minute.toString().padLeft(2, '0');
    final period = _time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(_isEdit ? 'நினைவூட்டல் திருத்து' : 'நினைவூட்டல் சேர்',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          Text(_isEdit ? 'Edit Reminder' : 'Add Reminder',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),

          // Type selector
          Text('வகை · Type',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ReminderType.values.map((t) {
              final sel = _type == t;
              return ChoiceChip(
                avatar: Text(t.emoji),
                label: Text(t.english,
                    style: GoogleFonts.notoSansTamil(fontSize: 12)),
                selected: sel,
                onSelected: (_) => setState(() {
                  _type = t;
                  if (_titleCtrl.text.isEmpty ||
                      ReminderType.values
                          .map((x) => x.english)
                          .contains(_titleCtrl.text)) {
                    _titleCtrl.text = t.english;
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Title
          TextField(
            controller: _titleCtrl,
            style: GoogleFonts.notoSansTamil(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'தலைப்பு · Title',
              labelStyle: GoogleFonts.notoSansTamil(fontSize: 13),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          // Time picker
          Row(
            children: [
              Icon(Icons.access_time_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                _fmtTime(),
                style: GoogleFonts.notoSansTamil(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.primary),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _pickTime,
                child: Text('மாற்று · Change',
                    style: GoogleFonts.notoSansTamil(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Daily toggle
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('தினசரி நினைவூட்டல்',
                style: GoogleFonts.notoSansTamil(fontSize: 14)),
            subtitle: Text('Repeat every day',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 11, color: cs.onSurfaceVariant)),
            value: _isDaily,
            onChanged: (v) => setState(() => _isDaily = v),
          ),

          // One-time date picker
          if (!_isDaily) ...[
            Row(
              children: [
                Icon(Icons.calendar_today, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  '${_onceDate.day}/${_onceDate.month}/${_onceDate.year}',
                  style: GoogleFonts.notoSansTamil(fontSize: 15),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _pickDate,
                  child: Text('தேதி · Pick date',
                      style: GoogleFonts.notoSansTamil(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),

          // Save
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(_isEdit ? 'சேமி · Save Changes' : 'சேமி · Save Reminder',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              onPressed: () {
                final title = _titleCtrl.text.trim();
                if (title.isEmpty) return;
                final onceAt = _isDaily
                    ? null
                    : DateTime(_onceDate.year, _onceDate.month, _onceDate.day,
                        _time.hour, _time.minute);
                final ex = widget.existing;
                final reminder = ex != null
                    // Edit mode: keep same id, notificationId, profileId, createdAt.
                    ? ex.copyWith(
                        title          : title,
                        type           : _type,
                        scheduledHour  : _time.hour,
                        scheduledMinute: _time.minute,
                        onceAt         : onceAt,
                        isDaily        : _isDaily,
                        clearOnceAt    : _isDaily,
                      )
                    // New reminder.
                    : Reminder(
                        id             : _uuid.v4(),
                        profileId      : widget.profileId,
                        title          : title,
                        type           : _type,
                        scheduledHour  : _time.hour,
                        scheduledMinute: _time.minute,
                        onceAt         : onceAt,
                        isDaily        : _isDaily,
                        isActive       : true,
                        notificationId : _nextId++,
                        createdAt      : DateTime.now(),
                      );
                Navigator.pop(context, reminder);
              },
            ),
          ),
        ],
      ),
    );
  }
}
