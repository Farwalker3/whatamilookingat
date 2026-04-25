import 'dart:async';

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';
import '../models/analysis_result.dart';
import '../models/device_context.dart';
import '../models/explanation.dart';
import '../services/ai_rotation_manager.dart';
import '../services/history_service.dart';
import '../services/location_service.dart';
import '../services/news_service.dart';
import '../services/vision_service.dart';

/// Main state provider for the analysis pipeline.
class AnalysisProvider extends ChangeNotifier {
  final AIRotationManager _aiManager;
  final LocationService _locationService;
  final NewsService _newsService;
  final VisionService _visionService = VisionService();
  final HistoryService _historyService = HistoryService();

  // Adaptive intervals
  static const _fastInterval = Duration(seconds: 2);
  static const _slowInterval = Duration(seconds: 5);
  Duration _currentInterval = _fastInterval;

  // Context cache (speed optimization)
  DeviceContext? _cachedContext;
  DateTime? _lastContextUpdate;
  static const _contextCacheDuration = Duration(minutes: 1);

  // Scene-change detection
  List<String> _previousLabels = [];
  int _staticFrameCount = 0;
  static const _staticThreshold = 2; // frames before slowing down

  // Self-learning memory
  List<String> _recentFindings = [];

  // State
  List<Explanation> _explanations = [];
  int _currentIndex = 0;
  bool _isAnalyzing = false;
  bool _isOnline = true;
  bool _isFrozen = false;
  String _locationName = 'Getting location...';
  String _providerName = '';
  String? _errorMessage;
  String _liveLabels = '';
  AnalysisResult? _lastResult;
  Uint8List? _frozenImage;

  // Live analysis loop
  Timer? _analysisTimer;
  CameraController? _cameraController;

  // AR Features
  bool _isARModeEnabled = false;
  bool get isARModeEnabled => _isARModeEnabled;
  final ValueNotifier<List<DetectedObject>> realtimeObjects = ValueNotifier([]);
  bool _isStreamProcessing = false;

  // Getters
  List<Explanation> get explanations => _explanations;
  int get currentIndex => _currentIndex;
  Explanation? get currentExplanation =>
      _explanations.isNotEmpty ? _explanations[_currentIndex] : null;
  bool get isAnalyzing => _isAnalyzing;
  bool get isOnline => _isOnline;
  bool get isFrozen => _isFrozen;
  String get locationName => _locationName;
  String get providerName => _providerName;
  String? get errorMessage => _errorMessage;
  String get liveLabels => _liveLabels;
  AnalysisResult? get lastResult => _lastResult;
  Uint8List? get frozenImage => _frozenImage;
  bool get hasExplanations => _explanations.isNotEmpty;
  int get explanationCount => _explanations.length;

  // History getters
  HistoryService get historyService => _historyService;
  List<AnalysisResult> get history => _historyService.history;
  int get historyCount => _historyService.count;

  AnalysisProvider({
    required AIRotationManager aiManager,
    required LocationService locationService,
    required NewsService newsService,
  })  : _aiManager = aiManager,
        _locationService = locationService,
        _newsService = newsService {
    _checkConnectivity();
    // Lazy-load history in background (non-blocking)
    _historyService.load().then((_) {
      _recentFindings = _historyService.getRecentHeadlines();
      notifyListeners();
    });
  }

  /// Set camera controller for frame capture.
  void setCameraController(CameraController controller) {
    _cameraController = controller;
  }

  void toggleARMode() {
    _isARModeEnabled = !_isARModeEnabled;
    notifyListeners();
    if (_isARModeEnabled && !_isFrozen) {
      _startARStream();
    } else if (!_isARModeEnabled && _cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
      realtimeObjects.value = [];
    }
  }

  Future<void> _startARStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;

    try {
      await _cameraController!.startImageStream((image) async {
        if (_isStreamProcessing || _isFrozen) return;
        _isStreamProcessing = true;
        
        final orientation = _cameraController!.description.sensorOrientation;
        final objects = await _visionService.detectObjectsRealtime(image, orientation);
        
        if (objects.isNotEmpty || realtimeObjects.value.isNotEmpty) {
          realtimeObjects.value = objects;
        }
        
        await Future.delayed(const Duration(milliseconds: 100)); // Rate limit roughly 10fps
        _isStreamProcessing = false;
      });
    } catch (e) {
      debugPrint('Failed to start AR stream: $e');
    }
  }

  /// Start the live analysis loop.
  void startLiveAnalysis() {
    _isFrozen = false;
    _frozenImage = null;
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(
      _currentInterval,
      (_) => _analyzeCurrentFrame(),
    );
    if (_isARModeEnabled) {
      _startARStream();
    }
    // Run immediately too
    _analyzeCurrentFrame();
    notifyListeners();
  }

  /// Stop live analysis.
  void stopLiveAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    if (_cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
    }
    notifyListeners();
  }

  /// Freeze the current view (take a picture).
  Future<Uint8List?> freezeFrame() async {
    _isFrozen = true;
    _analysisTimer?.cancel();
    _analysisTimer = null;

    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized) {
        final wasStreaming = _cameraController!.value.isStreamingImages;
        if (wasStreaming) await _cameraController!.stopImageStream();
        realtimeObjects.value = [];

        final xFile = await _cameraController!.takePicture();
        _frozenImage = await xFile.readAsBytes();
        
        notifyListeners();

        // Run one final analysis on the frozen image
        await _runAnalysis(xFile: xFile);
        return _frozenImage;
      }
    } catch (e) {
      _errorMessage = 'Failed to capture: $e';
      notifyListeners();
    }
    return null;
  }

  /// Unfreeze and resume live mode.
  void unfreezeFrame() {
    _isFrozen = false;
    _frozenImage = null;
    startLiveAnalysis();
  }

  /// Analyze an uploaded image.
  Future<void> analyzeUploadedImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      _isFrozen = true;
      _isAnalyzing = true;
      _analysisTimer?.cancel();
      notifyListeners();

      final bytes = await pickedFile.readAsBytes();
      _frozenImage = bytes;

      // Try to extract EXIF data
      DeviceContext? exifContext;
      try {
        final exifData = await readExifFromBytes(bytes);
        final latRef = exifData['GPS GPSLatitudeRef']?.toString();
        final lat = _parseGpsCoordinate(exifData['GPS GPSLatitude']?.toString());
        final lonRef = exifData['GPS GPSLongitudeRef']?.toString();
        final lon = _parseGpsCoordinate(exifData['GPS GPSLongitude']?.toString());

        if (lat != null && lon != null) {
          final finalLat = latRef == 'S' ? -lat : lat;
          final finalLon = lonRef == 'W' ? -lon : lon;

          final geocode = await _locationService.reverseGeocode(finalLat, finalLon);
          final news = await _newsService.getLocalNews(
            countryCode: geocode['countryCode'],
          );

          exifContext = DeviceContext(
            latitude: finalLat,
            longitude: finalLon,
            placeName: geocode['place'],
            street: geocode['street'],
            city: geocode['city'],
            country: geocode['country'],
            timestamp: DateTime.now(),
            newsHeadlines: news,
            recentFindings: _recentFindings,
          );
        }
      } catch (_) {
        // EXIF parsing failed, use current device context
      }

      await _runAnalysis(imageBytes: bytes, overrideContext: exifContext);
    } catch (e) {
      _errorMessage = 'Failed to load image: $e';
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Load a specific history item into the explanation cards.
  void loadHistoryItem(int index) {
    if (index < 0 || index >= _historyService.count) return;
    final result = _historyService.history[index];
    _explanations = result.explanations;
    _currentIndex = 0;
    _providerName = '${result.providerUsed} (history)';
    _lastResult = result;
    notifyListeners();
  }

  /// Navigate to next explanation.
  void nextExplanation() {
    if (_explanations.isNotEmpty) {
      _currentIndex = (_currentIndex + 1) % _explanations.length;
      notifyListeners();
    }
  }

  /// Navigate to previous explanation.
  void previousExplanation() {
    if (_explanations.isNotEmpty) {
      _currentIndex =
          (_currentIndex - 1 + _explanations.length) % _explanations.length;
      notifyListeners();
    }
  }

  // === Private Methods ===

  Future<void> _checkConnectivity() async {
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      _updateOnlineStatus(results);

      connectivity.onConnectivityChanged.listen((results) {
        _updateOnlineStatus(results);
      });
    } catch (_) {
      _isOnline = true;
      notifyListeners();
    }
  }

  void _updateOnlineStatus(List<ConnectivityResult> results) {
    _isOnline = results.isNotEmpty && 
                !results.every((r) => r == ConnectivityResult.none);
    notifyListeners();
  }

  Future<void> _analyzeCurrentFrame() async {
    if (_isAnalyzing || _isFrozen) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final wasStreaming = _cameraController!.value.isStreamingImages;
      if (wasStreaming) await _cameraController!.stopImageStream();

      final xFile = await _cameraController!.takePicture();
      
      if (wasStreaming && !_isFrozen && _isARModeEnabled) {
        await _startARStream();
      }

      await _runAnalysis(xFile: xFile);
    } catch (_) {
      // Frame capture failed
    }
  }

  Future<void> _runAnalysis({
    XFile? xFile,
    Uint8List? imageBytes,
    DeviceContext? overrideContext,
  }) async {
    final Uint8List? rawBytes = imageBytes ?? await xFile?.readAsBytes();
    if (rawBytes == null) return;

    // === Step 1: Fast ML Kit detection (instant, on-device) ===
    List<String> currentLabels = [];
    if (xFile != null) {
      currentLabels = await _visionService.detectLabelsFromPath(xFile.path);
    } else {
      currentLabels = await _visionService.detectLabelsFromBytes(rawBytes);
    }

    if (currentLabels.isNotEmpty) {
      _liveLabels = currentLabels.take(4).join(' • ');
      notifyListeners();
    }

    // === Step 2: Scene-change detection (skip if static) ===
    if (!_isFrozen && _previousLabels.isNotEmpty) {
      final similarity = _calculateLabelSimilarity(_previousLabels, currentLabels);
      if (similarity > 0.7) {
        _staticFrameCount++;
        if (_staticFrameCount > _staticThreshold) {
          // Scene hasn't changed — slow down and skip expensive AI call
          _adaptInterval(_slowInterval);
          _previousLabels = currentLabels;
          debugPrint('[Analysis] Scene static (${(similarity * 100).toInt()}% similar), skipping AI call');
          return;
        }
      } else {
        // Scene changed — reset to fast mode
        _staticFrameCount = 0;
        _adaptInterval(_fastInterval);
        debugPrint('[Analysis] Scene changed (${(similarity * 100).toInt()}% similar), running AI');
      }
    }
    _previousLabels = currentLabels;

    _isAnalyzing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // === Step 3: Compress image for faster upload ===
      final Uint8List compressedBytes = await compute(_compressImage, rawBytes);

      // === Step 3b: Determine contextual search query ===
      String? contextQuery;
      final fullTextLabel = currentLabels.firstWhere(
        (l) => l.startsWith('EXACT OCR'),
        orElse: () => '',
      ).toLowerCase();
      
      if (fullTextLabel.contains(RegExp(r'road\s*clos|construction|traffic|accident|police|detour'))) {
        contextQuery = 'road closed OR construction OR traffic OR accident';
        debugPrint('[Analysis] Context query triggered: $contextQuery');
      }

      // === Step 4: Build context (parallel with compression) ===
      final context = overrideContext ?? await _getOptimizedContext(currentLabels, contextQuery);

      if (context.hasLocation) {
        _locationName = context.placeName?.isNotEmpty == true
            ? context.placeName!
            : context.city?.isNotEmpty == true
                ? context.city!
                : context.locationSummary;
      }

      // === Step 5: AI analysis with timeout ===
      debugPrint('[Analysis] Calling AI manager with isOffline=${!_isOnline}');
      final (results, provider) = await _aiManager
          .analyzeImage(
            imageBytes: compressedBytes,
            context: context,
            isOffline: !_isOnline,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint('[Analysis] AI call timed out, using ML Kit labels only');
              // Return ML Kit labels as basic explanations if AI times out
              return (
                currentLabels.map((l) => Explanation(
                  headline: l,
                  summary: 'Detected on-device',
                  details: 'Fast detection result while waiting for AI analysis.',
                  sources: ['camera'],
                  category: 'object',
                  confidence: 0.6,
                )).toList(),
                'On-device (timeout)',
              );
            },
          );
      debugPrint('[Analysis] Got ${results.length} results from $provider');

      if (results.isNotEmpty) {
        _explanations = results;
        _currentIndex = 0;
        _providerName = provider;
        _liveLabels = ''; // Clear fast labels when deep analysis is done

        String? savedImagePath;
        if (_isFrozen && xFile != null) {
          // Copy the frozen image to history folder
          try {
            final appDir = await getApplicationDocumentsDirectory();
            savedImagePath = '\${appDir.path}/history_\${DateTime.now().millisecondsSinceEpoch}.jpg';
            await xFile.saveTo(savedImagePath);
          } catch (_) {}
        } else if (_isFrozen && imageBytes != null) { // For uploaded images
          try {
            final appDir = await getApplicationDocumentsDirectory();
            savedImagePath = '\${appDir.path}/history_\${DateTime.now().millisecondsSinceEpoch}.jpg';
            await File(savedImagePath).writeAsBytes(imageBytes);
          } catch (_) {}
        }

        final analysisResult = AnalysisResult(
          explanations: results,
          locationName: _locationName,
          latitude: context.latitude,
          longitude: context.longitude,
          timestamp: DateTime.now(),
          providerUsed: provider,
          isOffline: !_isOnline,
          imagePath: savedImagePath,
        );
        _lastResult = analysisResult;

        // Save to history (non-blocking)
        _historyService.add(analysisResult);

        // Update self-learning memory
        _recentFindings = results
            .map((e) => e.headline)
            .take(5)
            .toList();
      }
    } catch (e) {
      _errorMessage = 'Analysis failed: ${e.toString().split('\n').first}';
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Compress image to ~800px max dimension for faster upload.
  static Uint8List _compressImage(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      // Only compress if larger than target
      if (decoded.width <= 800 && decoded.height <= 800) return bytes;

      final resized = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? 800 : null,
        height: decoded.height >= decoded.width ? 800 : null,
        interpolation: img.Interpolation.linear,
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
    } catch (_) {
      return bytes;
    }
  }

  /// Calculate how similar two sets of labels are (0.0 = different, 1.0 = identical).
  double _calculateLabelSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final setA = a.map((l) => l.toLowerCase()).toSet();
    final setB = b.map((l) => l.toLowerCase()).toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;

    return union > 0 ? intersection / union : 0.0;
  }

  /// Adapt the analysis interval based on scene activity.
  void _adaptInterval(Duration newInterval) {
    if (_currentInterval == newInterval) return;
    _currentInterval = newInterval;
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(
      _currentInterval,
      (_) => _analyzeCurrentFrame(),
    );
    debugPrint('[Analysis] Interval adapted to ${_currentInterval.inSeconds}s');
  }

  Future<DeviceContext> _getOptimizedContext([List<String> labels = const [], String? query]) async {
    if (_cachedContext != null && _lastContextUpdate != null) {
      final age = DateTime.now().difference(_lastContextUpdate!);
      // If we have a specific query, we force a refresh to get the local news
      if (query == null && age < _contextCacheDuration) {
        // Return cached context but with fresh labels and findings
        return DeviceContext(
          latitude: _cachedContext!.latitude,
          longitude: _cachedContext!.longitude,
          placeName: _cachedContext!.placeName,
          street: _cachedContext!.street,
          city: _cachedContext!.city,
          country: _cachedContext!.country,
          heading: _cachedContext!.heading,
          timestamp: DateTime.now(),
          newsHeadlines: _cachedContext!.newsHeadlines,
          detectedLabels: labels,
          recentFindings: _recentFindings,
        );
      }
    }

    final position = await _locationService.getCurrentPosition();
    if (position == null) return _cachedContext ?? await _buildContext(labels);

    final geocode = await _locationService.reverseGeocode(
        position.latitude, position.longitude);
    
    // Add the city or street to the query for local context
    String? finalQuery;
    if (query != null && geocode['city'] != null) {
      finalQuery = '$query ${geocode['city']}';
    } else {
      finalQuery = query;
    }

    final news = await _newsService.getLocalNews(
        countryCode: geocode['countryCode'], query: finalQuery);

    _cachedContext = DeviceContext(
      latitude: position.latitude,
      longitude: position.longitude,
      placeName: geocode['place'],
      street: geocode['street'],
      city: geocode['city'],
      country: geocode['country'],
      heading: _locationService.getHeadingFromPosition(),
      timestamp: DateTime.now(),
      newsHeadlines: news,
      detectedLabels: labels,
      recentFindings: _recentFindings,
    );
    _lastContextUpdate = DateTime.now();
    
    return _cachedContext!;
  }

  Future<DeviceContext> _buildContext([List<String> labels = const []]) async {
    final position = await _locationService.getCurrentPosition();
    if (position == null) {
      return DeviceContext(
        timestamp: DateTime.now(),
        newsHeadlines: [],
        detectedLabels: labels,
        recentFindings: _recentFindings,
      );
    }

    final geocode = await _locationService.reverseGeocode(
      position.latitude,
      position.longitude,
    );

    final news = await _newsService.getLocalNews(
      countryCode: geocode['countryCode'],
    );

    return DeviceContext(
      latitude: position.latitude,
      longitude: position.longitude,
      placeName: geocode['place'],
      street: geocode['street'],
      city: geocode['city'],
      country: geocode['country'],
      heading: _locationService.getHeadingFromPosition(),
      timestamp: DateTime.now(),
      newsHeadlines: news,
      detectedLabels: labels,
      recentFindings: _recentFindings,
    );
  }

  double? _parseGpsCoordinate(String? value) {
    if (value == null) return null;
    try {
      final cleaned = value.replaceAll('[', '').replaceAll(']', '');
      final parts = cleaned.split(',').map((s) => s.trim()).toList();
      if (parts.length != 3) return null;

      double parsePart(String part) {
        if (part.contains('/')) {
          final fraction = part.split('/');
          return double.parse(fraction[0]) / double.parse(fraction[1]);
        }
        return double.parse(part);
      }

      final deg = parsePart(parts[0]);
      final min = parsePart(parts[1]);
      final sec = parsePart(parts[2]);
      return deg + min / 60 + sec / 3600;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    super.dispose();
  }
}
