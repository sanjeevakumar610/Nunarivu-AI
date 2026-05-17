import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

// ── Model paths ────────────────────────────────────────────────────────────────

/// 1. Pen-drive copy location (manual install via Advanced Settings)
Future<String> _voskModelPath() async {
  final ext = await getExternalStorageDirectory();
  final base = ext?.path ?? '/data/data/com.example.nunarivu_ai/files';
  return '$base/models/vosk-model-ta';
}

/// 2. Asset-extracted location (auto-bundled in APK if zip is present)
Future<String> _docsVoskPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return '${docs.path}/models/vosk-model-small-ta-0.4';
}

Future<String> _docsModelsDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return '${docs.path}/models';
}

/// Finds the best available Vosk model directory, or null if not installed.
/// Search order:
///   1. External storage (pen-drive copy)
///   2. App documents (previously extracted from APK assets)
///   3. APK assets (extracts vosk-model-small-ta-0.4.zip on first run)
Future<String?> _findOrExtractVoskModel() async {
  // 1. Pen-drive copy
  final extPath = await _voskModelPath();
  if (Directory(extPath).existsSync()) return extPath;

  // 2. Previously extracted from assets
  final docsPath = await _docsVoskPath();
  if (Directory(docsPath).existsSync()) return docsPath;

  // 3. Extract from bundled assets (vosk-model-small-ta-0.4.zip)
  //    The zip file must be declared in pubspec.yaml:
  //      assets:
  //        - assets/vosk-model-small-ta-0.4.zip
  //    Download from: https://alphacephei.com/vosk/models
  try {
    final modelsDir = await _docsModelsDir();
    final loader = ModelLoader(modelStorage: modelsDir);
    // Checks if already loaded before re-extracting
    final extractedPath = await loader.loadFromAssets(
        'assets/vosk-model-small-ta-0.4.zip');
    if (Directory(extractedPath).existsSync()) return extractedPath;
  } catch (_) {
    // Asset not bundled — that's OK, user can copy manually
  }

  return null; // No model found anywhere
}

/// True when any Vosk model is available on this device.
final voskModelReadyProvider = FutureProvider<bool>((ref) async {
  final path = await _findOrExtractVoskModel();
  return path != null;
});

// ── Service ────────────────────────────────────────────────────────────────────

class SttService {
  bool _initialized = false;
  bool _listening   = false;
  String? _activeModelDir;

  Model?         _model;
  Recognizer?    _recognizer;
  SpeechService? _speechService;

  StreamSubscription<String>? _resultSub;
  StreamSubscription<String>? _partialSub;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Initialises Vosk. Returns true even when the model is absent so the
  /// caller does not show the generic "Speech recognition unavailable" snackbar.
  Future<bool> init() async {
    if (_initialized) return true;

    final modelDir = await _findOrExtractVoskModel();
    if (modelDir == null) {
      // No model anywhere — error surfaces via onResult in startListening
      return true;
    }

    try {
      final plugin = VoskFlutterPlugin.instance();
      _model       = await plugin.createModel(modelDir);
      _recognizer  = await plugin.createRecognizer(
          model: _model!, sampleRate: 16000);
      _activeModelDir = modelDir;
      _initialized    = true;
    } catch (e) {
      print('SttService: Vosk init failed: $e');
    }
    return true;
  }

  /// Start listening. Results delivered to [onResult].
  Future<void> startListening({
    required void Function(String text, {required bool isFinal}) onResult,
    String locale = 'ta-IN',
  }) async {
    final modelDir = await _findOrExtractVoskModel();

    if (modelDir == null) {
      onResult(
        'குரல் மாதிரி இல்லை / Voice model not installed.\n'
        'Settings → Advanced → Copy Voice Model from pen drive, '
        'or bundle vosk-model-small-ta-0.4.zip in APK assets.',
        isFinal: true,
      );
      return;
    }

    if (!_initialized) await init();

    if (!_initialized) {
      onResult(
        'குரல் அங்கீகாரம் தொடங்கவில்லை / STT init failed — '
        'restart the app and try again.',
        isFinal: true,
      );
      return;
    }

    try {
      final plugin   = VoskFlutterPlugin.instance();
      _speechService = await plugin.initSpeechService(_recognizer!);

      _partialSub?.cancel();
      _partialSub = _speechService!.onPartial().listen((jsonStr) {
        final text = _extract(jsonStr, 'partial');
        if (text.isNotEmpty) onResult(text, isFinal: false);
      });

      _resultSub?.cancel();
      _resultSub = _speechService!.onResult().listen(
        (jsonStr) {
          final text = _extract(jsonStr, 'text');
          onResult(text, isFinal: true);
          _listening = false;
        },
        onError: (_) => _listening = false,
        onDone:  () => _listening = false,
      );

      await _speechService!.start();
      _listening = true;
    } catch (e) {
      _listening = false;
      onResult('குரல் அங்கீகாரத்தில் பிழை / STT error: $e', isFinal: true);
    }
  }

  Future<void> stopListening() async {
    _partialSub?.cancel(); _partialSub = null;
    _resultSub?.cancel();  _resultSub  = null;
    _listening = false;
    try { await _speechService?.stop(); } catch (_) {}
  }

  /// Re-initialise Vosk after a new model is copied from the pen drive.
  Future<void> reinitVosk() async {
    await stopListening();
    try { await _speechService?.dispose(); } catch (_) {}
    _speechService  = null;
    _recognizer     = null;
    _model          = null;
    _activeModelDir = null;
    _initialized    = false;
    await init();
  }

  bool get isListening => _listening;
  bool get isAvailable => _initialized;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _extract(String jsonStr, String key) {
    final marker = '"$key":"';
    final start  = jsonStr.indexOf(marker);
    if (start == -1) return '';
    final vs  = start + marker.length;
    final end = jsonStr.indexOf('"', vs);
    if (end == -1) return '';
    return jsonStr.substring(vs, end).trim();
  }
}

final sttServiceProvider = Provider<SttService>((ref) => SttService());
