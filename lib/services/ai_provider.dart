import 'dart:typed_data';
import '../models/device_context.dart';
import '../models/explanation.dart';

/// Abstract interface for all AI providers.
abstract class AIProvider {
  String get name;
  bool get isAvailable;

  /// Analyze an image with device context, returning multiple explanations.
  Future<List<Explanation>> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
  });

  /// Mark this provider as rate-limited. It will cool down.
  void markRateLimited();

  /// Check if provider is currently cooled down.
  bool get isCoolingDown;
}

/// Base mixin for rate limit tracking.
mixin RateLimitTracker {
  DateTime? _cooldownUntil;
  int _consecutiveFailures = 0;

  void markRateLimited() {
    _consecutiveFailures++;
    // Exponential backoff: 30s, 60s, 120s, max 5min
    final seconds = (30 * (1 << (_consecutiveFailures - 1))).clamp(30, 300);
    _cooldownUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  bool get isCoolingDown {
    if (_cooldownUntil == null) return false;
    if (DateTime.now().isAfter(_cooldownUntil!)) {
      _cooldownUntil = null;
      return false;
    }
    return true;
  }

  void resetCooldown() {
    _consecutiveFailures = 0;
    _cooldownUntil = null;
  }
}
