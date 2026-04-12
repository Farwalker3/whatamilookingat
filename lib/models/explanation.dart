/// Data model for a single explanation of something visible in the camera view.
class Explanation {
  final String headline;
  final String summary;
  final String details;
  final List<String> sources;
  final String category;
  final double confidence;

  const Explanation({
    required this.headline,
    required this.summary,
    required this.details,
    this.sources = const [],
    this.category = 'general',
    this.confidence = 0.5,
  });

  factory Explanation.fromJson(Map<String, dynamic> json) {
    return Explanation(
      headline: json['headline'] as String? ?? 'Unknown',
      summary: json['summary'] as String? ?? '',
      details: json['details'] as String? ?? '',
      sources: (json['sources'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      category: json['category'] as String? ?? 'general',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'summary': summary,
        'details': details,
        'sources': sources,
        'category': category,
        'confidence': confidence,
      };

  /// Icon for the category
  String get categoryIcon {
    switch (category) {
      case 'landmark':
        return '🏛️';
      case 'event':
        return '📅';
      case 'sign':
        return '🪧';
      case 'object':
        return '📦';
      case 'person':
        return '👤';
      case 'nature':
        return '🌿';
      case 'vehicle':
        return '🚗';
      case 'text':
        return '📝';
      case 'scene':
        return '🌆';
      default:
        return '🔍';
    }
  }
}
