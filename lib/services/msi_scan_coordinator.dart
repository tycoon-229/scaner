import 'dart:io';

import 'package:flutter_zxing/flutter_zxing.dart';

import 'package:poc_multi_scan/services/msi_scanner_service.dart';

class MsiScanCandidate {
  const MsiScanCandidate({
    required this.text,
    required this.durationMs,
    required this.source,
  });

  final String text;
  final int durationMs;
  final String source;
}

class MsiScanCoordinator {
  MsiScanCoordinator({
    this.minAttemptInterval = const Duration(milliseconds: 150),
    this.requiredConsecutiveMatches = 2,
    this.checksumScheme = MsiChecksumScheme.auto,
  });

  final Duration minAttemptInterval;
  final int requiredConsecutiveMatches;
  final MsiChecksumScheme checksumScheme;

  bool _isProcessing = false;
  DateTime _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastCandidateText;
  int _candidateMatchCount = 0;

  Future<MsiScanCandidate?> scanProcessedImage(Code code) async {
    if (!_canAttemptProcessedImage(code)) return null;

    _isProcessing = true;
    _lastAttemptAt = DateTime.now();

    try {
      final MsiScanResult result = await MsiScannerService.decodeYuvLuminance(
        code.imageBytes!,
        imageWidth: code.imageWidth!,
        imageHeight: code.imageHeight!,
        rowStride: code.imageWidth,
        checksumScheme: checksumScheme,
      );

      if (!result.hasResult) return null;
      if (!_isConfirmedCandidate(result.text!)) return null;

      return MsiScanCandidate(
        text: result.text!,
        durationMs: result.durationMs,
        source: result.source,
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<MsiScanCandidate?> scanImageFile(String path) async {
    final File imageFile = File(path);
    if (!await imageFile.exists()) return null;

    final MsiScanResult result = await MsiScannerService.decodeBitmapBytes(
      await imageFile.readAsBytes(),
      checksumScheme: checksumScheme,
    );

    if (!result.hasResult) return null;
    return MsiScanCandidate(
      text: result.text!,
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

  bool _canAttemptProcessedImage(Code code) {
    if (_isProcessing) return false;
    if (DateTime.now().difference(_lastAttemptAt) < minAttemptInterval) {
      return false;
    }
    return code.imageBytes != null &&
        code.imageBytes!.isNotEmpty &&
        code.imageWidth != null &&
        code.imageWidth! > 0 &&
        code.imageHeight != null &&
        code.imageHeight! > 0;
  }

  bool _isConfirmedCandidate(String text) {
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
