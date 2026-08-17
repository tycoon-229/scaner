import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MsiChecksumScheme {
  auto('AUTO'),
  mod10('MOD_10'),
  mod11('MOD_11'),
  mod1010('MOD_10_10'),
  mod1110('MOD_11_10'),
  mod43('MOD_43'),
  none('NONE');

  const MsiChecksumScheme(this.nativeName);

  final String nativeName;
}

class MsiScanResult {
  const MsiScanResult({
    required this.text,
    required this.durationMs,
    required this.source,
    this.errorCode,
    this.errorMessage,
  });

  const MsiScanResult.empty({this.source = 'unknown'})
    : text = null,
      durationMs = 0,
      errorCode = null,
      errorMessage = null;

  const MsiScanResult.failure({
    required this.source,
    required this.errorCode,
    required this.errorMessage,
  }) : text = null,
       durationMs = 0;

  factory MsiScanResult.fromNative(
    Map<dynamic, dynamic>? value, {
    required String fallbackSource,
  }) {
    if (value == null) {
      return MsiScanResult.empty(source: fallbackSource);
    }

    return MsiScanResult(
      text: value['text'] as String?,
      durationMs: value['durationMs'] as int? ?? 0,
      source: value['source'] as String? ?? fallbackSource,
    );
  }

  final String? text;
  final int durationMs;
  final String source;
  final String? errorCode;
  final String? errorMessage;

  bool get hasResult => text != null && text!.isNotEmpty;
}

class MsiScannerService {
  static const MethodChannel _channel = MethodChannel(
    'com.fpt.yuyama/msi_scanner',
  );

  static Future<MsiScanResult> decodeYuvLuminance(
    Uint8List luminanceBytes, {
    required int imageWidth,
    required int imageHeight,
    int? rowStride,
    MsiChecksumScheme checksumScheme = MsiChecksumScheme.auto,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMapMethod('decodeMsiYuv', <String, dynamic>{
            'imageBytes': luminanceBytes,
            'imageWidth': imageWidth,
            'imageHeight': imageHeight,
            'rowStride': rowStride ?? imageWidth,
            'checksumScheme': checksumScheme.nativeName,
          });
      return MsiScanResult.fromNative(result, fallbackSource: 'yuv');
    } on PlatformException catch (e) {
      debugPrint('MSI YUV decode failed: ${e.code} - ${e.message}');
      return MsiScanResult.failure(
        source: 'yuv',
        errorCode: e.code,
        errorMessage: e.message ?? 'Platform error',
      );
    } on MissingPluginException catch (e) {
      debugPrint('MSI YUV decode is not available on this platform: $e');
      return const MsiScanResult.failure(
        source: 'yuv',
        errorCode: 'MISSING_PLUGIN',
        errorMessage: 'MSI native decoder is not registered',
      );
    }
  }

  static Future<MsiScanResult> decodeBitmapBytes(
    Uint8List imageBytes, {
    MsiChecksumScheme checksumScheme = MsiChecksumScheme.auto,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMapMethod(
        'decodeMsiBitmap',
        <String, dynamic>{
          'imageBytes': imageBytes,
          'checksumScheme': checksumScheme.nativeName,
        },
      );
      return MsiScanResult.fromNative(result, fallbackSource: 'bitmap');
    } on PlatformException catch (e) {
      debugPrint('MSI bitmap decode failed: ${e.code} - ${e.message}');
      return MsiScanResult.failure(
        source: 'bitmap',
        errorCode: e.code,
        errorMessage: e.message ?? 'Platform error',
      );
    } on MissingPluginException catch (e) {
      debugPrint('MSI bitmap decode is not available on this platform: $e');
      return const MsiScanResult.failure(
        source: 'bitmap',
        errorCode: 'MISSING_PLUGIN',
        errorMessage: 'MSI native decoder is not registered',
      );
    }
  }
}
