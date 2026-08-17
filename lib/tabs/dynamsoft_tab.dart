import 'package:camera/camera.dart';
import 'package:dynamsoft_capture_vision_flutter/dynamsoft_capture_vision_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:poc_multi_scan/config/license_keys.dart';
import 'package:poc_multi_scan/extensions/code_format_extensions.dart';
import 'package:poc_multi_scan/services/native_scanners/gs1/gs1_composite_assembler.dart';
import 'package:poc_multi_scan/utils/scan_entries.dart';
import 'package:poc_multi_scan/utils/scan_monitor.dart';
import 'package:poc_multi_scan/widgets/scan_result_widget.dart';
import 'package:poc_multi_scan/widgets/camera_scanner/camera_scanner.dart';
import 'package:poc_multi_scan/widgets/scanner_camera_preview.dart';
import 'package:poc_multi_scan/widgets/scanner_live_scaffold.dart';
import 'package:poc_multi_scan/widgets/scanner_message.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level isolate helper (must be outside class for compute())
// ─────────────────────────────────────────────────────────────────────────────

/// Data passed into the isolate for YUV → NV21 conversion.
class _ConvertParams {
  const _ConvertParams({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uvPixelStride,
    required this.width,
    required this.height,
  });

  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uvPixelStride;
  final int width;
  final int height;
}

/// Runs in a background isolate — no Flutter UI code allowed here.
Uint8List _yuv420ToNv21Isolate(_ConvertParams p) {
  final int ySize = p.width * p.height;
  final Uint8List nv21 = Uint8List(ySize + ySize ~/ 2);

  // Copy Y plane row by row (handles non-contiguous strides)
  for (int row = 0; row < p.height; row++) {
    nv21.setRange(
      row * p.width,
      row * p.width + p.width,
      p.yBytes,
      row * p.yRowStride,
    );
  }

  // Interleave V, U → NV21
  int offset = ySize;
  for (int i = 0; i < p.uBytes.length; i += p.uvPixelStride) {
    if (offset + 1 >= nv21.length) break;
    nv21[offset++] = p.vBytes[i];
    nv21[offset++] = p.uBytes[i];
  }

  return nv21;
}

// ─────────────────────────────────────────────────────────────────────────────
// DynamsoftTab
// ─────────────────────────────────────────────────────────────────────────────

/// Demo tab wiring [CameraScannerWidget] to [CaptureVisionRouter]
/// for frame-by-frame Dynamsoft barcode decoding.
///
/// All heavy work (YUV conversion) is offloaded to a background isolate
/// via [compute] so the camera preview stays smooth.
class DynamsoftTab extends StatefulWidget {
  const DynamsoftTab({super.key});

  @override
  State<DynamsoftTab> createState() => _DynamsoftTabState();
}

class _DynamsoftTabState extends State<DynamsoftTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScannerUIController _scannerController = ScannerUIController();
  final ScanMonitor _monitor = ScanMonitor(engineName: 'Dynamsoft');

  /// Key-Value pairs list for multi scan results:
  /// * `entry.key`   -> formatName (e.g. 'QR_CODE', 'EAN_13')
  /// * `entry.value` -> decoded text string
  final List<ScanEntry> _scannedEntries = <ScanEntry>[];

  /// Single scan result (Key = formatName, Value = text)
  ScanEntry? _singleResult;

  ScanMode _scanMode = ScanMode.single;
  bool _showMultiResultScreen = false;

  /// Prevents re-entrant captures (belt-and-suspenders on top of
  /// [CameraScannerWidget]'s own _isProcessing guard).
  bool _isCaptureRunning = false;

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scannerController.addListener(_onControllerChanged);
    _monitor.startSession(modeLabel: _modeLabel);
    _initDynamsoft();
  }

  Future<void> _initDynamsoft() async {
    try {
      await LicenseManager.initLicense(LicenseKeys.dynamsoft);
    } catch (e) {
      debugPrint('[DynamsoftTab] initLicense error: $e');
    }
  }

  @override
  void dispose() {
    _scannerController
      ..removeListener(_onControllerChanged)
      ..dispose();
    CaptureVisionRouter.instance.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Restarts the camera stream and laser animation when switching tabs.
  Future<void> restartCameraLaser() async {
    await _scannerController.restartCameraLaser();
    if (mounted) {
      setState(() {
        _singleResult = null;
        _clearMultiResults();
      });
      _monitor.startSession(modeLabel: _modeLabel);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Frame handler
  // ──────────────────────────────────────────────────────────────────────────

  Future<bool?> _handleFrame(CameraImage image, Rect? cropRect) async {
    // Extra guard: skip if a capture is already in-flight
    if (_isCaptureRunning) return false;
    _isCaptureRunning = true;
    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.liveCamera,
      modeLabel: _modeLabel,
    );
    bool hasDecodedCode = false;

    try {
      // 1. Build ImageData (YUV conversion runs in isolate → non-blocking)
      final ImageData? imageData = await _buildImageData(image);
      if (imageData == null) return false;

      // 2. Decode with Dynamsoft
      final CapturedResult result = await CaptureVisionRouter.instance.capture(
        imageData,
        EnumPresetTemplate.readBarcodesReadRateFirst,
      );

      // 3. Extract barcodes
      final List<BarcodeResultItem> barcodes =
          result.decodedBarcodesResult?.items ?? <BarcodeResultItem>[];
      if (barcodes.isEmpty) return false;

      hasDecodedCode = true;
      if (_scanMode == ScanMode.single) {
        // Single: take first → show result → pause camera
        final BarcodeResultItem first = barcodes.first;
        _monitor.recordResults(uniqueCount: 1);
        if (mounted) {
          setState(() {
            _singleResult = _entryForBarcode(first);
          });
        }
        return true; // CameraScannerWidget auto-pauses stream
      } else {
        // Multi: accumulate unique barcodes
        bool hasNew = false;
        int newCodeCount = 0;
        int duplicateCodeCount = 0;
        for (final BarcodeResultItem b in barcodes) {
          final ScanEntry e = _entryForBarcode(b);
          if (addUniqueScanEntry(_scannedEntries, e)) {
            hasNew = true;
            newCodeCount++;
          } else {
            duplicateCodeCount++;
          }
        }
        _monitor.recordResults(
          uniqueCount: newCodeCount,
          duplicateCount: duplicateCodeCount,
        );
        if (hasNew && mounted) setState(() {});
        return false;
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] capture error: $e');
      return false;
    } finally {
      operation.finish(success: hasDecodedCode);
      _isCaptureRunning = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Gallery handler
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _handleGalleryImage(String path) async {
    // Stop the live stream first so CaptureVisionRouter is free for a file decode.
    await _scannerController.pauseStream();
    _monitor.startSession(modeLabel: '$_modeLabel / Gallery');
    final ScanMonitorOperation operation = _monitor.startDecode(
      source: ScanMonitorSource.galleryImage,
      modeLabel: '$_modeLabel / Gallery',
    );
    bool hasDecodedCode = false;

    try {
      // captureFile works on an image path — no ImageData conversion needed.
      final CapturedResult result = await CaptureVisionRouter.instance
          .captureFile(
            path,
            EnumPresetTemplate
                .readBarcodesReadRateFirst, // best accuracy for still images
          );

      final List<BarcodeResultItem> barcodes =
          result.decodedBarcodesResult?.items ?? <BarcodeResultItem>[];

      if (!mounted) return;

      if (barcodes.isNotEmpty) {
        hasDecodedCode = true;
        _monitor.recordResults(uniqueCount: 1);
        setState(() {
          _singleResult = _entryForBarcode(barcodes.first);
        });
      } else {
        showScannerMessage(context, 'No valid code found in the image');
        // Resume stream so user can scan again
        _resumeScan();
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] gallery decode error: $e');
      if (mounted) showScannerMessage(context, 'Failed to read image: $e');
      _resumeScan();
    } finally {
      operation.finish(success: hasDecodedCode);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CameraImage → Dynamsoft ImageData
  // ──────────────────────────────────────────────────────────────────────────

  Future<ImageData?> _buildImageData(CameraImage image) async {
    try {
      switch (image.format.group) {
        case ImageFormatGroup.yuv420:
          // Offload YUV → NV21 conversion to a background isolate
          final Uint8List nv21 = await compute(
            _yuv420ToNv21Isolate,
            _ConvertParams(
              yBytes: image.planes[0].bytes,
              uBytes: image.planes[1].bytes,
              vBytes: image.planes[2].bytes,
              yRowStride: image.planes[0].bytesPerRow,
              uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
              width: image.width,
              height: image.height,
            ),
          );
          return ImageData(
            bytes: nv21,
            width: image.width,
            height: image.height,
            stride: image.width,
            format: EnumImagePixelFormat.nv21,
            orientation: 0,
          );

        case ImageFormatGroup.bgra8888:
          // iOS BGRA — already contiguous, copy directly
          return ImageData(
            bytes: image.planes[0].bytes,
            width: image.width,
            height: image.height,
            stride: image.planes[0].bytesPerRow,
            format: EnumImagePixelFormat.abgr8888,
            orientation: 0,
          );

        default:
          return null;
      }
    } catch (e) {
      debugPrint('[DynamsoftTab] _buildImageData error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 1. Single Scan result screen
    if (_scanMode == ScanMode.single && _singleResult != null) {
      return ScanResultPage(
        results: <ScanEntry>[_singleResult!],
        monitorSnapshot: _monitor.snapshot(resultCount: 1),
        onScanAgain: () {
          setState(() => _singleResult = null);
          _monitor.startSession(modeLabel: _modeLabel);
          _resumeScan();
        },
      );
    }

    // 2. Multi Scan result screen
    if (_scanMode == ScanMode.multiscan && _showMultiResultScreen) {
      return ScanResultPage(
        results: _scannedEntries,
        monitorSnapshot: _monitor.snapshot(resultCount: _scannedEntries.length),
        onScanAgain: () {
          setState(_clearMultiResults);
          _monitor.startSession(modeLabel: _modeLabel);
          _resumeScan();
        },
      );
    }

    return ScannerLiveScaffold(
      preview: ScannerCameraPreview(
        tabIndex: 1,
        controller: _scannerController,
        scanMode: _scanMode,
        resolution: ResolutionPreset.medium,
        scanDelay: const Duration(milliseconds: 300),
        frameIntervalMs: 400,
        onFrameCaptured: _handleFrame,
        onGalleryImageSelected: _handleGalleryImage,
        onControllerCreated: (CameraController? cam, Exception? err) {
          if (err != null && mounted) {
            showScannerMessage(context, 'Camera error: $err');
          }
        },
      ),
      scanMode: _scanMode,
      resultCount: _scannedEntries.length,
      onShowResults: _showMultiResults,
      onModeChanged: _changeMode,
      onGalleryImageSelected: _handleGalleryImage,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _resumeScan() {
    _scannerController.resumeStream(
      (CameraImage image) => _handleFrame(image, null),
    );
  }

  void _changeMode(ScanMode mode) {
    setState(() {
      _scanMode = mode;
      _singleResult = null;
      _clearMultiResults();
    });
    _monitor.startSession(modeLabel: _modeLabel);
  }

  void _clearMultiResults() {
    _scannedEntries.clear();
    _showMultiResultScreen = false;
  }

  void _showMultiResults() {
    setState(() => _showMultiResultScreen = true);
  }

  ScanEntry _entryForBarcode(BarcodeResultItem barcode) {
    final String formatName = barcode.formatString;
    final String rawText = barcode.text;
    final bool looksLikeGs1 = _looksLikeGs1(formatName, rawText);
    final String? gs1Text = Gs1ElementStringParser.tryFormatElementString(
      rawText,
      fallbackFormat: formatName.toZxingFormat,
      requireGs1Marker: !looksLikeGs1,
    );

    return ScanEntry(formatName, gs1Text ?? rawText);
  }

  bool _looksLikeGs1(String formatName, String text) {
    final String normalizedFormat = formatName.toUpperCase();
    return normalizedFormat.contains('GS1') ||
        normalizedFormat.contains('COMPOSITE') ||
        text.contains('\u001d') ||
        text.contains('\u241d') ||
        RegExp(
          r'\{GS\}|<GS>|\\u001d|\\x1d',
          caseSensitive: false,
        ).hasMatch(text);
  }

  String get _modeLabel {
    return _scanMode == ScanMode.single ? 'Single Code' : 'Multi Code';
  }
}
