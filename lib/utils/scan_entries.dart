import 'package:flutter/foundation.dart';

typedef ScanEntry = MapEntry<String, String>;

bool addUniqueScanEntry(List<ScanEntry> entries, ScanEntry entry) {
  if (entry.value.isEmpty ||
      entries.any((ScanEntry existing) => existing.value == entry.value)) {
    return false;
  }

  entries.add(entry);
  return true;
}

void logScanResult(
  String source,
  ScanEntry entry, {
  String? mode,
  String? origin,
}) {
  final String modeLabel = mode == null ? '' : ' mode=$mode';
  final String originLabel = origin == null ? '' : ' origin=$origin';
  debugPrint(
    '[$source] Scan result$modeLabel$originLabel: format="${entry.key}", text="${entry.value}"',
  );
}
