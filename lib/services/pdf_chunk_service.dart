import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/pdf_chunk.dart';
import '../models/pdf_doc.dart';
import 'db_service.dart';
import 'embedding_service.dart';

const _uuid = Uuid();

final pdfChunkServiceProvider =
    Provider<PdfChunkService>((_) => PdfChunkService.instance);

/// Global indexing-status provider — tracks which PDF IDs are currently being
/// chunked/embedded. UI watches this to show the "Indexing…" badge.
final indexingPdfsProvider = StateProvider<Set<String>>((ref) => const {});

/// Manages chunking, embedding, and similarity search for PDF pages.
class PdfChunkService {
  PdfChunkService._();
  static final PdfChunkService instance = PdfChunkService._();

  // Rough characters per chunk (split on word boundary). ~400 chars ≈ 80 words.
  static const _chunkSize    = 400;
  static const _chunkOverlap =  50; // overlap prevents cutting mid-concept

  // ── Chunking + embedding ───────────────────────────────────────────────────

  /// Parse [pdf.extractedText], embed every chunk, and persist to `pdf_chunks`.
  ///
  /// Runs entirely in the background — call with `unawaited()`.
  /// [onIndexingChanged] is invoked with `true` at start and `false` at end so
  /// the caller can update [indexingPdfsProvider].
  Future<void> chunkAndEmbed(
    PdfDoc pdf,
    String profileId, {
    void Function(bool indexing)? onIndexingChanged,
  }) async {
    onIndexingChanged?.call(true);
    try {
      await EmbeddingService.instance.init();
      final db = await DbService.instance.db;

      // Already indexed? (e.g. re-open after process restart)
      final existing = await db.rawQuery(
          'SELECT COUNT(*) FROM pdf_chunks WHERE pdf_id = ?', [pdf.id]);
      if ((existing.first.values.first as int) > 0) return;

      // 1. Parse extracted text into per-page strings.
      final pageTexts = _parsePages(pdf.extractedText);

      // 2. Chunk, embed and collect rows.
      final rows = <Map<String, dynamic>>[];
      for (final entry in pageTexts.entries) {
        final pageNum = entry.key;
        final chunks  = _splitPage(entry.value);
        for (int idx = 0; idx < chunks.length; idx++) {
          final text      = chunks[idx];
          final embedding = await EmbeddingService.instance.embed(text);
          rows.add(PdfChunk(
            id          : _uuid.v4(),
            pdfId       : pdf.id,
            profileId   : profileId,
            pageNumber  : pageNum,
            chunkText   : text,
            embeddingBlob: EmbeddingService.encodeFloat32(embedding),
            chunkIndex  : idx,
          ).toMap());

          // Batch-insert every 20 rows to keep DB lock contention low.
          if (rows.length >= 20) {
            await _batchInsert(db, rows);
            rows.clear();
          }
        }
      }
      if (rows.isNotEmpty) await _batchInsert(db, rows);
    } finally {
      onIndexingChanged?.call(false);
    }
  }

  Future<void> _batchInsert(
      Database db, List<Map<String, dynamic>> rows) async {
    final batch = db.batch();
    for (final row in rows) {
      batch.insert('pdf_chunks', row,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  /// Returns `true` if [pdfId] has at least one chunk in the DB.
  Future<bool> isChunked(String pdfId) async {
    final db   = await DbService.instance.db;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) FROM pdf_chunks WHERE pdf_id = ?', [pdfId]);
    return (rows.first.values.first as int) > 0;
  }

  /// Retrieve the [topK] most semantically similar chunks to [queryVec] within
  /// pages [pageMin]–[pageMax] of [pdfId].
  ///
  /// If [pageMin] == 1 and [pageMax] >= [pdf.pageCount], searches the whole doc.
  Future<List<PdfChunk>> search(
    String pdfId,
    Float32List queryVec,
    int pageMin,
    int pageMax, {
    int topK = 4,
  }) async {
    final db   = await DbService.instance.db;
    final rows = await db.query(
      'pdf_chunks',
      where: 'pdf_id = ? AND page_number BETWEEN ? AND ?',
      whereArgs: [pdfId, pageMin, pageMax],
    );

    if (rows.isEmpty) return [];

    final svc = EmbeddingService.instance;
    final scored = <({PdfChunk chunk, double score})>[];

    for (final row in rows) {
      final chunk = PdfChunk.fromMap(row);
      final emb   = chunk.embedding;
      if (emb == null) continue;

      // Only compare vectors of matching dimensionality (guards against
      // mixed TFLite / TF-IDF embeddings if the user swapped models).
      if (emb.length != queryVec.length) continue;

      final score = svc.cosineSimilarity(queryVec, emb);
      scored.add((chunk: chunk, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).map((e) => e.chunk).toList();
  }

  // ── Text processing ────────────────────────────────────────────────────────

  /// Parse `--- Page N ---` markers written by `PdfService.import()`.
  Map<int, String> _parsePages(String extractedText) {
    final result = <int, String>{};
    final re = RegExp(r'--- Page (\d+) ---', multiLine: true);
    final matches = re.allMatches(extractedText).toList();

    for (int i = 0; i < matches.length; i++) {
      final pageNum = int.parse(matches[i].group(1)!);
      final start   = matches[i].end;
      final end     = i + 1 < matches.length ? matches[i + 1].start : extractedText.length;
      final text    = extractedText.substring(start, end).trim();
      if (text.isNotEmpty) result[pageNum] = text;
    }
    return result;
  }

  /// Split a page's text into overlapping ~[_chunkSize]-char chunks, breaking
  /// on word (whitespace) boundaries where possible.
  List<String> _splitPage(String text) {
    if (text.isEmpty) return [];
    if (text.length <= _chunkSize) return [text.trim()];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = (start + _chunkSize).clamp(0, text.length);

      // Extend to the next whitespace so we don't cut a word mid-stream.
      if (end < text.length) {
        final nextSpace = text.indexOf(RegExp(r'\s'), end);
        if (nextSpace != -1 && nextSpace - end < 60) end = nextSpace;
      }

      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);

      // Move start forward, keeping [_chunkOverlap] chars of context overlap.
      start = end - _chunkOverlap;
      if (start >= text.length) break;
    }
    return chunks;
  }
}
