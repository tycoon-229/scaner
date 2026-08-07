import 'package:dynamsoft_barcode_reader_bundle_flutter/dynamsoft_barcode_reader_bundle_flutter.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'code_format_extensions.dart';

extension DynamsoftScanResultExtension on BarcodeScanResult {
  Code? toSingleCode({int duration = 0}) {
    if (barcodes != null && barcodes!.isNotEmpty && barcodes![0] != null) {
      final b = barcodes![0]!;
      final textStr = b.text?.toString();
      final formatStr = b.formatString?.toString();
      return Code(
        text: textStr,
        format: formatStr.toZxingFormat,
        isValid: textStr != null && textStr.isNotEmpty,
        duration: duration,
      );
    }
    return null;
  }

  Codes toCodes({int duration = 0}) {
    final list = <Code>[];
    if (barcodes != null) {
      for (final b in barcodes!) {
        if (b != null) {
          final textStr = b.text?.toString();
          final formatStr = b.formatString?.toString();
          if (textStr != null && textStr.isNotEmpty) {
            list.add(Code(
              text: textStr,
              format: formatStr.toZxingFormat,
              isValid: true,
              duration: duration,
            ));
          }
        }
      }
    }
    return Codes(
      codes: list,
      duration: duration,
    );
  }
}
