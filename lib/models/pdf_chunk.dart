import 'dart:typed_data';

/// A single text chunk from a PDF page, with an optional embedding vector
/// stored as raw bytes (4 bytes per float32 value).
class PdfChunk {
  final String id;
  final String pdfId;
  final String profileId;
  final int pageNumber;
  final String chunkText;
  /// Serialized Float32List — null until the embedding has been computed.
  final Uint8List? embeddingBlob;
  final int chunkIndex;

  const PdfChunk({
    required this.id,
    required this.pdfId,
    required this.profileId,
    required this.pageNumber,
    required this.chunkText,
    this.embeddingBlob,
    required this.chunkIndex,
  });

  /// Decode the stored BLOB back to a Float32List.
  /// Returns null if the embedding has not been computed yet.
  Float32List? get embedding {
    if (embeddingBlob == null || embeddingBlob!.isEmpty) return null;
    return embeddingBlob!.buffer.asFloat32List(
        embeddingBlob!.offsetInBytes, embeddingBlob!.lengthInBytes ~/ 4);
  }

  Map<String, dynamic> toMap() => {
        'id'          : id,
        'pdf_id'      : pdfId,
        'profile_id'  : profileId,
        'page_number' : pageNumber,
        'chunk_text'  : chunkText,
        'embedding'   : embeddingBlob,
        'chunk_index' : chunkIndex,
      };

  factory PdfChunk.fromMap(Map<String, dynamic> m) => PdfChunk(
        id            : m['id'] as String,
        pdfId         : m['pdf_id'] as String,
        profileId     : m['profile_id'] as String,
        pageNumber    : m['page_number'] as int,
        chunkText     : m['chunk_text'] as String,
        embeddingBlob : m['embedding'] as Uint8List?,
        chunkIndex    : m['chunk_index'] as int,
      );
}
