/// Aggregated device context sent to AI providers.
class DeviceContext {
  final double? latitude;
  final double? longitude;
  final String? placeName;
  final String? street;
  final String? city;
  final String? country;
  final double? heading;
  final DateTime timestamp;
  final List<String> newsHeadlines;

  /// On-device ML Kit labels detected in the current frame.
  final List<String> detectedLabels;

  /// Headlines from recent analyses (self-learning memory).
  final List<String> recentFindings;

  const DeviceContext({
    this.latitude,
    this.longitude,
    this.placeName,
    this.street,
    this.city,
    this.country,
    this.heading,
    required this.timestamp,
    this.newsHeadlines = const [],
    this.detectedLabels = const [],
    this.recentFindings = const [],
  });

  bool get hasLocation => latitude != null && longitude != null;

  String get locationSummary {
    final parts = <String>[];
    if (placeName != null) parts.add(placeName!);
    if (street != null && street != placeName) parts.add(street!);
    if (city != null) parts.add(city!);
    if (country != null) parts.add(country!);
    if (parts.isEmpty && hasLocation) {
      return '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    }
    return parts.join(', ');
  }

  String toPromptText() {
    final buf = StringBuffer();
    buf.writeln('DEVICE CONTEXT:');
    buf.writeln('- Time: ${timestamp.toIso8601String()}');
    if (hasLocation) {
      buf.writeln('- GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}');
    }
    if (placeName != null) buf.writeln('- Place: $placeName');
    if (street != null) buf.writeln('- Street: $street');
    if (city != null) buf.writeln('- City: $city');
    if (country != null) buf.writeln('- Country: $country');
    if (heading != null) buf.writeln('- Compass heading: ${heading!.toStringAsFixed(0)}°');

    if (detectedLabels.isNotEmpty) {
      buf.writeln('- On-device detected objects: ${detectedLabels.join(', ')}');
    }

    if (recentFindings.isNotEmpty) {
      buf.writeln('- Previously identified in this session:');
      for (final f in recentFindings.take(5)) {
        buf.writeln('  • $f');
      }
      buf.writeln('  (Don\'t repeat these unless something changed)');
    }

    if (newsHeadlines.isNotEmpty) {
      buf.writeln('- Local news headlines:');
      for (final h in newsHeadlines.take(5)) {
        buf.writeln('  • $h');
      }
    }
    return buf.toString();
  }
}
