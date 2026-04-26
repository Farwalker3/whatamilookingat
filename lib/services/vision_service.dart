import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Service for fast, on-device computer vision using Google ML Kit.
class VisionService {
  late final ObjectDetector _objectDetector;
  late final TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    _isInitialized = true;
  }

  /// Quickly detect objects and text in a camera frame.
  Future<List<String>> detectLabels(CameraImage image, int sensorOrientation) async {
    if (!_isInitialized) await initialize();

    try {
      final inputImage = _buildInputImage(image, sensorOrientation);
      if (inputImage == null) return [];

      final results = await Future.wait([
        _objectDetector.processImage(inputImage),
        _textRecognizer.processImage(inputImage),
      ]);

      final objects = results[0] as List<DetectedObject>;
      final visionText = results[1] as RecognizedText;

      final labels = <String>{};

      for (final obj in objects) {
        for (final label in obj.labels) {
          if (label.confidence > 0.5) {
            labels.add(label.text);
          }
        }
      }

      if (visionText.text.isNotEmpty) {
        final cleanedText = visionText.text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleanedText.isNotEmpty) {
          labels.add('EXACT OCR TEXT IN IMAGE: """$cleanedText""" (Treat this as absolute truth, DO NOT guess)');
        }
      }

      return labels.toList();
    } catch (e) {
      return [];
    }
  }

  /// Extremely fast, targeted object detection strictly for AR Bounding Box rendering.
  Future<List<DetectedObject>> detectObjectsRealtime(CameraImage image, int sensorOrientation) async {
    if (!_isInitialized) await initialize();

    try {
      final inputImage = _buildInputImage(image, sensorOrientation);
      if (inputImage == null) return [];

      return await _objectDetector.processImage(inputImage);
    } catch (_) {
      return [];
    }
  }

  /// Analyze an image from a file path.
  Future<List<String>> detectLabelsFromPath(String path) async {
    if (!_isInitialized) await initialize();

    try {
      final inputImage = InputImage.fromFilePath(path);

      final results = await Future.wait([
        _objectDetector.processImage(inputImage),
        _textRecognizer.processImage(inputImage),
      ]);

      final objects = results[0] as List<DetectedObject>;
      final visionText = results[1] as RecognizedText;

      final labels = <String>{};

      for (final obj in objects) {
        for (final label in obj.labels) {
          if (label.confidence > 0.5) {
            labels.add(label.text);
          }
        }
      }

      if (visionText.text.isNotEmpty) {
        final cleanedText = visionText.text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleanedText.isNotEmpty) {
          labels.add('EXACT OCR TEXT IN IMAGE: """$cleanedText""" (Treat this as absolute truth, DO NOT guess)');
        }
      }

      return labels.toList();
    } catch (_) {
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
          size: const Size(640, 480),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: 640 * 4,
        ),
      );

      final results = await Future.wait([
        _objectDetector.processImage(inputImage),
        _textRecognizer.processImage(inputImage),
      ]);

      final objects = results[0] as List<DetectedObject>;
      final visionText = results[1] as RecognizedText;
      
      final labels = objects
          .expand((o) => o.labels)
          .where((l) => l.confidence > 0.5)
          .map((l) => l.text)
          .toSet()
          .toList();

      if (visionText.text.isNotEmpty) {
        final cleanedText = visionText.text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleanedText.isNotEmpty) {
          labels.add('EXACT OCR TEXT IN IMAGE: """$cleanedText""" (Treat this as absolute truth, DO NOT guess)');
        }
      }

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
