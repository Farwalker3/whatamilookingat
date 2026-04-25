import 'dart:typed_data';

import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';
import 'proxy_ai_client.dart';

class ProxyVisualAIProvider extends AIProvider with RateLimitTracker {
  final String proxyBaseUrl;
  final String providerId;
  final String displayName;
  final String model;

  ProxyVisualAIProvider({
    required this.proxyBaseUrl,
    required this.providerId,
    required this.displayName,
    required this.model,
  });

  @override
  String get name => displayName;

  @override
  bool get isAvailable => !isCoolingDown;

  @override
  Future<List<Explanation>> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
  }) async {
    try {
      final prompt = buildVisualAnalysisPrompt(context);
      final text = await analyzeViaProxy(
        proxyBaseUrl: proxyBaseUrl,
        provider: providerId,
        model: model,
        prompt: prompt,
        imageBytes: imageBytes,
      );

      resetCooldown();
      return parseExplanationResponse(text);
    } catch (e) {
      if (e.toString().contains('429') ||
          e.toString().contains('RESOURCE_EXHAUSTED')) {
        markRateLimited();
      }
      rethrow;
    }
  }
}
