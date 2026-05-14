import 'dart:io';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:sqflite/sqflite.dart';

import 'db_service.dart';

/// On-device OCR service using Tesseract (Tamil + English).
///
/// Workflow:
///   1. Check in-memory cache → return immediately if hit.
///   2. Check DB (pdf_chunks where chunk_index = -1) → return if stored.
///   3. Render the PDF page to a PNG image via pdfx.
///   4. Run Tesseract OCR (tam+eng) on the image.
///   5. Cache in memory + persist to DB for next time.
///
/// Processing time per page: ~3–8 seconds on mid-range device.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  // In-memory cache: pdfId → { pageNumber → ocrText }
  final Map<String, Map<int, String>> _cache = {};

  // Cached temp-copy paths: pdfId → ASCII temp path.
  // The PDF is copied once per pdfId; subsequent page calls reuse the copy.
  final Map<String, String> _tempPdfPaths = {};

  /// Returns OCR text for [pageNumber] of the PDF at [pdfPath].
  /// [pdfId] is used for DB caching.
  /// [onProgress] is called while OCR is running (true = busy, false = done).
  Future<String> extractPageText({
    required String pdfPath,
    required String pdfId,
    required int pageNumber,
    void Function(bool busy)? onProgress,
  }) async {
    // 1. Memory cache
    final cached = _cache[pdfId]?[pageNumber];
    if (cached != null) return cached;

    // 2. DB cache (chunk_index = -1 marks a full-page OCR entry)
    final db = await DbService.instance.db;
    final rows = await db.query(
      'pdf_chunks',
      columns: ['chunk_text'],
      where: 'pdf_id = ? AND page_number = ? AND chunk_index = -1',
      whereArgs: [pdfId, pageNumber],
    );
    if (rows.isNotEmpty) {
      final text = rows.first['chunk_text'] as String;
      _cache.putIfAbsent(pdfId, () => <int, String>{})[pageNumber] = text;
      return text;
    }

    // 3. Run OCR
    onProgress?.call(true);
    String text = '';
    String lastError = '';
    try {
      final tempDir = await getTemporaryDirectory();

      // Copy PDF to a temp path with ASCII-only name to avoid Tamil filename
      // issues with Android's PdfRenderer.  We cache the copy per pdfId so
      // the 30–100 MB file is copied only ONCE across all page calls for the
      // same book (rather than once per page, which would time out).
      String safePdfPath = _tempPdfPaths[pdfId] ?? '';
      if (safePdfPath.isEmpty || !await File(safePdfPath).exists()) {
        safePdfPath =
            '${tempDir.path}/ocr_src_${pdfId.substring(0, 8)}.pdf';
        await File(pdfPath).copy(safePdfPath);
        _tempPdfPaths[pdfId] = safePdfPath;
      }

      // Render page to PNG
      final doc = await PdfDocument.openFile(safePdfPath);
      final page = await doc.getPage(pageNumber);

      // 2× scale for better OCR accuracy
      final img = await page.render(
        width: page.width * 2.0,
        height: page.height * 2.0,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      await doc.close();
      // Note: safePdfPath is intentionally NOT deleted here — it is reused
      // by subsequent page calls for the same book (see _tempPdfPaths cache).

      if (img != null && img.bytes.isNotEmpty) {
        final imgPath = '${tempDir.path}/ocr_${pdfId.substring(0, 8)}_$pageNumber.png';
        final imgFile = File(imgPath);
        await imgFile.writeAsBytes(img.bytes);

        // Tesseract OCR — Tamil + English
        text = await FlutterTesseractOcr.extractText(
          imgPath,
          language: 'tam+eng',
          args: {
            'psm': '6', // uniform block of text
            'oem': '3', // LSTM engine (best accuracy)
          },
        );

        try { await imgFile.delete(); } catch (_) {}
      } else {
        lastError = 'Page render returned null/empty image';
      }
    } catch (e) {
      lastError = e.toString();
      text = '__ERROR__: $lastError';
    } finally {
      onProgress?.call(false);
    }

    // 4. Persist to DB + memory cache
    // Store errors with prefix so we know it failed vs genuinely empty page.
    final isError = text.startsWith('__ERROR__:');
    final cleaned = isError ? text : text.trim(); // keep error message
    _cache.putIfAbsent(pdfId, () => <int, String>{})[pageNumber] = cleaned;

    if (!isError) {
      // Only persist successful (even if empty) OCR results.
      try {
        await db.insert(
          'pdf_chunks',
          {
            'id': '${pdfId}_ocr_$pageNumber',
            'pdf_id': pdfId,
            'profile_id': '__builtin__',
            'page_number': pageNumber,
            'chunk_text': cleaned,
            'embedding': null,
            'chunk_index': -1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {}
    }

    return cleaned;
  }

  /// Clears in-memory cache for a specific PDF (e.g. after re-import).
  /// Also deletes the cached temp copy so the next OCR run re-copies.
  void clearCache(String pdfId) {
    _cache.remove(pdfId);
    final path = _tempPdfPaths.remove(pdfId);
    if (path != null) {
      try { File(path).delete(); } catch (_) {}
    }
  }
}
