typedef ScanEntry = MapEntry<String, String>;

bool addUniqueScanEntry(List<ScanEntry> entries, ScanEntry entry) {
  if (entry.value.isEmpty ||
      entries.any((ScanEntry existing) => existing.value == entry.value)) {
    return false;
  }

  entries.add(entry);
  return true;
}
