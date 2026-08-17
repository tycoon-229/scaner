import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'package:poc_multi_scan/services/gs1_composite_scanner_service.dart';

class Gs1CompositeScanCandidate {
  const Gs1CompositeScanCandidate({
    required this.text,
    required this.primary1dText,
    required this.composite2dText,
    required this.symbology,
    required this.durationMs,
    required this.source,
  });

  final String text;
  final String? primary1dText;
  final String? composite2dText;
  final String symbology;
  final int durationMs;
  final String source;
}

class Gs1CompositeCoordinator {
  Gs1CompositeCoordinator({
    this.minAttemptInterval = const Duration(milliseconds: 100),
    this.requiredConsecutiveMatches = 1,
  });

  final Duration minAttemptInterval;
  final int requiredConsecutiveMatches;

  bool _isProcessing = false;
  DateTime _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastCandidateText;
  int _candidateMatchCount = 0;

  /// Decodes GS1 Composite barcode directly from live Flutter [CameraImage] frame.
  Future<Gs1CompositeScanCandidate?> scanCameraImage(CameraImage image) async {
    if (_isProcessing) return null;
    if (DateTime.now().difference(_lastAttemptAt) < minAttemptInterval) {
      return null;
    }

    _isProcessing = true;
    _lastAttemptAt = DateTime.now();

    try {
      if (image.planes.isEmpty) return null;

      final Uint8List yuvBytes = image.planes[0].bytes;
      final int rowStride = image.planes[0].bytesPerRow;

      final Gs1CompositeScanResult result =
          await Gs1CompositeScannerService.decodeYuvLuminance(
        yuvBytes,
        imageWidth: image.width,
        imageHeight: image.height,
        rowStride: rowStride,
      );

      if (!result.hasResult) return null;
      if (!_isConfirmedCandidate(result.text!)) return null;

      return Gs1CompositeScanCandidate(
        text: result.text!,
        primary1dText: result.primary1dText,
        composite2dText: result.composite2dText,
        symbology: result.symbology,
        durationMs: result.durationMs,
        source: result.source,
      );
    } finally {
      _isProcessing = false;
    }
  }

  /// Decodes GS1 Composite barcode from a local image file path.
  Future<Gs1CompositeScanCandidate?> scanImageFile(String path) async {
    final File imageFile = File(path);
    if (!await imageFile.exists()) return null;

    final Gs1CompositeScanResult result =
        await Gs1CompositeScannerService.decodeBitmapBytes(
      await imageFile.readAsBytes(),
    );

    if (!result.hasResult) return null;
    return Gs1CompositeScanCandidate(
      text: result.text!,
      primary1dText: result.primary1dText,
      composite2dText: result.composite2dText,
      symbology: result.symbology,
      durationMs: result.durationMs,
      source: result.source,
    );
  }

  void reset() {
    _isProcessing = false;
    _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCandidateText = null;
    _candidateMatchCount = 0;
  }

  bool _isConfirmedCandidate(String text) {
    if (requiredConsecutiveMatches <= 1) return true;

    if (text == _lastCandidateText) {
      _candidateMatchCount++;
    } else {
      _lastCandidateText = text;
      _candidateMatchCount = 1;
    }

    if (_candidateMatchCount < requiredConsecutiveMatches) return false;

    _lastCandidateText = null;
    _candidateMatchCount = 0;
    return true;
  }
}
