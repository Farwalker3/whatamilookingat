FILE lib/services/ai_provider.dart
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


---END---

FILE lib/screens/camera_screen.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:whatamilookingat/providers/analysis_provider.dart';
import 'package:whatamilookingat/theme/app_theme.dart';
import 'package:whatamilookingat/widgets/explanation_card.dart';
import 'package:whatamilookingat/widgets/history_panel.dart';
import 'package:whatamilookingat/widgets/status_bar.dart';
import 'package:whatamilookingat/screens/settings_screen.dart';

/// Main camera screen with live preview, explanation overlay, and controls.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isInitializing = true;
  int _currentCameraIndex = 0;

  final GlobalKey _repaintKey = GlobalKey();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _isInitializing = false);
        return;
      }

      final camera = _cameras[_currentCameraIndex];
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      // Provide camera to analysis provider
      final provider = context.read<AnalysisProvider>();
      provider.setCameraController(_cameraController!);

      setState(() {
        _isCameraReady = true;
        _isInitializing = false;
      });

      // Start live analysis
      provider.startLiveAnalysis();
    } catch (e) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

    final provider = context.read<AnalysisProvider>();
    provider.stopLiveAnalysis();

    await _cameraController?.dispose();
    setState(() => _isCameraReady = false);

    await _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RepaintBoundary(
        key: _repaintKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
          // Camera preview or frozen image
          _buildCameraLayer(),

          // Top status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Consumer<AnalysisProvider>(
              builder: (_, provider, _) => StatusBar(
                locationName: provider.locationName,
                isOnline: provider.isOnline,
                isAnalyzing: provider.isAnalyzing,
                providerName: provider.providerName,
                isFrozen: provider.isFrozen,
              ),
            ),
          ),

          // Bottom explanation card + controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(),
          ),

          // Top-right controls
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 60, right: 16),
                child: Column(
                  children: [
                    _buildIconButton(
                      Icons.cameraswitch_rounded,
                      onTap: _switchCamera,
                      tooltip: 'Switch camera',
                    ),
                    const SizedBox(height: 12),
                    _buildIconButton(
                      Icons.history_rounded,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => const HistoryPanel(),
                        );
                      },
                      tooltip: 'History',
                    ),
                    const SizedBox(height: 12),
                    _buildIconButton(
                      Icons.settings_rounded,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      tooltip: 'Settings',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _savePhotoToGallery() async {
    final provider = context.read<AnalysisProvider>();
    if (provider.frozenImage == null) return;
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) await Gal.requestAccess();
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_freeze_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(tempPath).writeAsBytes(provider.frozenImage!);
      await Gal.putImage(tempPath, album: 'WhatAmILookingAt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved to gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save to gallery: $e')),
        );
      }
    }
  }

  Future<void> _saveCardToGallery() async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) await Gal.requestAccess();
      
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null) return;

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_card_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(tempPath).writeAsBytes(pngBytes);
      await Gal.putImage(tempPath, album: 'WhatAmILookingAt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Explanation card saved to gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save card: $e')),
        );
      }
    }
  }

  Widget _buildCameraLayer() {
    return Consumer<AnalysisProvider>(
      builder: (_, provider, _) {
        // Show frozen image
        if (provider.isFrozen && provider.frozenImage != null) {
          return Image.memory(
            provider.frozenImage!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }

        // Show camera preview
        if (_isCameraReady && _cameraController != null) {
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1920,
                height: _cameraController!.value.previewSize?.width ?? 1080,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_cameraController!),
                    if (provider.isARModeEnabled)
                      ValueListenableBuilder<List<DetectedObject>>(
                        valueListenable: provider.realtimeObjects,
                        builder: (context, objects, child) {
                          if (objects.isEmpty) return const SizedBox.shrink();
                          return CustomPaint(
                            painter: BoundingBoxPainter(
                              objects: objects,
                              imageSize: Size(
                                _cameraController!.value.previewSize?.width ?? 1080,
                                _cameraController!.value.previewSize?.height ?? 1920,
                              ),
                              rotation: _cameraController!.description.sensorOrientation,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        // Loading state
        if (_isInitializing) {
          return Container(
            color: AppTheme.background,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 16),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        // No camera available
        return Container(
          color: AppTheme.background,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_photography_rounded,
                    color: AppTheme.textMuted, size: 64),
                SizedBox(height: 16),
                Text(
                  'No camera available',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Upload an image to analyze',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    return Consumer<AnalysisProvider>(
      builder: (_, provider, _) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fast detection labels (Live)
              if (provider.isAnalyzing && provider.liveLabels.isNotEmpty)
                _buildLiveLabelsPill(provider.liveLabels),

              const SizedBox(height: 8),

              // Explanation card
              if (provider.hasExplanations)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ExplanationCard(
                      explanation: provider.currentExplanation!,
                      currentIndex: provider.currentIndex,
                      totalCount: provider.explanationCount,
                      onNext: provider.nextExplanation,
                      onPrevious: provider.previousExplanation,
                      isAnalyzing: provider.isAnalyzing,
                    ),
                  ),
                )
              else if (provider.isAnalyzing)
                _buildLoadingCard(provider.analysisStatusMessage)
              else if (provider.errorMessage != null)
                _buildErrorCard(provider.errorMessage!)
              else
                _buildWelcomeCard(),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Save/Upload button
                  if (provider.isFrozen)
                    _buildActionButton(
                      icon: Icons.download_rounded,
                      label: 'Save Photo',
                      onTap: _savePhotoToGallery,
                      color: Colors.blueAccent,
                    )
                  else
                    _buildActionButton(
                      icon: Icons.image_rounded,
                      label: 'Upload',
                      onTap: provider.analyzeUploadedImage,
                      color: AppTheme.accent,
                    ),

                  // Capture / Unfreeze button
                  _buildCaptureButton(provider),

                  // Share/Resume button
                  if (provider.isFrozen)
                    _buildActionButton(
                      icon: Icons.ios_share_rounded,
                      label: 'Share Card',
                      onTap: _saveCardToGallery,
                      color: Colors.greenAccent,
                    )
                  else
                    _buildActionButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Resume',
                      onTap: provider.startLiveAnalysis,
                      color: AppTheme.textMuted,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCaptureButton(AnalysisProvider provider) {
    return GestureDetector(
      onTap: () async {
        if (provider.isFrozen) {
          provider.unfreezeFrame();
        } else {
          HapticFeedback.mediumImpact();
          await provider.freezeFrame();
        }
      },
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: provider.isFrozen
              ? null
              : AppTheme.captureGradient,
          color: provider.isFrozen ? AppTheme.surfaceLight : null,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: (provider.isFrozen ? AppTheme.textMuted : AppTheme.error)
                  .withValues(alpha: 0.3),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(
          provider.isFrozen ? Icons.refresh_rounded : Icons.camera_alt_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.glassCard,
        child: Shimmer.fromColors(
          baseColor: AppTheme.textMuted,
          highlightColor: AppTheme.textSecondary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 18,
                width: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 14,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 14,
                width: 250,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glassCard,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.warning, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.glassCard,
        child: const Column(
          children: [
            Text(
              '👁️ Point your camera at anything',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'AI will explain what you\'re looking at using your location, '
              'local news, and visual analysis.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon, {
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.glassBorder, width: 1),
          ),
          child: Icon(icon, color: AppTheme.textPrimary, size: 20),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'What Am I Looking At?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'An AI-powered smart camera that explains what you see.\n\n'
          '• Point your camera at anything\n'
          '• Get AI-powered explanations in real-time\n'
          '• Uses your location & local news for context\n'
          '• Multiple explanations per scene\n'
          '• Take photos to freeze & save explanations\n'
          '• Works offline with basic analysis\n\n'
          'Powered by Gemini, Groq, and OpenRouter AI.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveLabelsPill(String labels) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            labels,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws neon bounding boxes over detected objects in real-time.
class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final int rotation;

  BoundingBoxPainter({
    required this.objects,
    required this.imageSize,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = AppTheme.primary
      ..strokeJoin = StrokeJoin.round;

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppTheme.primary.withAlpha(40);

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final obj in objects) {
      final rect = obj.boundingBox;
      
      // Calculate scaled rect based on camera preview
      // Note: mapping bounding boxes directly from raw camera pixel space to screen
      // can require rotation/translation matrices, but we approximate for simple AR:
      final left = rect.left * scaleX;
      final top = rect.top * scaleY;
      final right = rect.right * scaleX;
      final bottom = rect.bottom * scaleY;
      
      final displayRect = Rect.fromLTRB(left, top, right, bottom);

      // Draw neon box
      canvas.drawRRect(
        RRect.fromRectAndRadius(displayRect, const Radius.circular(8)),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(displayRect, const Radius.circular(8)),
        paint,
      );

      // Draw primary label if above threshold
      final labels = obj.labels.where((l) => l.confidence > 0.6).toList();
      if (labels.isNotEmpty) {
        final label = labels.first.text;
        
        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(displayRect.left + 4, displayRect.top + 4));
      }
    }
  }

  @override
  bool shouldRepaint(BoundingBoxPainter oldDelegate) {
    return oldDelegate.objects != objects || oldDelegate.imageSize != imageSize;
  }
}



---END---

FILE lib/services/ai_rotation_manager.dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../models/device_context.dart';
import '../models/explanation.dart';
import 'ai_provider.dart';
import 'providers/localllamaprovider.dart';
import 'providers/offline_provider.dart';
import 'providers/proxy_visual_provider.dart';

/// Manages rotation between AI providers with automatic failover.
class AIRotationManager {
  final List<AIProvider> _providers = [];
  final OfflineProvider _offlineProvider = OfflineProvider();
  int _currentIndex = 0;
  String _lastUsedProvider = '';

  String get lastUsedProvider => _lastUsedProvider;

  void initialize({
    String proxyBaseUrl = '/api/chat',
    String localModelFileName = LocalLlamaProvider.defaultModelFileName,
    String? localModelPath,
  }) {
    _providers.clear();

    final resolvedProxyBaseUrl =
        proxyBaseUrl.trim().isEmpty ? '/api/chat' : proxyBaseUrl.trim();

    _providers.add(LocalLlamaProvider(
      modelFileName: localModelFileName,
      modelPathOverride: localModelPath,
    ));

    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'groq',
      displayName: 'Groq (Llama 4)',
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    ));
    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'gemini',
      displayName: 'Gemini Flash',
      model: 'gemini-2.5-flash',
    ));
    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'together',
      displayName: 'Together (Llama 4)',
      model: 'meta-llama/Llama-4-Scout-17B-16E-Instruct',
    ));
    _providers.add(ProxyVisualAIProvider(
      proxyBaseUrl: resolvedProxyBaseUrl,
      providerId: 'openrouter',
      displayName: 'OpenRouter',
      model: 'google/gemini-2.5-flash',
    ));

    debugPrint(
        '[AI] Initialized ${_providers.length} providers via local + proxy fallback: $resolvedProxyBaseUrl');
  }

  bool get hasOnlineProviders => _providers.any((p) => p.isAvailable);

  /// Analyze image with automatic provider rotation and failover.
  Future<(List<Explanation>, String)> analyzeImage({
    required Uint8List imageBytes,
    required DeviceContext context,
    bool isOffline = false,
  }) async {
    if (isOffline || _providers.isEmpty) {
      final results = await _offlineProvider.analyzeImage(
        imageBytes: imageBytes,
        context: context,
      );
      _lastUsedProvider = _offlineProvider.name;
      debugPrint(
          '[AI] Using offline provider (isOffline=$isOffline, providers=${_providers.length})');
      return (results, _offlineProvider.name);
    }

    final startIndex = _currentIndex % _providers.length;
    for (int i = 0; i < _providers.length; i++) {
      final index = (startIndex + i) % _providers.length;
      final provider = _providers[index];

      if (!provider.isAvailable) {
        debugPrint('[AI] Skipping ${provider.name} (unavailable)');
        continue;
      }

      try {
        final results = await provider.analyzeImage(
          imageBytes: imageBytes,
          context: context,
        );

        if (results.isNotEmpty) {
          _currentIndex = (index + 1) % _providers.length;
          _lastUsedProvider = provider.name;
          return (results, provider.name);
        }
      } catch (e) {
        debugPrint('[AI] Provider ${provider.name} failed: $e');
        continue;
      }
    }

    final results = await _offlineProvider.analyzeImage(
      imageBytes: imageBytes,
      context: context,
    );
    _lastUsedProvider = _offlineProvider.name;
    debugPrint('[AI] All online providers failed, falling back to offline');
    return (results, _offlineProvider.name);
  }
}


---END---

FILE lib/services/providers/offline_provider.dart
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


---END---

