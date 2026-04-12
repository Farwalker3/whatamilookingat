import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Service for fast, on-device computer vision using Google ML Kit.
class VisionService {
  late final ObjectDetector _objectDetector;
  late final TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize Object Detector
    final options = ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    // Initialize Text Recognizer
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    _isInitialized = true;
  }

  /// Quickly detect objects and text in a camera frame.
  Future<List<String>> detectLabels(CameraImage image, int sensorOrientation) async {
    if (!_isInitialized) await initialize();

    try {
      final inputImage = _buildInputImage(image, sensorOrientation);
      if (inputImage == null) return [];

      // Run detection in parallel
      final results = await Future.wait([
        _objectDetector.processImage(inputImage),
        _textRecognizer.processImage(inputImage),
      ]);

      final objects = results[0] as List<DetectedObject>;
      final visionText = results[1] as RecognizedText;

      final labels = <String>{};

      // Add object labels
      for (final obj in objects) {
        for (final label in obj.labels) {
          if (label.confidence > 0.5) {
            labels.add(label.text);
          }
        }
      }

      // Add prominent text snippets
      if (visionText.text.isNotEmpty) {
        final lines = visionText.blocks.take(2).map((b) => b.text).toList();
        for (final line in lines) {
          if (line.length < 30) labels.add('Text: "$line"');
        }
      }

      return labels.toList();
    } catch (e) {
      return [];
    }
  }

  /// Analyze a static image byte array.
  Future<List<String>> detectLabelsFromBytes(Uint8List bytes) async {
    if (!_isInitialized) await initialize();

    try {
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: const Size(640, 480), // Approximated
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888, // Standard for bytes
          bytesPerRow: 640 * 4,
        ),
      );

      final results = await Future.wait([
        _objectDetector.processImage(inputImage),
        _textRecognizer.processImage(inputImage),
      ]);

      final objects = results[0] as List<DetectedObject>;
      final labels = objects
          .expand((o) => o.labels)
          .where((l) => l.confidence > 0.5)
          .map((l) => l.text)
          .toSet()
          .toList();

      return labels;
    } catch (_) {
      return [];
    }
  }

  InputImage? _buildInputImage(CameraImage image, int sensorOrientation) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final InputImageRotation rotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg;

      final InputImageFormat format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final planeData = image.planes.map(
        (Plane plane) {
          return InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          );
        },
      ).toList();

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _objectDetector.close();
    _textRecognizer.close();
  }
}
