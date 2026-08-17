import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Gs1CompositeScanResult {
  const Gs1CompositeScanResult({
    required this.text,
    required this.primary1dText,
    required this.composite2dText,
    required this.symbology,
    required this.durationMs,
    required this.source,
    this.errorCode,
    this.errorMessage,
  });

  const Gs1CompositeScanResult.empty({this.source = 'unknown'})
      : text = null,
        primary1dText = null,
        composite2dText = null,
        symbology = 'None',
        durationMs = 0,
        errorCode = null,
        errorMessage = null;

  const Gs1CompositeScanResult.failure({
    required this.source,
    required this.errorCode,
    required this.errorMessage,
  })  : text = null,
        primary1dText = null,
        composite2dText = null,
        symbology = 'Error',
        durationMs = 0;

  factory Gs1CompositeScanResult.fromNative(
    Map<dynamic, dynamic>? value, {
    required String fallbackSource,
  }) {
    if (value == null) {
      return Gs1CompositeScanResult.empty(source: fallbackSource);
    }

    return Gs1CompositeScanResult(
      text: value['text'] as String?,
      primary1dText: value['primary1dText'] as String?,
      composite2dText: value['composite2dText'] as String?,
      symbology: value['symbology'] as String? ?? 'GS1 Composite',
      durationMs: value['durationMs'] as int? ?? 0,
      source: value['source'] as String? ?? fallbackSource,
    );
  }

  final String? text;
  final String? primary1dText;
  final String? composite2dText;
  final String symbology;
  final int durationMs;
  final String source;
  final String? errorCode;
  final String? errorMessage;

  bool get hasResult => text != null && text!.isNotEmpty;
}

class Gs1CompositeScannerService {
  static const MethodChannel _channel = MethodChannel(
    'com.fpt.yuyama/gs1_composite_scanner',
  );

  static Future<Gs1CompositeScanResult> decodeYuvLuminance(
    Uint8List luminanceBytes, {
    required int imageWidth,
    required int imageHeight,
    int? rowStride,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMapMethod('decodeGs1CompositeYuv', <String, dynamic>{
        'imageBytes': luminanceBytes,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'rowStride': rowStride ?? imageWidth,
      });
      return Gs1CompositeScanResult.fromNative(result, fallbackSource: 'yuv');
    } on PlatformException catch (e) {
      debugPrint('GS1 Composite YUV decode failed: ${e.code} - ${e.message}');
      return Gs1CompositeScanResult.failure(
        source: 'yuv',
        errorCode: e.code,
        errorMessage: e.message ?? 'Platform error',
      );
    } on MissingPluginException catch (e) {
      debugPrint('GS1 Composite native decoder is not available: $e');
      return const Gs1CompositeScanResult.failure(
        source: 'yuv',
        errorCode: 'MISSING_PLUGIN',
        errorMessage: 'GS1 Composite native decoder is not registered',
      );
    }
  }

  static Future<Gs1CompositeScanResult> decodeBitmapBytes(
    Uint8List imageBytes,
  ) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMapMethod(
        'decodeGs1CompositeBitmap',
        <String, dynamic>{
          'imageBytes': imageBytes,
        },
      );
      return Gs1CompositeScanResult.fromNative(result, fallbackSource: 'bitmap');
    } on PlatformException catch (e) {
      debugPrint('GS1 Composite bitmap decode failed: ${e.code} - ${e.message}');
      return Gs1CompositeScanResult.failure(
        source: 'bitmap',
        errorCode: e.code,
        errorMessage: e.message ?? 'Platform error',
      );
    } on MissingPluginException catch (e) {
      debugPrint('GS1 Composite native decoder is not available: $e');
      return const Gs1CompositeScanResult.failure(
        source: 'bitmap',
        errorCode: 'MISSING_PLUGIN',
        errorMessage: 'GS1 Composite native decoder is not registered',
      );
    }
  }
}
