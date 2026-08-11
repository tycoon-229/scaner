import 'package:flutter/material.dart';

/// A completely decoupled multi-scan result widget.
///
/// Accepts a list of Key-Value pairs (`List<MapEntry<String, String>>`):
/// * `entry.key`   -> Barcode format / type name (e.g. 'QR_CODE', 'EAN_13')
/// * `entry.value` -> Decoded text string
///
/// Can be reused across any barcode decoding library (ZXing, MLKit, MobileScanner, etc.).
class ScanResultWidget extends StatelessWidget {
  const ScanResultWidget({
    super.key,
    required this.results,
    this.durationMs,
    this.onScanAgain,
  });

  /// Factory constructor to convert a `Map<String, String>` directly into `MultiScanResultWidget`:
  /// * `Key`   -> formatName
  /// * `Value` -> decoded text
  factory ScanResultWidget.fromMap({
    Key? key,
    required Map<String, String> mapResults,
    int? durationMs,
    VoidCallback? onScanAgain,
  }) {
    return ScanResultWidget(
      key: key,
      results: mapResults.entries.toList(),
      durationMs: durationMs,
      onScanAgain: onScanAgain,
    );
  }

  /// List of Key-Value pairs:
  /// * `key`   = formatName (loại mã)
  /// * `value` = decoded text (chuỗi giải mã)
  final List<MapEntry<String, String>> results;
  final int? durationMs;
  final VoidCallback? onScanAgain;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 6.0),
              child: Text(
                'Scan Results',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            if (durationMs != null && durationMs! > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.orange, width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.timer_outlined, color: Colors.orange, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'TTFD: $durationMs ms',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        'Chưa có kết quả nào',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (BuildContext context, int index) {
                        final MapEntry<String, String> entry = results[index];
                        final String formatName = entry.key;
                        final String text = entry.value;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withValues(alpha: 0.1),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                            title: SelectableText(
                              text,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: formatName.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: <Widget>[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            formatName,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (onScanAgain != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text(
                        'Scan Again',
                        style: TextStyle(fontSize: 16),
                      ),
                      onPressed: onScanAgain,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
