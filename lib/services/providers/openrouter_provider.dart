import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';

/// OpenRouter AI provider — access to free multimodal models.
class OpenRouterProvider extends AIProvider with RateLimitTracker {
  final String apiKey;

  OpenRouterProvider({required this.apiKey});

  @override
  String get name => 'OpenRouter';

  @override
  bool get isAvailable => apiKey.isNotEmpty && !isCoolingDown;

  @override
  Future<List<Explanation>> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final prompt = _buildPrompt(context);

      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://whatamilookingat.app',
          'X-Title': 'What Am I Looking At',
        },
        body: jsonEncode({
          'model': 'google/gemini-2.5-flash',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'temperature': 0.4,
          'max_tokens': 2048,
        }),
      );

      if (response.statusCode == 429) {
        markRateLimited();
        throw Exception('Rate limited');
      }

      if (response.statusCode != 200) {
        throw Exception('OpenRouter API error: ${response.statusCode}');
      }

      resetCooldown();
      final data = jsonDecode(response.body);
      final text = data['choices'][0]['message']['content'] as String;
      return _parseResponse(text);
    } catch (e) {
      if (e.toString().contains('429')) markRateLimited();
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

Return ONLY a JSON array of 3-8 explanation objects:
[{"headline": "...", "summary": "...", "details": "...", "sources": ["camera","location","news","time"], "category": "landmark|event|sign|object|person|nature|vehicle|text|scene|product", "confidence": 0.0-1.0}]''';
  }

  List<Explanation> _parseResponse(String text) {
    try {
      String cleaned = text.trim();
      // Strip markdown code blocks if present
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
        cleaned = cleaned.trim();
      }

      final decoded = jsonDecode(cleaned);

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
      return [
        Explanation(
          headline: 'Scene Analysis',
          summary: text.length > 200 ? '${text.substring(0, 200)}...' : text,
          details: text,
          sources: ['camera'],
        ),
      ];
    }
  }
}
