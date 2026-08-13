import 'package:flutter_zxing/flutter_zxing.dart';

abstract class FormatMsi {
  static const int msiCode = 9999;
}

abstract class CustomFormat {
  static const int msiCode = 9999;
  static const int industrial25 = 9998;
  static const int matrix25 = 9997;
  static const int code11 = 9996;
  static const int code32 = 9995;
  static const int dotcode = 9994;
  static const int telepen = 9993;
  static const int pharmacode = 9992;
  static const int patchcode = 9991;
  static const int uspsIntelligentMail = 9990;
  static const int postnet = 9989;
  static const int planet = 9988;
  static const int australianPost = 9987;
  static const int rm4scc = 9986;
  static const int kix = 9985;
}

extension SafeCodeFormatExt on int {
  String get safeFormatName {
    switch (this) {
      case FormatMsi.msiCode:
        return 'MSI Code';
      case CustomFormat.industrial25:
        return 'Industrial 2 of 5';
      case CustomFormat.matrix25:
        return 'Matrix 2 of 5';
      case CustomFormat.code11:
        return 'Code 11';
      case CustomFormat.code32:
        return 'Code 32';
      case CustomFormat.dotcode:
        return 'DotCode';
      case CustomFormat.telepen:
        return 'Telepen';
      case CustomFormat.pharmacode:
        return 'Pharmacode';
      case CustomFormat.patchcode:
        return 'Patchcode';
      case CustomFormat.uspsIntelligentMail:
        return 'USPS Intelligent Mail';
      case CustomFormat.postnet:
        return 'Postnet';
      case CustomFormat.planet:
        return 'Planet';
      case CustomFormat.australianPost:
        return 'Australian Post';
      case CustomFormat.rm4scc:
        return 'RM4SCC';
      case CustomFormat.kix:
        return 'KIX Code';
      default:
        return name;
    }
  }
}

extension CodeFormatNameExt on Code {
  String? get formatName => format?.safeFormatName;
}

extension DynamsoftFormatStringExt on String? {
  int? get toZxingFormat {
    if (this == null || this!.isEmpty) {
      return null;
    }
    final upper = this!.toUpperCase();

    // 1. Direct matches available in ZXing Format enum
    if (upper.contains('MICRO_QR') || upper.contains('QR')) {
      return Format.qrCode;
    }
    if (upper.contains('128')) {
      return Format.code128;
    }
    if (upper.contains('39')) {
      return Format.code39;
    }
    if (upper.contains('93')) {
      return Format.code93;
    }
    if (upper.contains('CODABAR')) {
      return Format.codabar;
    }
    if (upper.contains('ITF')) {
      return Format.itf;
    }
    if (upper.contains('EAN_13') || upper.contains('EAN13')) {
      return Format.ean13;
    }
    if (upper.contains('EAN_8') || upper.contains('EAN8')) {
      return Format.ean8;
    }
    if (upper.contains('UPC_A') || upper.contains('UPCA')) {
      return Format.upca;
    }
    if (upper.contains('UPC_E') || upper.contains('UPCE')) {
      return Format.upce;
    }
    if (upper.contains('DATA_MATRIX') || upper.contains('DATAMATRIX')) {
      return Format.dataMatrix;
    }
    if (upper.contains('MICRO_PDF') ||
        upper.contains('PDF_417') ||
        upper.contains('PDF417')) {
      return Format.pdf417;
    }
    if (upper.contains('AZTEC')) {
      return Format.aztec;
    }
    if (upper.contains('MAXICODE')) {
      return Format.maxiCode;
    }
    if (upper.contains('GS1') ||
        upper.contains('DATABAR') ||
        upper.contains('RSS')) {
      return Format.dataBar;
    }
    if (upper.contains('MSI')) {
      return FormatMsi.msiCode;
    }

    // 2. Formats supported by Dynamsoft but not in ZXing enum (CustomFormat mapping)
    if (upper.contains('INDUSTRIAL')) {
      return CustomFormat.industrial25;
    }
    if (upper.contains('MATRIX_25')) {
      return CustomFormat.matrix25;
    }
    if (upper.contains('CODE_11') || upper.contains('CODE11')) {
      return CustomFormat.code11;
    }
    if (upper.contains('CODE_32') || upper.contains('CODE32')) {
      return CustomFormat.code32;
    }
    if (upper.contains('DOTCODE')) {
      return CustomFormat.dotcode;
    }
    if (upper.contains('TELEPEN')) {
      return CustomFormat.telepen;
    }
    if (upper.contains('PHARMACODE')) {
      return CustomFormat.pharmacode;
    }
    if (upper.contains('PATCHCODE')) {
      return CustomFormat.patchcode;
    }
    if (upper.contains('USPS') || upper.contains('INTELLIGENT_MAIL')) {
      return CustomFormat.uspsIntelligentMail;
    }
    if (upper.contains('POSTNET')) {
      return CustomFormat.postnet;
    }
    if (upper.contains('PLANET')) {
      return CustomFormat.planet;
    }
    if (upper.contains('AUSTRALIAN')) {
      return CustomFormat.australianPost;
    }
    if (upper.contains('RM4SCC')) {
      return CustomFormat.rm4scc;
    }
    if (upper.contains('KIX')) {
      return CustomFormat.kix;
    }

    return null;
  }
}
