import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum ModelState { notFound, loading, ready, error }

// LiteRT-LM format — single bundled file (language model + vision encoder).
// Download from: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
const _defaultModelFile = 'gemma-4-E2B-it-litert-lm.litertlm';

/// Search order on Android (no special permissions needed for the first path):
///   1. App-specific external dir (/storage/emulated/0/Android/data/<pkg>/files/models/)
///   2. App documents dir (internal — last-resort fallback)
///   3. Legacy public path /storage/emulated/0/nunarivu/models/ (only works
///      with MANAGE_EXTERNAL_STORAGE permission)
Future<List<String>> _candidateModelDirs() async {
  final dirs = <String>[];
  try {
    final ext = await getExternalStorageDirectory();
    if (ext != null) dirs.add('${ext.path}/models');
  } catch (_) {}
  try {
    final docs = await getApplicationDocumentsDirectory();
    dirs.add('${docs.path}/models');
  } catch (_) {}
  dirs.add('/storage/emulated/0/nunarivu/models');
  return dirs;
}

class ModelServiceNotifier extends Notifier<ModelState> {
  static const _channel = MethodChannel('com.nunarivu/inference');

  // EventChannel for real-time streaming tokens.
  static const _streamChannel = EventChannel('com.nunarivu/stream');

  /// Resolved model dir from the last successful auto-load attempt. Useful
  /// for showing the user where to push files when the model is missing.
  String? _searchedDirsSummary;
  String? get searchedDirsSummary => _searchedDirsSummary;

  @override
  ModelState build() => ModelState.notFound;

  Future<void> tryAutoLoad() async {
    final dirs = await _candidateModelDirs();
    _searchedDirsSummary = dirs.join('\n');

    for (final dir in dirs) {
      final modelPath = '$dir/$_defaultModelFile';
      if (await File(modelPath).exists()) {
        await loadModel(modelPath);
        return;
      }
    }
    state = ModelState.notFound;
  }

  Future<void> loadModel(String modelPath) async {
    state = ModelState.loading;
    try {
      await _channel.invokeMethod<void>('loadModel', {
        'modelPath': modelPath,
        // mmprojPath removed: LiteRT-LM bundles vision encoder in the .litertlm file
      });
      state = ModelState.ready;
    } on PlatformException catch (e) {
      state = ModelState.error;
      throw Exception('Model load failed: ${e.message}');
    }
  }

  /// Non-streaming inference — returns the full response string.
  /// Kept for fallback / simple use-cases.
  Future<String> infer(String prompt, {String? imagePath}) async {
    if (state != ModelState.ready) throw StateError('Model not ready');
    try {
      final result = await _channel.invokeMethod<String>('infer', {
        'prompt': prompt,
        'imagePath': imagePath ?? '',
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('Inference failed: ${e.message}');
    }
  }

  /// Streaming inference — yields token chunks as they are generated.
  /// The [EventChannel] arguments trigger `onListen` in [InferencePlugin],
  /// which starts the LiteRT-LM coroutine and emits each chunk via the sink.
  Stream<String> inferStream(String prompt, {String? imagePath}) {
    if (state != ModelState.ready) {
      return Stream.error(StateError('Model not ready'));
    }
    return _streamChannel
        .receiveBroadcastStream({
          'prompt': prompt,
          'imagePath': imagePath ?? '',
        })
        .cast<String>();
  }

  /// Like [infer] but prepends a document-context block to the prompt.
  /// Used when chatting about a PDF or lesson.
  Future<String> inferWithContext({
    required String prompt,
    required String contextText,
    String? imagePath,
  }) {
    final combined =
        '''Use the following document content to answer the question.
If the answer is not in the document, say so politely.

DOCUMENT:
$contextText

QUESTION:
$prompt''';
    return infer(combined, imagePath: imagePath);
  }
}

final modelServiceProvider =
    NotifierProvider<ModelServiceNotifier, ModelState>(
  ModelServiceNotifier.new,
);
