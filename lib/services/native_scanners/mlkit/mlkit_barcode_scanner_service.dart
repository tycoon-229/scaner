import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_detected_code.dart';

class MlKitBarcodeScanResult {
  const MlKitBarcodeScanResult({
    required this.codes,
    required this.durationMs,
    required this.source,
    this.warning,
  });

  factory MlKitBarcodeScanResult.fromNative(Map<dynamic, dynamic>? value) {
    if (value == null) {
      return const MlKitBarcodeScanResult.empty(
        warning: 'ML Kit returned no payload',
      );
    }

    final List<dynamic> rawCodes = value['codes'] as List<dynamic>? ?? const [];
    return MlKitBarcodeScanResult(
      codes: rawCodes
          .whereType<Map<dynamic, dynamic>>()
          .map(MlKitDetectedBarcode.fromNative)
          .toList(),
      durationMs: value['durationMs'] as int? ?? 0,
      source: value['source'] as String? ?? 'mlkit',
    );
  }

  const MlKitBarcodeScanResult.empty({this.warning})
    : codes = const <MlKitDetectedBarcode>[],
      durationMs = 0,
      source = 'mlkit';

  const MlKitBarcodeScanResult.failure({required this.warning})
    : codes = const <MlKitDetectedBarcode>[],
      durationMs = 0,
      source = 'mlkit';

  final List<MlKitDetectedBarcode> codes;
  final int durationMs;
  final String source;
  final String? warning;

  bool get hasCandidates => codes.isNotEmpty;
}

class MlKitDetectedBarcode {
  const MlKitDetectedBarcode({
    required this.format,
    required this.rawValue,
    required this.rawBytes,
    required this.position,
  });

  factory MlKitDetectedBarcode.fromNative(Map<dynamic, dynamic> value) {
    final String? format = value['format'] as String?;
    final int imageWidth = value['imageWidth'] as int? ?? 0;
    final int imageHeight = value['imageHeight'] as int? ?? 0;
    final List<dynamic>? corners = value['cornerPoints'] as List<dynamic>?;
    final Map<dynamic, dynamic>? box = value['boundingBox'] == null
        ? null
        : Map<dynamic, dynamic>.from(value['boundingBox'] as Map);

    return MlKitDetectedBarcode(
      format: format,
      rawValue: value['rawValue'] as String?,
      rawBytes: _rawBytesFromNative(value['rawBytes']),
      position: _positionFromNative(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        corners: corners,
        box: box,
      ),
    );
  }

  final String? format;
  final String? rawValue;
  final List<int>? rawBytes;
  final Gs1DetectedPosition? position;

  Gs1DetectedCode toGs1DetectedCode() {
    return Gs1DetectedCode(
      text: rawValue,
      format: Gs1DetectedFormat.fromName(format),
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

  static Gs1DetectedPosition? _positionFromNative({
    required int imageWidth,
    required int imageHeight,
    required List<dynamic>? corners,
    required Map<dynamic, dynamic>? box,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    if (corners != null && corners.length >= 4) {
      final List<Map<dynamic, dynamic>> points = corners
          .take(4)
          .map((dynamic point) => Map<dynamic, dynamic>.from(point as Map))
          .toList();
      return Gs1DetectedPosition(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        topLeftX: points[0]['x'] as int? ?? 0,
        topLeftY: points[0]['y'] as int? ?? 0,
        topRightX: points[1]['x'] as int? ?? 0,
        topRightY: points[1]['y'] as int? ?? 0,
        bottomRightX: points[2]['x'] as int? ?? 0,
        bottomRightY: points[2]['y'] as int? ?? 0,
        bottomLeftX: points[3]['x'] as int? ?? 0,
        bottomLeftY: points[3]['y'] as int? ?? 0,
      );
    }

    if (box == null) return null;
    final int left = box['left'] as int? ?? 0;
    final int top = box['top'] as int? ?? 0;
    final int right = box['right'] as int? ?? left;
    final int bottom = box['bottom'] as int? ?? top;
    return Gs1DetectedPosition(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      topLeftX: left,
      topLeftY: top,
      topRightX: right,
      topRightY: top,
      bottomRightX: right,
      bottomRightY: bottom,
      bottomLeftX: left,
      bottomLeftY: bottom,
    );
  }
}

class MlKitBarcodeScannerService {
  static const MethodChannel _channel = MethodChannel(
    'com.fpt.yuyama/mlkit_barcode_scanner',
  );

  static Future<MlKitBarcodeScanResult> decodeYuv420(
    CameraImage image, {
    int rotationDegrees = 0,
  }) async {
    if (!Platform.isAndroid) {
      return const MlKitBarcodeScanResult.empty(
        warning: 'ML Kit barcode scanner is Android-only in this POC',
      );
    }
    if (image.planes.length < 3) {
      return const MlKitBarcodeScanResult.empty(
        warning: 'ML Kit requires a 3-plane YUV420 camera image',
      );
    }

    try {
      final Plane yPlane = image.planes[0];
      final Plane uPlane = image.planes[1];
      final Plane vPlane = image.planes[2];
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMapMethod('decodeYuv420', <String, dynamic>{
            'yBytes': yPlane.bytes,
            'uBytes': uPlane.bytes,
            'vBytes': vPlane.bytes,
            'imageWidth': image.width,
            'imageHeight': image.height,
            'yRowStride': yPlane.bytesPerRow,
            'yPixelStride': yPlane.bytesPerPixel ?? 1,
            'uRowStride': uPlane.bytesPerRow,
            'uPixelStride': uPlane.bytesPerPixel ?? 1,
            'vRowStride': vPlane.bytesPerRow,
            'vPixelStride': vPlane.bytesPerPixel ?? 1,
            'rotationDegrees': rotationDegrees,
          });
      return MlKitBarcodeScanResult.fromNative(result);
    } on PlatformException catch (e) {
      debugPrint('ML Kit barcode decode failed: ${e.code} - ${e.message}');
      return MlKitBarcodeScanResult.failure(warning: e.message ?? e.code);
    } on MissingPluginException catch (e) {
      debugPrint('ML Kit barcode scanner is not registered: $e');
      return const MlKitBarcodeScanResult.failure(
        warning: 'ML Kit barcode scanner is not registered',
      );
    }
  }
}
