import 'explanation.dart';

/// Holds a complete analysis result from one frame.
class AnalysisResult {
  final List<Explanation> explanations;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final String providerUsed;
  final bool isOffline;

  const AnalysisResult({
    required this.explanations,
    this.locationName,
    this.latitude,
    this.longitude,
    required this.timestamp,
    this.providerUsed = 'unknown',
    this.isOffline = false,
  });

  bool get hasExplanations => explanations.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'explanations': explanations.map((e) => e.toJson()).toList(),
        'locationName': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'providerUsed': providerUsed,
        'isOffline': isOffline,
      };

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      explanations: (json['explanations'] as List<dynamic>?)
              ?.map((e) => Explanation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      locationName: json['locationName'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      providerUsed: json['providerUsed'] as String? ?? 'unknown',
      isOffline: json['isOffline'] as bool? ?? false,
    );
  }
}
