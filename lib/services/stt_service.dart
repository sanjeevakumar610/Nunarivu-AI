import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

// ── Vosk model path ────────────────────────────────────────────────────────────

/// Canonical on-device location for the Vosk Tamil small model:
/// [getExternalStorageDirectory()]/models/vosk-model-ta/
Future<String> _voskModelPath() async {
  final ext = await getExternalStorageDirectory();
  final base = ext?.path ?? '/data/data/com.example.nunarivu_ai/files';
  return '$base/models/vosk-model-ta';
}

/// True when the vosk-model-ta directory exists on device.
/// Watched by AdvancedSettingsScreen to show ✅/❌ status.
final voskModelReadyProvider = FutureProvider<bool>((ref) async {
  final path = await _voskModelPath();
  return Directory(path).existsSync();
});

// ── Service ────────────────────────────────────────────────────────────────────

class SttService {
  bool _initialized = false;
  bool _listening = false;

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription<String>? _resultSub;
  StreamSubscription<String>? _partialSub;

  // ── Public API (identical to old speech_to_text-based API) ──────────────────

  /// Initialises Vosk. Returns true even when the model is absent so the
  /// caller (chat_screen.dart _toggleListening) does not show the generic
  /// "Speech recognition unavailable" snackbar. If the model is missing the
  /// error surfaces via onResult inside startListening with a Tamil message.
  Future<bool> init() async {
    if (_initialized) return true;
    final modelDir = await _voskModelPath();
    if (!Directory(modelDir).existsSync()) {
      // Model not yet installed — init succeeds; error shown at listen time.
      return true;
    }
    try {
      final plugin = VoskFlutterPlugin.instance();
      _model = await plugin.createModel(modelDir);
      _recognizer = await plugin.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      _initialized = true;
    } catch (e) {
      print('SttService: Vosk init failed: $e');
    }
    return true; // always true — error delivered via onResult
  }

  /// Start listening. Results delivered to [onResult].
  /// [locale] kept for API compatibility — Vosk uses the Tamil model regardless.
  Future<void> startListening({
    required void Function(String text, {required bool isFinal}) onResult,
    String locale = 'ta-IN',
  }) async {
    final modelDir = await _voskModelPath();

    if (!Directory(modelDir).existsSync()) {
      // Guide the student to Advanced Settings
      onResult(
        'குரல் மாதிரி இல்லை / Voice model not installed — '
        'open Settings → Advanced to copy from pen drive',
        isFinal: true,
      );
      return;
    }

    if (!_initialized) await init();

    if (!_initialized) {
      onResult(
        'குரல் அங்கீகாரம் தொடங்கவில்லை / STT init failed — please restart the app',
        isFinal: true,
      );
      return;
    }

    try {
      final plugin = VoskFlutterPlugin.instance();
      _speechService = await plugin.initSpeechService(_recognizer!);

      // Subscribe to partial results
      _partialSub?.cancel();
      _partialSub = _speechService!.onPartial().listen((jsonStr) {
        try {
          // Partial JSON: {"partial": "some text"}
          final text = _extractText(jsonStr, 'partial');
          if (text.isNotEmpty) onResult(text, isFinal: false);
        } catch (_) {}
      });

      // Subscribe to final results
      _resultSub?.cancel();
      _resultSub = _speechService!.onResult().listen(
        (jsonStr) {
          try {
            // Final JSON: {"text": "some text"}
            final text = _extractText(jsonStr, 'text');
            onResult(text, isFinal: true);
            _listening = false;
          } catch (_) {}
        },
        onError: (_) => _listening = false,
        onDone: () => _listening = false,
      );

      await _speechService!.start();
      _listening = true;
    } catch (e) {
      _listening = false;
      onResult(
        'குரல் அங்கீகாரத்தில் பிழை / STT error: $e',
        isFinal: true,
      );
    }
  }

  Future<void> stopListening() async {
    _partialSub?.cancel();
    _partialSub = null;
    _resultSub?.cancel();
    _resultSub = null;
    _listening = false;
    try {
      await _speechService?.stop();
    } catch (_) {}
  }

  /// Re-initialise Vosk after a new model is copied from the pen drive.
  /// Called by AdvancedSettingsScreen on successful voice model copy.
  Future<void> reinitVosk() async {
    await stopListening();
    try {
      await _speechService?.dispose();
    } catch (_) {}
    _speechService = null;
    _recognizer = null;
    _model = null;
    _initialized = false;
    await init();
  }

  bool get isListening => _listening;
  bool get isAvailable => _initialized;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _extractText(String jsonStr, String key) {
    // Simple extraction without full json.decode to stay lightweight
    final marker = '"$key":"';
    final start = jsonStr.indexOf(marker);
    if (start == -1) return '';
    final valueStart = start + marker.length;
    final end = jsonStr.indexOf('"', valueStart);
    if (end == -1) return '';
    return jsonStr.substring(valueStart, end).trim();
  }
}

final sttServiceProvider = Provider<SttService>((ref) => SttService());
