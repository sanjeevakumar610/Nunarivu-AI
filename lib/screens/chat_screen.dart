import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../providers/chat_session_provider.dart';
import '../providers/profile_provider.dart';
import '../services/badge_service.dart';
import '../services/chat_history_service.dart';
import '../services/chat_session_service.dart';
import '../services/model_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import 'reminder_screen.dart';

const _uuid = Uuid();

// ── Providers ────────────────────────────────────────────────────────────────

final _messagesProvider =
    AsyncNotifierProvider<_MessagesNotifier, List<ChatMessage>>(
        _MessagesNotifier.new);

class _MessagesNotifier extends AsyncNotifier<List<ChatMessage>> {
  @override
  Future<List<ChatMessage>> build() async {
    final profile = ref.watch(currentProfileProvider);
    final chatId  = ref.watch(currentChatIdProvider);
    if (profile == null) return [];
    if (chatId == null) return [];
    return ref.read(chatHistoryServiceProvider).loadForChat(chatId);
  }

  Future<void> add(ChatMessage m) async {
    state = AsyncData([...(state.value ?? []), m]);
    await ref.read(chatHistoryServiceProvider).save(m);
  }
}

final _isThinkingProvider    = StateProvider<bool>((ref) => false);
final _streamingTextProvider = StateProvider<String?>((ref) => null);

// ── TTS text cleaning ────────────────────────────────────────────────────────

String _cleanForTts(String text) {
  text = text.replaceAll(
    RegExp(
      r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}\u{200D}]',
      unicode: true,
    ),
    ' ',
  );
  text = text.replaceAll(RegExp(r'[*_`~#>\\]'), '');
  text = text.replaceAll(RegExp(r'^\s*-\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

// ── Chat screen ───────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isListening = false;

  // ── Inference cancellation ────────────────────────────────────────────────
  StreamSubscription<String>? _inferSubscription;
  Completer<void>? _streamCompleter;

  @override
  void dispose() {
    _inferSubscription?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleListening() async {
    final stt = ref.read(sttServiceProvider);
    if (_isListening) {
      await stt.stopListening();
      setState(() => _isListening = false);
      return;
    }
    final ok = await stt.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Speech recognition unavailable. Install Tamil (ta-IN) offline pack.'),
        ));
      }
      return;
    }
    setState(() => _isListening = true);
    await stt.startListening(onResult: (text, {required bool isFinal}) {
      if (mounted) {
        setState(() {
          _textCtrl.text = text;
          _textCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
          if (isFinal) _isListening = false;
        });
      }
    });
  }

  // ── Shared streaming inference runner ────────────────────────────────────

  /// Streams tokens from the model, saves the completed assistant message,
  /// and resets thinking/streaming state.  Can be stopped mid-stream via
  /// [_stopInference] — partial text is saved by the stop handler.
  Future<void> _runInference(
    String fullPrompt, {
    required String profileId,
    required String? chatId,
    String? imagePath,
  }) async {
    _streamCompleter = Completer<void>();
    ref.read(_streamingTextProvider.notifier).state = '';
    ref.read(_isThinkingProvider.notifier).state = true;
    _scrollToBottom();

    _inferSubscription = ref
        .read(modelServiceProvider.notifier)
        .inferStream(fullPrompt, imagePath: imagePath)
        .listen(
      (chunk) {
        ref.read(_streamingTextProvider.notifier).state =
            (ref.read(_streamingTextProvider) ?? '') + chunk;
        _scrollToBottom();
      },
      onDone: () => _streamCompleter?.complete(),
      onError: (e) => _streamCompleter?.completeError(e),
      cancelOnError: true,
    );

    try {
      await _streamCompleter!.future;
      final finalText = ref.read(_streamingTextProvider) ?? '';
      if (finalText.isNotEmpty) {
        await ref.read(_messagesProvider.notifier).add(ChatMessage(
              id: _uuid.v4(),
              profileId: profileId,
              chatId: chatId,
              role: MessageRole.assistant,
              text: finalText,
              timestamp: DateTime.now(),
            ));
      } else {
        // EventChannel stream completed with zero tokens — fall back to the
        // non-streaming MethodChannel infer() so the user still gets a reply.
        try {
          final response = await ref
              .read(modelServiceProvider.notifier)
              .infer(fullPrompt, imagePath: imagePath);
          await ref.read(_messagesProvider.notifier).add(ChatMessage(
                id: _uuid.v4(),
                profileId: profileId,
                chatId: chatId,
                role: MessageRole.assistant,
                text: response.isNotEmpty
                    ? response
                    : 'மன்னிக்கவும், மாதிரி பதில் தரவில்லை.\n'
                      'No response from model. '
                      'Go to Settings → Advanced and reload the model.',
                timestamp: DateTime.now(),
              ));
        } catch (fallbackErr) {
          await ref.read(_messagesProvider.notifier).add(ChatMessage(
                id: _uuid.v4(),
                profileId: profileId,
                chatId: chatId,
                role: MessageRole.assistant,
                text: 'மாதிரி பிழை / Model error: $fallbackErr\n'
                    'Settings → Advanced → மாதிரி மீண்டும் ஏற்று / Reload Model.',
                timestamp: DateTime.now(),
              ));
        }
      }
    } catch (e) {
      await ref.read(_messagesProvider.notifier).add(ChatMessage(
            id: _uuid.v4(),
            profileId: profileId,
            chatId: chatId,
            role: MessageRole.assistant,
            text: 'பிழை / Error: $e\n'
                'Settings → Advanced → மாதிரி மீண்டும் ஏற்று / Reload Model.',
            timestamp: DateTime.now(),
          ));
    } finally {
      _inferSubscription = null;
      _streamCompleter = null;
      ref.read(_streamingTextProvider.notifier).state = null;
      ref.read(_isThinkingProvider.notifier).state = false;
      _scrollToBottom();
    }
  }

  /// Cancels the current inference, saves whatever was generated so far,
  /// and resets UI state immediately.
  void _stopInference() {
    final partialText = ref.read(_streamingTextProvider) ?? '';
    // Complete the future first so _runInference's await resumes cleanly
    final completer = _streamCompleter;
    _streamCompleter = null;
    _inferSubscription?.cancel();
    _inferSubscription = null;
    completer?.complete();
    // Reset state immediately for responsive UI
    ref.read(_streamingTextProvider.notifier).state = null;
    ref.read(_isThinkingProvider.notifier).state = false;
    // Save partial text as a message (non-blocking)
    if (partialText.isNotEmpty && mounted) {
      final profile = ref.read(currentProfileProvider);
      final chatId  = ref.read(currentChatIdProvider);
      if (profile != null) {
        unawaited(ref.read(_messagesProvider.notifier).add(ChatMessage(
              id: _uuid.v4(),
              profileId: profile.id,
              chatId: chatId,
              role: MessageRole.assistant,
              text: partialText,
              timestamp: DateTime.now(),
            )));
      }
    }
  }

  // ── Core send ─────────────────────────────────────────────────────────────

  Future<void> _sendMessage({String? overrideDisplayText}) async {
    final displayText = (overrideDisplayText ?? _textCtrl.text).trim();
    if (displayText.isEmpty) return;

    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    // Auto-create session on first message
    var chatId = ref.read(currentChatIdProvider);
    if (chatId == null) {
      final title =
          displayText.length > 40 ? '${displayText.substring(0, 40)}…' : displayText;
      chatId = await ref
          .read(chatSessionServiceProvider)
          .create(profile.id, title);
      ref.read(currentChatIdProvider.notifier).state = chatId;
    }

    // Save & display user message (uses displayText, not the expanded prompt)
    await ref.read(_messagesProvider.notifier).add(ChatMessage(
          id: _uuid.v4(),
          profileId: profile.id,
          chatId: chatId,
          role: MessageRole.user,
          text: displayText,
          timestamp: DateTime.now(),
        ));

    _textCtrl.clear();
    _scrollToBottom(); // show the user message immediately before inference starts

    // Build full prompt: system context + user question (no history — each Q is independent).
    // End with "Answer:" so the model has a clear signal to start generating a response,
    // mirroring the library chat's proven "_buildPrompt" pattern that always works.
    final systemPrompt = profile.buildSystemPrompt();
    final fullPrompt   = '$systemPrompt\n\nStudent: $displayText\n\nAnswer:';

    // Always pass imagePath: null (Gemma 4 E2B is text-only)
    await _runInference(fullPrompt,
        profileId: profile.id, chatId: chatId, imagePath: null);

    // Check for newly-unlocked badges (non-blocking)
    unawaited(_checkBadges(profile.id));
  }

  // ── Badge check & toast ───────────────────────────────────────────────────

  Future<void> _checkBadges(String profileId) async {
    final newBadges =
        await BadgeService.instance.checkAndAward(profileId);
    for (final b in newBadges) {
      if (!mounted) break;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.amber.shade700,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Text(b.badgeType.emoji,
                style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('புதிய பதக்கம்! / New Badge!',
                      style: GoogleFonts.notoSansTamil(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13)),
                  Text(
                      '${b.badgeType.tamil} · ${b.badgeType.english}',
                      style: GoogleFonts.notoSansTamil(
                          fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ));
      // Stagger multiple badge toasts
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  // ── Feedback action buttons ───────────────────────────────────────────────

  /// Called when student taps "More Examples" or "Extra Help".
  /// Directly asks the model — no data is collected or sent anywhere.
  Future<void> _handleFeedback(
    bool moreExamples,          // true = more examples, false = extra help
    ChatMessage assistantMsg,
  ) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final String displayText;
    final String followUp;
    if (moreExamples) {
      displayText = 'மேலும் உதாரணம் / More examples';
      followUp =
          'The student wants more examples.\n'
          'Previous explanation:\n${assistantMsg.text}\n\n'
          'Please provide 2–3 more different, concrete real-life examples '
          'to help the student understand this better.';
    } else {
      displayText = 'மேலும் விளக்கவும் / Explain more';
      followUp =
          'The student needs a clearer explanation.\n'
          'Previous explanation:\n${assistantMsg.text}\n\n'
          'Please explain this again in a different, simpler way, '
          'step by step, as if talking to a student who is confused.';
    }

    final systemPrompt = profile.buildSystemPrompt();
    final fullPrompt   = '$systemPrompt\n\n$followUp\n\nAnswer:';

    var chatId = ref.read(currentChatIdProvider);
    if (chatId == null) {
      chatId = await ref
          .read(chatSessionServiceProvider)
          .create(profile.id, displayText);
      ref.read(currentChatIdProvider.notifier).state = chatId;
    }

    await ref.read(_messagesProvider.notifier).add(ChatMessage(
          id: _uuid.v4(),
          profileId: profile.id,
          chatId: chatId,
          role: MessageRole.user,
          text: displayText,
          timestamp: DateTime.now(),
        ));

    await _runInference(fullPrompt,
        profileId: profile.id, chatId: chatId);
  }

  // ── Translate (In English / தமிழில்) ─────────────────────────────────────

  /// Re-explains [assistantMsg] in [targetLang] ('English' or 'Tamil').
  Future<void> _handleTranslate(
    ChatMessage assistantMsg,
    String targetLang,
  ) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final isEnglish = targetLang == 'English';
    final displayText = isEnglish
        ? 'In English / ஆங்கிலத்தில்'
        : 'In Tamil / தமிழில்';

    final instruction = isEnglish
        ? 'Explain the following answer again in clear, simple English. '
          'Keep the same meaning but use everyday English words a student can understand easily.\n\n'
          'Answer to re-explain:\n${assistantMsg.text}'
        : 'Explain the following answer again in clear, simple Tamil (தமிழ்). '
          'Keep the same meaning but use everyday Tamil words a student can understand easily.\n\n'
          'Answer to re-explain:\n${assistantMsg.text}';

    final systemPrompt = profile.buildSystemPrompt();
    final fullPrompt   = '$systemPrompt\n\n$instruction\n\nAnswer:';

    var chatId = ref.read(currentChatIdProvider);
    if (chatId == null) {
      chatId = await ref
          .read(chatSessionServiceProvider)
          .create(profile.id, displayText);
      ref.read(currentChatIdProvider.notifier).state = chatId;
    }

    await ref.read(_messagesProvider.notifier).add(ChatMessage(
          id: _uuid.v4(),
          profileId: profile.id,
          chatId: chatId,
          role: MessageRole.user,
          text: displayText,
          timestamp: DateTime.now(),
        ));

    await _runInference(fullPrompt,
        profileId: profile.id, chatId: chatId);
  }

  // ── New chat / history ────────────────────────────────────────────────────

  void _newChat() {
    ref.read(currentChatIdProvider.notifier).state = null;
    ref.invalidate(_messagesProvider);
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ChatHistorySheet(
        onSessionSelected: (chatId) {
          ref.read(currentChatIdProvider.notifier).state = chatId;
          ref.invalidate(_messagesProvider);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messagesAsync  = ref.watch(_messagesProvider);
    final isThinking     = ref.watch(_isThinkingProvider);
    final modelState     = ref.watch(modelServiceProvider);
    final profile        = ref.watch(currentProfileProvider);
    final streamingText  = ref.watch(_streamingTextProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile != null ? 'வணக்கம் ${profile.name}' : 'நுணரிவு AI',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              profile != null ? 'Hi ${profile.name}' : 'Nunarivu AI',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'நினைவூட்டல் / Reminders',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ReminderScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'புதிய அரட்டை / New chat',
            onPressed: _newChat,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'வரலாறு / History',
            onPressed: _showHistory,
          ),
          _ModelStatusChip(modelState: modelState),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (modelState == ModelState.notFound || modelState == ModelState.error)
            _ModelBanner(modelState: modelState),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) => messages.isEmpty && !isThinking
                  ? const _WelcomeView()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: messages.length + (isThinking ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == messages.length) {
                          return _StreamingBubble(text: streamingText ?? '');
                        }
                        final msg = messages[i];
                        if (msg.role == MessageRole.assistant) {
                          return _MessageBubble(
                            message: msg,
                            onMoreExamples: isThinking ? null : () =>
                                _handleFeedback(true, msg),
                            onExtraHelp: isThinking ? null : () =>
                                _handleFeedback(false, msg),
                            onInEnglish: isThinking ? null : () =>
                                _handleTranslate(msg, 'English'),
                            onInTamil: isThinking ? null : () =>
                                _handleTranslate(msg, 'Tamil'),
                          );
                        }
                        return _MessageBubble(message: msg);
                      },
                    ),
            ),
          ),
          // "AI can make mistakes" disclaimer
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Center(
              child: Text(
                'AI தவறு செய்யலாம் · AI can make mistakes',
                style: GoogleFonts.notoSansTamil(
                  fontSize: 9,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.45),
                ),
              ),
            ),
          ),
          // Context-full warning when chat gets long
          if (messagesAsync.value != null &&
              (messagesAsync.value!.length) >= 200)
            _ContextFullBanner(onNewChat: _newChat),
          _InputBar(
            controller: _textCtrl,
            isListening: _isListening,
            canSend: modelState == ModelState.ready && !isThinking,
            isStreaming: isThinking,
            onMicPressed: _toggleListening,
            onSendPressed: _sendMessage,
            onStopPressed: _stopInference,
          ),
        ],
      ),
    );
  }
}

// ─── Status chip ─────────────────────────────────────────────────────────────

class _ModelStatusChip extends StatelessWidget {
  final ModelState modelState;
  const _ModelStatusChip({required this.modelState});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (modelState) {
      ModelState.ready    => ('தயார்',   Colors.greenAccent),
      ModelState.loading  => ('ஏற்றுகிறது…', Colors.orangeAccent),
      ModelState.notFound => ('மாதிரி இல்லை', Colors.redAccent),
      ModelState.error    => ('பிழை',    Colors.redAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Model banner ─────────────────────────────────────────────────────────────

class _ModelBanner extends ConsumerWidget {
  final ModelState modelState;
  const _ModelBanner({required this.modelState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isError = modelState == ModelState.error;
    return MaterialBanner(
      backgroundColor: isError ? cs.errorContainer : cs.tertiaryContainer,
      leading: Icon(
          isError ? Icons.error_outline : Icons.folder_off_outlined),
      content: Text(
        isError
            ? 'மாதிரி ஏற்றுவதில் தோல்வி. '
              'Try /Android/data/com.example.nunarivu_ai/files/models/'
            : 'Push model to /Android/data/com.example.nunarivu_ai/files/models/',
        style: const TextStyle(fontSize: 11, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              ref.read(modelServiceProvider.notifier).tryAutoLoad(),
          child: const Text('மீண்டும் / RETRY'),
        ),
      ],
    );
  }
}

// ─── Welcome view ─────────────────────────────────────────────────────────────

class _WelcomeView extends ConsumerWidget {
  const _WelcomeView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, size: 72, color: cs.primary)
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 16),
            Text(
              profile != null ? 'வணக்கம் ${profile.name}!' : 'வணக்கம்!',
              style: GoogleFonts.notoSansTamil(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ).animate().fadeIn(delay: 150.ms),
            const SizedBox(height: 4),
            Text(
              profile != null ? 'Hello ${profile.name}!' : 'Hello!',
              style: GoogleFonts.notoSansTamil(
                  fontSize: 14, color: cs.onSurfaceVariant),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 12),
            Text(
              'தமிழ் அல்லது English-ல் கேளுங்கள்.\n'
              'Ask me anything in Tamil or English.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTamil(
                  fontSize: 13, color: cs.onSurfaceVariant, height: 1.6),
            ).animate().fadeIn(delay: 300.ms),
          ],
        ),
      ),
    );
  }
}

// ─── Message bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends ConsumerWidget {
  final ChatMessage message;
  final VoidCallback? onMoreExamples;
  final VoidCallback? onExtraHelp;
  final VoidCallback? onInEnglish;
  final VoidCallback? onInTamil;

  const _MessageBubble({
    required this.message,
    this.onMoreExamples,
    this.onExtraHelp,
    this.onInEnglish,
    this.onInTamil,
  });

  bool get _hasActionButtons =>
      onMoreExamples != null || onExtraHelp != null ||
      onInEnglish != null || onInTamil != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            constraints:
                BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: isUser ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.imagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(message.imagePath!),
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SelectableText(
                  message.text,
                  style: GoogleFonts.notoSansTamil(
                    color: isUser ? cs.onPrimary : cs.onSurface,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // ── Action row below AI messages ──────────────────────────────
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Listen + Copy
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SpeakButton(text: message.text),
                      _CopyButton(text: message.text),
                    ],
                  ),
                  // Feedback + language buttons
                  if (_hasActionButtons)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (onMoreExamples != null)
                          _FeedbackButton(
                            tamilLabel: 'மேலும் உதாரணம்',
                            englishLabel: 'More examples',
                            icon: Icons.lightbulb_outline,
                            onTap: onMoreExamples!,
                            color: Colors.amber,
                          ),
                        if (onExtraHelp != null)
                          _FeedbackButton(
                            tamilLabel: 'மேலும் விளக்கவும்',
                            englishLabel: 'Explain more',
                            icon: Icons.help_outline,
                            onTap: onExtraHelp!,
                            color: Colors.blue,
                          ),
                        if (onInEnglish != null)
                          _FeedbackButton(
                            tamilLabel: 'ஆங்கிலத்தில்',
                            englishLabel: 'In English',
                            icon: Icons.translate_rounded,
                            onTap: onInEnglish!,
                            color: Colors.green,
                          ),
                        if (onInTamil != null)
                          _FeedbackButton(
                            tamilLabel: 'தமிழில்',
                            englishLabel: 'In Tamil',
                            icon: Icons.translate_rounded,
                            onTap: onInTamil!,
                            color: Colors.deepPurple,
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Speak button ─────────────────────────────────────────────────────────────

class _SpeakButton extends ConsumerStatefulWidget {
  final String text;
  const _SpeakButton({required this.text});

  @override
  ConsumerState<_SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends ConsumerState<_SpeakButton> {
  bool _speaking = false;
  StreamSubscription<void>? _completionSub;

  @override
  void dispose() {
    _completionSub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final tts = ref.read(ttsServiceProvider);
    if (_speaking) {
      await tts.stop();
      _completionSub?.cancel();
      _completionSub = null;
      if (mounted) setState(() => _speaking = false);
    } else {
      setState(() => _speaking = true);
      _completionSub?.cancel();
      _completionSub = tts.onComplete.listen((_) {
        if (mounted) setState(() => _speaking = false);
      });
      tts.speak(_cleanForTts(widget.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _speaking ? Icons.stop_circle : Icons.volume_up_outlined,
        size: 20,
        color: _speaking ? cs.error : cs.onSurfaceVariant,
      ),
      tooltip: _speaking ? 'நிறுத்து / Stop' : 'கேளு / Listen',
      onPressed: _toggle,
    );
  }
}

// ─── Copy button ─────────────────────────────────────────────────────────────

class _CopyButton extends StatelessWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.copy_outlined,
          size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      tooltip: 'நகல் / Copy',
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('நகல் எடுக்கப்பட்டது / Copied!'),
          duration: Duration(seconds: 1),
        ));
      },
    );
  }
}

// ─── Feedback action button ───────────────────────────────────────────────────

class _FeedbackButton extends StatelessWidget {
  final String tamilLabel;
  final String englishLabel;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _FeedbackButton({
    required this.tamilLabel,
    required this.englishLabel,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tamilLabel,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                Text(englishLabel,
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 9, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Streaming bubble ─────────────────────────────────────────────────────────

class _StreamingBubble extends StatelessWidget {
  final String text;
  const _StreamingBubble({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: text.isEmpty
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                _AnimatedDot(delay: 0,   color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                _AnimatedDot(delay: 180, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                _AnimatedDot(delay: 360, color: cs.onSurfaceVariant),
              ])
            : Text(text,
                style: GoogleFonts.notoSansTamil(
                    color: cs.onSurface, fontSize: 15, height: 1.5)),
      ),
    );
  }
}

// ─── Animated dot ─────────────────────────────────────────────────────────────

class _AnimatedDot extends StatefulWidget {
  final int delay;
  final Color color;
  const _AnimatedDot({required this.delay, required this.color});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
    Future.delayed(Duration(milliseconds: widget.delay),
        () { if (mounted) _ctrl.repeat(reverse: true); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8, height: 8,
        decoration:
            BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─── Context-full banner ──────────────────────────────────────────────────────

class _ContextFullBanner extends StatelessWidget {
  final VoidCallback onNewChat;
  const _ContextFullBanner({required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('இந்த அரட்டை நீண்டுவிட்டது',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                Text('Chat is long — start a new chat for better replies',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onNewChat,
            icon: const Icon(Icons.edit_note_rounded, size: 14),
            label: Text('புதிய அரட்டை',
                style: GoogleFonts.notoSansTamil(fontSize: 11)),
            style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          ),
        ],
      ),
    );
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isListening;
  final bool canSend;
  final bool isStreaming;
  final VoidCallback onMicPressed;
  final VoidCallback onSendPressed;
  final VoidCallback? onStopPressed;

  const _InputBar({
    required this.controller,
    required this.isListening,
    required this.canSend,
    required this.isStreaming,
    required this.onMicPressed,
    required this.onSendPressed,
    this.onStopPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: cs.surface,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: GoogleFonts.notoSansTamil(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'தமிழ் அல்லது English-ல் கேளுங்கள்…',
                  hintStyle: GoogleFonts.notoSansTamil(
                      color: cs.onSurfaceVariant, fontSize: 13),
                ),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
            ),
            // Mic button — disabled while model is streaming
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isListening
                  ? IconButton(
                      key: const ValueKey('mic_stop'),
                      icon: Icon(Icons.stop_circle, color: cs.error),
                      onPressed: isStreaming ? null : onMicPressed,
                    )
                  : IconButton(
                      key: const ValueKey('mic'),
                      icon: Icon(Icons.mic_none,
                          color: isStreaming
                              ? cs.onSurfaceVariant
                              : cs.primary),
                      onPressed: isStreaming ? null : onMicPressed,
                      tooltip: 'தமிழில் பேசு / Speak',
                    ),
            ),
            // Send OR Stop generation
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isStreaming
                  ? IconButton(
                      key: const ValueKey('stop_gen'),
                      icon: Icon(Icons.stop_circle_rounded,
                          color: cs.error, size: 28),
                      tooltip: 'நிறுத்து / Stop',
                      onPressed: onStopPressed,
                    )
                  : IconButton(
                      key: const ValueKey('send'),
                      icon: const Icon(Icons.send_rounded),
                      color: canSend ? cs.primary : cs.onSurfaceVariant,
                      onPressed: canSend ? onSendPressed : null,
                      tooltip: 'அனுப்பு / Send',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chat history sheet ───────────────────────────────────────────────────────

class _ChatHistorySheet extends ConsumerStatefulWidget {
  final void Function(String chatId) onSessionSelected;
  const _ChatHistorySheet({required this.onSessionSelected});

  @override
  ConsumerState<_ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends ConsumerState<_ChatHistorySheet> {
  List<ChatSession>? _sessions;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) { setState(() => _loading = false); return; }
    final sessions = await ref
        .read(chatSessionServiceProvider)
        .loadForProfile(profile.id);
    if (mounted) setState(() { _sessions = sessions; _loading = false; });
  }

  Future<void> _delete(ChatSession s) async {
    await ref.read(chatSessionServiceProvider).delete(s.id);
    setState(() => _sessions?.remove(s));
  }

  Future<void> _rename(ChatSession s) async {
    final ctrl = TextEditingController(text: s.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('பெயர் மாற்று · Rename',
            style: GoogleFonts.notoSansTamil()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.notoSansTamil(),
          decoration:
              const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ரத்து · Cancel',
                style: GoogleFonts.notoSansTamil()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('சேமி · Save',
                style: GoogleFonts.notoSansTamil()),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newTitle != null &&
        newTitle.isNotEmpty &&
        newTitle != s.title) {
      await ref.read(chatSessionServiceProvider).rename(s.id, newTitle);
      setState(() {
        final idx =
            _sessions?.indexWhere((e) => e.id == s.id) ?? -1;
        if (idx >= 0) {
          _sessions![idx] = ChatSession(
            id: s.id,
            profileId: s.profileId,
            title: newTitle,
            createdAt: s.createdAt,
          );
        }
      });
    }
  }

  String _fmt(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) {
      return 'இன்று ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'நேற்று / Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('அரட்டை வரலாறு',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('Chat History',
                    style: GoogleFonts.notoSansTamil(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_sessions == null || _sessions!.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('அரட்டை வரலாறு இல்லை',
                                style: GoogleFonts.notoSansTamil(
                                    color: cs.onSurfaceVariant)),
                            Text('No chat history yet.',
                                style: GoogleFonts.notoSansTamil(
                                    color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: _sessions!.length,
                        itemBuilder: (_, i) {
                          final s = _sessions![i];
                          return Dismissible(
                            key: Key(s.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: cs.errorContainer,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: Icon(Icons.delete_outline,
                                  color: cs.onErrorContainer),
                            ),
                            onDismissed: (_) => _delete(s),
                            child: ListTile(
                              leading: const Icon(Icons.chat_bubble_outline),
                              title: Text(s.title,
                                  style:
                                      GoogleFonts.notoSansTamil(fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(_fmt(s.createdAt),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    tooltip: 'பெயர் மாற்று · Rename',
                                    onPressed: () => _rename(s),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 18,
                                        color: cs.error),
                                    tooltip: 'நீக்கு · Delete',
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(
                                              'நீக்கவா? · Delete?',
                                              style: GoogleFonts
                                                  .notoSansTamil()),
                                          content: Text(
                                              'This chat and all its messages will be deleted.',
                                              style: GoogleFonts
                                                  .notoSansTamil()),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                      ctx, false),
                                              child: Text(
                                                  'ரத்து · Cancel',
                                                  style: GoogleFonts
                                                      .notoSansTamil()),
                                            ),
                                            FilledButton(
                                              style:
                                                  FilledButton.styleFrom(
                                                      backgroundColor:
                                                          cs.error),
                                              onPressed: () =>
                                                  Navigator.pop(
                                                      ctx, true),
                                              child: Text(
                                                  'நீக்கு · Delete',
                                                  style: GoogleFonts
                                                      .notoSansTamil()),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) _delete(s);
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onSessionSelected(s.id);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
