import 'dart:convert';
import 'package:http/http.dart' as http;

/// News service using NewsData.io API (free tier: 200 req/day).
class NewsService {
  final String apiKey;
  List<String> _cachedHeadlines = [];
  DateTime? _lastFetchTime;
  String? _lastCountryCode;

  NewsService({required this.apiKey});

  bool get isAvailable => apiKey.isNotEmpty;

  /// Fetch local news headlines based on country code.
  /// Caches results for 30 minutes to conserve API quota.
  Future<List<String>> getLocalNews({
    String? countryCode,
    String? query,
  }) async {
    if (!isAvailable) return [];

    final cc = countryCode?.toLowerCase() ?? 'us';

    // Return cache if fresh (30 min) and same country
    if (_cachedHeadlines.isNotEmpty &&
        _lastFetchTime != null &&
        _lastCountryCode == cc &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 30) {
      return _cachedHeadlines;
    }

    try {
      final params = <String, String>{
        'apikey': apiKey,
        'country': cc,
        'language': 'en',
        'size': '10',
      };

      if (query != null && query.isNotEmpty) {
        params['q'] = query;
      }

      final url = Uri.https('newsdata.io', '/api/1/latest', params);
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];

        _cachedHeadlines = results
            .map((article) {
              final title = article['title'] as String? ?? '';
              final desc = article['description'] as String? ?? '';
              return title.isNotEmpty ? title : desc;
            })
            .where((s) => s.isNotEmpty)
            .toList();

        _lastFetchTime = DateTime.now();
        _lastCountryCode = cc;
        return _cachedHeadlines;
      }
    } catch (_) {
      // News fetch failed, return cached or empty
    }

    return _cachedHeadlines;
  }

  /// Get cached headlines without making a new request.
  List<String> getCachedHeadlines() => _cachedHeadlines;
}
