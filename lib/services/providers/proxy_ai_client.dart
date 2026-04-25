import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/device_context.dart';
import '../../models/explanation.dart';

Uri _resolveProxyUri(String proxyBaseUrl) {
  final raw = proxyBaseUrl.trim().isEmpty ? '/api/chat' : proxyBaseUrl.trim();
  final uri = Uri.parse(raw);
  if (uri.hasScheme) return uri;
  return Uri.base.resolve(raw);
}

String buildVisualAnalysisPrompt(DeviceContext context) {
  return '''You are an expert visual analyst. Identify EVERY distinct object visible in this camera image with maximum specificity.

${context.toPromptText()}

CRITICAL RULES:
- Identify the EXACT make and model (e.g. "Ford F-350", "John Deere Tractor") ONLY IF there are highly distinct visual indicators. If the item is generic, unlabeled, or handmade, describe it physically without guessing a brand.
- NEVER invent or guess text. You MUST strictly rely on the "EXACT OCR TEXT IN IMAGE" provided in the DEVICE CONTEXT above. If no text is provided, do NOT guess text.
- Identify objects both NEAR and FAR in the scene
- Get STRAIGHT TO THE POINT — no filler phrases
- Use location/news context to identify landmarks, businesses, events

Return ONLY a JSON array of 3-8 explanation objects:
[{"headline": "...", "summary": "...", "details": "...", "sources": ["camera","location","news","time"], "category": "landmark|event|sign|object|person|nature|vehicle|text|scene|product", "confidence": 0.0-1.0}]''';
}

Future<String> analyzeViaProxy({
  required String proxyBaseUrl,
  required String provider,
  required String model,
  required String prompt,
  required Uint8List imageBytes,
  double temperature = 0.4,
  int maxTokens = 2048,
}) async {
  final response = await http.post(
    _resolveProxyUri(proxyBaseUrl),
    headers: const {
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'provider': provider,
      'model': model,
      'prompt': prompt,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'imageBase64': base64Encode(imageBytes),
      'imageMimeType': 'image/jpeg',
      'temperature': temperature,
      'maxTokens': maxTokens,
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('Proxy error (${response.statusCode}): ${response.body}');
  }

  final decoded = jsonDecode(response.body);
  if (decoded is Map) {
    final text = decoded['text'] ?? decoded['content'];
    if (text is String && text.trim().isNotEmpty) {
      return text;
    }

    final providerResponse = decoded['providerResponse'];
    if (providerResponse is Map) {
      final providerText = providerResponse['text'];
      if (providerText is String && providerText.trim().isNotEmpty) {
        return providerText;
      }
      final choices = providerResponse['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map) {
            final content = message['content'];
            if (content is String && content.trim().isNotEmpty) {
              return content;
            }
          }
        }
      }
    }
  }

  throw Exception('Proxy returned an empty response');
}

List<Explanation> parseExplanationResponse(String text) {
  try {
    final cleaned = text.trim();
    final jsonMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(cleaned) ??
        RegExp(r'\{.*\}', dotAll: true).firstMatch(cleaned);

    final jsonStr = jsonMatch?.group(0) ?? cleaned;
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
