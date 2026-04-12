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
}
