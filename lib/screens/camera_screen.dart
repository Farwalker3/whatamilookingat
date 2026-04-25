import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        imageFormatGroup: ImageFormatGroup.jpeg,
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
      body: Stack(
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
    );
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
                child: CameraPreview(_cameraController!),
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
                _buildLoadingCard()
              else if (provider.errorMessage != null)
                _buildErrorCard(provider.errorMessage!)
              else
                _buildWelcomeCard(),

              const SizedBox(height: 12),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Upload button
                  _buildActionButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Upload',
                    onTap: provider.analyzeUploadedImage,
                    color: AppTheme.secondary,
                  ),

                  // Capture / Unfreeze button
                  _buildCaptureButton(provider),

                  // Share button (when frozen)
                  _buildActionButton(
                    icon: provider.isFrozen
                        ? Icons.play_arrow_rounded
                        : Icons.info_outline_rounded,
                    label: provider.isFrozen ? 'Resume' : 'About',
                    onTap: provider.isFrozen
                        ? provider.unfreezeFrame
                        : () => _showAboutDialog(context),
                    color: provider.isFrozen ? AppTheme.accent : AppTheme.textMuted,
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

  Widget _buildLoadingCard() {
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
