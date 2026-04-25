import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../models/device_context.dart';
import '../models/explanation.dart';
import 'ai_provider.dart';
import 'providers/offline_provider.dart';
import 'providers/proxy_visual_provider.dart';

/// Manages rotation between AI providers with automatic failover.
class AIRotationManager {
  final List<AIProvider> _providers = [];
  final OfflineProvider _offlineProvider = OfflineProvider();
  int _currentIndex = 0;
  String _lastUsedProvider = '';

  String get lastUsedProvider => _lastUsedProvider;

  void initialize({
    String proxyBaseUrl = '/api/chat',
  }) {
    _providers.clear();

    final resolvedProxyBaseUrl = proxyBaseUrl.trim().isEmpty ? '/api/chat' : proxyBaseUrl.trim();

    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'groq',
      displayName: 'Groq (Llama 4)',
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    ));
    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'gemini',
      displayName: 'Gemini Flash',
      model: 'gemini-2.5-flash',
    ));
    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'together',
      displayName: 'Together (Llama 4)',
      model: 'meta-llama/Llama-4-Scout-17B-16E-Instruct',
    ));
    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'openrouter',
      displayName: 'OpenRouter',
      model: 'google/gemini-2.5-flash',
    ));

    debugPrint('[AI] Initialized ${_providers.length} providers via proxy: $resolvedProxyBaseUrl');
  }

  bool get hasOnlineProviders => _providers.any((p) => p.isAvailable);

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
      debugPrint('[AI] Using offline provider (isOffline=$isOffline, providers=${_providers.length})');
      return (results, _offlineProvider.name);
    }

    final startIndex = _currentIndex % _providers.length;
    for (int i = 0; i < _providers.length; i++) {
      final index = (startIndex + i) % _providers.length;
      final provider = _providers[index];

      if (!provider.isAvailable) {
        debugPrint('[AI] Skipping ${provider.name} (unavailable)');
        continue;
      }

      try {
        final results = await provider.analyzeImage(
          imageBytes: imageBytes,
          context: context,
        );

        if (results.isNotEmpty) {
          _currentIndex = (index + 1) % _providers.length;
          _lastUsedProvider = provider.name;
          return (results, provider.name);
        }
      } catch (e) {
        debugPrint('[AI] Provider ${provider.name} failed: $e');
        continue;
      }
    }

    final results = await _offlineProvider.analyzeImage(
      imageBytes: imageBytes,
      context: context,
    );
    _lastUsedProvider = _offlineProvider.name;
    debugPrint('[AI] All online providers failed, falling back to offline');
    return (results, _offlineProvider.name);
  }
}
