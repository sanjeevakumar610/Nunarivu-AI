import 'dart:async' show unawaited;
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../models/pdf_doc.dart';
import 'db_service.dart';
import 'pdf_chunk_service.dart';

/// The shared profile-ID used for built-in textbooks.
/// All user profiles see books with this profile_id in their library.
const builtinProfileId = '__builtin__';

/// One-time flag stored in SharedPreferences.
/// Bump the version suffix whenever the books folder changes so users
/// who already have the app get a re-scan on next launch.
const _seedPrefKey = 'builtin_books_v1_seeded';

/// Background service that auto-imports all PDFs found in the app's
/// external `books/` directory into the shared `__builtin__` library.
///
/// Intended directory on Android:
///   /Android/data/com.example.nunarivu_ai/files/books/
///
/// Folder structure is used to derive human-readable titles:
///   books/Grade 10/கணிதம்/maths Gr 10 P I (T).pdf
///   → "Grade 10 › கணிதம்"                 (single file in subject)
///   → "Grade 10 › கணிதம் › Part I"        (multiple files in same subject)
class BookSeedService {
  BookSeedService._();
  static final BookSeedService instance = BookSeedService._();

  static const _uuid = Uuid();

  /// True while seeding is in progress.
  bool _seeding = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the books directory on this device (may not exist yet).
  Future<Directory> booksDir() async {
    final ext = await getExternalStorageDirectory();
    // Falls back to internal docs dir if no external storage.
    final base = ext ?? await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'books'));
  }

  /// Scans [booksDir] and imports any new PDFs into the __builtin__ library.
  ///
  /// Safe to call multiple times — already-imported files are skipped.
  /// [onProgress] is called with (current, total) as books are processed.
  Future<int> seed({
    void Function(int current, int total)? onProgress,
    void Function(String pdfId, bool indexing)? onIndexingChanged,
    bool forceRescan = false,
  }) async {
    if (_seeding) return 0;

    // Check whether we've already seeded (skip unless forced).
    final prefs = await SharedPreferences.getInstance();
    if (!forceRescan && (prefs.getBool(_seedPrefKey) ?? false)) return 0;

    final dir = await booksDir();
    if (!dir.existsSync()) return 0;

    _seeding = true;
    int seeded = 0;

    try {
      final pdfFiles = (await dir
          .list(recursive: true)
          .where((e) => e is File && e.path.toLowerCase().endsWith('.pdf'))
          .cast<File>()
          .toList())
        ..sort((a, b) => a.path.compareTo(b.path));

      if (pdfFiles.isEmpty) {
        _seeding = false;
        await prefs.setBool(_seedPrefKey, true);
        return 0;
      }

      // Build a subject-count map so we know when to append filenames.
      // Key = "Grade › Subject", value = list of files in that folder.
      final Map<String, List<File>> bySubject = {};
      final basePath = dir.path;
      for (final f in pdfFiles) {
        final key = _subjectKey(f.path, basePath);
        bySubject.putIfAbsent(key, () => []).add(f);
      }

      final db = await DbService.instance.db;

      // Ensure the virtual '__builtin__' profile row exists so that the
      // foreign key constraint on pdfs.profile_id is satisfied.
      await db.rawInsert('''
        INSERT OR IGNORE INTO profiles
          (id, name, avatar_seed, created_at, last_used_at)
        VALUES ('__builtin__', 'Built-in Books', 0, 0, 0)
      ''');

      // Phase 1: Register all new books in DB immediately (fast, no PDF I/O).
      // This lets the library show titles right away.
      final List<PdfDoc> newlyRegistered = [];

      for (int i = 0; i < pdfFiles.length; i++) {
        final file = pdfFiles[i];
        onProgress?.call(i + 1, pdfFiles.length);

        // Skip if already in DB by file path.
        final existing = await db.query(
          'pdfs',
          columns: ['id'],
          where: 'file_path = ? AND profile_id = ?',
          whereArgs: [file.path, builtinProfileId],
        );
        if (existing.isNotEmpty) continue;

        // Derive title from folder hierarchy.
        final subjectKey = _subjectKey(file.path, basePath);
        final multiFile = (bySubject[subjectKey]?.length ?? 1) > 1;
        final title = _deriveTitle(file.path, basePath, subjectKey, multiFile);

        final id = _uuid.v4();
        final pdf = PdfDoc(
          id: id,
          profileId: builtinProfileId,
          filePath: file.path,
          title: title,
          extractedText: '',
          pageCount: 0,   // 0 = still processing
          createdAt: DateTime.now().subtract(Duration(seconds: pdfFiles.length - i)),
        );
        await db.insert('pdfs', pdf.toMap());
        seeded++;
        newlyRegistered.add(pdf);

        // Yield to the event loop every 10 inserts to keep UI responsive.
        if (i % 10 == 0) await Future.delayed(Duration.zero);
      }

      await prefs.setBool(_seedPrefKey, true);

      // Phase 2: Extract text + embed ONE book at a time in the background.
      // Running all 161 concurrently causes OOM/ANR on the device.
      if (newlyRegistered.isNotEmpty) {
        unawaited(_extractSequentially(newlyRegistered, onIndexingChanged));
      }
    } finally {
      _seeding = false;
    }

    return seeded;
  }

  /// Returns true if the books directory exists and contains at least one PDF.
  Future<bool> hasBooksFolder() async {
    final dir = await booksDir();
    if (!dir.existsSync()) return false;
    return await dir
        .list(recursive: true)
        .any((e) => e is File && e.path.toLowerCase().endsWith('.pdf'));
  }

  /// Clear the "already seeded" flag so the next [seed] call performs a
  /// full re-scan (useful after copying new books to the device).
  Future<void> resetSeedFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seedPrefKey);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  /// Process PDF extraction ONE AT A TIME to avoid OOM / ANR.
  Future<void> _extractSequentially(
    List<PdfDoc> pdfs,
    void Function(String pdfId, bool indexing)? onIndexingChanged,
  ) async {
    for (final pdf in pdfs) {
      await _extractAndChunk(pdf, onIndexingChanged);
      // Small pause between books — lets the GC run and UI breathe.
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Extract text + page count in background, then kick off chunking.
  Future<void> _extractAndChunk(
    PdfDoc pdf,
    void Function(String pdfId, bool indexing)? onIndexingChanged,
  ) async {
    onIndexingChanged?.call(pdf.id, true);
    try {
      final bytes = await File(pdf.filePath).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final buf = StringBuffer();
      final pageCount = document.pages.count;
      for (int i = 0; i < pageCount; i++) {
        final t = extractor.extractText(startPageIndex: i, endPageIndex: i);
        buf.writeln('--- Page ${i + 1} ---');
        buf.writeln(t);
      }
      document.dispose();

      final extracted = buf.toString().trim();

      // Update the DB row with real text + page count.
      final db = await DbService.instance.db;
      await db.update(
        'pdfs',
        {'extracted_text': extracted, 'page_count': pageCount},
        where: 'id = ?',
        whereArgs: [pdf.id],
      );

      // Build a complete PdfDoc for chunking.
      final complete = PdfDoc(
        id: pdf.id,
        profileId: pdf.profileId,
        filePath: pdf.filePath,
        title: pdf.title,
        extractedText: extracted,
        pageCount: pageCount,
        createdAt: pdf.createdAt,
      );

      await PdfChunkService.instance.chunkAndEmbed(
        complete,
        builtinProfileId,
        onIndexingChanged: onIndexingChanged != null
            ? (active) => onIndexingChanged(pdf.id, active)
            : null,
      );
    } catch (e) {
      // If extraction fails (corrupt PDF, OOM on huge file), mark with
      // pageCount = -1 so the UI can show "Unavailable".
      try {
        final db = await DbService.instance.db;
        await db.update(
          'pdfs',
          {'page_count': -1},
          where: 'id = ?',
          whereArgs: [pdf.id],
        );
      } catch (_) {}
      onIndexingChanged?.call(pdf.id, false);
    }
  }

  // ── Title helpers ──────────────────────────────────────────────────────────

  /// "Grade 11 › கணிதம்" key for a file, regardless of file name.
  String _subjectKey(String filePath, String basePath) {
    final rel = p.relative(filePath, from: basePath);
    final parts = p.split(rel);
    if (parts.length <= 1) return '';
    // All path segments except the last (which is the filename).
    return parts.sublist(0, parts.length - 1).join(' › ');
  }

  /// Human-readable title.
  ///
  /// Single file per subject: "Grade 11 › கணிதம்"
  /// Multiple files per subject: "Grade 11 › கணிதம் - Chapter 9" (from filename)
  String _deriveTitle(
    String filePath,
    String basePath,
    String subjectKey,
    bool multiFile,
  ) {
    if (!multiFile) {
      return subjectKey.isEmpty
          ? p.basenameWithoutExtension(filePath)
          : subjectKey;
    }

    // Append a cleaned filename stem.
    final stem = p.basenameWithoutExtension(filePath);

    // Step 1 — strip common course-code noise
    var cleaned = stem
        .replaceAll(RegExp(r'[Gg][Rr]?[- ]?\d{2}', caseSensitive: false), '')
        .replaceAll(RegExp(r'[Gg]-?1[012]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\([Tt]\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bGr\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bT\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\binner\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s*[-–]\s*', unicode: true), ' - ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    // Step 2 — format numeric patterns into readable chapter labels
    //   "01 - 08"  →  "Chapters 1–8"
    //   "09"       →  "Chapter 9"
    //   "chap 3"   →  "Chapter 3"
    //   "P I", "P II", "P III"  →  "Part I / II / III"
    final rangeRe  = RegExp(r'^(\d+)\s*-\s*(\d+)$');
    final singleRe = RegExp(r'^(?:chap(?:ter)?\s*)?(\d+)$',
        caseSensitive: false);
    final partRe   = RegExp(r'^P\s*(I{1,3}|IV|V|VI|VII|VIII|IX|X)$',
        caseSensitive: false);

    if (rangeRe.hasMatch(cleaned)) {
      final m = rangeRe.firstMatch(cleaned)!;
      cleaned = 'Chapters ${int.parse(m.group(1)!)}–${int.parse(m.group(2)!)}';
    } else if (singleRe.hasMatch(cleaned)) {
      final m = singleRe.firstMatch(cleaned)!;
      cleaned = 'Chapter ${int.parse(m.group(1)!)}';
    } else if (partRe.hasMatch(cleaned)) {
      final m = partRe.firstMatch(cleaned)!;
      cleaned = 'Part ${m.group(1)!.toUpperCase()}';
    }

    if (cleaned.isEmpty || cleaned == subjectKey) return subjectKey;
    return '$subjectKey - $cleaned';
  }

  /// Re-derives titles for all `__builtin__` books already in the DB and
  /// updates any rows whose titles have changed.
  ///
  /// Safe to call on every app launch — no-op if all titles are already correct.
  Future<void> updateTitles() async {
    final dir = await booksDir();
    if (!dir.existsSync()) return;

    final db       = await DbService.instance.db;
    final basePath = dir.path;

    final rows = await db.query(
      'pdfs',
      columns: ['id', 'file_path', 'title'],   // skip extracted_text
      where: 'profile_id = ?',
      whereArgs: [builtinProfileId],
    );
    if (rows.isEmpty) return;

    // Rebuild subject→file-count map for multiFile detection
    final pdfFiles = await dir
        .list(recursive: true)
        .where((e) => e is File && e.path.toLowerCase().endsWith('.pdf'))
        .cast<File>()
        .toList();
    final Map<String, int> subjectCount = {};
    for (final f in pdfFiles) {
      final key = _subjectKey(f.path, basePath);
      subjectCount[key] = (subjectCount[key] ?? 0) + 1;
    }

    for (final row in rows) {
      final filePath  = row['file_path'] as String;
      final oldTitle  = row['title'] as String;
      final id        = row['id'] as String;
      final subKey    = _subjectKey(filePath, basePath);
      final multi     = (subjectCount[subKey] ?? 1) > 1;
      final newTitle  = _deriveTitle(filePath, basePath, subKey, multi);
      if (newTitle != oldTitle && newTitle.isNotEmpty) {
        await db.update(
          'pdfs',
          {'title': newTitle},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }
}
