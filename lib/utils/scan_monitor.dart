import 'dart:math' as math;

enum ScanMonitorSource { liveCamera, galleryImage, nativeSdk }

class ScanMonitorSnapshot {
  const ScanMonitorSnapshot({
    required this.engineName,
    required this.modeLabel,
    required this.resultCount,
    required this.sessionDurationMs,
    required this.decodeAttempts,
    required this.successfulDecodes,
    required this.failedDecodes,
    required this.uniqueResults,
    required this.duplicateResults,
    required this.liveDecodeAttempts,
    required this.galleryDecodeAttempts,
    required this.nativeEvents,
    required this.totalDecodeMs,
    this.timeToFirstResultMs,
    this.lastResultMs,
    this.lastDecodeMs,
    this.minDecodeMs,
    this.maxDecodeMs,
  });

  final String engineName;
  final String modeLabel;
  final int resultCount;
  final int sessionDurationMs;
  final int decodeAttempts;
  final int successfulDecodes;
  final int failedDecodes;
  final int uniqueResults;
  final int duplicateResults;
  final int liveDecodeAttempts;
  final int galleryDecodeAttempts;
  final int nativeEvents;
  final int totalDecodeMs;
  final int? timeToFirstResultMs;
  final int? lastResultMs;
  final int? lastDecodeMs;
  final int? minDecodeMs;
  final int? maxDecodeMs;

  bool get hasDecodeStats => decodeAttempts > 0;

  double? get averageDecodeMs {
    if (decodeAttempts == 0) return null;
    return totalDecodeMs / decodeAttempts;
  }
}

class ScanMonitor {
  ScanMonitor({required this.engineName});

  final String engineName;

  final Stopwatch _session = Stopwatch();
  String _modeLabel = '';
  int _decodeAttempts = 0;
  int _successfulDecodes = 0;
  int _failedDecodes = 0;
  int _uniqueResults = 0;
  int _duplicateResults = 0;
  int _liveDecodeAttempts = 0;
  int _galleryDecodeAttempts = 0;
  int _nativeEvents = 0;
  int _totalDecodeMs = 0;
  int? _timeToFirstResultMs;
  int? _lastResultMs;
  int? _lastDecodeMs;
  int? _minDecodeMs;
  int? _maxDecodeMs;

  void startSession({required String modeLabel}) {
    _modeLabel = modeLabel;
    _session
      ..reset()
      ..start();
    _decodeAttempts = 0;
    _successfulDecodes = 0;
    _failedDecodes = 0;
    _uniqueResults = 0;
    _duplicateResults = 0;
    _liveDecodeAttempts = 0;
    _galleryDecodeAttempts = 0;
    _nativeEvents = 0;
    _totalDecodeMs = 0;
    _timeToFirstResultMs = null;
    _lastResultMs = null;
    _lastDecodeMs = null;
    _minDecodeMs = null;
    _maxDecodeMs = null;
  }

  ScanMonitorOperation startDecode({
    required ScanMonitorSource source,
    required String modeLabel,
  }) {
    _ensureSession(modeLabel);
    _decodeAttempts++;
    switch (source) {
      case ScanMonitorSource.liveCamera:
        _liveDecodeAttempts++;
        break;
      case ScanMonitorSource.galleryImage:
        _galleryDecodeAttempts++;
        break;
      case ScanMonitorSource.nativeSdk:
        _nativeEvents++;
        break;
    }

    return ScanMonitorOperation._(this);
  }

  void recordNativeEvent({
    required int uniqueCount,
    required int duplicateCount,
    required String modeLabel,
  }) {
    _ensureSession(modeLabel);
    _nativeEvents++;
    recordResults(uniqueCount: uniqueCount, duplicateCount: duplicateCount);
  }

  void recordResults({required int uniqueCount, int duplicateCount = 0}) {
    _duplicateResults += math.max(0, duplicateCount);
    if (uniqueCount <= 0) return;

    _uniqueResults += uniqueCount;
    final int elapsedMs = _session.elapsedMilliseconds;
    _timeToFirstResultMs ??= elapsedMs;
    _lastResultMs = elapsedMs;
  }

  ScanMonitorSnapshot snapshot({required int resultCount}) {
    return ScanMonitorSnapshot(
      engineName: engineName,
      modeLabel: _modeLabel,
      resultCount: resultCount,
      sessionDurationMs: _session.elapsedMilliseconds,
      decodeAttempts: _decodeAttempts,
      successfulDecodes: _successfulDecodes,
      failedDecodes: _failedDecodes,
      uniqueResults: _uniqueResults,
      duplicateResults: _duplicateResults,
      liveDecodeAttempts: _liveDecodeAttempts,
      galleryDecodeAttempts: _galleryDecodeAttempts,
      nativeEvents: _nativeEvents,
      totalDecodeMs: _totalDecodeMs,
      timeToFirstResultMs: _timeToFirstResultMs,
      lastResultMs: _lastResultMs,
      lastDecodeMs: _lastDecodeMs,
      minDecodeMs: _minDecodeMs,
      maxDecodeMs: _maxDecodeMs,
    );
  }

  void _finishDecode(ScanMonitorOperation operation, {required bool success}) {
    if (operation._isFinished) return;

    operation._isFinished = true;
    operation._stopwatch.stop();

    final int elapsedMs = operation._stopwatch.elapsedMilliseconds;
    _lastDecodeMs = elapsedMs;
    _minDecodeMs = _minDecodeMs == null
        ? elapsedMs
        : math.min(_minDecodeMs!, elapsedMs);
    _maxDecodeMs = _maxDecodeMs == null
        ? elapsedMs
        : math.max(_maxDecodeMs!, elapsedMs);
    _totalDecodeMs += elapsedMs;

    if (success) {
      _successfulDecodes++;
    } else {
      _failedDecodes++;
    }
  }

  void _ensureSession(String modeLabel) {
    if (_modeLabel != modeLabel) {
      _modeLabel = modeLabel;
    }
    if (!_session.isRunning && _session.elapsedMilliseconds == 0) {
      _session.start();
    }
  }
}

class ScanMonitorOperation {
  ScanMonitorOperation._(this._monitor);

  final ScanMonitor _monitor;
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool _isFinished = false;

  void finish({required bool success}) {
    _monitor._finishDecode(this, success: success);
  }
}
