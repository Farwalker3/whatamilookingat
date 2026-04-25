import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';

/// Groq AI provider — fastest inference (~300ms), 30 RPM free.
/// Uses Llama 4 Scout with vision capabilities.
class GroqProvider extends AIProvider with RateLimitTracker {
  final String apiKey;

  GroqProvider({required this.apiKey});

  @override
  String get name => 'Groq (Llama 4)';

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
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'meta-llama/llama-4-scout-17b-16e-instruct',
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
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 429) {
        markRateLimited();
        throw Exception('Rate limited');
      }

      if (response.statusCode != 200) {
        throw Exception('Groq API error: ${response.statusCode}');
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
- DO NOT HALLUCINATE brands or models. If an object lacks a clear logo, describe it generically (e.g., "white circular device", NOT "Apple AirPod").
- NEVER invent or guess text. You MUST strictly rely on the "EXACT OCR TEXT IN IMAGE" provided in the DEVICE CONTEXT above. If no text is provided, do NOT guess text.
- Identify objects both NEAR and FAR in the scene
- Get STRAIGHT TO THE POINT — no filler phrases
- Use location/news context to identify landmarks, businesses, events

Return JSON: {"explanations": [{"headline": "...", "summary": "...", "details": "...", "sources": ["camera","location","news","time"], "category": "landmark|event|sign|object|person|nature|vehicle|text|scene|product", "confidence": 0.0-1.0}]}

Format: 3-8 objects, sorted by visual prominence. headline=one punchy sentence, summary=2-3 key details, details=full paragraph.''';
  }

  List<Explanation> _parseResponse(String text) {
    try {
      String jsonStr = text.trim();
      
      // Extract JSON if wrapped in markdown or other text
      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(jsonStr);
      
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(0)!;
      }

      final decoded = jsonDecode(jsonStr);

      // Handle both array and object-with-array format
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
