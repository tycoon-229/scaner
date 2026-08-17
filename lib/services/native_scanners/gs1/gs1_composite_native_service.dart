import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Gs1CompositeNativeResult {
  const Gs1CompositeNativeResult({
    required this.hasResult,
    required this.text,
    required this.durationMs,
    required this.source,
    required this.typeEstimate,
    required this.confidence,
    required this.raw,
    required this.warning,
  });

  factory Gs1CompositeNativeResult.fromNative(Map<dynamic, dynamic>? value) {
    if (value == null) {
      return const Gs1CompositeNativeResult.empty(
        warning: 'Native decoder returned no payload',
      );
    }

    return Gs1CompositeNativeResult(
      hasResult: value['hasResult'] as bool? ?? false,
      text: value['text'] as String?,
      durationMs: value['durationMs'] as int? ?? 0,
      source: value['source'] as String? ?? 'unknown',
      typeEstimate: value['typeEstimate'] as String?,
      confidence: value['confidence'] as double?,
      raw: Map<dynamic, dynamic>.from(value),
      warning: value['warning'] as String?,
    );
  }

  const Gs1CompositeNativeResult.empty({this.warning})
    : hasResult = false,
      text = null,
      durationMs = 0,
      source = 'unknown',
      typeEstimate = null,
      confidence = null,
      raw = const <dynamic, dynamic>{};

  const Gs1CompositeNativeResult.failure({
    required this.source,
    required this.warning,
  }) : hasResult = false,
       text = null,
       durationMs = 0,
       typeEstimate = null,
       confidence = null,
       raw = const <dynamic, dynamic>{};

  final bool hasResult;
  final String? text;
  final int durationMs;
  final String source;
  final String? typeEstimate;
  final double? confidence;
  final Map<dynamic, dynamic> raw;
  final String? warning;
}

class Gs1CompositeNativeService {
  static const MethodChannel _channel = MethodChannel(
    'com.fpt.yuyama/gs1_composite_scanner',
  );

  static Future<Gs1CompositeNativeResult> decodeYuvLuminance(
    Uint8List luminanceBytes, {
    required int imageWidth,
    required int imageHeight,
    int? rowStride,
    String? imageFormatGroup,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMapMethod('decodeCompositeYuv', <String, dynamic>{
            'imageBytes': luminanceBytes,
            'imageWidth': imageWidth,
            'imageHeight': imageHeight,
            'rowStride': rowStride ?? imageWidth,
            'imageFormatGroup': imageFormatGroup,
          });
      return Gs1CompositeNativeResult.fromNative(result);
    } on PlatformException catch (e) {
      debugPrint('GS1 Composite YUV decode failed: ${e.code} - ${e.message}');
      return Gs1CompositeNativeResult.failure(
        source: 'yuv',
        warning: e.message ?? e.code,
      );
    } on MissingPluginException catch (e) {
      debugPrint('GS1 Composite native decoder is not registered: $e');
      return const Gs1CompositeNativeResult.failure(
        source: 'yuv',
        warning: 'GS1 Composite native decoder is not registered',
      );
    }
  }

  static Future<Gs1CompositeNativeResult> decodeBitmapPath(String path) async {
    try {
      final Uint8List imageBytes = await File(path).readAsBytes();
      return await decodeBitmapBytes(imageBytes);
    } on Exception catch (e) {
      debugPrint('GS1 Composite bitmap file read failed: $e');
      return Gs1CompositeNativeResult.failure(
        source: 'bitmap',
        warning: 'Failed to read bitmap bytes: $e',
      );
    }
  }

  static Future<Gs1CompositeNativeResult> decodeBitmapBytes(
    Uint8List imageBytes,
  ) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMapMethod(
        'decodeCompositeBitmap',
        <String, dynamic>{'imageBytes': imageBytes},
      );
      return Gs1CompositeNativeResult.fromNative(result);
    } on PlatformException catch (e) {
      debugPrint(
        'GS1 Composite bitmap decode failed: ${e.code} - ${e.message}',
      );
      return Gs1CompositeNativeResult.failure(
        source: 'bitmap',
        warning: e.message ?? e.code,
      );
    } on MissingPluginException catch (e) {
      debugPrint('GS1 Composite native decoder is not registered: $e');
      return const Gs1CompositeNativeResult.failure(
        source: 'bitmap',
        warning: 'GS1 Composite native decoder is not registered',
      );
    }
  }
}
