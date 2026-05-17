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

// ── SharedPreferences key ─────────────────────────────────────────────────────

const _kCustomModelPath = 'custom_model_path';
const _modelFileName    = 'gemma-4-E2B-it-litert-lm.litertlm';

// ── Internal path helpers ─────────────────────────────────────────────────────

Future<String> _internalModelsDir() async {
  final ext = await getExternalStorageDirectory();
  final base = ext?.path ?? '/data/data/com.example.nunarivu_ai/files';
  return '$base/models';
}

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

Stream<double> _copyWithProgress(String src, String dst) async* {
  final source = File(src);
  final total  = await source.length();
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

  // ── Device status ────────────────────────────────────────────────────────────
  bool _hasAiModel    = false;
  int  _bookCount     = 0;
  String _loadedModelPath = '';

  // ── USB state ────────────────────────────────────────────────────────────────
  List<Directory> _usbDrives        = [];
  Directory?      _selectedDrive;
  bool            _scanningUsb      = false;
  bool            _usbScanned       = false;   // true after first scan attempt
  bool            _usbNunarivuFound = false;
  bool            _usbHasAiModel    = false;
  bool            _usbHasBooks      = false;

  // ── Copy progress ────────────────────────────────────────────────────────────
  double? _aiProgress;
  double? _booksProgress;
  String  _copyStatus = '';

  // ── Manual / custom path ─────────────────────────────────────────────────────
  final _pathCtrl = TextEditingController();
  bool   _customScanned      = false;
  bool   _customHasAiModel   = false;
  bool   _customHasBooks     = false;
  double? _customAiProgress;
  double? _customBooksProgress;

  bool get _copying =>
      _aiProgress != null || _booksProgress != null ||
      _customAiProgress != null || _customBooksProgress != null;

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

  // ── Status ───────────────────────────────────────────────────────────────────

  Future<void> _loadDeviceStatus() async {
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

    // Read saved custom path for loaded model display
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kCustomModelPath) ?? '';

    if (mounted) {
      setState(() {
        _hasAiModel      = hasAi;
        _bookCount       = bookCount;
        _loadedModelPath = hasAi ? modelFile.path : saved;
      });
    }
  }

  Future<void> _loadCustomPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kCustomModelPath) ?? '';
    if (mounted) setState(() => _pathCtrl.text = saved);
  }

  // ── Permission ────────────────────────────────────────────────────────────────

  Future<bool> _ensureStoragePermission() async {
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    status = await Permission.storage.request();
    return status.isGranted;
  }

  // ── USB scan ──────────────────────────────────────────────────────────────────

  Future<void> _scanForDrive() async {
    setState(() {
      _scanningUsb      = true;
      _usbScanned       = false;
      _selectedDrive    = null;
      _usbNunarivuFound = false;
      _usbHasAiModel = _usbHasBooks = false;
    });

    final granted = await _ensureStoragePermission();
    if (!granted) {
      _snack('அனுமதி மறுக்கப்பட்டது / Storage permission denied');
      setState(() { _scanningUsb = false; _usbScanned = true; });
      return;
    }

    final drives = await _findUsbDrives();
    Directory? selected;
    bool nunarivuFound = false;
    bool hasAi = false, hasBooks = false;

    if (drives.isNotEmpty) {
      selected = drives.first;
      final base = Directory('${selected.path}/nunarivu');
      nunarivuFound = base.existsSync();
      if (nunarivuFound) {
        hasAi    = File('${base.path}/models/$_modelFileName').existsSync();
        hasBooks = Directory('${base.path}/books').existsSync();
      }
    }

    if (mounted) {
      setState(() {
        _usbDrives        = drives;
        _selectedDrive    = selected;
        _usbNunarivuFound = nunarivuFound;
        _usbHasAiModel    = hasAi;
        _usbHasBooks      = hasBooks;
        _scanningUsb      = false;
        _usbScanned       = true;
      });
    }
  }

  // ── USB copy operations ───────────────────────────────────────────────────────

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
        await _loadDeviceStatus();
        _snack('AI மாதிரி நகலெடுக்கப்பட்டது ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiProgress = null);
        _snack('பிழை / Copy error: $e');
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
        await _loadDeviceStatus();
        setState(() => _booksProgress = 1.0);
        _snack('பாடப்புத்தகங்கள் நகலெடுக்கப்பட்டது ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _booksProgress = null);
        _snack('பிழை / Copy error: $e');
      }
    }
  }

  Future<void> _copyAll() async {
    if (_usbHasAiModel) await _copyAiModel();
    if (_usbHasBooks)   await _copyBooks();
  }

  // ── Manual / custom path ──────────────────────────────────────────────────────

  Future<void> _browsePath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'மாதிரி கோப்புறை தேர்வு / Select folder',
    );
    if (result != null && mounted) {
      setState(() {
        _pathCtrl.text = result;
        _customScanned = false;
      });
    }
  }

  /// Scans the manually entered path for AI model file and books folder.
  Future<void> _scanCustomPath() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) {
      _snack('பாதை உள்ளிடவும் / Enter a path first');
      return;
    }
    // Check for model file directly in path, or in path/models/
    final hasModel =
        File('$path/$_modelFileName').existsSync() ||
        File('$path/models/$_modelFileName').existsSync();
    // Check for books folder
    final hasBooks =
        Directory('$path/books').existsSync() ||
        Directory(p.join(path, '..', 'books')).existsSync();

    setState(() {
      _customScanned    = true;
      _customHasAiModel = hasModel;
      _customHasBooks   = hasBooks;
    });

    if (!hasModel && !hasBooks) {
      _snack('இந்த பாதையில் மாதிரி இல்லை / No model or books found at this path');
    }
  }

  /// Load the AI model directly from the custom path (no copy needed if it fits).
  Future<void> _loadModelFromCustomPath() async {
    final path = _pathCtrl.text.trim();
    // Prefer direct file, then models/ subfolder
    String? modelFile;
    if (File('$path/$_modelFileName').existsSync()) {
      modelFile = '$path/$_modelFileName';
    } else if (File('$path/models/$_modelFileName').existsSync()) {
      modelFile = '$path/models/$_modelFileName';
    }
    if (modelFile == null) {
      _snack('மாதிரி கோப்பு இல்லை / Model file not found at path');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomModelPath, path);
    try {
      await ref.read(modelServiceProvider.notifier).loadModel(modelFile);
      await _loadDeviceStatus();
      _snack('மாதிரி ஏற்றப்பட்டது ✓ / Model loaded');
    } catch (e) {
      _snack('மாதிரி ஏற்றுவதில் பிழை / Load error: $e');
    }
  }

  /// Copy AI model from the custom path into internal app storage.
  Future<void> _copyAiModelFromCustomPath() async {
    final path = _pathCtrl.text.trim();
    String? srcFile;
    if (File('$path/$_modelFileName').existsSync()) {
      srcFile = '$path/$_modelFileName';
    } else if (File('$path/models/$_modelFileName').existsSync()) {
      srcFile = '$path/models/$_modelFileName';
    }
    if (srcFile == null) {
      _snack('மாதிரி கோப்பு இல்லை / Model file not found');
      return;
    }
    final dst = '${await _internalModelsDir()}/$_modelFileName';
    setState(() { _customAiProgress = 0.0; });
    try {
      await for (final progress in _copyWithProgress(srcFile, dst)) {
        if (!mounted) return;
        setState(() => _customAiProgress = progress);
      }
      if (mounted) {
        setState(() { _customAiProgress = 1.0; _hasAiModel = true; });
        await ref.read(modelServiceProvider.notifier).tryAutoLoad();
        await _loadDeviceStatus();
        _snack('AI மாதிரி நகலெடுக்கப்பட்டது ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _customAiProgress = null);
        _snack('பிழை / Copy error: $e');
      }
    }
  }

  /// Copy books folder from the custom path into internal app storage.
  Future<void> _copyBooksFromCustomPath() async {
    final path = _pathCtrl.text.trim();
    Directory? srcDir;
    if (Directory('$path/books').existsSync()) {
      srcDir = Directory('$path/books');
    } else {
      final parent = Directory(p.join(path, '..', 'books'));
      if (parent.existsSync()) srcDir = parent;
    }
    if (srcDir == null) {
      _snack('books கோப்புறை இல்லை / books/ folder not found');
      return;
    }
    final dst = Directory(await _internalBooksDir());
    setState(() { _customBooksProgress = 0.0; });
    try {
      await _copyDir(srcDir, dst);
      if (mounted) {
        await _loadDeviceStatus();
        setState(() => _customBooksProgress = 1.0);
        _snack('பாடப்புத்தகங்கள் நகலெடுக்கப்பட்டது ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _customBooksProgress = null);
        _snack('பிழை / Copy error: $e');
      }
    }
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
    final cs       = Theme.of(context).colorScheme;
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
                    fontSize: 11,
                    color: cs.onPrimary.withOpacity(0.7))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh status',
            onPressed: _loadDeviceStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Device Status ─────────────────────────────────────────────────
          _SectionLabel('சாதன நிலை · Device Status'),

          // AI model status with loaded path
          _StatusRow(
            label: 'AI மாதிரி · AI Model (Gemma 4)',
            sublabel: _hasAiModel
                ? _loadedModelPath.isNotEmpty
                    ? _loadedModelPath
                    : 'Installed ✓'
                : '❌ Not installed — copy from pen drive or set custom path',
            ok: _hasAiModel,
          ),
          // Show model state chip
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 4),
            child: Row(
              children: [
                _StateChip(modelState),
                if (!_hasAiModel) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: Text('மீண்டும் தேடு / Retry',
                        style: GoogleFonts.notoSansTamil(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () =>
                        ref.read(modelServiceProvider.notifier).tryAutoLoad(),
                  ),
                ],
              ],
            ),
          ),

          _StatusRow(
            label: 'பாடப்புத்தகங்கள் · Textbooks',
            sublabel: _bookCount > 0
                ? '$_bookCount grade folder(s) installed ✓'
                : '❌ Not installed — copy from pen drive',
            ok: _bookCount > 0,
          ),

          const Divider(height: 28),

          // ── OTG Pen Drive ─────────────────────────────────────────────────
          _SectionLabel('OTG பேனா டிரைவ் · Pen Drive'),
          Text(
            'பேனா டிரைவில் nunarivu/ கோப்புறையை வைக்கவும்:\n'
            'Place a nunarivu/ folder on the pen drive with this layout:',
            style: GoogleFonts.notoSansTamil(
                fontSize: 11, color: cs.onSurfaceVariant, height: 1.6),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'nunarivu/\n'
              '  models/\n'
              '    gemma-4-E2B-it-litert-lm.litertlm  ← 2.4 GB\n'
              '  books/\n'
              '    Grade 10/\n'
              '    Grade 11/',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            icon: _scanningUsb
                ? const SizedBox(
                    width: 16, height: 16,
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

          // After scan — no drive found
          if (_usbScanned && _usbDrives.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _AlertCard(
                icon: Icons.usb_off_rounded,
                color: cs.error,
                title: 'OTG டிரைவ் கண்டுபிடிக்கப்படவில்லை',
                subtitle: 'No USB drive detected.\n'
                    '• Make sure the OTG cable is connected\n'
                    '• Unplug and re-plug, then scan again\n'
                    '• Check Settings → Apps → Allow manage files permission',
              ),
            ),

          // Drive found — show details
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
                        style: GoogleFonts.notoSansTamil(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // nunarivu/ folder not on drive
                  if (!_usbNunarivuFound)
                    _AlertCard(
                      icon: Icons.folder_off_rounded,
                      color: cs.error,
                      title: 'nunarivu/ கோப்புறை இல்லை',
                      subtitle: 'Create a nunarivu/ folder on the drive '
                          'with the layout shown above.',
                    )
                  // nunarivu/ found but nothing inside
                  else if (!_usbHasAiModel && !_usbHasBooks)
                    _AlertCard(
                      icon: Icons.search_off_rounded,
                      color: Colors.orange,
                      title: 'மாதிரி கோப்புகள் இல்லை',
                      subtitle: 'nunarivu/ folder found but no model or books '
                          'inside. Check the folder structure.',
                    )
                  else
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      if (_usbHasAiModel) _FoundChip('AI Model ✓'),
                      if (_usbHasBooks)   _FoundChip('Books ✓'),
                      if (!_usbHasAiModel) _MissingChip('AI Model ✗'),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_copying)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_copyStatus,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 12, color: cs.primary)),
              ),

            if (_usbHasAiModel) ...[
              _aiProgress != null
                  ? _ProgressRow('AI மாதிரி (2.4 GB)', _aiProgress!)
                  : _CopyTile(
                      icon: Icons.memory_rounded,
                      label: 'AI மாதிரி நகலெடு / Copy AI Model',
                      sublabel: '~2.4 GB — takes 5–10 minutes',
                      onPressed: _copying ? null : _copyAiModel,
                    ),
              const SizedBox(height: 8),
            ],

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

            if ((_usbHasAiModel || _usbHasBooks) && !_copying)
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_all_rounded),
                label: Text('அனைத்தையும் நகலெடு / Copy All',
                    style: GoogleFonts.notoSansTamil()),
                onPressed: _copyAll,
              ),
          ],

          const Divider(height: 28),

          // ── Manual Path ───────────────────────────────────────────────────
          _SectionLabel('கைமுறை பாதை · Manual Path'),
          Text(
            'தனிப்பட்ட சேமிப்பு இடத்தில் மாதிரி இருந்தால் கீழே பாதையை உள்ளிடவும்.\n'
            'If the model is stored in a custom location, enter the folder path below.',
            style: GoogleFonts.notoSansTamil(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 10),

          // Path field + browse
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pathCtrl,
                style: GoogleFonts.notoSansTamil(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'கோப்புறை பாதை · Folder path',
                  labelStyle: GoogleFonts.notoSansTamil(fontSize: 12),
                  hintText: '/storage/emulated/0/nunarivu/models',
                  hintStyle: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _customScanned = false),
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

          // Scan + action buttons
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.search_rounded),
                label: Text('இங்கே தேடு / Scan this path',
                    style: GoogleFonts.notoSansTamil(fontSize: 12)),
                onPressed: _copying ? null : _scanCustomPath,
              ),
            ),
          ]),

          // Scan results
          if (_customScanned) ...[
            const SizedBox(height: 10),
            if (!_customHasAiModel && !_customHasBooks)
              _AlertCard(
                icon: Icons.search_off_rounded,
                color: cs.error,
                title: 'மாதிரி கோப்பு இல்லை / Model not found',
                subtitle: 'No $_modelFileName or books/ folder found at this path.\n'
                    'Check the path and try again.',
              )
            else ...[
              Wrap(spacing: 8, runSpacing: 4, children: [
                if (_customHasAiModel)  _FoundChip('AI Model found ✓'),
                if (_customHasBooks)    _FoundChip('Books found ✓'),
                if (!_customHasAiModel) _MissingChip('AI Model not found'),
              ]),
              const SizedBox(height: 12),

              // AI model actions
              if (_customHasAiModel) ...[
                if (_customAiProgress != null)
                  _ProgressRow('AI மாதிரி நகலெடுக்கிறது', _customAiProgress!)
                else
                  Column(children: [
                    _CopyTile(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'இந்த இடத்திலிருந்து ஏற்று / Load from this path',
                      sublabel: 'No copy — loads directly (fast)',
                      onPressed: _copying ? null : _loadModelFromCustomPath,
                    ),
                    const SizedBox(height: 6),
                    _CopyTile(
                      icon: Icons.drive_file_move_rounded,
                      label: 'உள்ளே நகலெடு / Copy to app storage',
                      sublabel: '~2.4 GB — needed if model is on removable storage',
                      onPressed: _copying ? null : _copyAiModelFromCustomPath,
                    ),
                  ]),
                const SizedBox(height: 8),
              ],

              // Books actions
              if (_customHasBooks) ...[
                if (_customBooksProgress != null)
                  _ProgressRow('பாடப்புத்தகங்கள் நகலெடுக்கிறது',
                      _customBooksProgress!)
                else
                  _CopyTile(
                    icon: Icons.menu_book_rounded,
                    label: 'பாடப்புத்தகங்கள் நகலெடு / Copy Books',
                    sublabel: 'Copies books/ folder to app storage',
                    onPressed: _copying ? null : _copyBooksFromCustomPath,
                  ),
              ],
            ],
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
          style: GoogleFonts.notoSansTamil(
              fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(sublabel,
          style: GoogleFonts.notoSansTamil(
              fontSize: 11,
              color: ok ? cs.onSurfaceVariant : cs.error,
              height: 1.4)),
    );
  }
}

class _StateChip extends StatelessWidget {
  final ModelState state;
  const _StateChip(this.state);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ModelState.ready    => ('தயார் · Ready',        Colors.green),
      ModelState.loading  => ('ஏற்றுகிறது…',          Colors.orange),
      ModelState.notFound => ('கோப்பு இல்லை · Not found', Colors.red),
      ModelState.error    => ('பிழை · Error',          Colors.red),
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
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _AlertCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11, height: 1.5)),
              ],
            ),
          ),
        ]),
      );
}

class _FoundChip extends StatelessWidget {
  final String label;
  const _FoundChip(this.label);
  @override
  Widget build(BuildContext context) => Chip(
        label: Text(label, style: GoogleFonts.notoSansTamil(fontSize: 11)),
        backgroundColor: Colors.green.withOpacity(0.12),
        side: BorderSide(color: Colors.green.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
}

class _MissingChip extends StatelessWidget {
  final String label;
  const _MissingChip(this.label);
  @override
  Widget build(BuildContext context) => Chip(
        label: Text(label, style: GoogleFonts.notoSansTamil(fontSize: 11)),
        backgroundColor: Colors.red.withOpacity(0.08),
        side: BorderSide(color: Colors.red.withOpacity(0.4)),
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
            Expanded(
                child: Text(label,
                    style: GoogleFonts.notoSansTamil(fontSize: 12))),
            Text(
              value >= 1.0
                  ? '✓ Done'
                  : '${(value * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 11,
                  color: value >= 1.0 ? Colors.green : null),
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.notoSansTamil(fontSize: 12)),
                Text(sublabel,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ]),
        ),
      ]),
    );
  }
}
