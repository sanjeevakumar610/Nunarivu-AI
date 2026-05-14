import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pdf_doc.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/book_seed_service.dart';
import '../services/pdf_chunk_service.dart';
import '../services/pdf_service.dart';
import 'pdf_viewer_screen.dart';

// ── Grade helpers ─────────────────────────────────────────────────────────────

String? _gradeNumber(String? grade) {
  if (grade == null || grade.isEmpty) return null;
  if (grade.contains('10')) return '10';
  if (grade.contains('11') || grade.toUpperCase().contains('O/L')) return '11';
  return null;
}

bool _bookMatchesGrade(PdfDoc pdf, String gradeNum) =>
    pdf.filePath.contains('/Grade $gradeNum/') ||
    pdf.filePath.contains('\\Grade $gradeNum\\') ||
    pdf.title.startsWith('Grade $gradeNum');

String _displayTitle(String title) {
  final match = RegExp(r'^Grade \d+ › ').firstMatch(title);
  return match != null ? title.substring(match.end) : title;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PdfLibraryScreen extends ConsumerStatefulWidget {
  const PdfLibraryScreen({super.key});

  @override
  ConsumerState<PdfLibraryScreen> createState() => _PdfLibraryScreenState();
}

class _PdfLibraryScreenState extends ConsumerState<PdfLibraryScreen> {
  List<PdfDoc> _pdfs        = [];
  bool         _loading     = true;
  String?      _error;
  bool         _seeding     = false;
  int          _seedProgress = 0;
  int          _seedTotal    = 0;

  @override
  void initState() {
    super.initState();
    // Defer to post-frame so currentProfileProvider is populated by then.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBooks());
  }

  // ── Core load ──────────────────────────────────────────────────────────────

  Future<void> _loadBooks() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final profile = ref.read(currentProfileProvider);
      debugPrint('[Library] _loadBooks: profile=${profile?.id}, name=${profile?.name}');
      if (profile == null) {
        debugPrint('[Library] profile is null — showing empty list');
        if (mounted) setState(() { _pdfs = []; _loading = false; });
        return;
      }
      final pdfs = await ref.read(pdfServiceProvider).listForProfile(profile.id);
      debugPrint('[Library] loaded ${pdfs.length} PDFs from DB');
      if (mounted) setState(() { _pdfs = pdfs; _loading = false; });
    } catch (e, st) {
      debugPrint('[Library] ERROR in _loadBooks: $e\n$st');
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }

    // After showing the list, fix titles + seed new books in background.
    _fixTitlesInBackground();
    _seedBuiltinBooks();
  }

  Future<void> _fixTitlesInBackground() async {
    try {
      await BookSeedService.instance.updateTitles();
      // Silently refresh list if any titles changed.
      if (!mounted) return;
      final profile = ref.read(currentProfileProvider);
      if (profile == null) return;
      final pdfs = await ref.read(pdfServiceProvider).listForProfile(profile.id);
      if (mounted) setState(() => _pdfs = pdfs);
    } catch (_) {
      // Non-critical — swallow silently.
    }
  }

  Future<void> _seedBuiltinBooks() async {
    try {
      final hasBooks = await BookSeedService.instance.hasBooksFolder();
      if (!hasBooks || !mounted) return;

      setState(() { _seeding = true; _seedProgress = 0; _seedTotal = 0; });

      await BookSeedService.instance.seed(
        onProgress: (cur, total) {
          if (mounted) setState(() { _seedProgress = cur; _seedTotal = total; });
        },
        onIndexingChanged: (pdfId, active) {
          if (!mounted) return;
          final notifier = ref.read(indexingPdfsProvider.notifier);
          if (active) {
            notifier.state = {...notifier.state, pdfId};
          } else {
            notifier.state = notifier.state.where((id) => id != pdfId).toSet();
            // Refresh list as each book finishes indexing.
            _refreshList();
          }
        },
      );

      if (mounted) {
        setState(() => _seeding = false);
        _refreshList();
      }
    } catch (e, st) {
      debugPrint('[Library] seed error: $e\n$st');
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _refreshList() async {
    try {
      final profile = ref.read(currentProfileProvider);
      if (profile == null || !mounted) return;
      final pdfs = await ref.read(pdfServiceProvider).listForProfile(profile.id);
      if (mounted) setState(() => _pdfs = pdfs);
    } catch (_) {}
  }

  Future<void> _import(BuildContext ctx) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!ctx.mounted) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(pdfServiceProvider).import(
        sourcePath: path,
        profileId: profile.id,
        onIndexingChanged: (pdfId, active) {
          if (!mounted) return;
          final notifier = ref.read(indexingPdfsProvider.notifier);
          if (active) {
            notifier.state = {...notifier.state, pdfId};
          } else {
            notifier.state = notifier.state.where((id) => id != pdfId).toSet();
          }
        },
      );
      if (ctx.mounted) Navigator.of(ctx).pop();
      _refreshList();
    } catch (e) {
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Reload when the active profile changes (e.g. grade switch in Settings).
    ref.listen<Profile?>(currentProfileProvider, (prev, next) {
      if (next != null && next.id != prev?.id) _loadBooks();
    });

    final profile      = ref.watch(currentProfileProvider);
    final profileGrade = _gradeNumber(profile?.grade);
    final cs           = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('நூலகம் · Library', style: GoogleFonts.notoSansTamil()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan built-in books',
            onPressed: (_seeding || _loading)
                ? null
                : () async {
                    await BookSeedService.instance.resetSeedFlag();
                    _loadBooks();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Seeding progress banner ─────────────────────────────────────
          if (_seeding)
            Container(
              width: double.infinity,
              color: cs.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _seedTotal > 0
                          ? 'நூலகம் தயாரிக்கிறேன்… $_seedProgress / $_seedTotal'
                          : 'நூலகம் தயாரிக்கிறேன்…',
                      style: GoogleFonts.notoSansTamil(
                          fontSize: 12, color: cs.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),

          // ── Book list ───────────────────────────────────────────────────
          Expanded(child: _buildBody(profileGrade, cs)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(context),
        icon: const Icon(Icons.upload_file),
        label: Text('Import PDF', style: GoogleFonts.notoSansTamil()),
      ),
    );
  }

  Widget _buildBody(String? profileGrade, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text('நூலகம் திறக்கவில்லை · Could not load library',
                  style: GoogleFonts.notoSansTamil(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Text(_error!,
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadBooks,
                icon: const Icon(Icons.refresh),
                label: Text('மீண்டும் முயற்சி · Retry',
                    style: GoogleFonts.notoSansTamil()),
              ),
            ],
          ),
        ),
      );
    }

    final builtin = _pdfs.where((p) => p.profileId == builtinProfileId).toList();
    final user    = _pdfs.where((p) => p.profileId != builtinProfileId).toList();

    final grade11    = builtin.where((b) => _bookMatchesGrade(b, '11')).toList();
    final grade10    = builtin.where((b) => _bookMatchesGrade(b, '10')).toList();
    final otherBooks = builtin
        .where((b) => !_bookMatchesGrade(b, '10') && !_bookMatchesGrade(b, '11'))
        .toList();

    final showG11 = profileGrade == null || profileGrade == '11';
    final showG10 = profileGrade == null || profileGrade == '10';

    final items = <Widget>[];

    if (showG11 && grade11.isNotEmpty) {
      items.add(_GradeHeader(
        label: '📚 Grade 11 Textbooks · தரம் 11 பாடநூல்கள்',
        isMyGrade: profileGrade == '11',
      ));
      for (int i = 0; i < grade11.length; i++) {
        items.add(
          _PdfTile(pdf: grade11[i], isBuiltin: true)
              .animate().fadeIn(delay: (i * 20).ms),
        );
      }
    }

    if (showG10 && grade10.isNotEmpty) {
      items.add(_GradeHeader(
        label: '📚 Grade 10 Textbooks · தரம் 10 பாடநூல்கள்',
        isMyGrade: profileGrade == '10',
      ));
      for (int i = 0; i < grade10.length; i++) {
        items.add(
          _PdfTile(pdf: grade10[i], isBuiltin: true)
              .animate().fadeIn(delay: (i * 20).ms),
        );
      }
    }

    if (otherBooks.isNotEmpty) {
      items.add(const _GradeHeader(label: '📚 Other Books · பிற நூல்கள்'));
      for (final b in otherBooks) {
        items.add(_PdfTile(pdf: b, isBuiltin: true));
      }
    }

    if (user.isNotEmpty) {
      items.add(const _GradeHeader(label: '📁 My Imports · என் கோப்புகள்'));
      for (int i = 0; i < user.length; i++) {
        items.add(
          _PdfTile(pdf: user[i], isBuiltin: false)
              .animate().fadeIn(delay: (i * 40).ms),
        );
      }
    }

    if (items.isEmpty && !_seeding) return const _EmptyLibrary();
    if (items.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

// ── Grade section header ──────────────────────────────────────────────────────

class _GradeHeader extends StatelessWidget {
  final String label;
  final bool isMyGrade;
  const _GradeHeader({required this.label, this.isMyGrade = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.notoSansTamil(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isMyGrade ? cs.primary : cs.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (isMyGrade)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'உங்கள் தரம்',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 9, color: cs.onPrimaryContainer),
              ),
            ),
        ],
      ),
    );
  }
}

// ── PDF tile ──────────────────────────────────────────────────────────────────

class _PdfTile extends ConsumerWidget {
  final PdfDoc pdf;
  final bool isBuiltin;
  const _PdfTile({required this.pdf, required this.isBuiltin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final indexing = ref.watch(indexingPdfsProvider).contains(pdf.id);
    final failed   = pdf.pageCount < 0;
    final title    = _displayTitle(pdf.title);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Card(
        elevation: isBuiltin ? 0 : 1,
        color: isBuiltin ? cs.surfaceContainerLowest : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isBuiltin
              ? BorderSide(color: cs.outlineVariant.withOpacity(0.4))
              : BorderSide.none,
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isBuiltin ? cs.secondaryContainer : cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isBuiltin ? Icons.menu_book_rounded : Icons.picture_as_pdf,
              color: isBuiltin ? cs.onSecondaryContainer : cs.onPrimaryContainer,
              size: 22,
            ),
          ),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTamil(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Row(
            children: [
              if (failed) ...[
                Icon(Icons.image_outlined, size: 12, color: cs.error),
                const SizedBox(width: 4),
                Text('படம் மட்டுமே · Image PDF',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11, color: cs.error)),
              ] else if (indexing) ...[
                SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: cs.primary),
                ),
                const SizedBox(width: 5),
                Text('Indexing…',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11, color: cs.primary)),
              ] else if (pdf.pageCount > 0) ...[
                Text(
                  '${pdf.pageCount} பக்கங்கள்',
                  style: GoogleFonts.notoSansTamil(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
          trailing: isBuiltin
              ? null
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) async {
                    if (v == 'delete') {
                      await ref.read(pdfServiceProvider).delete(pdf);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
          // Processing books can still be opened (PDF renders fine;
          // AI chat will note that text isn't ready yet).
          // Only permanently-failed books are blocked.
          onTap: failed
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      'இந்தக் கோப்பு திறக்க முடியவில்லை / Could not read file',
                      style: GoogleFonts.notoSansTamil(),
                    ),
                  ));
                }
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(pdf: pdf)),
                  ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_rounded, size: 80, color: cs.primary),
            const SizedBox(height: 20),
            Text(
              'நூலகம் காலி',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Import a PDF using the button below,\n'
              'or copy books to the device books folder.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTamil(
                  fontSize: 13, color: cs.onSurfaceVariant, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
