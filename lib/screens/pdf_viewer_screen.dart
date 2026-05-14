import 'dart:async';
import 'dart:io';
import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/pdf_doc.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/model_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_chunk_service.dart'; // for indexingPdfsProvider
import '../services/pdf_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// PDF viewer with a draggable bottom chat panel.
///
/// Layout:
///   ┌─────────────┐
///   │   PDF view  │  ← shrinks as sheet expands
///   ├─────────────┤
///   │ drag handle │  ← always visible ~72 px
///   │  messages   │  ← visible when sheet is dragged up
///   │ mic│input│► │  ← input row always at bottom of sheet
///   └─────────────┘
///
/// Context: uses the text extracted from the current page ±1 page.
/// No embeddings needed — exact page content is sent to the model.
///
/// Chat messages are LOCAL (not persisted). Navigating away clears them.
class PdfViewerScreen extends ConsumerStatefulWidget {
  final PdfDoc pdf;
  const PdfViewerScreen({super.key, required this.pdf});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  // ── PDF ───────────────────────────────────────────────────────────────────
  final _viewerCtrl = PdfViewerController();
  int _currentPage  = 1;
  // Full doc loaded on open (includes extracted_text which listForProfile omits)
  PdfDoc? _fullDoc;
  bool _loadingDoc = true;   // true until findById() completes

  // ── Chat (local — cleared on dispose / navigate-away) ────────────────────
  final _qCtrl            = TextEditingController();
  final _msgScrollCtrl    = ScrollController();
  final List<ChatMessage> _msgs = [];
  bool _chatBusy          = false;
  StreamSubscription<String>? _inferSub;

  // ── Voice ─────────────────────────────────────────────────────────────────
  bool _isListening = false;

  // ── OCR ───────────────────────────────────────────────────────────────────
  bool _ocring    = false; // true while Tesseract is running on current page
  int  _ocrDone   = 0;     // pages OCR'd so far in background pass
  int  _ocrTotal  = 0;     // total pages in this book

  // ── Panel height (replaces DraggableScrollableSheet) ─────────────────────
  // Three snap levels in logical pixels, calculated in build().
  // _panelHeight is updated by the GestureDetector on the handle.
  double _panelHeight = 0; // set in first build
  bool   _panelHeightSet = false;

  // ── Back navigation ───────────────────────────────────────────────────────
  // Set to true when the user triggers back; replaces SfPdfViewer with an
  // empty box for one frame so SyncFusion doesn't throw during pop animation.
  bool _leaving = false;
  // Snap levels (set once screen size is known)
  double _snapSmall  = 0;
  double _snapMid    = 0;
  double _snapLarge  = 0;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadFullDoc();
  }

  Future<void> _loadFullDoc() async {
    final full = await PdfService().findById(widget.pdf.id);
    if (mounted) {
      setState(() {
        _fullDoc    = full;
        _loadingDoc = false;
      });
      // Start background OCR of all pages so answers are ready before asked.
      if (full != null && full.pageCount > 0) {
        _backgroundOcrAllPages(full);
      }
    }
  }

  /// Smart background OCR strategy:
  ///   Pass 1 — current page ±5 (student is reading here RIGHT NOW, ~30s max)
  ///   Pass 2 — rest of the book sequentially (long, runs quietly after pass 1)
  /// Already-cached pages (DB hit) return instantly — no real delay.
  Future<void> _backgroundOcrAllPages(PdfDoc doc) async {
    if (!mounted) return;
    final total = doc.pageCount;
    setState(() { _ocrTotal = total; _ocrDone = 0; });

    // Pass 1: nearby pages first so first question is answered quickly.
    final nearby = <int>[];
    for (int d = 0; d <= 5; d++) {
      if (_currentPage + d <= total) nearby.add(_currentPage + d);
      if (d > 0 && _currentPage - d >= 1) nearby.add(_currentPage - d);
    }
    for (final p in nearby) {
      if (!mounted) return;
      await OcrService.instance.extractPageText(
          pdfPath: doc.filePath, pdfId: doc.id, pageNumber: p);
      if (mounted) setState(() => _ocrDone++);
    }

    // Pass 2: remaining pages in order.
    for (int p = 1; p <= total; p++) {
      if (!mounted) return;
      if (nearby.contains(p)) continue; // already done
      await OcrService.instance.extractPageText(
          pdfPath: doc.filePath, pdfId: doc.id, pageNumber: p);
      if (mounted) setState(() => _ocrDone++);
    }
  }

  @override
  void dispose() {
    _viewerCtrl.dispose();
    _qCtrl.dispose();
    _msgScrollCtrl.dispose();
    _inferSub?.cancel();
    ref.read(sttServiceProvider).stopListening();
    super.dispose();
  }

  void _snapPanel(double dy) {
    // Snap to nearest level when drag ends.
    final levels = [_snapSmall, _snapMid, _snapLarge];
    double nearest = levels.reduce((a, b) =>
        (a - _panelHeight).abs() < (b - _panelHeight).abs() ? a : b);
    setState(() => _panelHeight = nearest);
  }

  void _cyclePanelSnap() {
    // Tap handle → cycle Small → Mid → Large → Small
    if (_panelHeight <= _snapSmall + 2) {
      setState(() => _panelHeight = _snapMid);
    } else if (_panelHeight <= _snapMid + 2) {
      setState(() => _panelHeight = _snapLarge);
    } else {
      setState(() => _panelHeight = _snapSmall);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Page-text helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Extracts text for a single page from the stored extractedText blob.
  String _pageText(int page) {
    // Prefer the full doc (loaded after open); fall back to widget.pdf
    final text = (_fullDoc ?? widget.pdf).extractedText;
    if (text.isEmpty) return '';
    final re = RegExp(
      '--- Page $page ---\\n([\\s\\S]*?)(?=--- Page \\d+ ---|\\s*\$)',
    );
    return re.firstMatch(text)?.group(1)?.trim() ?? '';
  }

  /// Returns the context block for the current page ±1, labelled [Page N].
  String _contextForCurrentPage() {
    final page = _currentPage;
    final doc  = _fullDoc ?? widget.pdf;
    final maxPage = doc.pageCount > 0 ? doc.pageCount : page + 2;
    final from = max(1, page - 1);
    final to   = min(maxPage, page + 1);

    final buf = StringBuffer();
    for (int p = from; p <= to; p++) {
      final t = _pageText(p);
      if (t.isNotEmpty) {
        buf.writeln('[Page $p]');
        buf.writeln(t);
        buf.writeln();
      }
    }
    return buf.toString().trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Send / infer
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _send({String? voiceText}) async {
    final q = (voiceText ?? _qCtrl.text).trim();
    if (q.isEmpty || _chatBusy) return;

    // ── Block until the full doc (with extracted_text) is loaded ─────────
    if (_loadingDoc) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('பக்க உரை ஏற்றுகிறது… / Loading page text, please wait…',
            style: GoogleFonts.notoSansTamil()),
        duration: const Duration(seconds: 2),
      ));
      return;
    }


    // Expand panel so the student can see the answer.
    if (_panelHeight < _snapMid && _snapMid > 0) {
      setState(() => _panelHeight = _snapMid);
    }

    // Add user bubble.
    setState(() {
      _msgs.add(ChatMessage(
        id: _uuid.v4(), role: MessageRole.user,
        text: q, timestamp: DateTime.now(),
      ));
      _chatBusy = true;
      _qCtrl.clear();
    });
    _scrollToBottom();

    // Add empty assistant placeholder.
    final assistantId = _uuid.v4();
    setState(() {
      _msgs.add(ChatMessage(
        id: assistantId, role: MessageRole.assistant,
        text: '', pdfId: widget.pdf.id, timestamp: DateTime.now(),
      ));
    });

    try {
      // ── OCR: extract text from the current page (cached after first run) ──
      final pageText = await OcrService.instance.extractPageText(
        pdfPath   : (_fullDoc ?? widget.pdf).filePath,
        pdfId     : widget.pdf.id,
        pageNumber: _currentPage,
        onProgress: (busy) {
          if (mounted) setState(() => _ocring = busy);
        },
      );

      // Hard block — if OCR returned nothing or errored, replace assistant
      // bubble with a clear error message. No fallback to model knowledge.
      if (pageText.trim().isEmpty || pageText.startsWith('__ERROR__:')) {
        final idx = _msgs.indexWhere((m) => m.id == assistantId);
        if (idx >= 0 && mounted) {
          setState(() {
            _msgs[idx] = ChatMessage(
              id: assistantId, role: MessageRole.assistant,
              text: '⚠ பக்கம் $_currentPage படிக்க முடியவில்லை\n'
                    'Page $_currentPage could not be read by OCR.\n'
                    'Tap 🐛 in the toolbar to check what text was extracted.',
              timestamp: _msgs[idx].timestamp,
            );
            _chatBusy = false;
          });
        }
        return;
      }

      final profile = ref.read(currentProfileProvider);
      final prompt  = _buildPrompt(q, pageText, profile);

      String accumulated = '';

      _inferSub = ref
          .read(modelServiceProvider.notifier)
          .inferStream(prompt)
          .listen(
        (chunk) {
          accumulated += chunk;
          final idx = _msgs.indexWhere((m) => m.id == assistantId);
          if (idx >= 0 && mounted) {
            setState(() {
              _msgs[idx] = ChatMessage(
                id: assistantId, role: MessageRole.assistant,
                text: accumulated, pdfId: widget.pdf.id,
                timestamp: _msgs[idx].timestamp,
              );
            });
            _scrollToBottom();
          }
        },
        onDone: () {
          if (mounted) setState(() => _chatBusy = false);
        },
        onError: (e) {
          final idx = _msgs.indexWhere((m) => m.id == assistantId);
          if (idx >= 0 && mounted) {
            setState(() {
              _msgs[idx] = ChatMessage(
                id: assistantId, role: MessageRole.assistant,
                text: 'பிழை / Error: $e',
                timestamp: _msgs[idx].timestamp,
              );
              _chatBusy = false;
            });
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      final idx = _msgs.indexWhere((m) => m.id == assistantId);
      if (idx >= 0 && mounted) {
        setState(() {
          _msgs[idx] = ChatMessage(
            id: assistantId, role: MessageRole.assistant,
            text: 'பிழை / Error: $e',
            timestamp: _msgs[idx].timestamp,
          );
          _chatBusy = false;
        });
      }
    }
  }

  String _buildPrompt(String question, String pageText, Profile? profile) {
    final lang = (profile?.langTamil == true) ? 'Tamil' : 'Tamil or English';

    // OCR text available — ground the answer STRICTLY in page content only.
    return 'You are a teacher answering a student\'s question '
        'about their textbook "${widget.pdf.title}", page $_currentPage.\n'
        'Answer STRICTLY using ONLY the page text below. '
        'Do NOT use any outside knowledge.\n'
        'Do NOT add motivational phrases.\n'
        'If the answer cannot be found in the page text, reply ONLY with:\n'
        '"இந்தப் பக்கத்தில் இந்தத் தகவல் இல்லை · This information is not on this page."\n\n'
        'PAGE TEXT (page $_currentPage):\n"""\n$pageText\n"""\n\n'
        'Question: $question\n\n'
        'Answer in $lang:';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Voice
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _toggleMic() async {
    final stt = ref.read(sttServiceProvider);

    if (_isListening) {
      await stt.stopListening();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final ok = await stt.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Speech recognition unavailable.',
              style: GoogleFonts.notoSansTamil()),
        ));
      }
      return;
    }

    if (mounted) setState(() => _isListening = true);

    await stt.startListening(
      onResult: (text, {required bool isFinal}) {
        if (mounted) setState(() => _qCtrl.text = text);
        if (isFinal && text.trim().isNotEmpty) {
          if (mounted) setState(() => _isListening = false);
          _send(voiceText: text.trim());
        }
      },
    );
  }


  /// Called when the user presses the system back button.
  /// Sets [_leaving] so the SfPdfViewer is swapped out for a blank box before
  /// the pop animation starts — prevents the one-frame red SyncFusion error.
  void _handleBack() {
    if (_leaving) return;
    setState(() => _leaving = true);
    // Cancel background work immediately
    _inferSub?.cancel();
    ref.read(sttServiceProvider).stopListening();
    // Pop after one frame (SfPdfViewer is already gone from the tree)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_msgScrollCtrl.hasClients &&
          _msgScrollCtrl.position.maxScrollExtent > 0) {
        _msgScrollCtrl.animateTo(
          _msgScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final indexing = ref.watch(indexingPdfsProvider).contains(widget.pdf.id);

    // Calculate snap heights once using LayoutBuilder values.
    // We use a LayoutBuilder below for this.
    return PopScope(
      canPop: false,               // we handle the pop ourselves via _handleBack
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.pdf.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTamil(fontSize: 15)),
            Text(
              widget.pdf.pageCount > 0
                  ? 'பக்கம் $_currentPage / ${widget.pdf.pageCount}'
                  : 'பக்கம் $_currentPage',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 10, color: cs.onPrimary.withOpacity(0.7)),
            ),
          ],
        ),
        actions: [
          // ── OCR diagnostic button ─────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            tooltip: 'Check OCR text for this page',
            onPressed: () async {
              // Show loading dialog while OCR runs
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => AlertDialog(
                  content: Row(children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 16),
                    Text('OCR பக்கம் $_currentPage…',
                        style: GoogleFonts.notoSansTamil()),
                  ]),
                ),
              );

              final ocrText = await OcrService.instance.extractPageText(
                pdfPath   : (_fullDoc ?? widget.pdf).filePath,
                pdfId     : widget.pdf.id,
                pageNumber: _currentPage,
              );

              if (mounted) Navigator.pop(context); // close loading dialog

              if (!mounted) return;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('OCR — பக்கம் $_currentPage',
                      style: GoogleFonts.notoSansTamil(fontSize: 14)),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (ocrText.isEmpty || ocrText.startsWith('__ERROR__:'))
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            Icon(
                              (ocrText.isEmpty || ocrText.startsWith('__ERROR__:'))
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: (ocrText.isEmpty || ocrText.startsWith('__ERROR__:'))
                                  ? Colors.red
                                  : Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ocrText.isEmpty
                              ? 'EMPTY — blank page'
                              : ocrText.startsWith('__ERROR__:')
                                  ? ocrText.replaceFirst('__ERROR__: ', '')
                                  : '${ocrText.length} chars extracted ✓',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: ocrText.isEmpty
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Text('Extracted text:',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                          ocrText.isEmpty
                              ? '(no text — blank page or OCR skipped)'
                              : ocrText.substring(
                                  0, ocrText.length.clamp(0, 800)),
                          style: GoogleFonts.notoSansTamil(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('மூடு / Close',
                          style: GoogleFonts.notoSansTamil()),
                    ),
                  ],
                ),
              );
            },
          ),
          if (indexing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('Indexing…',
                    style: GoogleFonts.notoSansTamil(fontSize: 9)),
                avatar: const SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                backgroundColor: Colors.amber.withOpacity(0.2),
                side: BorderSide(color: Colors.amber.withOpacity(0.5)),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
        ],
      ),

      // Layout: PDF → AnimatedPanel (messages only) → fixed input bar
      // The input bar is OUTSIDE the animated panel so it is always visible.
      body: LayoutBuilder(builder: (ctx, constraints) {
        final totalH = constraints.maxHeight;

        if (!_panelHeightSet) {
          _snapSmall      = 44;              // just the drag handle, input is fixed
          _snapMid        = totalH * 0.40;
          _snapLarge      = totalH * 0.78;
          _panelHeight    = _snapSmall;
          _panelHeightSet = true;
        }

        return Column(
          children: [
            // ── PDF viewer ───────────────────────────────────────────────────
            Expanded(
              child: _leaving
                  // Replace viewer with blank box while pop animation plays —
                  // prevents the SyncFusion one-frame red error on back press.
                  ? const SizedBox.shrink()
                  : widget.pdf.pageCount == -1
                      ? _UnavailableView()
                      : SfPdfViewer.file(
                          File(widget.pdf.filePath),
                          controller: _viewerCtrl,
                          onPageChanged: (d) =>
                              setState(() => _currentPage = d.newPageNumber),
                        ),
            ),

            // ── Slide-up messages panel (no input bar inside) ────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              height: _panelHeight,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 12,
                      offset: const Offset(0, -2)),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Column(
                children: [
                  // Drag handle — tap cycles, drag resizes
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cyclePanelSnap,
                    onVerticalDragUpdate: (d) => setState(() {
                      _panelHeight = (_panelHeight - d.delta.dy)
                          .clamp(_snapSmall, _snapLarge);
                    }),
                    onVerticalDragEnd: (d) =>
                        _snapPanel(d.primaryVelocity ?? 0),
                    child: Container(
                      width: double.infinity,
                      color: cs.surface,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40, height: 4,
                            decoration: BoxDecoration(
                              color: cs.onSurfaceVariant.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_ocring)
                                Text('பக்கம் $_currentPage படிக்கிறேன்… / Reading page…',
                                    style: GoogleFonts.notoSansTamil(
                                        fontSize: 11, color: cs.primary))
                              else if (_ocrTotal > 0 && _ocrDone < _ocrTotal)
                                Text(
                                  'தயாராகிறது $_ocrDone / $_ocrTotal பக்கங்கள் · Indexing…',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 11, color: cs.onSurfaceVariant),
                                )
                              else
                                Text(
                                  'பக்கம் $_currentPage · கேளுங்கள் / Ask about this page',
                                  style: GoogleFonts.notoSansTamil(
                                      fontSize: 11, color: cs.onSurfaceVariant),
                                ),
                              if (_ocrTotal > 0 && _ocrDone < _ocrTotal)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: LinearProgressIndicator(
                                    value: _ocrDone / _ocrTotal,
                                    minHeight: 2,
                                    backgroundColor: cs.surfaceContainerHighest,
                                    color: cs.primary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Messages — only rendered when panel is open
                  if (_panelHeight > _snapSmall + 10)
                    Expanded(
                      child: _msgs.isEmpty
                          ? _EmptyHint()
                          : ListView.builder(
                              controller: _msgScrollCtrl,
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 4),
                              itemCount: _msgs.length,
                              itemBuilder: (_, i) =>
                                  _Bubble(msg: _msgs[i]),
                            ),
                    ),

                ],
              ),
            ),

            // ── Fixed input bar — always visible, outside the animated panel ─
            SafeArea(
              top: false,
              child: Container(
                color: cs.surface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qCtrl,
                        style: GoogleFonts.notoSansTamil(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: _isListening
                              ? 'கேட்கிறேன்… / Listening…'
                              : _loadingDoc
                                  ? 'தயாராகிறது… / Loading…'
                                  : 'பக்கம் $_currentPage பற்றி கேளுங்கள்…',
                          hintStyle: GoogleFonts.notoSansTamil(
                              fontSize: 13,
                              color: _isListening
                                  ? cs.error.withOpacity(0.8)
                                  : cs.onSurfaceVariant),
                        ),
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _send(),
                        enabled: !_chatBusy && !_loadingDoc,
                      ),
                    ),
                    // Mic
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isListening
                          ? IconButton(
                              key: const ValueKey('mic_stop'),
                              icon: Icon(Icons.stop_circle, color: cs.error),
                              onPressed: _toggleMic,
                            )
                          : IconButton(
                              key: const ValueKey('mic'),
                              icon: Icon(Icons.mic_none,
                                  color: _chatBusy
                                      ? cs.onSurfaceVariant
                                      : cs.primary),
                              onPressed: _chatBusy ? null : _toggleMic,
                              tooltip: 'பேசு / Speak',
                            ),
                    ),
                    // Send / spinner
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _chatBusy
                          ? Padding(
                              key: const ValueKey('busy'),
                              padding: const EdgeInsets.all(12),
                              child: SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.primary),
                              ),
                            )
                          : IconButton(
                              key: const ValueKey('send'),
                              icon: const Icon(Icons.send_rounded),
                              color: cs.primary,
                              onPressed: _send,
                              tooltip: 'அனுப்பு / Send',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
      ), // Scaffold
    );   // PopScope
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isUser = msg.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft    : const Radius.circular(16),
            topRight   : const Radius.circular(16),
            bottomLeft : Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4  : 16),
          ),
        ),
        child: msg.text.isEmpty && !isUser
            ? Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Dot(delay: 0),
                  const SizedBox(width: 5),
                  _Dot(delay: 180),
                  const SizedBox(width: 5),
                  _Dot(delay: 360),
                ]),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: Text(
                      msg.text,
                      style: GoogleFonts.notoSansTamil(
                        color   : isUser ? cs.onPrimary : cs.onSurface,
                        fontSize: 14,
                        height  : 1.55,
                      ),
                    ),
                  ),
                  // Speaker button — only on completed assistant messages
                  if (!isUser && msg.text.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _SpeakButton(text: msg.text),
                    ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speaker button (same pattern as chat page)
// ─────────────────────────────────────────────────────────────────────────────

/// Strips markdown symbols, currency signs, and emoji before TTS reads aloud.
String _cleanForTts(String text) {
  // Remove markdown formatting characters (**, __, ~~, ``, ##, >, \)
  text = text.replaceAll(RegExp(r'[*_`~#>\\]'), '');
  // Remove common math/code/currency symbols that TTS reads as noise
  text = text.replaceAll(RegExp(r'[\$€£¥₹@\^{}\[\]|=+<>]'), '');
  // Remove emoji (supplementary Unicode blocks)
  text = text.replaceAll(
    RegExp(
      r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}\u{200D}]',
      unicode: true,
    ),
    ' ',
  );
  // Collapse multiple spaces / excess blank lines
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

class _SpeakButton extends ConsumerStatefulWidget {
  final String text;
  const _SpeakButton({required this.text});
  @override
  ConsumerState<_SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends ConsumerState<_SpeakButton> {
  bool _speaking = false;

  Future<void> _toggle() async {
    final tts = ref.read(ttsServiceProvider);
    if (_speaking) {
      await tts.stop();
      if (mounted) setState(() => _speaking = false);
    } else {
      setState(() => _speaking = true);
      tts.onComplete.first.then((_) {
        if (mounted) setState(() => _speaking = false);
      });
      // Clean symbols before speaking — TTS should read words only
      tts.speak(_cleanForTts(widget.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _speaking ? Icons.stop_circle : Icons.volume_up_outlined,
        size: 18,
        color: _speaking ? cs.error : cs.onSurfaceVariant,
      ),
      tooltip: _speaking ? 'நிறுத்து / Stop' : 'கேளு / Listen',
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: _toggle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty hint
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined,
                size: 36, color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 8),
            Text('இந்தப் பக்கம் பற்றி கேளுங்கள்',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Ask the AI about what you see on this page.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTamil(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status views (pageCount -1)
// ─────────────────────────────────────────────────────────────────────────────

class _UnavailableView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('படம் மட்டுமே உள்ள PDF',
                style: GoogleFonts.notoSansTamil(
                    fontSize: 15, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('This PDF contains only images — text extraction unavailable.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTamil(
                    fontSize: 12, color: cs.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated typing dots
// ─────────────────────────────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
