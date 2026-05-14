import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SttService {
  final _stt = SpeechToText();
  bool _initialized = false;

  Future<bool> init() async {
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onError: (error) => print('STT error: ${error.errorMsg}'),
      onStatus: (status) => print('STT status: $status'),
    );
    return _initialized;
  }

  Future<void> startListening({
    required void Function(String text, {required bool isFinal}) onResult,
    String locale = 'ta-IN',
  }) async {
    if (!_initialized) await init();
    await _stt.listen(
      onResult: (result) {
        onResult(result.recognizedWords, isFinal: result.finalResult);
      },
      localeId: locale,
      listenMode: ListenMode.dictation,
      // Keep listening for up to 3 minutes total.
      listenFor: const Duration(minutes: 3),
      // Only stop after 10 seconds of silence (default is ~2 s on Android).
      pauseFor: const Duration(seconds: 10),
    );
  }

  Future<void> stopListening() => _stt.stop();

  bool get isListening => _stt.isListening;
  bool get isAvailable => _initialized;
}

final sttServiceProvider = Provider<SttService>((ref) => SttService());
