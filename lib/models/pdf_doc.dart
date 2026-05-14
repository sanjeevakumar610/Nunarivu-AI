class PdfDoc {
  final String id;
  final String profileId;
  final String filePath;
  final String title;
  /// Full extracted text. May be large for big books — stored in DB
  /// for simplicity; future: move to file on disk if >2 MB.
  final String extractedText;
  final int pageCount;
  final DateTime createdAt;

  const PdfDoc({
    required this.id,
    required this.profileId,
    required this.filePath,
    required this.title,
    required this.extractedText,
    required this.pageCount,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'file_path': filePath,
        'title': title,
        'extracted_text': extractedText,
        'page_count': pageCount,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory PdfDoc.fromMap(Map<String, Object?> m) => PdfDoc(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        filePath: m['file_path'] as String,
        title: m['title'] as String,
        // extracted_text may be omitted in lightweight list queries
        extractedText: (m['extracted_text'] as String?) ?? '',
        pageCount: m['page_count'] as int,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
