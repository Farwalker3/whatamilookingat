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
    return '''You are an expert visual analyst. Identify EVERY distinct object visible in this camera image with maximum specificity.

${context.toPromptText()}

CRITICAL RULES:
- Identify the EXACT make and model (e.g. 'Ford F-350', 'John Deere Tractor') ONLY IF there are highly distinct visual indicators. If the item is generic, unlabeled, or handmade, describe it physically without guessing a brand.
- NEVER invent or guess text. You MUST strictly rely on the "EXACT OCR TEXT IN IMAGE" provided in the DEVICE CONTEXT above. If no text is provided, do NOT guess text.
- Identify objects both NEAR and FAR in the scene
- Get STRAIGHT TO THE POINT — no filler phrases
- Use location/news context to identify landmarks, businesses, events

Return a JSON array of 3-8 explanation objects, sorted by visual prominence:
[{"headline": "One clear sentence - what this is", "summary": "2-3 sentences with key details", "details": "Full paragraph with context", "sources": ["camera","location","news","time"], "category": "landmark|event|sign|object|person|nature|vehicle|text|scene|product", "confidence": 0.0-1.0}]''';
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
