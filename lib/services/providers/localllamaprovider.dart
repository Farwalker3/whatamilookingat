import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';

class LocalLlamaProvider extends AIProvider with RateLimitTracker {
  static const String defaultModelFileName = 'llama-3.2-1b-instruct-q4_k_m.gguf';

  final String modelFileName;
  final String? modelPathOverride;

  Llama? _llama;
  Future<void>? _loadFuture;
  String? _resolvedModelPath;

  LocalLlamaProvider({
    this.modelFileName = defaultModelFileName,
    this.modelPathOverride,
  });

  @override
  String get name => 'Local Llama 3.2 1B';

  @override
  bool get isAvailable => !isCoolingDown;

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
        throw StateError('Local Llama model is not ready.');
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
    final modelPath = await _findModelPath();
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

  Future<String?> _findModelPath() async {
    final overridePath = modelPathOverride?.trim();
    if (overridePath != null && overridePath.isNotEmpty) {
      final file = File(overridePath);
      if (await file.exists()) return file.path;
    }

    final directories = <Directory>[];
    try {
      directories.add(await getApplicationSupportDirectory());
    } catch (_) {}
    try {
      directories.add(await getApplicationDocumentsDirectory());
    } catch (_) {}

    final candidateNames = <String>[
      modelFileName,
      'models/$modelFileName',
      'llm/$modelFileName',
    ];

    for (final directory in directories) {
      for (final candidate in candidateNames) {
        final file = File('${directory.path}${Platform.pathSeparator}$candidate');
        if (await file.exists()) {
          return file.path;
        }
      }
    }

    return null;
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
    if (error is FileSystemException) return true;

    final text = error.toString();
    return text.contains('429') ||
        text.contains('RESOURCE_EXHAUSTED') ||
        text.contains('timed out') ||
        text.contains('Context full') ||
        text.contains('Failed to eval') ||
        text.contains('loading') ||
        text.contains('not found');
  }
}
