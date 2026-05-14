import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../models/pdf_doc.dart';
import 'db_service.dart';
import 'pdf_chunk_service.dart';

/// PDF import + text extraction.
/// On import we copy the file into the app's documents dir (so external
/// files being moved doesn't break the library), extract page-wise text,
/// and persist a row in the `pdfs` table.
class PdfService {
  static const _uuid = Uuid();

  /// Approximate cap on how much PDF text to send as model context.
  /// Gemma 4 IT context is 4096 tokens ≈ ~14000 characters; we leave
  /// room for the user prompt + response.
  static const int contextCharBudget = 8000;

  /// Lightweight list for the library UI — omits `extracted_text` so we
  /// don't load megabytes of text just to render titles and page counts.
  /// Use [findById] when you actually need the full text.
  Future<List<PdfDoc>> listForProfile(String profileId) async {
    final db = await DbService.instance.db;
    final rows = await db.query(
      'pdfs',
      columns: ['id', 'profile_id', 'file_path', 'title', 'page_count', 'created_at'],
      where: 'profile_id = ? OR profile_id = ?',
      whereArgs: [profileId, '__builtin__'],
      orderBy: 'created_at ASC',
    );
    return rows.map(PdfDoc.fromMap).toList();
  }

  Future<PdfDoc?> findById(String id) async {
    final db = await DbService.instance.db;
    final rows = await db.query('pdfs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return PdfDoc.fromMap(rows.first);
  }

  /// Imports a PDF from [sourcePath]: copies, extracts text, persists,
  /// and kicks off async chunking + embedding.
  ///
  /// [onIndexingChanged] is forwarded to [PdfChunkService.chunkAndEmbed] so the
  /// caller (PdfLibraryScreen) can update [indexingPdfsProvider].
  Future<PdfDoc> import({
    required String sourcePath,
    required String profileId,
    String? title,
    /// Called with (pdfId, true) when indexing starts and (pdfId, false) when done.
    void Function(String pdfId, bool indexing)? onIndexingChanged,
  }) async {
    // 1. Copy to app documents dir
    final appDir = await getApplicationDocumentsDirectory();
    final pdfsDir = Directory(p.join(appDir.path, 'pdfs'));
    if (!pdfsDir.existsSync()) pdfsDir.createSync(recursive: true);

    final id = _uuid.v4();
    final destPath = p.join(pdfsDir.path, '$id.pdf');
    await File(sourcePath).copy(destPath);

    // 2. Extract text
    final bytes = await File(destPath).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);

    final buf = StringBuffer();
    final pageCount = document.pages.count;
    for (int i = 0; i < pageCount; i++) {
      final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
      buf.writeln('--- Page ${i + 1} ---');
      buf.writeln(pageText);
    }
    document.dispose();

    final extracted = buf.toString().trim();
    final cleanTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : p.basenameWithoutExtension(sourcePath);

    // 3. Persist
    final pdf = PdfDoc(
      id: id,
      profileId: profileId,
      filePath: destPath,
      title: cleanTitle,
      extractedText: extracted,
      pageCount: pageCount,
      createdAt: DateTime.now(),
    );
    final db = await DbService.instance.db;
    await db.insert('pdfs', pdf.toMap());

    // Kick off background chunking + embedding (non-blocking).
    // Close over pdf.id so the callback knows which PDF is indexing.
    final capturedId = pdf.id;
    unawaited(PdfChunkService.instance.chunkAndEmbed(
      pdf, profileId,
      onIndexingChanged: onIndexingChanged != null
          ? (active) => onIndexingChanged(capturedId, active)
          : null,
    ));

    return pdf;
  }

  Future<void> delete(PdfDoc pdf) async {
    final db = await DbService.instance.db;
    await db.delete('pdfs', where: 'id = ?', whereArgs: [pdf.id]);
    // Never delete the physical file for built-in books — they live in the
    // external books folder and are shared across profiles.
    if (pdf.profileId != '__builtin__') {
      final f = File(pdf.filePath);
      if (await f.exists()) await f.delete();
    }
  }

  /// Returns a chunk of [pdf] text suitable for prepending to a prompt.
  /// Currently: takes the first [contextCharBudget] chars (head of doc).
  /// Future: smart RAG retrieval based on user question.
  String contextSnippet(PdfDoc pdf) {
    final t = pdf.extractedText;
    if (t.length <= contextCharBudget) return t;
    return t.substring(0, contextCharBudget);
  }
}

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());
