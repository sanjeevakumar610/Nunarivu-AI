import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

// ── Service ────────────────────────────────────────────────────────────────────

/// Speech-to-text using Google's on-device/cloud recogniser.
/// Requires internet. Works for Tamil (ta-IN) with no additional setup —
/// just install the APK and the mic button works immediately.
class SttService {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _listening   = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Initialise the speech recogniser. Returns true when ready.
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      _initialized = await _stt.initialize(
        onError:  (e) => debugPrint('SttService error: $e'),
        onStatus: (s) => debugPrint('SttService status: $s'),
      );
    } catch (e) {
      debugPrint('SttService init failed: $e');
      _initialized = false;
    }
    return _initialized;
  }

  /// Start listening. Results delivered to [onResult].
  /// Uses Google Speech Recognition — internet required.
  Future<void> startListening({
    required void Function(String text, {required bool isFinal}) onResult,
    String locale = 'ta-IN',
  }) async {
    if (!_initialized) await init();

    if (!_initialized || !_stt.isAvailable) {
      onResult(
        'இணைய இணைப்பு இல்லை அல்லது குரல் அங்கீகாரம் கிடைக்கவில்லை.\n'
        'No internet or speech recognition unavailable.',
        isFinal: true,
      );
      return;
    }

    try {
      await _stt.listen(
        onResult: (result) {
          onResult(result.recognizedWords, isFinal: result.finalResult);
          if (result.finalResult) _listening = false;
        },
        localeId:   locale,
        pauseFor:   const Duration(seconds: 10),
        listenMode: ListenMode.confirmation,
      );
      _listening = true;
    } catch (e) {
      _listening = false;
      onResult('குரல் அங்கீகாரத்தில் பிழை / STT error: $e', isFinal: true);
    }
  }

  Future<void> stopListening() async {
    _listening = false;
    try { await _stt.stop(); } catch (_) {}
  }

  bool get isListening => _listening;
  bool get isAvailable => _initialized && _stt.isAvailable;
}

final sttServiceProvider = Provider<SttService>((ref) => SttService());
