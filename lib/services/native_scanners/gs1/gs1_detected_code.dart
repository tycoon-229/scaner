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
    if (upper.contains('MICRO_PDF') ||
        upper.contains('PDF_417') ||
        upper.contains('PDF417')) {
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
      upca => 'UPCA',
      upce => 'UPCE',
      _ => 'Unknown',
    };
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
    this.position,
  });

  final String? text;
  final int? format;
  final bool isValid;
  final Gs1DetectedPosition? position;
}
