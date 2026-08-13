import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:poc_multi_scan/utils/scan_monitor.dart';

class ScanResultWidget extends StatelessWidget {
  const ScanResultWidget({
    super.key,
    required this.results,
    this.durationMs,
    this.monitorSnapshot,
    this.onScanAgain,
  });

  factory ScanResultWidget.fromMap({
    Key? key,
    required Map<String, String> mapResults,
    int? durationMs,
    ScanMonitorSnapshot? monitorSnapshot,
    VoidCallback? onScanAgain,
  }) {
    return ScanResultWidget(
      key: key,
      results: mapResults.entries.toList(),
      durationMs: durationMs,
      monitorSnapshot: monitorSnapshot,
      onScanAgain: onScanAgain,
    );
  }

  final List<MapEntry<String, String>> results;
  final int? durationMs;
  final ScanMonitorSnapshot? monitorSnapshot;
  final VoidCallback? onScanAgain;

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).primaryColor;
    final int count = results.length;

    return Column(
      children: <Widget>[
        _ResultHeader(
          count: count,
          durationMs: durationMs,
          monitorSnapshot: monitorSnapshot,
          primaryColor: primaryColor,
        ),
        Expanded(
          child: count == 0
              ? _EmptyResultState(primaryColor: primaryColor)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    return _ResultTile(
                      index: index,
                      entry: results[index],
                      primaryColor: primaryColor,
                    );
                  },
                ),
        ),
        if (onScanAgain != null)
          _ResultActionBar(
            primaryColor: primaryColor,
            onScanAgain: onScanAgain!,
          ),
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.count,
    required this.durationMs,
    required this.monitorSnapshot,
    required this.primaryColor,
  });

  final int count;
  final int? durationMs;
  final ScanMonitorSnapshot? monitorSnapshot;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    final int? effectiveDurationMs =
        durationMs ?? monitorSnapshot?.timeToFirstResultMs;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: primaryColor,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.fact_check_outlined, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Scan Results',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _CountPill(count: count),
              if (monitorSnapshot != null) ...<Widget>[
                const SizedBox(width: 8),
                _MonitorInfoButton(snapshot: monitorSnapshot!),
              ],
            ],
          ),
          if (effectiveDurationMs != null &&
              effectiveDurationMs > 0) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Time to first result: ${_formatDuration(effectiveDurationMs)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MonitorInfoButton extends StatelessWidget {
  const _MonitorInfoButton({required this.snapshot});

  final ScanMonitorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        tooltip: 'Scan monitor',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
        onPressed: () => _showMonitorDialog(context, snapshot),
      ),
    );
  }
}

void _showMonitorDialog(BuildContext context, ScanMonitorSnapshot snapshot) {
  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      final Size screenSize = MediaQuery.sizeOf(context);
      final double dialogWidth = (screenSize.width - 32).clamp(320.0, 560.0);
      final double dialogMaxHeight = screenSize.height * 0.82;

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: dialogMaxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.query_stats_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Scan Monitor',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _MonitorSection(
                          title: 'Session',
                          rows: <_MonitorRowData>[
                            _MonitorRowData('Engine', snapshot.engineName),
                            _MonitorRowData('Mode', snapshot.modeLabel),
                            _MonitorRowData(
                              'Results',
                              '${snapshot.resultCount}',
                            ),
                            _MonitorRowData(
                              'Session duration',
                              _formatDuration(snapshot.sessionDurationMs),
                            ),
                            _MonitorRowData(
                              'Time to first result',
                              _formatOptionalDuration(
                                snapshot.timeToFirstResultMs,
                              ),
                            ),
                            _MonitorRowData(
                              'Last result at',
                              _formatOptionalDuration(snapshot.lastResultMs),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _MonitorSection(
                          title: 'Decode',
                          rows: <_MonitorRowData>[
                            _MonitorRowData(
                              'Attempts',
                              '${snapshot.decodeAttempts}',
                            ),
                            _MonitorRowData(
                              'Success / failed',
                              '${snapshot.successfulDecodes} / ${snapshot.failedDecodes}',
                            ),
                            _MonitorRowData(
                              'Live attempts',
                              '${snapshot.liveDecodeAttempts}',
                            ),
                            _MonitorRowData(
                              'Gallery attempts',
                              '${snapshot.galleryDecodeAttempts}',
                            ),
                            _MonitorRowData(
                              'Native SDK events',
                              '${snapshot.nativeEvents}',
                            ),
                          ],
                        ),
                        if (snapshot.hasDecodeStats) ...<Widget>[
                          const SizedBox(height: 14),
                          _MonitorSection(
                            title: 'Latency',
                            rows: <_MonitorRowData>[
                              _MonitorRowData(
                                'Average decode',
                                _formatOptionalDoubleDuration(
                                  snapshot.averageDecodeMs,
                                ),
                              ),
                              _MonitorRowData(
                                'Min decode',
                                _formatOptionalDuration(snapshot.minDecodeMs),
                              ),
                              _MonitorRowData(
                                'Max decode',
                                _formatOptionalDuration(snapshot.maxDecodeMs),
                              ),
                              _MonitorRowData(
                                'Last decode',
                                _formatOptionalDuration(snapshot.lastDecodeMs),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        _MonitorSection(
                          title: 'Results',
                          rows: <_MonitorRowData>[
                            _MonitorRowData(
                              'Unique results',
                              '${snapshot.uniqueResults}',
                            ),
                            _MonitorRowData(
                              'Duplicate results',
                              '${snapshot.duplicateResults}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _MonitorSection extends StatelessWidget {
  const _MonitorSection({required this.title, required this.rows});

  final String title;
  final List<_MonitorRowData> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final _MonitorRowData row in rows) _MonitorMetricRow(row: row),
          ],
        ),
      ),
    );
  }
}

class _MonitorMetricRow extends StatelessWidget {
  const _MonitorMetricRow({required this.row});

  final _MonitorRowData row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(
              row.label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorRowData {
  const _MonitorRowData(this.label, this.value);

  final String label;
  final String value;
}

String _formatOptionalDuration(int? valueMs) {
  if (valueMs == null) return 'N/A';
  return _formatDuration(valueMs);
}

String _formatOptionalDoubleDuration(double? valueMs) {
  if (valueMs == null) return 'N/A';
  return _formatDuration(valueMs.round());
}

String _formatDuration(int valueMs) {
  if (valueMs < 1000) return '$valueMs ms';
  return '${(valueMs / 1000).toStringAsFixed(2)} s';
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        '$count ${count == 1 ? 'code' : 'codes'}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.index,
    required this.entry,
    required this.primaryColor,
  });

  final int index;
  final MapEntry<String, String> entry;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _IndexBadge(index: index, primaryColor: primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (entry.key.isNotEmpty) _FormatBadge(text: entry.key),
                  if (entry.key.isNotEmpty) const SizedBox(height: 8),
                  SelectableText(
                    entry.value,
                    style: const TextStyle(
                      color: Color(0xFF1F1F1F),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Copy result',
              icon: const Icon(Icons.copy_rounded, size: 20),
              color: Colors.black54,
              onPressed: () => _copyResult(context, entry.value),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyResult(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Result copied')));
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index, required this.primaryColor});

  final int index;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: primaryColor,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyResultState extends StatelessWidget {
  const _EmptyResultState({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.qr_code_scanner_rounded,
            size: 48,
            color: primaryColor.withValues(alpha: 0.65),
          ),
          const SizedBox(height: 12),
          const Text(
            'No scan results yet',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultActionBar extends StatelessWidget {
  const _ResultActionBar({
    required this.primaryColor,
    required this.onScanAgain,
  });

  final Color primaryColor;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        child: SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text(
              'Scan Again',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: onScanAgain,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScanResultPage extends StatelessWidget {
  const ScanResultPage({
    super.key,
    required this.results,
    required this.onScanAgain,
    this.durationMs,
    this.monitorSnapshot,
  });

  final List<MapEntry<String, String>> results;
  final VoidCallback onScanAgain;
  final int? durationMs;
  final ScanMonitorSnapshot? monitorSnapshot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: ScanResultWidget(
          results: results,
          durationMs: durationMs,
          monitorSnapshot: monitorSnapshot,
          onScanAgain: onScanAgain,
        ),
      ),
    );
  }
}
