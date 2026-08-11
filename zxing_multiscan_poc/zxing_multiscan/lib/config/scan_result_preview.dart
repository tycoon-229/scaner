class ScanResultPreview {
  const ScanResultPreview._();

  static const bool enabled = bool.fromEnvironment(
    'PREVIEW_SCAN_RESULTS',
    defaultValue: false,
  );

  static const List<MapEntry<String, String>>
  sampleResults = <MapEntry<String, String>>[
    MapEntry<String, String>('QR_CODE', 'POC-MULTISCAN-ORDER-20260811'),
    MapEntry<String, String>('EAN_13', '8938505974197'),
    MapEntry<String, String>('CODE_128', 'YUYAMA-BIN-A04-SLOT-12'),
    MapEntry<String, String>('DATA_MATRIX', '010893850597419721ABC123'),
    MapEntry<String, String>('MSI_CODE', '00012345678900112233445566778899'),
    MapEntry<String, String>(
      'PDF_417',
      'PATIENT:NGUYEN VAN A|RX:RX-2026-0811-00042|QTY:120|LOT:YYM2408',
    ),
    MapEntry<String, String>(
      'QR_CODE',
      'https://example.yuyama.local/scan/result/very-long-value-for-layout-preview',
    ),
  ];
}
