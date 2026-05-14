import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// NOTE: tflite_flutter support is scaffolded but disabled because tflite_flutter
// 0.10.4 has an internal compilation bug with Dart >=3.10. Re-enable by adding
// tflite_flutter to pubspec.yaml and uncommenting the Interpreter blocks below
// once a compatible version is available.
// import 'package:tflite_flutter/tflite_flutter.dart';

final embeddingServiceProvider =
    Provider<EmbeddingService>((_) => EmbeddingService.instance);

/// Singleton that produces sentence embeddings for semantic chunk search.
///
/// Two operating modes — selected automatically at [init]:
///
///   Full mode  — multilingual-e5-small TFLite model loaded from device storage.
///                True semantic embeddings; 384-dim Float32 vectors.
///                Model path (side-load like Gemma):
///                  …/Android/data/<pkg>/files/models/multilingual-e5-small.tflite
///
///   Fallback   — Pure-Dart TF-IDF over a 2048-bucket hash space.
///                Good for domain-specific textbook terminology (Tamil + English).
///                No model file required; fully offline.
///
/// The app works correctly in both modes; full mode gives higher semantic quality.
class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  static const _tfidfDim = 2048;

  // TFLite mode is scaffolded for future use; currently always uses TF-IDF.
  bool _initialized = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // Future: load TFLite model when tflite_flutter is re-enabled.
  }

  bool get usingFallback => true;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Embed [text] and return a normalized Float32List vector.
  ///
  /// For "passage" text (chunks being indexed), call as-is.
  /// For "query" text (student question), the E5 model expects a "query: " prefix
  /// which is applied automatically when [isQuery] is true.
  Future<Float32List> embed(String text, {bool isQuery = false}) async {
    if (!_initialized) await init();
    return _tfidfEmbed(text);
  }

  /// Cosine similarity between two L2-normalised vectors.
  /// Works for any dimensionality as long as both vectors match.
  double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;
    double dot = 0;
    for (int i = 0; i < a.length; i++) dot += a[i] * b[i];
    return dot.clamp(-1.0, 1.0);
  }

  // ── BLOB serialisation ─────────────────────────────────────────────────────

  /// Serialise a Float32List to raw bytes for SQLite BLOB storage.
  static Uint8List encodeFloat32(Float32List v) {
    final bd = ByteData(v.length * 4);
    for (int i = 0; i < v.length; i++) bd.setFloat32(i * 4, v[i], Endian.little);
    return bd.buffer.asUint8List();
  }

  /// Deserialise a BLOB back to a Float32List.
  static Float32List decodeFloat32(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final result = Float32List(bytes.length ~/ 4);
    for (int i = 0; i < result.length; i++) {
      result[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return result;
  }

  // ── TF-IDF (pure Dart, no native dependencies) ────────────────────────────

  /// Hash-based TF-IDF vector over a [_tfidfDim]-bucket space.
  Float32List _tfidfEmbed(String text) {
    final terms = _tokenizeTerms(text);
    if (terms.isEmpty) return Float32List(_tfidfDim);

    final tf = <int, double>{};
    for (final t in terms) {
      final bucket = _hashBucket(t);
      tf[bucket] = (tf[bucket] ?? 0) + 1;
    }

    final vec = Float32List(_tfidfDim);
    for (final entry in tf.entries) {
      // Simple log-TF weighting (IDF approximated as 1 — acceptable for similarity)
      vec[entry.key] = math.log(1 + entry.value);
    }
    return _l2Normalize(vec);
  }

  /// Simple Unicode-aware tokeniser: split on whitespace + common punctuation,
  /// lowercase ASCII, keep Tamil graphemes as-is.
  List<String> _tokenizeTerms(String text) {
    final terms = <String>[];
    // Split on whitespace, punctuation, and numbers
    final parts = text.split(RegExp(r'[\s\p{P}\p{N}]+', unicode: true));
    for (final p in parts) {
      final t = p.trim().toLowerCase();
      if (t.length >= 2) terms.add(t);
    }
    return terms;
  }

  /// FNV-1a 32-bit hash mapped to [0, _tfidfDim).
  int _hashBucket(String term) {
    int hash = 0x811c9dc5;
    for (final unit in term.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % _tfidfDim;
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  Float32List _l2Normalize(Float32List v) {
    double norm = 0;
    for (final x in v) norm += x * x;
    norm = math.sqrt(norm);
    if (norm < 1e-10) return v;
    final out = Float32List(v.length);
    for (int i = 0; i < v.length; i++) out[i] = v[i] / norm;
    return out;
  }
}
