import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MsiScannerService {
  static const MethodChannel _channel =
  MethodChannel('com.example/msi_scanner');

  static Future<String?> decodeMsiYuv(
      Uint8List yuvBytes, {
        required int imageWidth,
        required int imageHeight,
      }) async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'decodeMsiYuv',
        <String, dynamic>{
          'imageBytes': yuvBytes,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
        },
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint(
          'Error PlatformChannel decode YUV MSI: ${e.code} - ${e.message}');
      return null;
    }
  }

  static Future<String?> decodeMsiBitmap(
      Uint8List imageBytes, {
        int imageWidth = 0,
        int imageHeight = 0,
      }) async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'decodeMsiBitmap',
        <String, dynamic>{
          'imageBytes': imageBytes,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
        },
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint(
          'Error PlatformChannel decode image MSI: ${e.code} - ${e.message}');
      return null;
    }
  }
}
