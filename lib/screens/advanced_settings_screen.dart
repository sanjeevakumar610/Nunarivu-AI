import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/model_service.dart';
import '../services/stt_service.dart';

// ── SharedPreferences key ─────────────────────────────────────────────────────

const _kCustomModelPath = 'custom_model_path';
const _modelFileName = 'gemma-4-E2B-it-litert-lm.litertlm';

// ── Internal path helpers ─────────────────────────────────────────────────────

Future<String> _internalModelsDir() async {
  final ext = await getExternalStorageDirectory();
  final base = ext?.path ?? '/data/data/com.example.nunarivu_ai/files';
  return '$base/models';
}

Future<String> _internalVoskDir() async =>
    '${await _internalModelsDir()}/vosk-model-ta';

Future<String> _internalBooksDir() async {
  final modelsDir = await _internalModelsDir();
  return p.join(p.dirname(modelsDir), 'books');
}

// ── USB drive detection ───────────────────────────────────────────────────────

Future<List<Directory>> _findUsbDrives() async {
  final found = <Directory>[];
  try {
    await for (final entity in Directory('/storage').list()) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        // OTG USB drives always mount as XXXX-XXXX (8 uppercase hex chars + dash)
        if (RegExp(r'^[A-F0-9]{4}-[A-F0-9]{4}$', caseSensitive: false)
            .hasMatch(name)) {
          found.add(entity);
        }
      }
    }
  } catch (_) {}
  return found;
}

// ── File copy helpers ─────────────────────────────────────────────────────────

/// Streams copy progress 0.0 → 1.0. Used for the 2.4 GB AI model.
Stream<double> _copyWithProgress(String src, String dst) async* {
  final source = File(src);
  final total = await source.length();
  final outFile = File(dst);
  await outFile.parent.create(recursive: true);
  final output = outFile.openWrite();
  int copied = 0;
  await for (final chunk in source.openRead()) {
    output.add(chunk);
    copied += chunk.length;
    yield total > 0 ? copied / total : 0.0;
  }
  await output.flush();
  await output.close();
}

/// Recursively copies a directory tree. Used for voice model folder and books.
Future<void> _copyDir(Directory src, Directory dst) async {
  await dst.create(recursive: true);
  await for (final entity in src.list(recursive: false)) {
    final target = p.join(dst.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(target);
    } else if (entity is Directory) {
      await _copyDir(entity, Directory(target));
    }
  }
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

  // ── Device status ───────────────────────────────────────────────────────────
  bool _hasAiModel    = false;
  bool _hasVoiceModel = false;
  int  _bookCount     = 0;

  // ── USB state ────────────────────────────────────────────────────────────────
  List<Directory> _usbDrives   = [];
  Directory?      _selectedDrive;
  bool            _scanningUsb = false;
  bool            _usbHasAiModel    = false;
  bool            _usbHasVoiceModel = false;
  bool            _usbHasBooks      = false;

  // ── Copy progress (null = idle, 0–1 = in progress, 1 = done) ───────────────
  double? _aiProgress;
  double? _voiceProgress;
  double? _booksProgress;
  String  _copyStatus = '';

  // ── Custom path ──────────────────────────────────────────────────────────────
  final _pathCtrl = TextEditingController();

  bool get _copying =>
      _aiProgress != null || _voiceProgress != null || _booksProgress != null;

  @override
  void initState() {
    super.initState();
    _loadDeviceStatus();
    _loadCustomPath();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  // ── Status ──────────────────────────────────────────────────────────────────

  Future<void> _loadDeviceStatus() async {
    final modelsDir = await _internalModelsDir();
    final voskDir   = await _internalVoskDir();
    final booksDir  = await _internalBooksDir();

    final hasAi    = File('$modelsDir/$_modelFileName').existsSync();
    final hasVoice = Directory(voskDir).existsSync();

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
        _hasAiModel    = hasAi;
        _hasVoiceModel = hasVoice;
        _bookCount     = bookCount;
      });
    }
  }

  Future<void> _loadCustomPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kCustomModelPath) ?? '';
    if (mounted) setState(() => _pathCtrl.text = saved);
  }

  // ── Permission ───────────────────────────────────────────────────────────────

  Future<bool> _ensureStoragePermission() async {
    // Try MANAGE_EXTERNAL_STORAGE first (Android 11+, needed for USB paths)
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    // Fall back to legacy READ_EXTERNAL_STORAGE
    status = await Permission.storage.request();
    return status.isGranted;
  }

  // ── USB scan ─────────────────────────────────────────────────────────────────

  Future<void> _scanForDrive() async {
    setState(() {
      _scanningUsb   = true;
      _selectedDrive = null;
      _usbHasAiModel = _usbHasVoiceModel = _usbHasBooks = false;
    });

    final granted = await _ensureStoragePermission();
    if (!granted) {
      _snack('அனுமதி மறுக்கப்பட்டது / Storage permission denied');
      setState(() => _scanningUsb = false);
      return;
    }

    final drives = await _findUsbDrives();
    Directory? selected;
    bool hasAi = false, hasVoice = false, hasBooks = false;

    if (drives.isNotEmpty) {
      selected = drives.first;
      final base = '${selected.path}/nunarivu';
      hasAi    = File('$base/models/$_modelFileName').existsSync();
      hasVoice = Directory('$base/models/vosk-model-ta').existsSync();
      hasBooks = Directory('$base/books').existsSync();
    }

    if (mounted) {
      setState(() {
        _usbDrives        = drives;
        _selectedDrive    = selected;
        _usbHasAiModel    = hasAi;
        _usbHasVoiceModel = hasVoice;
        _usbHasBooks      = hasBooks;
        _scanningUsb      = false;
      });
    }
  }

  // ── Copy operations ──────────────────────────────────────────────────────────

  Future<void> _copyAiModel() async {
    if (_selectedDrive == null) return;
    final src = '${_selectedDrive!.path}/nunarivu/models/$_modelFileName';
    final dst = '${await _internalModelsDir()}/$_modelFileName';

    setState(() {
      _aiProgress = 0.0;
      _copyStatus = 'AI மாதிரி நகலெடுக்கிறது… / Copying AI model…';
    });

    try {
      await for (final progress in _copyWithProgress(src, dst)) {
        if (!mounted) return;
        setState(() => _aiProgress = progress);
      }
      if (mounted) {
        setState(() { _aiProgress = 1.0; _hasAiModel = true; });
        await ref.read(modelServiceProvider.notifier).tryAutoLoad();
        _snack('AI மாதிரி நகலெடுக்கப்பட்டது / AI model copied ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiProgress = null);
        _snack('பிழை / Error: $e');
      }
    }
  }

  Future<void> _copyVoiceModel() async {
    if (_selectedDrive == null) return;
    final src = Directory('${_selectedDrive!.path}/nunarivu/models/vosk-model-ta');
    final dst = Directory(await _internalVoskDir());

    setState(() {
      _voiceProgress = 0.0;
      _copyStatus = 'குரல் மாதிரி நகலெடுக்கிறது… / Copying voice model…';
    });

    try {
      await _copyDir(src, dst);
      if (mounted) {
        setState(() { _voiceProgress = 1.0; _hasVoiceModel = true; });
        await ref.read(sttServiceProvider).reinitVosk();
        ref.invalidate(voskModelReadyProvider);
        _snack('குரல் மாதிரி நகலெடுக்கப்பட்டது / Voice model copied ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _voiceProgress = null);
        _snack('பிழை / Error: $e');
      }
    }
  }

  Future<void> _copyBooks() async {
    if (_selectedDrive == null) return;
    final src = Directory('${_selectedDrive!.path}/nunarivu/books');
    final dst = Directory(await _internalBooksDir());

    setState(() {
      _booksProgress = 0.0;
      _copyStatus = 'பாடப்புத்தகங்கள் நகலெடுக்கிறது… / Copying textbooks…';
    });

    try {
      await _copyDir(src, dst);
      if (mounted) {
        await _loadDeviceStatus(); // refresh book count
        setState(() => _booksProgress = 1.0);
        _snack('பாடப்புத்தகங்கள் நகலெடுக்கப்பட்டது / Textbooks copied ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _booksProgress = null);
        _snack('பிழை / Error: $e');
      }
    }
  }

  Future<void> _copyAll() async {
    if (_usbHasAiModel)    await _copyAiModel();
    if (_usbHasVoiceModel) await _copyVoiceModel();
    if (_usbHasBooks)      await _copyBooks();
  }

  // ── Custom path ──────────────────────────────────────────────────────────────

  Future<void> _browsePath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'மாதிரி கோப்புறை தேர்வு / Select model folder',
    );
    if (result != null && mounted) setState(() => _pathCtrl.text = result);
  }

  Future<void> _saveCustomPath() async {
    final path = _pathCtrl.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomModelPath, path);
    final modelFile = '$path/$_modelFileName';
    if (File(modelFile).existsSync()) {
      await ref.read(modelServiceProvider.notifier).loadModel(modelFile);
    }
    _snack('பாதை சேமிக்கப்பட்டது / Path saved');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.notoSansTamil())),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                    fontSize: 11,
                    color: cs.onPrimary.withOpacity(0.7))),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Device Status ─────────────────────────────────────────────────
          _SectionLabel('சாதன நிலை · Device Status'),
          _StatusRow(
            label: 'AI மாதிரி · AI Model (Gemma 4)',
            sublabel: 'gemma-4-E2B-it-litert-lm.litertlm (~2.4 GB)',
            ok: _hasAiModel,
          ),
          _StatusRow(
            label: 'தமிழ் குரல் மாதிரி · Tamil Voice Model',
            sublabel: 'vosk-model-ta (~43 MB)',
            ok: _hasVoiceModel,
          ),
          _StatusRow(
            label: 'பாடப்புத்தகங்கள் · Textbooks',
            sublabel: _bookCount > 0
                ? '$_bookCount grade folder(s) found'
                : 'Not installed',
            ok: _bookCount > 0,
          ),

          const Divider(height: 28),

          // ── Pen Drive ─────────────────────────────────────────────────────
          _SectionLabel('பேனா டிரைவ் · Pen Drive (OTG USB)'),
          Text(
            'பேனா டிரைவில் nunarivu/ கோப்புறையை வை:\n'
            'Place a nunarivu/ folder on the pen drive:',
            style: GoogleFonts.notoSansTamil(
                fontSize: 11, color: cs.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'nunarivu/\n'
              '  models/\n'
              '    gemma-4-E2B-it-litert-lm.litertlm\n'
              '    vosk-model-ta/   ← extracted folder\n'
              '  books/\n'
              '    Grade 10/\n'
              '    Grade 11/',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),

          // Scan button
          FilledButton.icon(
            icon: _scanningUsb
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.usb_rounded),
            label: Text(
              _scanningUsb
                  ? 'தேடுகிறது… / Scanning…'
                  : 'பேனா டிரைவ் தேடு / Scan for Pen Drive',
              style: GoogleFonts.notoSansTamil(),
            ),
            onPressed: (_scanningUsb || _copying) ? null : _scanForDrive,
          ),

          // Drive found
          if (_selectedDrive != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.usb_rounded, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _selectedDrive!.path,
                        style: GoogleFonts.notoSansTamil(
                            fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (_usbHasAiModel || _usbHasVoiceModel || _usbHasBooks)
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      if (_usbHasAiModel)    _FoundChip('AI Model'),
                      if (_usbHasVoiceModel) _FoundChip('Voice Model'),
                      if (_usbHasBooks)      _FoundChip('Books'),
                    ])
                  else
                    Text(
                      'nunarivu/ கோப்புறை இல்லை\nnunarivu/ folder not found on drive',
                      style: GoogleFonts.notoSansTamil(
                          fontSize: 11, color: cs.error, height: 1.5),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Status text while copying
            if (_copying)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_copyStatus,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 12, color: cs.primary)),
              ),

            // AI model copy row
            if (_usbHasAiModel) ...[
              _aiProgress != null
                  ? _ProgressRow('AI மாதிரி (2.4 GB)', _aiProgress!)
                  : _CopyTile(
                      icon: Icons.memory_rounded,
                      label: 'AI மாதிரி நகலெடு / Copy AI Model',
                      sublabel: '~2.4 GB — takes several minutes',
                      onPressed: _copying ? null : _copyAiModel,
                    ),
              const SizedBox(height: 8),
            ],

            // Voice model copy row
            if (_usbHasVoiceModel) ...[
              _voiceProgress != null
                  ? _ProgressRow('குரல் மாதிரி (~43 MB)', _voiceProgress!)
                  : _CopyTile(
                      icon: Icons.mic_rounded,
                      label: 'குரல் மாதிரி நகலெடு / Copy Voice Model',
                      sublabel: '~43 MB',
                      onPressed: _copying ? null : _copyVoiceModel,
                    ),
              const SizedBox(height: 8),
            ],

            // Books copy row
            if (_usbHasBooks) ...[
              _booksProgress != null
                  ? _ProgressRow('பாடப்புத்தகங்கள்', _booksProgress!)
                  : _CopyTile(
                      icon: Icons.menu_book_rounded,
                      label: 'பாடப்புத்தகங்கள் நகலெடு / Copy Textbooks',
                      sublabel: 'PDF books',
                      onPressed: _copying ? null : _copyBooks,
                    ),
              const SizedBox(height: 8),
            ],

            // Copy All
            if ((_usbHasAiModel || _usbHasVoiceModel || _usbHasBooks) &&
                !_copying)
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_all_rounded),
                label: Text('அனைத்தையும் நகலெடு / Copy All',
                    style: GoogleFonts.notoSansTamil()),
                onPressed: _copyAll,
              ),
          ],

          // No drive found
          if (_usbDrives.isEmpty && !_scanningUsb && _selectedDrive == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'OTG பேனா டிரைவ் கண்டுபிடிக்கப்படவில்லை.\n'
                'No USB drive detected. Connect the pen drive and scan again.',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 12, color: cs.onSurfaceVariant, height: 1.6),
              ),
            ),

          const Divider(height: 28),

          // ── Custom Path ───────────────────────────────────────────────────
          _SectionLabel('தனிப்பயன் பாதை · Custom Model Path'),
          Text(
            'AI மாதிரி கோப்புறை பாதையை கைமுறையாக அமைக்கவும்.\n'
            'Manually set the folder path where the AI model file is stored.',
            style: GoogleFonts.notoSansTamil(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pathCtrl,
                style: GoogleFonts.notoSansTamil(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'மாதிரி கோப்புறை · Model folder path',
                  labelStyle: GoogleFonts.notoSansTamil(fontSize: 12),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _browsePath,
              child: Text('தேடு\nBrowse',
                  style: GoogleFonts.notoSansTamil(fontSize: 11),
                  textAlign: TextAlign.center),
            ),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.save_rounded),
            label: Text('மாதிரி பாதை சேமி / Set Model Path',
                style: GoogleFonts.notoSansTamil()),
            onPressed: _saveCustomPath,
          ),
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
  final String label;
  final String sublabel;
  final bool ok;
  const _StatusRow(
      {required this.label, required this.sublabel, required this.ok});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
        color: ok ? Colors.green : cs.error,
        size: 22,
      ),
      title: Text(label,
          style: GoogleFonts.notoSansTamil(fontSize: 13)),
      subtitle: Text(sublabel,
          style: GoogleFonts.notoSansTamil(
              fontSize: 11, color: cs.onSurfaceVariant)),
    );
  }
}

class _FoundChip extends StatelessWidget {
  final String label;
  const _FoundChip(this.label);
  @override
  Widget build(BuildContext context) => Chip(
        label:
            Text(label, style: GoogleFonts.notoSansTamil(fontSize: 11)),
        backgroundColor: Colors.green.withOpacity(0.12),
        side: BorderSide(color: Colors.green.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double value;
  const _ProgressRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label,
                style: GoogleFonts.notoSansTamil(fontSize: 12))),
            Text('${(value * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.notoSansTamil(fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      );
}

class _CopyTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback? onPressed;
  const _CopyTile(
      {required this.icon,
      required this.label,
      required this.sublabel,
      this.onPressed});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.notoSansTamil(fontSize: 12)),
          Text(sublabel,
              style: GoogleFonts.notoSansTamil(
                  fontSize: 10, color: cs.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}
