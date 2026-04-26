import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../models/device_context.dart';
import '../models/explanation.dart';
import 'ai_provider.dart';
import 'providers/localllamaprovider.dart';
import 'providers/offline_provider.dart';
import 'providers/proxy_visual_provider.dart';

/// Manages rotation between AI providers with automatic failover.
class AIRotationManager {
  final List<AIProvider> _providers = [];
  final OfflineProvider _offlineProvider = OfflineProvider();
  int _currentIndex = 0;
  String _lastUsedProvider = '';

  String get lastUsedProvider => _lastUsedProvider;

  String _describeProvider(AIProvider provider) {
    if (provider is LocalLlamaProvider) {
      return 'LocalLlama: modelFileName=' + provider.modelFileName +
          ', overridePath=' + (provider.modelPathOverride ?? '<none>') +
          ', resolvedPath=' + (provider.resolvedModelPath ?? '<not resolved>') +
          ', isAvailable=' + provider.isAvailable.toString() +
          ', isPreparing=' + provider.isPreparingModel.toString() +
          ', isDownloading=' + provider.isDownloadingModel.toString() +
          ', isCoolingDown=' + provider.isCoolingDown.toString();
    }

    if (provider is ProxyVisualAIProvider) {
      return provider.displayName + ': providerId=' + provider.providerId +
          ', model=' + provider.model +
          ', isAvailable=' + provider.isAvailable.toString() +
          ', isCoolingDown=' + provider.isCoolingDown.toString();
    }

    return provider.name + ': isAvailable=' + provider.isAvailable.toString() +
        ', isCoolingDown=' + provider.isCoolingDown.toString();
  }

  bool get isLocalModelDownloading =>
      _providers.whereType<LocalLlamaProvider>().any((provider) => provider.isDownloadingModel);

  bool get isLocalModelPreparing =>
      _providers.whereType<LocalLlamaProvider>().any((provider) => provider.isPreparingModel);

  void initialize({
    String proxyBaseUrl = '/api/chat',
    String localModelFileName = LocalLlamaProvider.defaultModelFileName,
    String? localModelPath,
  }) {
    _providers.clear();

    final resolvedProxyBaseUrl =
        proxyBaseUrl.trim().isEmpty ? '/api/chat' : proxyBaseUrl.trim();

    print('[AIRotationManager] initialize() proxyBaseUrl=' + resolvedProxyBaseUrl + ', localModelFileName=' + localModelFileName + ', localModelPath=' + (localModelPath ?? '<null>'));

    _providers.add(LocalLlamaProvider(
      modelFileName: localModelFileName,
      modelPathOverride: localModelPath,
    ));

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

    for (final provider in _providers) {
      print('[AIRotationManager] initialized provider => ' + _describeProvider(provider));
    }

    debugPrint(
        '[AI] Initialized ${_providers.length} providers via local + proxy fallback: $resolvedProxyBaseUrl');
  }

  bool get hasOnlineProviders => _providers.any((p) => p.isAvailable);

  /// Analyze image with automatic provider rotation and failover.
  Future<(List<Explanation>, String)> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
    bool isOffline = false,
  }) async {
    print('[AIRotationManager] analyzeImage() called; isOffline=' + isOffline.toString() + ', providerCount=' + _providers.length.toString() + ', currentIndex=' + _currentIndex.toString() + ', lastUsedProvider=' + _lastUsedProvider);
    if (isOffline || _providers.isEmpty) {
      print('[AIRotationManager] using offline provider because isOffline=' + isOffline.toString() + ' and providerCount=' + _providers.length.toString());
      for (final provider in _providers) {
        print('[AIRotationManager] offline inventory => ' + _describeProvider(provider));
      }
      final results = await _offlineProvider.analyzeImage(
        imageBytes: imageBytes,
        context: context,
      );
      _lastUsedProvider = _offlineProvider.name;
      debugPrint(
          '[AI] Using offline provider (isOffline=$isOffline, providers=${_providers.length})');
      return (results, _offlineProvider.name);
    }

    final startIndex = _currentIndex % _providers.length;
    print('[AIRotationManager] starting provider rotation at index=' + startIndex.toString());
    for (int i = 0; i < _providers.length; i++) {
      final index = (startIndex + i) % _providers.length;
      final provider = _providers[index];
      print('[AIRotationManager] considering provider index=' + index.toString() + ' => ' + _describeProvider(provider));

      if (!provider.isAvailable) {
        print('[AIRotationManager] skipping provider because isAvailable=false => ' + _describeProvider(provider));
        continue;
      }

      try {
        print('[AIRotationManager] invoking provider.analyzeImage for ' + provider.name);
        final results = await provider.analyzeImage(
          imageBytes: imageBytes,
          context: context,
        );

        if (results.isNotEmpty) {
          print('[AIRotationManager] provider succeeded => ' + provider.name + ', results=' + results.length.toString());
          _currentIndex = (index + 1) % _providers.length;
          _lastUsedProvider = provider.name;
          return (results, provider.name);
        }

        print('[AIRotationManager] provider returned no results => ' + provider.name);
      } catch (e) {
        print('[AIRotationManager] provider threw => ' + provider.name + ': ' + e.toString());
        continue;
      }
    }

    print('[AIRotationManager] all online providers failed; falling back to offline provider');
    final results = await _offlineProvider.analyzeImage(
      imageBytes: imageBytes,
      context: context,
    );
    _lastUsedProvider = _offlineProvider.name;
    debugPrint('[AI] All online providers failed, falling back to offline');
    print('[AIRotationManager] offline fallback complete; results=' + results.length.toString() + ', lastUsedProvider=' + _lastUsedProvider);
    return (results, _offlineProvider.name);
  }
}

