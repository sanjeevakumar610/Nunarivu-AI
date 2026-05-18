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

// ── Internal destination helpers ──────────────────────────────────────────────

Future<String> _internalModelsDir() async {
  final ext = await getExternalStorageDirectory();
  return '${ext?.path ?? '/data/data/com.example.nunarivu_ai/files'}/models';
}

Future<String> _internalBooksDir() async =>
    '${p.dirname(await _internalModelsDir())}/books';

// ── File-copy helpers ─────────────────────────────────────────────────────────

/// Streams 0.0–1.0 progress while copying [src] to [dst].
/// Uses the source file's own read stream so progress is accurate even for
/// large files (2.4 GB). No intermediate temp copy.
Stream<double> _copyWithProgress(String src, String dst) async* {
  final source = File(src);
  final total  = await source.length();
  final out    = File(dst);
  await out.parent.create(recursive: true);
  final sink   = out.openWrite();
  int copied   = 0;
  await for (final chunk in source.openRead()) {
    sink.add(chunk);
    copied += chunk.length;
    yield total > 0 ? copied / total : 0.0;
  }
  await sink.flush();
  await sink.close();
}

/// Recursively copies a directory. Returns count of files copied.
Future<int> _copyDir(Directory src, Directory dst) async {
  await dst.create(recursive: true);
  int count = 0;
  await for (final e in src.list(recursive: false)) {
    final target = p.join(dst.path, p.basename(e.path));
    if (e is File) {
      await e.copy(target);
      count++;
    } else if (e is Directory) {
      count += await _copyDir(e, Directory(target));
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

  // ── Device status ─────────────────────────────────────────────────────────
  bool   _hasAiModel = false;
  int    _bookCount  = 0;
  String _installedModelPath = '';

  // ── AI model – browse state ───────────────────────────────────────────────
  /// Full path to the model file the user selected via Browse.
  String? _browsedModelPath;
  /// Whether the browsed file is actually the right model file.
  bool    _browsedModelValid = false;

  // ── AI model – copy state ─────────────────────────────────────────────────
  double? _modelProgress;   // null=idle, 0–1=copying
  String  _modelStatus = '';

  // ── Books – browse state ──────────────────────────────────────────────────
  String? _browsedBooksPath;
  int     _browsedBooksCount = 0;   // PDF count preview

  // ── Books – copy state ────────────────────────────────────────────────────
  bool   _copyingBooks = false;
  String _booksStatus  = '';

  bool get _busy => _modelProgress != null || _copyingBooks;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // ── Status ─────────────────────────────────────────────────────────────────

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
        _hasAiModel          = hasAi;
        _bookCount           = bookCount;
        _installedModelPath  = hasAi ? modelFile.path : '';
      });
    }
  }

  Future<bool> _ensurePermission() async {
    var s = await Permission.manageExternalStorage.request();
    if (s.isGranted) return true;
    s = await Permission.storage.request();
    return s.isGranted;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.notoSansTamil())));
  }

  // ── AI Model ───────────────────────────────────────────────────────────────

  /// Step 1: Browse — let the student navigate to the model file.
  Future<void> _browseModel() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'மாதிரி கோப்புறையை தேர்வு செய் / Select folder containing model',
    );
    if (result == null) return;

    // Look for the model file inside the selected folder.
    final modelFile = File(p.join(result, _modelFileName));
    final exists    = modelFile.existsSync();

    if (mounted) {
      setState(() {
        _browsedModelPath  = modelFile.path;
        _browsedModelValid = exists;
      });
    }

    if (!exists) {
      _snack('$_modelFileName இந்த கோப்புறையில் இல்லை / Model file not found in this folder');
    }
  }

  /// Step 2: Pull — copy the browsed model into app storage with a real
  /// progress bar that streams 0 → 100 % from the source file directly.
  Future<void> _pullModel() async {
    final src = _browsedModelPath;
    if (src == null || !File(src).existsSync()) {
      _snack('முதலில் கோப்புறையை தேர்வு செய்யவும் / Browse first to select folder');
      return;
    }

    await _ensurePermission();

    final dst = '${await _internalModelsDir()}/$_modelFileName';
    setState(() {
      _modelProgress = 0.0;
      _modelStatus   = 'நகலெடுக்கிறது… / Copying…';
    });

    try {
      await for (final progress in _copyWithProgress(src, dst)) {
        if (!mounted) return;
        setState(() => _modelProgress = progress);
      }
      if (!mounted) return;

      // Show 100% completion clearly before loading
      setState(() { _modelProgress = 1.0; _modelStatus = 'முடிந்தது ✓ / Done!'; });

      // Load directly from the just-copied file — do NOT use tryAutoLoad() which
      // might load from a stale pen-drive path saved in SharedPreferences.
      await ref.read(modelServiceProvider.notifier).loadModel(dst);
      await _refresh();
      _snack('AI மாதிரி நகலெடுக்கப்பட்டது ✓ / AI model copied and loaded');

      // Keep 100% visible for 3 seconds so the user can see it completed
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() { _modelProgress = null; _modelStatus = ''; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _modelProgress = null; _modelStatus = ''; });
      _snack('பிழை / Error: $e');
    }
  }

  // ── Books ──────────────────────────────────────────────────────────────────

  /// Step 1: Browse — student picks the folder that contains Grade 10/, Grade 11/…
  Future<void> _browseBooks() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'புத்தகக் கோப்புறையை தேர்வு செய் / Select books folder',
    );
    if (result == null) return;

    // Quick preview count of PDF files.
    int pdfCount = 0;
    try {
      pdfCount = await Directory(result)
          .list(recursive: true)
          .where((e) => e is File && e.path.toLowerCase().endsWith('.pdf'))
          .length;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _browsedBooksPath  = result;
        _browsedBooksCount = pdfCount;
      });
    }

    if (pdfCount == 0) {
      _snack('PDF கோப்புகள் இல்லை / No PDF files found in this folder');
    }
  }

  /// Step 2: Pull — copy all PDFs from the browsed folder into app storage.
  Future<void> _pullBooks() async {
    final src = _browsedBooksPath;
    if (src == null || !Directory(src).existsSync()) {
      _snack('முதலில் கோப்புறையை தேர்வு செய்யவும் / Browse first to select folder');
      return;
    }

    await _ensurePermission();

    setState(() {
      _copyingBooks = true;
      _booksStatus  = 'புத்தகங்கள் நகலெடுக்கிறது… / Copying books…';
    });

    try {
      final dst   = Directory(await _internalBooksDir());
      final count = await _copyDir(Directory(src), dst);
      if (!mounted) return;
      await _refresh();
      setState(() {
        _copyingBooks = false;
        _booksStatus  = '$count PDF கோப்புகள் நகலெடுக்கப்பட்டன ✓';
      });
      _snack('$count files copied ✓');
    } catch (e) {
      if (!mounted) return;
      setState(() { _copyingBooks = false; _booksStatus = ''; });
      _snack('பிழை / Error: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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

          // ── Status ───────────────────────────────────────────────────────
          _SectionLabel('சாதன நிலை · Device Status'),
          _StatusTile(
            ok: _hasAiModel,
            title: 'AI மாதிரி · AI Model (Gemma 4)',
            subtitle: _hasAiModel
                ? (_installedModelPath.isNotEmpty ? _installedModelPath : 'Installed ✓')
                : 'Not installed — browse and pull from pen drive below',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _StateChip(modelState),
              const SizedBox(width: 6),
              // Reload directly from internal storage — fixes "no response" after Pull
              _SmallButton(
                label: 'Reload',
                onPressed: _busy ? null : () async {
                  final path = '${await _internalModelsDir()}/$_modelFileName';
                  if (!File(path).existsSync()) {
                    _snack('No model in internal storage — Pull first');
                    return;
                  }
                  try {
                    await ref.read(modelServiceProvider.notifier).loadModel(path);
                    _snack('மாதிரி ஏற்றப்பட்டது ✓ / Model loaded ✓');
                  } catch (e) {
                    _snack('பிழை / Error: $e');
                  }
                },
              ),
            ]),
          ),
          _StatusTile(
            ok: _bookCount > 0,
            title: 'பாடப்புத்தகங்கள் · Textbooks',
            subtitle: _bookCount > 0
                ? '$_bookCount grade folder(s) installed ✓'
                : 'Not installed — browse and pull from pen drive below',
          ),

          const Divider(height: 28),

          // ── AI Model ─────────────────────────────────────────────────────
          _SectionLabel('AI மாதிரி · AI Model'),
          Text(
            'பேனா டிரைவில் மாதிரி கோப்புறையை தேர்வு செய், பின்னர் Pull செய்யவும்.\n'
            'Browse to the folder on your pen drive, then tap Pull to copy.',
            style: GoogleFonts.notoSansTamil(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 10),

          // Step 1: Browse button
          FilledButton.icon(
            icon: const Icon(Icons.folder_open_rounded),
            label: Text('1. Browse — கோப்புறை தேர்வு செய்',
                style: GoogleFonts.notoSansTamil()),
            onPressed: _busy ? null : _browseModel,
          ),

          // Show what was found after browsing
          if (_browsedModelPath != null) ...[
            const SizedBox(height: 8),
            _FoundCard(
              valid: _browsedModelValid,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_browsedModelPath!,
                      style: GoogleFonts.notoSansTamil(fontSize: 11),
                      overflow: TextOverflow.ellipsis, maxLines: 2),
                  const SizedBox(height: 4),
                  Text(
                    _browsedModelValid
                        ? '✓ $_modelFileName found (~2.4 GB)'
                        : '✗ $_modelFileName not found in this folder',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11,
                        color: _browsedModelValid ? Colors.green : cs.error,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Step 2: Pull button + progress
          if (_modelProgress != null) ...[
            Text(_modelStatus,
                style: GoogleFonts.notoSansTamil(fontSize: 12, color: cs.primary)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _modelProgress,          // always deterministic: 0.0–1.0
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 4),
            Text(
              _modelProgress! >= 1.0
                  ? '✓ முடிந்தது / Done!'
                  : '${(_modelProgress! * 100).toStringAsFixed(1)}%  '
                    '— 5–10 நிமிடம் ஆகலாம் / May take 5–10 min',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ] else
            OutlinedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: Text(
                '2. Pull — சாதனத்திற்கு நகலெடு',
                style: GoogleFonts.notoSansTamil(),
              ),
              onPressed: (_busy || !(_browsedModelValid))
                  ? null
                  : _pullModel,
            ),

          const Divider(height: 28),

          // ── Books ─────────────────────────────────────────────────────────
          _SectionLabel('பாடப்புத்தகங்கள் · Textbooks'),
          Text(
            'Grade 10 மற்றும் Grade 11 கோப்புறைகளை கொண்ட books கோப்புறையை தேர்வு செய்யவும்.\n'
            'Select the folder that contains Grade 10/ and Grade 11/ sub-folders.',
            style: GoogleFonts.notoSansTamil(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'books/          ← இதை தேர்வு செய் / select this\n'
              '  Grade 10/\n'
              '  Grade 11/',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.6),
            ),
          ),
          const SizedBox(height: 10),

          // Step 1: Browse
          FilledButton.icon(
            icon: const Icon(Icons.folder_open_rounded),
            label: Text('1. Browse — புத்தகக் கோப்புறை தேர்வு செய்',
                style: GoogleFonts.notoSansTamil()),
            onPressed: _busy ? null : _browseBooks,
          ),

          if (_browsedBooksPath != null) ...[
            const SizedBox(height: 8),
            _FoundCard(
              valid: _browsedBooksCount > 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_browsedBooksPath!,
                      style: GoogleFonts.notoSansTamil(fontSize: 11),
                      overflow: TextOverflow.ellipsis, maxLines: 2),
                  const SizedBox(height: 4),
                  Text(
                    _browsedBooksCount > 0
                        ? '✓ $_browsedBooksCount PDF files found'
                        : '✗ No PDF files found in this folder',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11,
                        color: _browsedBooksCount > 0 ? Colors.green : cs.error,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Step 2: Pull + progress
          if (_copyingBooks) ...[
            Text(_booksStatus,
                style: GoogleFonts.notoSansTamil(fontSize: 12, color: cs.primary)),
            const SizedBox(height: 6),
            const LinearProgressIndicator(),
          ] else ...[
            if (_booksStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_booksStatus,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 12, color: Colors.green)),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: Text('2. Pull — சாதனத்திற்கு நகலெடு',
                  style: GoogleFonts.notoSansTamil()),
              onPressed: (_busy || _browsedBooksPath == null || _browsedBooksCount == 0)
                  ? null
                  : _pullBooks,
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
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.notoSansTamil(
            fontSize: 11, fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.1,
          ),
        ),
      );
}

class _StatusTile extends StatelessWidget {
  final bool ok;
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _StatusTile({
    required this.ok, required this.title, required this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
        color: ok ? Colors.green : cs.error, size: 22,
      ),
      title: Text(title,
          style: GoogleFonts.notoSansTamil(
              fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: GoogleFonts.notoSansTamil(
              fontSize: 11,
              color: ok ? cs.onSurfaceVariant : cs.error,
              height: 1.4)),
      trailing: trailing,
    );
  }
}

class _StateChip extends StatelessWidget {
  final ModelState state;
  const _StateChip(this.state);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ModelState.ready    => ('Ready ✓',     Colors.green),
      ModelState.loading  => ('Loading…',    Colors.orange),
      ModelState.notFound => ('Not found',   Colors.red),
      ModelState.error    => ('Error',       Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SmallButton({required this.label, required this.onPressed});
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: GoogleFonts.notoSansTamil(fontSize: 10)),
        child: Text(label),
      );
}

/// Green or red card shown after browsing to confirm what was found.
class _FoundCard extends StatelessWidget {
  final bool valid;
  final Widget child;
  const _FoundCard({required this.valid, required this.child});
  @override
  Widget build(BuildContext context) {
    final color = valid ? Colors.green : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: child,
    );
  }
}
