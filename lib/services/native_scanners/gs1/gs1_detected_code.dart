abstract class Gs1DetectedFormat {
  static const int code128 = 1 << 4;
  static const int dataBar = 1 << 5;
  static const int dataBarExpanded = 1 << 6;
  static const int ean8 = 1 << 8;
  static const int ean13 = 1 << 9;
  static const int pdf417 = 1 << 12;
  static const int upca = 1 << 14;
  static const int upce = 1 << 15;
  static const int dataBarLimited = 1 << 19;
  static const int microPdf417 = 1 << 20;

  static int? fromName(String? value) {
    if (value == null || value.isEmpty) return null;
    final String upper = value.toUpperCase();

    if (upper.contains('128')) return code128;
    if (upper.contains('EAN_13') || upper.contains('EAN13')) return ean13;
    if (upper.contains('EAN_8') || upper.contains('EAN8')) return ean8;
    if (upper.contains('UPC_A') || upper.contains('UPCA')) return upca;
    if (upper.contains('UPC_E') || upper.contains('UPCE')) return upce;
    if (upper.contains('LIMITED')) return dataBarLimited;
    if (upper.contains('EXPANDED')) return dataBarExpanded;
    if (upper.contains('DATABAR') || upper.contains('RSS')) return dataBar;
    if (upper.contains('MICRO_PDF') || upper.contains('MICROPDF')) {
      return microPdf417;
    }
    if (upper.contains('PDF_417') || upper.contains('PDF417')) {
      return pdf417;
    }

    return null;
  }

  static String name(int? format) {
    return switch (format) {
      code128 => 'Code128',
      dataBar => 'DataBar',
      dataBarExpanded => 'DataBarExpanded',
      dataBarLimited => 'DataBarLimited',
      ean8 => 'EAN8',
      ean13 => 'EAN13',
      pdf417 => 'PDF417',
      microPdf417 => 'MicroPDF417',
      upca => 'UPCA',
      upce => 'UPCE',
      _ => 'Unknown',
    };
  }
}

class Gs1DataBarTextNormalizer {
  const Gs1DataBarTextNormalizer._();

  static String normalize({
    required String text,
    String? formatName,
    int? format,
  }) {
    final String upperFormat = (formatName ?? '').toUpperCase();
    final bool isDataBar = format == null
        ? upperFormat.contains('DATABAR')
        : format == Gs1DetectedFormat.dataBar ||
              format == Gs1DetectedFormat.dataBarLimited;
    final bool isOmnidirectional =
        isDataBar &&
        upperFormat.contains('DATABAR') &&
        !upperFormat.contains('EXPANDED') &&
        !upperFormat.contains('STACKED');

    if (!isOmnidirectional) return text;
    if (text.contains('(') || text.contains('\u001d')) return text;
    if (!RegExp(r'^\d{14}$').hasMatch(text)) return text;
    if (!_hasValidGtinCheckDigit(text)) return text;

    return '(01)$text';
  }

  static bool _hasValidGtinCheckDigit(String value) {
    int sum = 0;
    for (int index = 0; index < value.length - 1; index++) {
      final int digit = value.codeUnitAt(index) - 48;
      sum += digit * (index.isEven ? 3 : 1);
    }
    final int expected = (10 - (sum % 10)) % 10;
    return expected == value.codeUnitAt(value.length - 1) - 48;
  }
}

class Gs1DetectedPosition {
  const Gs1DetectedPosition({
    required this.imageWidth,
    required this.imageHeight,
    required this.topLeftX,
    required this.topLeftY,
    required this.topRightX,
    required this.topRightY,
    required this.bottomLeftX,
    required this.bottomLeftY,
    required this.bottomRightX,
    required this.bottomRightY,
  });

  final int imageWidth;
  final int imageHeight;
  final int topLeftX;
  final int topLeftY;
  final int topRightX;
  final int topRightY;
  final int bottomLeftX;
  final int bottomLeftY;
  final int bottomRightX;
  final int bottomRightY;
}

class Gs1DetectedCode {
  const Gs1DetectedCode({
    required this.text,
    required this.format,
    required this.isValid,
    this.rawBytes,
    this.position,
  });

  final String? text;
  final int? format;
  final bool isValid;
  final List<int>? rawBytes;
  final Gs1DetectedPosition? position;
}
