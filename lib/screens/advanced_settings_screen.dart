import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/model_service.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _modelFileName = 'gemma-4-E2B-it-litert-lm.litertlm';

// ── Internal destination paths ────────────────────────────────────────────────

Future<String> _internalModelsDir() async {
  final ext = await getExternalStorageDirectory();
  final base = ext?.path ?? '/data/data/com.example.nunarivu_ai/files';
  return '$base/models';
}

Future<String> _internalBooksDir() async {
  final base = p.dirname(await _internalModelsDir());
  return '$base/books';
}

// ── File copy helpers ─────────────────────────────────────────────────────────

/// Streams copy progress 0.0 → 1.0 for large files (e.g. 2.4 GB model).
Stream<double> _copyWithProgress(String src, String dst) async* {
  final source = File(src);
  final total  = await source.length();
  final out    = File(dst);
  await out.parent.create(recursive: true);
  final sink = out.openWrite();
  int copied = 0;
  await for (final chunk in source.openRead()) {
    sink.add(chunk);
    copied += chunk.length;
    yield total > 0 ? copied / total : 0.0;
  }
  await sink.flush();
  await sink.close();
}

/// Recursively copies a directory (for the books folder).
Future<int> _copyDir(Directory src, Directory dst) async {
  await dst.create(recursive: true);
  int count = 0;
  await for (final entity in src.list(recursive: false)) {
    final target = p.join(dst.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(target);
      count++;
    } else if (entity is Directory) {
      count += await _copyDir(entity, Directory(target));
    }
  }
  return count;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AdvancedSettingsScreen extends ConsumerStatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  ConsumerState<AdvancedSettingsScreen> createState() =>
      _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState
    extends ConsumerState<AdvancedSettingsScreen> {

  // ── Status ───────────────────────────────────────────────────────────────────
  bool   _hasAiModel  = false;
  int    _bookCount   = 0;
  String _modelPath   = '';

  // ── AI model copy ─────────────────────────────────────────────────────────────
  double? _modelProgress;    // null = idle, 0.0–1.0 = copying
  String  _modelStatus = '';

  // ── Books copy ────────────────────────────────────────────────────────────────
  bool   _copyingBooks  = false;
  String _booksStatus   = '';

  bool get _busy => _modelProgress != null || _copyingBooks;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    final modelsDir = await _internalModelsDir();
    final booksDir  = await _internalBooksDir();
    final modelFile = File('$modelsDir/$_modelFileName');
    final hasAi     = modelFile.existsSync();

    int bookCount = 0;
    if (Directory(booksDir).existsSync()) {
      try {
        bookCount = await Directory(booksDir)
            .list(recursive: false)
            .where((e) => e is Directory)
            .length;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _hasAiModel = hasAi;
        _bookCount  = bookCount;
        _modelPath  = hasAi ? modelFile.path : '';
      });
    }
  }

  Future<bool> _requestPermission() async {
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    status = await Permission.storage.request();
    return status.isGranted;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.notoSansTamil())),
    );
  }

  // ── AI Model — browse & copy ──────────────────────────────────────────────────

  Future<void> _browseModel() async {
    // 1. Pick the model file from wherever the student has it (pen drive, SD card, etc.)
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'மாதிரி கோப்பை தேர்வு செய் / Select model file',
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final srcPath = result.files.single.path;
    if (srcPath == null) { _snack('கோப்பு பாதை கிடைக்கவில்லை / File path not found'); return; }

    // 2. Warn if it doesn't look like the right file
    final fname = p.basename(srcPath);
    if (!fname.endsWith('.litertlm')) {
      final ok = await _confirm(
        title: 'தவறான கோப்பு? / Wrong file?',
        body: '"$fname"\n\nThe AI model file should be:\n$_modelFileName\n\nCopy anyway?',
      );
      if (ok != true) return;
    }

    await _requestPermission();

    // 3. Copy to internal app storage with progress bar
    final dst = '${await _internalModelsDir()}/$_modelFileName';
    setState(() {
      _modelProgress = 0.0;
      _modelStatus   = 'நகலெடுக்கிறது… / Copying…';
    });

    try {
      await for (final progress in _copyWithProgress(srcPath, dst)) {
        if (!mounted) return;
        setState(() => _modelProgress = progress);
      }
      if (!mounted) return;
      setState(() {
        _modelProgress = 1.0;
        _modelStatus   = 'நகலெடுக்கப்பட்டது ✓ / Copy complete';
      });
      await ref.read(modelServiceProvider.notifier).tryAutoLoad();
      await _refresh();
      _snack('AI மாதிரி தயார்! / AI model ready ✓');
    } catch (e) {
      if (!mounted) return;
      setState(() { _modelProgress = null; _modelStatus = ''; });
      _snack('பிழை / Error: $e');
    }
  }

  // ── Books — browse & copy ─────────────────────────────────────────────────────

  Future<void> _browseBooks() async {
    // 1. Student picks the folder that contains Grade 10/, Grade 11/ sub-folders
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'புத்தகக் கோப்புறை தேர்வு செய் / Select books folder',
    );
    if (dirPath == null) return;

    final src = Directory(dirPath);
    if (!src.existsSync()) { _snack('கோப்புறை இல்லை / Folder not found'); return; }

    await _requestPermission();

    // 2. Copy everything into internal books directory
    final dst = Directory(await _internalBooksDir());
    setState(() {
      _copyingBooks = true;
      _booksStatus  = 'புத்தகங்கள் நகலெடுக்கிறது… / Copying books…';
    });

    try {
      final count = await _copyDir(src, dst);
      if (!mounted) return;
      await _refresh();
      setState(() { _copyingBooks = false; _booksStatus = '$count கோப்புகள் நகலெடுக்கப்பட்டன ✓'; });
      _snack('$count book files copied ✓');
    } catch (e) {
      if (!mounted) return;
      setState(() { _copyingBooks = false; _booksStatus = ''; });
      _snack('பிழை / Error: $e');
    }
  }

  Future<bool?> _confirm({required String title, required String body}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: GoogleFonts.notoSansTamil()),
          content: Text(body, style: GoogleFonts.notoSansTamil(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('ரத்து · Cancel', style: GoogleFonts.notoSansTamil()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('தொடர் · Continue', style: GoogleFonts.notoSansTamil()),
            ),
          ],
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final modelState = ref.watch(modelServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('மேம்பட்ட அமைப்புகள்',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Advanced Settings',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 11, color: cs.onPrimary.withOpacity(0.7))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Device Status ──────────────────────────────────────────────────
          _SectionLabel('சாதன நிலை · Device Status'),

          _StatusRow(
            icon: _hasAiModel ? Icons.check_circle_rounded : Icons.cancel_rounded,
            iconColor: _hasAiModel ? Colors.green : cs.error,
            title: 'AI மாதிரி · AI Model (Gemma 4)',
            subtitle: _hasAiModel
                ? _modelPath.isNotEmpty ? _modelPath : 'Installed ✓'
                : 'Not installed — browse and copy from pen drive below',
            subtitleColor: _hasAiModel ? cs.onSurfaceVariant : cs.error,
          ),

          // Model engine state chip
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 8),
            child: Row(children: [
              _StateChip(modelState),
              if (!_hasAiModel) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text('மீண்டும் தேடு / Retry',
                      style: GoogleFonts.notoSansTamil(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () =>
                      ref.read(modelServiceProvider.notifier).tryAutoLoad(),
                ),
              ],
            ]),
          ),

          _StatusRow(
            icon: _bookCount > 0 ? Icons.check_circle_rounded : Icons.cancel_rounded,
            iconColor: _bookCount > 0 ? Colors.green : cs.error,
            title: 'பாடப்புத்தகங்கள் · Textbooks',
            subtitle: _bookCount > 0
                ? '$_bookCount grade folder(s) installed ✓'
                : 'Not installed — browse and copy from pen drive below',
            subtitleColor: _bookCount > 0 ? cs.onSurfaceVariant : cs.error,
          ),

          const Divider(height: 28),

          // ── AI Model ───────────────────────────────────────────────────────
          _SectionLabel('AI மாதிரி · AI Model'),

          Text(
            'பேனா டிரைவில் உள்ள மாதிரி கோப்பை தேர்வு செய்யவும், '
            'பயன்பாடு தானாகவே சேமிக்கும்.\n'
            'Browse to the model file on your pen drive — the app copies it automatically.',
            style: GoogleFonts.notoSansTamil(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 10),

          // Expected filename hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'கோப்பு பெயர்: $_modelFileName  (~2.4 GB)',
                  style: GoogleFonts.notoSansTamil(fontSize: 11),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          if (_modelProgress != null) ...[
            // Progress bar while copying
            Text(_modelStatus,
                style: GoogleFonts.notoSansTamil(
                    fontSize: 12, color: cs.primary)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _modelProgress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Text(
              _modelProgress! >= 1.0
                  ? '✓ Done!'
                  : '${(_modelProgress! * 100).toStringAsFixed(1)}% — '
                    'இது 5–10 நிமிடம் ஆகலாம் / This may take 5–10 minutes',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ] else
            FilledButton.icon(
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(
                'மாதிரி கோப்பை தேர்வு செய் · Browse for Model File',
                style: GoogleFonts.notoSansTamil(),
              ),
              onPressed: _busy ? null : _browseModel,
            ),

          const Divider(height: 28),

          // ── Books ──────────────────────────────────────────────────────────
          _SectionLabel('பாடப்புத்தகங்கள் · Textbooks'),

          Text(
            'Grade 10 மற்றும் Grade 11 கோப்புறைகளை கொண்ட கோப்புறையை தேர்வு செய்யவும்.\n'
            'Select the folder that contains your Grade 10/ and Grade 11/ sub-folders.',
            style: GoogleFonts.notoSansTamil(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 6),

          // Expected folder structure hint
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'books/          ← தேர்வு செய் / select this\n'
              '  Grade 10/\n'
              '    Science/\n'
              '    Maths/ …\n'
              '  Grade 11/\n'
              '    Science/\n'
              '    Maths/ …',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),

          if (_copyingBooks) ...[
            Text(_booksStatus,
                style: GoogleFonts.notoSansTamil(
                    fontSize: 12, color: cs.primary)),
            const SizedBox(height: 6),
            const LinearProgressIndicator(),
          ] else ...[
            if (_booksStatus.isNotEmpty && !_copyingBooks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_booksStatus,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 12, color: Colors.green)),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(
                'புத்தகக் கோப்புறை தேர்வு செய் · Browse for Books Folder',
                style: GoogleFonts.notoSansTamil(),
              ),
              onPressed: _busy ? null : _browseBooks,
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.notoSansTamil(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.1,
          ),
        ),
      );
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final Color    subtitleColor;
  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
  });
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: iconColor, size: 22),
        title: Text(title,
            style: GoogleFonts.notoSansTamil(
                fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: GoogleFonts.notoSansTamil(
                fontSize: 11, color: subtitleColor, height: 1.4)),
      );
}

class _StateChip extends StatelessWidget {
  final ModelState state;
  const _StateChip(this.state);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ModelState.ready    => ('தயார் · Ready',            Colors.green),
      ModelState.loading  => ('ஏற்றுகிறது… · Loading',   Colors.orange),
      ModelState.notFound => ('கோப்பு இல்லை · Not found', Colors.red),
      ModelState.error    => ('பிழை · Error',              Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: GoogleFonts.notoSansTamil(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
