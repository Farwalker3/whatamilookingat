import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';

/// Gemini Flash AI provider — best quality, 15 RPM free.
class GeminiProvider extends AIProvider with RateLimitTracker {
  final String apiKey;
  late final GenerativeModel _model;
  bool _isInitialized = false;

  GeminiProvider({required this.apiKey}) {
    if (apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.4,
          maxOutputTokens: 2048,
          responseMimeType: 'application/json',
        ),
      );
      _isInitialized = true;
    }
  }

  @override
  String get name => 'Gemini Flash';

  @override
  bool get isAvailable => _isInitialized && apiKey.isNotEmpty && !isCoolingDown;

  @override
  Future<List<Explanation>> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
  }) async {
    try {
      final prompt = _buildPrompt(context);
      final content = Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]);

      final response = await _model.generateContent([content]);
      final text = response.text;
      if (text == null || text.isEmpty) return [];

      resetCooldown();
      return _parseResponse(text);
    } catch (e) {
      if (e.toString().contains('429') ||
          e.toString().contains('RESOURCE_EXHAUSTED')) {
        markRateLimited();
      }
      rethrow;
    }
  }

  String _buildPrompt(DeviceContext context) {
    return '''You are an expert visual analyst. Analyze this camera image and provide multiple distinct explanations of what the user is looking at.

${context.toPromptText()}

Return a JSON array of 3-8 explanation objects. Each should describe a DIFFERENT thing visible or relevant to the scene. Be specific and use the device context (location, news, time) to provide richer explanations.

For each explanation, get STRAIGHT TO THE POINT in the headline, then provide more detail in summary and details.

JSON format:
[
  {
    "headline": "One clear sentence - what this is",
    "summary": "2-3 sentences with key details",
    "details": "Full paragraph with rich context, interesting facts, connections to local news if relevant",
    "sources": ["camera", "location", "news", "time"],
    "category": "landmark|event|sign|object|person|nature|vehicle|text|scene",
    "confidence": 0.0-1.0
  }
]

Rules:
- headline must be punchy and immediately informative
- Sort by relevance/interest (most interesting first)
- Use location data to identify specific places, streets, businesses
- If news headlines relate to what's visible, create an explanation connecting them
- Include at least one explanation about the overall scene/setting
- Be factual but engaging''';
  }

  List<Explanation> _parseResponse(String text) {
    try {
      // Clean potential markdown wrapping
      String jsonStr = text.trim();
      
      // Extract JSON if wrapped in markdown or other text
      final jsonMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(jsonStr) ?? 
                        RegExp(r'\{.*\}', dotAll: true).firstMatch(jsonStr);
      
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(0)!;
      }

      final decoded = jsonDecode(jsonStr);
      
      List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map && decoded.containsKey('explanations')) {
        items = decoded['explanations'] as List;
      } else {
        return [];
      }

      return items
          .map((e) => Explanation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // If JSON fails, create a single explanation from raw text
      return [
        Explanation(
          headline: 'Scene Analysis',
          summary: text.length > 200 ? '${text.substring(0, 200)}...' : text,
          details: text,
          sources: ['camera'],
          category: 'scene',
        ),
      ];
    }
  }
}
