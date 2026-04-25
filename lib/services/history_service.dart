import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/analysis_result.dart';

/// Persists analysis history as a compact JSON file.
/// Loads lazily after app start, caps at [maxEntries] entries.
class HistoryService {
  static const int maxEntries = 50;
  static const String _fileName = 'analysis_history.json';

  List<AnalysisResult> _history = [];
  bool _isLoaded = false;
  File? _file;

  List<AnalysisResult> get history => _history;
  bool get isLoaded => _isLoaded;
  int get count => _history.length;

  /// Load history from disk in background. Non-blocking.
  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/$_fileName');

      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        _history = decoded
            .map((e) => AnalysisResult.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[History] Failed to load: $e');
      _history = [];
    }
    _isLoaded = true;
  }

  /// Add a new result to history and persist.
  Future<void> add(AnalysisResult result) async {
    // Deduplicate: skip if the top headline is identical to the last entry
    if (_history.isNotEmpty &&
        result.explanations.isNotEmpty &&
        _history.first.explanations.isNotEmpty &&
        _history.first.explanations.first.headline ==
            result.explanations.first.headline) {
      if (result.imagePath != null) {
        try {
          await File(result.imagePath!).delete();
        } catch (_) {}
      }
      return;
    }

    _history.insert(0, result);

    // Cap size
    while (_history.length > maxEntries) {
      final removed = _history.removeLast();
      if (removed.imagePath != null) {
        try {
          await File(removed.imagePath!).delete();
        } catch (_) {}
      }
    }

    // Persist in background (fire-and-forget)
    _persistAsync();
  }

  /// Get recent headlines for self-learning memory.
  List<String> getRecentHeadlines({int count = 5}) {
    return _history
        .take(count)
        .expand((r) => r.explanations.map((e) => e.headline))
        .take(count)
        .toList();
  }

  /// Clear all history.
  Future<void> clear() async {
    for (final r in _history) {
      if (r.imagePath != null) {
        try {
          await File(r.imagePath!).delete();
        } catch (_) {}
      }
    }
    _history.clear();
    _persistAsync();
  }

  void _persistAsync() {
    // Run serialization in isolate to avoid jank
    compute(_serializeHistory, _history).then((json) async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        _file ??= File('${dir.path}/$_fileName');
        await _file!.writeAsString(json);
      } catch (e) {
        debugPrint('[History] Failed to persist: $e');
      }
    });
  }

  static String _serializeHistory(List<AnalysisResult> history) {
    return jsonEncode(history.map((r) => r.toJson()).toList());
  }
}
