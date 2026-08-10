import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:scandit_flutter_datacapture_barcode/scandit_flutter_datacapture_barcode.dart';
import 'code_format_extensions.dart';

extension ScanditBarcodeExtension on Barcode {
  Code toCode({int duration = 0}) {
    final textStr = data ?? rawData;
    final symbologyStr = symbology.toString();
    return Code(
      text: textStr,
      format: symbologyStr.toZxingFormat,
      isValid: textStr.isNotEmpty,
      duration: duration,
    );
  }
}

extension ScanditBarcodeListExtension on List<Barcode> {
  Codes toCodes({int duration = 0}) {
    final list = <Code>[];
    for (final b in this) {
      final textStr = b.data ?? b.rawData;
      if (textStr.isNotEmpty) {
        list.add(b.toCode(duration: duration));
      }
    }
    return Codes(
      codes: list,
      duration: duration,
    );
  }
}
