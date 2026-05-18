import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ModelState { notFound, loading, ready, error }

// LiteRT-LM format — single bundled file (language model + vision encoder).
const _defaultModelFile = 'gemma-4-E2B-it-litert-lm.litertlm';

/// SharedPreferences key — the last path from which the model loaded successfully.
const _kLastModelPath = 'last_model_path';

/// Standard search directories for the model file.
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
  static const _channel       = MethodChannel('com.nunarivu/inference');
  static const _streamChannel = EventChannel('com.nunarivu/stream');

  String? _searchedDirsSummary;
  String? get searchedDirsSummary => _searchedDirsSummary;

  @override
  ModelState build() => ModelState.notFound;

  /// Searches all candidate directories (including the previously saved path)
  /// and loads the first model file found.
  Future<void> tryAutoLoad() async {
    final dirs = await _candidateModelDirs();

    // Check the last known-good path first (saved by loadModel after success).
    final prefs = await SharedPreferences.getInstance();
    final lastPath = prefs.getString(_kLastModelPath);
    if (lastPath != null) {
      final dir = lastPath.contains('/') ? lastPath.substring(0, lastPath.lastIndexOf('/')) : '';
      if (dir.isNotEmpty && !dirs.contains(dir)) dirs.insert(0, dir);
    }

    _searchedDirsSummary = dirs.join('\n');

    // Try lastPath directly (it is the full file path, not a dir).
    if (lastPath != null && await File(lastPath).exists()) {
      await loadModel(lastPath);
      return;
    }

    for (final dir in dirs) {
      final modelPath = '$dir/$_defaultModelFile';
      if (await File(modelPath).exists()) {
        await loadModel(modelPath);
        return;
      }
    }
    state = ModelState.notFound;
  }

  /// Loads the model at [modelPath] and saves the path so [tryAutoLoad]
  /// can find it on the next app launch without needing to browse again.
  Future<void> loadModel(String modelPath) async {
    state = ModelState.loading;
    try {
      await _channel.invokeMethod<void>('loadModel', {'modelPath': modelPath});
      state = ModelState.ready;
      // Persist for next launch.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastModelPath, modelPath);
    } on PlatformException catch (e) {
      state = ModelState.error;
      throw Exception('Model load failed: ${e.message}');
    }
  }

  /// Non-streaming inference — returns the full response string.
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
  Stream<String> inferStream(String prompt, {String? imagePath}) {
    if (state != ModelState.ready) {
      return Stream.error(StateError('Model not ready'));
    }
    return _streamChannel
        .receiveBroadcastStream({'prompt': prompt, 'imagePath': imagePath ?? ''})
        .cast<String>();
  }

  /// Like [infer] but prepends a document-context block to the prompt.
  Future<String> inferWithContext({
    required String prompt,
    required String contextText,
    String? imagePath,
  }) {
    final combined =
        'Use the following document content to answer the question.\n'
        'If the answer is not in the document, say so politely.\n\n'
        'DOCUMENT:\n$contextText\n\nQUESTION:\n$prompt';
    return infer(combined, imagePath: imagePath);
  }
}

final modelServiceProvider =
    NotifierProvider<ModelServiceNotifier, ModelState>(
  ModelServiceNotifier.new,
);
