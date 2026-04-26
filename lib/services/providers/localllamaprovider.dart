import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';

class LocalLlamaProvider extends AIProvider with RateLimitTracker {
  static const String defaultModelFileName = 'Llama-3.2-1B-Instruct-Q4KM.gguf';
  static const String legacyModelFileName = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';
  static const String modelDownloadUrl =
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  final String modelFileName;
  final String? modelPathOverride;

  Llama? _llama;
  Future<void>? _loadFuture;
  Future<String?>? _downloadFuture;
  String? _resolvedModelPath;

  LocalLlamaProvider({
    this.modelFileName = defaultModelFileName,
    this.modelPathOverride,
  });

  @override
  String get name => 'Local Llama 3.2 1B';

  @override
  bool get isAvailable => !isCoolingDown && !isPreparingModel;

  bool get isDownloadingModel => _downloadFuture != null;

  bool get isPreparingModel => _loadFuture != null || _downloadFuture != null;

  String? get resolvedModelPath => _resolvedModelPath;

  @override
  Future<List<Explanation>> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
  }) async {
    if (isCoolingDown) {
      throw StateError('Local Llama provider is cooling down.');
    }

    try {
      await _ensureLoaded();
      final llama = _llama;
      if (llama == null) {
        markRateLimited();
        debugPrint('[AI] Local Llama model is not ready, falling back to cloud providers.');
        return const [];
      }

      llama.clear();
      final prompt = _buildPrompt(context);
      llama.setPrompt(prompt);
      final text = await llama.generateCompleteText(maxTokens: 384);
      final explanations = _parseExplanationResponse(text);

      resetCooldown();
      return explanations.isNotEmpty ? explanations : _fallbackExplanations(context, text);
    } catch (e) {
      if (_looksTransient(e)) {
        markRateLimited();
        debugPrint('[AI] Local Llama unavailable, falling back to cloud providers: $e');
        return const [];
      }
      rethrow;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_llama != null) return;
    final pending = _loadFuture;
    if (pending != null) {
      await pending;
      return;
    }

    _loadFuture = _loadModel();
    try {
      await _loadFuture;
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> _loadModel() async {
    final modelPath = await _ensureModelPath();
    print('[LocalLlamaProvider] _loadModel() resolved modelPath=' + (modelPath ?? '<null>'));
    if (modelPath == null) {
      throw FileSystemException(
        'Local GGUF model not found in app storage',
        modelFileName,
      );
    }

    final threadCount = math.max(2, Platform.numberOfProcessors - 1);
    final modelParams = ModelParams()
      ..nGpuLayers = 0
      ..useMemorymap = true
      ..useMemoryLock = false;

    final contextParams = ContextParams()
      ..nCtx = 2048
      ..nBatch = 256
      ..nUbatch = 256
      ..nThreads = threadCount
      ..nThreadsBatch = threadCount
      ..nPredict = 384;

    _llama?.dispose();
    _llama = Llama(
      modelPath,
      modelParams: modelParams,
      contextParams: contextParams,
      samplerParams: SamplerParams(),
      verbose: false,
    );
    _resolvedModelPath = modelPath;

    debugPrint('[AI] Loaded local llama model from $modelPath');
  }

  Future<String?> _ensureModelPath() async {
    final overridePath = modelPathOverride?.trim();
    if (overridePath != null && overridePath.isNotEmpty) {
      final file = File(overridePath);
      final exists = file.existsSync();
      print('[LocalLlamaProvider] checking override model path: ' + file.path + ' existsSync=' + exists.toString());
      if (exists) return file.path;
    }

    final existingPath = await _findExistingModelPath();
    if (existingPath != null) {
      return existingPath;
    }

    return await _downloadModelIfNeeded();
  }

  Future<String?> _findExistingModelPath() async {
    final directories = <Directory>[];
    try {
      directories.add(await getApplicationDocumentsDirectory());
    } catch (_) {}
    try {
      directories.add(await getApplicationSupportDirectory());
    } catch (_) {}
    try {
      directories.add(await getTemporaryDirectory());
    } catch (_) {}

    final candidateNames = <String>{
      modelFileName,
      legacyModelFileName,
      modelFileName.toLowerCase(),
      legacyModelFileName.toLowerCase(),
    }.toList();

    final candidatePrefixes = <String>['', 'models', 'llm'];

    for (final directory in directories) {
      for (final candidateName in candidateNames) {
        for (final prefix in candidatePrefixes) {
          final candidatePath = prefix.isEmpty
              ? '${directory.path}${Platform.pathSeparator}$candidateName'
              : '${directory.path}${Platform.pathSeparator}$prefix${Platform.pathSeparator}$candidateName';
          final file = File(candidatePath);
          final exists = file.existsSync();
          print('[LocalLlamaProvider] checking candidate GGUF path: ' + candidatePath + ' existsSync=' + exists.toString());
          if (exists) {
            return file.path;
          }
        }
      }
    }

    print('[LocalLlamaProvider] no existing GGUF model path found after checking override and local candidates');
    return null;
  }

  Future<String?> _downloadModelIfNeeded() async {
    final pending = _downloadFuture;
    if (pending != null) {
      return await pending;
    }

    _downloadFuture = _downloadModel();
    try {
      return await _downloadFuture;
    } finally {
      _downloadFuture = null;
    }
  }

  Future<String?> _downloadModel() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final targetFile = File(
      '${documentsDirectory.path}${Platform.pathSeparator}$modelFileName',
    );
    print('[LocalLlamaProvider] checking download target GGUF path: ' + targetFile.path + ' existsSync=' + targetFile.existsSync().toString());

    if (targetFile.existsSync() && await targetFile.length() > 0) {
      _resolvedModelPath = targetFile.path;
      return targetFile.path;
    }

    final tempFile = File('${targetFile.path}.part');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = http.Client();
    try {
      debugPrint('[AI] Downloading local llama model to ${targetFile.path}');
      final response = await client.send(
        http.Request('GET', Uri.parse(modelDownloadUrl)),
      );

      if (response.statusCode != HttpStatus.ok) {
        await response.stream.drain();
        throw HttpException(
          'Failed to download local model (${response.statusCode})',
          uri: Uri.parse(modelDownloadUrl),
        );
      }

      final sink = tempFile.openWrite();
      try {
        await sink.addStream(response.stream);
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      _resolvedModelPath = targetFile.path;
      debugPrint('[AI] Downloaded local llama model to ${targetFile.path}');
      return targetFile.path;
    } finally {
      client.close();
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  String _buildPrompt(DeviceContext context) {
    return '''You are a compact on-device scene analyst running inside a Flutter app.
Use only the provided context. Do not invent text, brands, or objects that are not supported by the context.
If the scene is ambiguous, say so plainly.

Return ONLY a JSON array of 3 to 5 objects with these keys:
headline, summary, details, sources, category, confidence

Valid categories: landmark, event, sign, object, person, nature, vehicle, text, scene, product

Device context:
${context.toPromptText()}

Task:
Write concise, practical explanations of what the user is likely looking at based on the available context.
''';
  }

  List<Explanation> _parseExplanationResponse(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];

    final jsonCandidate = _extractJsonCandidate(cleaned);
    if (jsonCandidate == null) return const [];

    try {
      final decoded = jsonDecode(jsonCandidate);
      final List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map && decoded['explanations'] is List) {
        items = decoded['explanations'] as List<dynamic>;
      } else {
        return const [];
      }

      return items
          .whereType<Map>()
          .map((item) => Explanation.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String? _extractJsonCandidate(String text) {
    final cleaned = text
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    final arrayMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(cleaned);
    if (arrayMatch != null) return arrayMatch.group(0);

    final objectMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(cleaned);
    return objectMatch?.group(0);
  }

  List<Explanation> _fallbackExplanations(DeviceContext context, String rawText) {
    final trimmed = rawText.trim();
    final summary = trimmed.isEmpty
        ? 'Local analysis completed, but the model returned no structured output.'
        : (trimmed.length > 220 ? '${trimmed.substring(0, 220)}...' : trimmed);

    return [
      Explanation(
        headline: context.placeName ?? 'Local scene analysis',
        summary: summary,
        details: trimmed.isEmpty
            ? 'The local model did not return a JSON array, so this fallback explanation was generated from the current device context.'
            : trimmed,
        sources: const ['camera', 'location', 'time'],
        category: 'scene',
        confidence: 0.45,
      ),
    ];
  }

  bool _looksTransient(Object error) {
    if (error is FileSystemException || error is SocketException || error is HttpException) {
      return true;
    }

    if (error is http.ClientException) return true;

    final text = error.toString();
    return text.contains('429') ||
        text.contains('RESOURCE_EXHAUSTED') ||
        text.contains('timed out') ||
        text.contains('Context full') ||
        text.contains('Failed to eval') ||
        text.contains('loading') ||
        text.contains('not found') ||
        text.contains('No such file or directory') ||
        text.contains('Unable to open') ||
        text.contains('could not open') ||
        text.contains('download');
  }
}
