import 'dart:typed_data';
import '../../models/device_context.dart';
import '../../models/explanation.dart';
import '../ai_provider.dart';

/// Offline AI provider using basic heuristics when no network is available.
/// Provides generic scene descriptions based on available context.
class OfflineProvider extends AIProvider with RateLimitTracker {
  @override
  String get name => 'Offline Mode';

  @override
  bool get isAvailable => true; // Always available as last resort

  @override
  Future<List<Explanation>> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
  }) async {
    final explanations = <Explanation>[];

    // Basic scene explanation
    explanations.add(Explanation(
      headline: 'Camera view captured',
      summary: 'You are currently offline. Basic analysis is available using device sensors only.',
      details: 'Full AI analysis requires an internet connection. '
          'Connect to WiFi or mobile data for detailed explanations powered by AI. '
          'Your image has been captured and can be analyzed when you reconnect.',
      sources: ['camera'],
      category: 'scene',
      confidence: 0.3,
    ));

    // Location-based explanation if available
    if (context.hasLocation) {
      explanations.add(Explanation(
        headline: context.placeName ?? 'Current Location',
        summary: 'You are at ${context.locationSummary}. '
            '${context.heading != null ? "Facing ${_headingToDirection(context.heading!)}. " : ""}'
            'Coordinates: ${context.latitude!.toStringAsFixed(4)}, ${context.longitude!.toStringAsFixed(4)}.',
        details: 'Located at ${context.locationSummary}. '
            '${context.heading != null ? "Your device is pointing ${_headingToDirection(context.heading!)} (${context.heading!.toStringAsFixed(0)}°). " : ""}'
            'This information comes from your device\'s GPS and compass sensors.',
        sources: ['location'],
        category: 'landmark',
        confidence: 0.7,
      ));
    }

    // Time-based explanation
    final hour = context.timestamp.hour;
    String timeOfDay;
    if (hour < 6) {
      timeOfDay = 'early morning';
    } else if (hour < 12) {
      timeOfDay = 'morning';
    } else if (hour < 17) {
      timeOfDay = 'afternoon';
    } else if (hour < 21) {
      timeOfDay = 'evening';
    } else {
      timeOfDay = 'night';
    }

    explanations.add(Explanation(
      headline: 'Captured during the $timeOfDay',
      summary: 'This image was taken at ${context.timestamp.hour}:${context.timestamp.minute.toString().padLeft(2, '0')} '
          'on ${_formatDate(context.timestamp)}.',
      details: 'Time of capture can be important for understanding context — '
          'lighting conditions, business hours, event schedules, and more '
          'all depend on when the image was taken.',
      sources: ['time'],
      category: 'scene',
      confidence: 0.9,
    ));

    return explanations;
  }

  String _headingToDirection(double heading) {
    const directions = ['North', 'Northeast', 'East', 'Southeast',
                        'South', 'Southwest', 'West', 'Northwest'];
    final index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
