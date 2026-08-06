import 'package:flutter_zxing/flutter_zxing.dart';

abstract class FormatMsi {
  static const int msiPlessey = 9999;
}

extension SafeCodeFormatExt on int {
  String get safeFormatName {
    if (this == FormatMsi.msiPlessey) {
      return 'MSI Plessey';
    }
    return name;
  }
}

extension CodeFormatNameExt on Code {
  String? get formatName => format?.safeFormatName;
}
