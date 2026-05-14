import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final _tts = FlutterTts();
  bool _initialized = false;

  // Fires once each time TTS finishes speaking a piece of text naturally.
  final _completeCtrl = StreamController<void>.broadcast();
  Stream<void> get onComplete => _completeCtrl.stream;

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5); // Slightly slower — clearer for students
    _tts.setCompletionHandler(() => _completeCtrl.add(null));
    _initialized = true;
  }

  /// Speak [text]. Detects Tamil Unicode and picks the right locale automatically.
  /// Does NOT await completion — returns as soon as TTS has been enqueued.
  /// Listen to [onComplete] to know when speaking finishes naturally.
  Future<void> speak(String text) async {
    await _init();
    await _tts.stop();

    // If text contains Tamil characters (U+0B80–U+0BFF), use Tamil locale
    final hasTamil = text.runes.any((r) => r >= 0x0B80 && r <= 0x0BFF);
    await _tts.setLanguage(hasTamil ? 'ta-IN' : 'en-US');

    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  Future<bool> isTamilAvailable() async {
    final langs = await _tts.getLanguages as List?;
    return langs?.any((l) => l.toString().startsWith('ta')) ?? false;
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) => TtsService());
