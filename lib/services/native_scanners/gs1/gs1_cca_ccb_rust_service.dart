import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_detected_code.dart';

class Gs1CcaCcbRustScanResult {
  const Gs1CcaCcbRustScanResult({
    required this.codes,
    required this.durationMs,
    required this.nativeDurationMs,
    required this.source,
    required this.warnings,
  });

  factory Gs1CcaCcbRustScanResult.fromNative(Map<dynamic, dynamic>? value) {
    if (value == null) {
      return const Gs1CcaCcbRustScanResult.empty(
        warnings: <String>['Rust CC-A/B decoder returned no payload'],
      );
    }

    final List<dynamic> rawCodes = value['codes'] as List<dynamic>? ?? const [];
    final List<dynamic> rawWarnings =
        value['warnings'] as List<dynamic>? ?? const [];
    final String? warning = value['warning'] as String?;

    return Gs1CcaCcbRustScanResult(
      codes: rawCodes
          .whereType<Map<dynamic, dynamic>>()
          .map(Gs1CcaCcbRustDetectedCode.fromNative)
          .toList(),
      durationMs: value['durationMs'] as int? ?? 0,
      nativeDurationMs: value['nativeDurationMs'] as int? ?? 0,
      source: value['source'] as String? ?? 'rust-gs1-cca-ccb',
      warnings: <String>[
        ...rawWarnings.whereType<String>(),
        if (warning != null && warning.isNotEmpty) warning,
      ],
    );
  }

  const Gs1CcaCcbRustScanResult.empty({this.warnings = const <String>[]})
    : codes = const <Gs1CcaCcbRustDetectedCode>[],
      durationMs = 0,
      nativeDurationMs = 0,
      source = 'rust-gs1-cca-ccb';

  final List<Gs1CcaCcbRustDetectedCode> codes;
  final int durationMs;
  final int nativeDurationMs;
  final String source;
  final List<String> warnings;

  bool get hasCandidates => codes.isNotEmpty;
}

class Gs1CcaCcbRustDetectedCode {
  const Gs1CcaCcbRustDetectedCode({
    required this.source,
    required this.text,
    required this.format,
    required this.formatName,
    required this.rawBytes,
    required this.position,
  });

  factory Gs1CcaCcbRustDetectedCode.fromNative(Map<dynamic, dynamic> value) {
    final int imageWidth = value['imageWidth'] as int? ?? 0;
    final int imageHeight = value['imageHeight'] as int? ?? 0;

    return Gs1CcaCcbRustDetectedCode(
      source: value['source'] as String? ?? 'rust',
      text: value['text'] as String?,
      format: value['format'] as int?,
      formatName: value['formatName'] as String?,
      rawBytes: _rawBytesFromNative(value['rawBytes']),
      position: imageWidth <= 0 || imageHeight <= 0
          ? null
          : Gs1DetectedPosition(
              imageWidth: imageWidth,
              imageHeight: imageHeight,
              topLeftX: value['topLeftX'] as int? ?? 0,
              topLeftY: value['topLeftY'] as int? ?? 0,
              topRightX: value['topRightX'] as int? ?? 0,
              topRightY: value['topRightY'] as int? ?? 0,
              bottomLeftX: value['bottomLeftX'] as int? ?? 0,
              bottomLeftY: value['bottomLeftY'] as int? ?? 0,
              bottomRightX: value['bottomRightX'] as int? ?? 0,
              bottomRightY: value['bottomRightY'] as int? ?? 0,
            ),
    );
  }

  final String source;
  final String? text;
  final int? format;
  final String? formatName;
  final List<int>? rawBytes;
  final Gs1DetectedPosition? position;

  Gs1DetectedCode toGs1DetectedCode() {
    return Gs1DetectedCode(
      text: text,
      format: format ?? Gs1DetectedFormat.fromName(formatName),
      isValid: true,
      rawBytes: rawBytes,
      position: position,
    );
  }

  static List<int>? _rawBytesFromNative(dynamic value) {
    if (value == null) return null;
    if (value is Uint8List) return value.toList(growable: false);
    if (value is List<int>) return List<int>.from(value, growable: false);
    if (value is List<dynamic>) {
      return value.cast<int>().toList(growable: false);
    }
    return null;
  }
}

class Gs1CcaCcbRustScannerService {
  static const MethodChannel _channel = MethodChannel(
    'com.fpt.yuyama/gs1_cca_ccb_rust_scanner',
  );

  static Future<Gs1CcaCcbRustScanResult> decodeYuvLuminance(
    CameraImage image,
    Gs1DetectedPosition? linearHint,
  ) async {
    if (!Platform.isAndroid) {
      return const Gs1CcaCcbRustScanResult.empty(
        warnings: <String>['Rust CC-A/B scanner is Android-only in this POC'],
      );
    }
    if (image.planes.isEmpty) {
      return const Gs1CcaCcbRustScanResult.empty(
        warnings: <String>['Camera frame has no Y plane'],
      );
    }

    try {
      final Plane yPlane = image.planes.first;
      final Map<String, int>? hint = _hintBounds(linearHint);
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMapMethod('decodeCcaCcbYuv', <String, dynamic>{
            'imageBytes': yPlane.bytes,
            'imageWidth': image.width,
            'imageHeight': image.height,
            'rowStride': yPlane.bytesPerRow,
            if (hint != null) ...hint,
          });
      return Gs1CcaCcbRustScanResult.fromNative(result);
    } on PlatformException catch (e) {
      debugPrint('Rust CC-A/B decode failed: ${e.code} - ${e.message}');
      return Gs1CcaCcbRustScanResult.empty(
        warnings: <String>[e.message ?? e.code],
      );
    } on MissingPluginException catch (e) {
      debugPrint('Rust CC-A/B scanner is not registered: $e');
      return const Gs1CcaCcbRustScanResult.empty(
        warnings: <String>['Rust CC-A/B scanner is not registered'],
      );
    }
  }

  static Map<String, int>? _hintBounds(Gs1DetectedPosition? position) {
    if (position == null) return null;
    final List<int> xs = <int>[
      position.topLeftX,
      position.topRightX,
      position.bottomLeftX,
      position.bottomRightX,
    ]..sort();
    final List<int> ys = <int>[
      position.topLeftY,
      position.topRightY,
      position.bottomLeftY,
      position.bottomRightY,
    ]..sort();
    final int left = xs.first;
    final int top = ys.first;
    final int right = xs.last;
    final int bottom = ys.last;
    if (right <= left || bottom <= top) return null;

    return <String, int>{
      'hintLeft': left,
      'hintTop': top,
      'hintRight': right,
      'hintBottom': bottom,
    };
  }
}
