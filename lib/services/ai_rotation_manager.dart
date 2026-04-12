import 'dart:typed_data';
import '../models/device_context.dart';
import '../models/explanation.dart';
import 'ai_provider.dart';
import 'providers/gemini_provider.dart';
import 'providers/groq_provider.dart';
import 'providers/openrouter_provider.dart';
import 'providers/offline_provider.dart';

/// Manages rotation between AI providers with automatic failover.
class AIRotationManager {
  final List<AIProvider> _providers = [];
  final OfflineProvider _offlineProvider = OfflineProvider();
  int _currentIndex = 0;
  String _lastUsedProvider = '';

  String get lastUsedProvider => _lastUsedProvider;

  void initialize({
    required String geminiKey,
    required String groqKey,
    required String openRouterKey,
  }) {
    _providers.clear();
    
    // Clean keys (strip quotes if user added them)
    final gKey = geminiKey.trim().replaceAll("'", "").replaceAll('"', "");
    final grKey = groqKey.trim().replaceAll("'", "").replaceAll('"', "");
    final orKey = openRouterKey.trim().replaceAll("'", "").replaceAll('"', "");

    // Priority order: Groq (fastest) → Gemini (best quality) → OpenRouter (backup)
    if (grKey.isNotEmpty) {
      _providers.add(GroqProvider(apiKey: grKey));
    }
    if (gKey.isNotEmpty) {
      _providers.add(GeminiProvider(apiKey: gKey));
    }
    if (orKey.isNotEmpty) {
      _providers.add(OpenRouterProvider(apiKey: orKey));
    }
  }

  bool get hasOnlineProviders =>
      _providers.any((p) => p.isAvailable);

  /// Analyze image with automatic provider rotation and failover.
  Future<(List<Explanation>, String)> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
    bool isOffline = false,
  }) async {
    if (isOffline || _providers.isEmpty) {
      final results = await _offlineProvider.analyzeImage(
        imageBytes: imageBytes,
        context: context,
      );
      _lastUsedProvider = _offlineProvider.name;
      return (results, _offlineProvider.name);
    }

    // Try each provider in rotation until one succeeds
    final startIndex = _currentIndex % _providers.length;
    for (int i = 0; i < _providers.length; i++) {
      final index = (startIndex + i) % _providers.length;
      final provider = _providers[index];

      if (!provider.isAvailable) continue;

      try {
        final results = await provider.analyzeImage(
          imageBytes: imageBytes,
          context: context,
        );

        if (results.isNotEmpty) {
          // Rotate to next provider for the next call (spread load)
          _currentIndex = (index + 1) % _providers.length;
          _lastUsedProvider = provider.name;
          return (results, provider.name);
        }
      } catch (_) {
        // Provider failed, try next
        continue;
      }
    }

    // All online providers failed, use offline fallback
    final results = await _offlineProvider.analyzeImage(
      imageBytes: imageBytes,
      context: context,
    );
    _lastUsedProvider = _offlineProvider.name;
    return (results, _offlineProvider.name);
  }
}
